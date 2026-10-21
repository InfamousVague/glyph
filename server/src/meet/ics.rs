//! A calendar invite read (RFC 5545), as much of it as booking Ghost into a Google Meet needs: which meeting (its UID,
//! and RECURRENCE-ID for one changed occurrence), what it is called, when, where (the Meet link), whether it is
//! called off, and which version of it this is (SEQUENCE).
//!
//! Written here rather than taken from a crate because what is needed is small and exact: Google's invites, which are
//! regular in shape, read right. The lines are unfolded, each is split into its name, its parameters (a quoted value
//! may hold `:` and `;`) and its value, and the components are nested as BEGIN and END say.
//!
//! TIMES. A DTSTART is one of four things:
//!
//! - UTC (`20261020T150000Z`), taken as it is;
//! - wall-clock time in a zone (`DTSTART;TZID=America/New_York:20261020T110000`), resolved with the VTIMEZONE block the
//!   invite carries for that TZID. Google always sends one, with a STANDARD and a DAYLIGHT observance, each an onset,
//!   TZOFFSETFROM, TZOFFSETTO and a yearly RRULE (`FREQ=YEARLY;BYMONTH=3;BYDAY=2SU`). Only when the invite has no block
//!   for its TZID is the small table of common IANA names below used (`fallback_zone`); an unknown name with no block
//!   is read as UTC, which is wrong by the zone's offset, and the person sees that time in the app and can skip it;
//! - floating wall-clock time (no TZID, no Z), which means "whatever the attendee's clock says": the service has no
//!   clock of the attendee's, so it is read as UTC. Google never sends one for a timed event;
//! - a date (`VALUE=DATE`), an all-day event, which has nothing to join and is left out.
//!
//! RECURRENCE. A recurring meeting (RRULE on the VEVENT) is read as its next occurrence that has not ended yet,
//! expanded in the event's own wall-clock time, so a weekly 9:00 stays at 9:00 across a change of clocks, and as the
//! `Series` that makes it: the rule, DTSTART with its zone's observances, the length, and the starts the series does not
//! book (EXDATEs, and occurrences the same invite changes separately: a VEVENT with the same UID and a RECURRENCE-ID,
//! booked as a meeting of its own). meet.rs keeps the `Series` on the series' booking and books each occurrence once the
//! one before is over, with `Series::next`, and no new mail. DAILY, WEEKLY, MONTHLY and YEARLY with INTERVAL, COUNT,
//! UNTIL, BYDAY (with an ordinal for MONTHLY, `2TU`, `-1FR`), BYMONTHDAY and BYMONTH are read; a rule with any other
//! part (BYSETPOS, BYHOUR, ...) books only its first occurrence, if that is still to come. A series with no occurrence
//! to come is read all the same (`over`), so an update that ends it (an UNTIL moved earlier) reaches its booking.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// One meeting an invite books, moves or calls off, with the occurrence chosen and its time resolved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Invite {
    /// The VEVENT's UID; for one changed occurrence of a recurring meeting, `<UID>#<RECURRENCE-ID in ms>`.
    pub uid: String,
    /// One changed occurrence's original start, in ms (its RECURRENCE-ID), when this is one.
    pub recurrence_id: Option<i64>,
    pub title: Option<String>,
    /// The Google Meet link, in its one canonical form (`meet_url`), when the invite has one.
    pub url: Option<String>,
    /// The occurrence booked, in ms since the epoch.
    pub starts_at: i64,
    pub ends_at: i64,
    pub sequence: i64,
    /// METHOD:CANCEL, or STATUS:CANCELLED.
    pub cancelled: bool,
    /// The series this is the next occurrence of, when the VEVENT has an RRULE.
    pub series: Option<Series>,
    /// A series with no occurrence still to come: `starts_at` and `ends_at` are then its first, and it books nothing.
    pub over: bool,
    /// Who sent it, as the invite says (`mailto:` dropped). Read, and not kept: a booking has no use for it.
    #[allow(dead_code)]
    pub organizer: Option<String>,
}

// --- lines and components ------------------------------------------------------------------------

#[derive(Debug, Clone)]
struct Prop {
    name: String,
    params: Vec<(String, String)>,
    value: String,
}

impl Prop {
    fn param(&self, name: &str) -> Option<&str> {
        self.params.iter().find(|(n, _)| n == name).map(|(_, v)| v.as_str())
    }
}

#[derive(Debug, Default)]
struct Component {
    name: String,
    props: Vec<Prop>,
    children: Vec<Component>,
}

impl Component {
    fn prop(&self, name: &str) -> Option<&Prop> {
        self.props.iter().find(|p| p.name == name)
    }

    fn value(&self, name: &str) -> Option<&str> {
        self.prop(name).map(|p| p.value.as_str())
    }

    fn all<'a>(&'a self, name: &'a str) -> impl Iterator<Item = &'a Prop> + 'a {
        self.props.iter().filter(move |p| p.name == name)
    }
}

/// The text's logical lines: a line that begins with a space or a tab continues the one before (RFC 5545 3.1).
fn unfold(text: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for raw in text.split('\n') {
        let raw = raw.strip_suffix('\r').unwrap_or(raw);
        match (raw.strip_prefix([' ', '\t']), lines.last_mut()) {
            (Some(rest), Some(last)) => last.push_str(rest),
            _ if !raw.trim().is_empty() => lines.push(raw.to_string()),
            _ => {}
        }
    }
    lines
}

/// `NAME;PARAM=value;PARAM="quoted:value":the value`. A parameter's quotes are dropped; inside them `:` and `;` are
/// the value's own.
fn content_line(line: &str) -> Option<Prop> {
    let bytes = line.as_bytes();
    let mut i = 0;
    while i < bytes.len() && bytes[i] != b';' && bytes[i] != b':' {
        i += 1;
    }
    if i >= bytes.len() {
        return None;
    }
    let name = line[..i].trim().to_ascii_uppercase();
    let mut params = Vec::new();
    while bytes[i] == b';' {
        i += 1;
        let start = i;
        while i < bytes.len() && !matches!(bytes[i], b'=' | b';' | b':') {
            i += 1;
        }
        if i >= bytes.len() {
            return None;
        }
        let param = line[start..i].trim().to_ascii_uppercase();
        let mut value = String::new();
        if bytes[i] == b'=' {
            i += 1;
            let start = i;
            let mut quoted = false;
            while i < bytes.len() {
                match bytes[i] {
                    b'"' => quoted = !quoted,
                    b';' | b':' if !quoted => break,
                    _ => {}
                }
                i += 1;
            }
            if i >= bytes.len() {
                return None;
            }
            value = line[start..i].replace('"', "");
        }
        params.push((param, value));
    }
    Some(Prop { name, params, value: line[i + 1..].to_string() })
}

/// The components, nested as BEGIN and END say. A stray END, or a BEGIN never closed, is forgiven: what was read stays.
fn components(text: &str) -> Vec<Component> {
    let mut stack: Vec<Component> = Vec::new();
    let mut top: Vec<Component> = Vec::new();
    let mut close = |done: Component, stack: &mut Vec<Component>| match stack.last_mut() {
        Some(parent) => parent.children.push(done),
        None => top.push(done),
    };
    for line in unfold(text) {
        let Some(prop) = content_line(&line) else { continue };
        match prop.name.as_str() {
            "BEGIN" => stack.push(Component { name: prop.value.trim().to_ascii_uppercase(), ..Default::default() }),
            "END" => {
                if let Some(done) = stack.pop() {
                    close(done, &mut stack);
                }
            }
            _ => {
                if let Some(current) = stack.last_mut() {
                    current.props.push(prop);
                }
            }
        }
    }
    while let Some(open) = stack.pop() {
        close(open, &mut stack);
    }
    top
}

/// A TEXT value's escapes undone: `\n`, `\,`, `\;`, `\\`.
fn text(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n' | 'N') => out.push('\n'),
            Some(other) => out.push(other),
            None => {}
        }
    }
    out
}

// --- the calendar's arithmetic -------------------------------------------------------------------

const DAY: i64 = 86_400;

/// Days since 1970-01-01 of a civil date (Howard Hinnant's `days_from_civil`).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The civil date of a day number: year, month (1-12), day.
fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { yoe + era * 400 + 1 } else { yoe + era * 400 }, m, d)
}

/// 0 for Sunday through 6 for Saturday (1970-01-01 was a Thursday).
fn weekday(days: i64) -> i64 {
    (days + 4).rem_euclid(7)
}

fn days_in_month(y: i64, m: i64) -> i64 {
    let (ny, nm) = if m == 12 { (y + 1, 1) } else { (y, m + 1) };
    days_from_civil(ny, nm, 1) - days_from_civil(y, m, 1)
}

/// The day number of the `nth` `wd` of a month: `2SU` is the second Sunday, `-1SU` the last; none past its end.
fn nth_weekday(y: i64, m: i64, nth: i64, wd: i64) -> Option<i64> {
    let first = days_from_civil(y, m, 1);
    let length = days_in_month(y, m);
    let day = if nth > 0 {
        first + (wd - weekday(first)).rem_euclid(7) + (nth - 1) * 7
    } else {
        let last = first + length - 1;
        last - (weekday(last) - wd).rem_euclid(7) + (nth + 1) * 7
    };
    (day >= first && day < first + length).then_some(day)
}

/// `SU`..`SA`, as 0..6.
fn weekday_code(code: &str) -> Option<i64> {
    ["SU", "MO", "TU", "WE", "TH", "FR", "SA"].iter().position(|c| c.eq_ignore_ascii_case(code)).map(|i| i as i64)
}

/// `[+-]n` and a weekday: `2SU` is (2, 0), `-1FR` (-1, 5), `MO` (0, 1), every Monday.
fn by_day(item: &str) -> Option<(i64, i64)> {
    let item = item.trim();
    if item.len() < 2 || !item.is_ascii() {
        return None;
    }
    let (nth, code) = item.split_at(item.len() - 2);
    let nth = if nth.is_empty() { 0 } else { nth.trim_start_matches('+').parse().ok()? };
    Some((nth, weekday_code(code)?))
}

/// A DATE-TIME's wall-clock time as seconds since the epoch, as though it were UTC, and whether it is (`Z`).
fn date_time(value: &str) -> Option<(i64, bool)> {
    let value = value.trim();
    let (body, utc) = match value.strip_suffix(['Z', 'z']) {
        Some(body) => (body, true),
        None => (value, false),
    };
    let (date, time) = body.split_once(['T', 't'])?;
    let days = date_value(date)?;
    if time.len() != 6 || !time.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let n = |r: std::ops::Range<usize>| time[r].parse::<i64>().ok();
    let (h, mi, s) = (n(0..2)?, n(2..4)?, n(4..6)?);
    if h > 23 || mi > 59 || s > 60 {
        return None;
    }
    Some((days * DAY + h * 3600 + mi * 60 + s.min(59), utc))
}

/// A DATE (`20261020`) as its day number.
fn date_value(value: &str) -> Option<i64> {
    let value = value.trim();
    if value.len() != 8 || !value.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let (y, m, d) = (value[0..4].parse().ok()?, value[4..6].parse().ok()?, value[6..8].parse().ok()?);
    if !(1..=12).contains(&m) || d < 1 || d > days_in_month(y, m) {
        return None;
    }
    Some(days_from_civil(y, m, d))
}

/// A UTC offset, `-0500` or `+053000`, in seconds.
fn offset(value: &str) -> Option<i64> {
    let value = value.trim();
    let (sign, digits) = match value.as_bytes().first()? {
        b'+' => (1, &value[1..]),
        b'-' => (-1, &value[1..]),
        _ => return None,
    };
    if !(digits.len() == 4 || digits.len() == 6) || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let h: i64 = digits[0..2].parse().ok()?;
    let m: i64 = digits[2..4].parse().ok()?;
    let s: i64 = if digits.len() == 6 { digits[4..6].parse().ok()? } else { 0 };
    Some(sign * (h * 3600 + m * 60 + s))
}

/// A DURATION (`PT1H30M`, `P1D`, `P1W`), in seconds.
fn duration(value: &str) -> Option<i64> {
    let value = value.trim();
    let (sign, rest) = match value.strip_prefix('-') {
        Some(rest) => (-1, rest),
        None => (1, value.strip_prefix('+').unwrap_or(value)),
    };
    let rest = rest.strip_prefix(['P', 'p'])?;
    let (mut total, mut number, mut seen) = (0i64, String::new(), false);
    for c in rest.chars() {
        match c.to_ascii_uppercase() {
            'T' => {}
            d if d.is_ascii_digit() => number.push(d),
            unit => {
                let n: i64 = number.parse().ok()?;
                number.clear();
                seen = true;
                total += n * match unit {
                    'W' => 7 * DAY,
                    'D' => DAY,
                    'H' => 3600,
                    'M' => 60,
                    'S' => 1,
                    _ => return None,
                };
            }
        }
    }
    (seen && number.is_empty()).then_some(sign * total)
}

// --- time zones ----------------------------------------------------------------------------------

/// When an observance begins again each year: a month and a weekday's ordinal in it, or a day of the month.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
struct Yearly {
    month: i64,
    nth: i64,
    weekday: i64,
    month_day: Option<i64>,
}

/// One of a zone's observances (STANDARD or DAYLIGHT): from its onset, and each year's by its rule, the clock reads
/// UTC + `to`. The onset is wall-clock time under the offset it replaces, `from`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Observance {
    onset: i64,
    from: i64,
    to: i64,
    yearly: Option<Yearly>,
    /// The rule's UNTIL, as UTC seconds.
    until: Option<i64>,
    rdates: Vec<i64>,
}

type Zone = Vec<Observance>;

/// An observance's onsets around `year` (the year before to the year after), as (UTC seconds, the offset from then).
fn onsets(observance: &Observance, year: i64, out: &mut Vec<(i64, i64)>) {
    let onset_year = civil_from_days(observance.onset.div_euclid(DAY)).0;
    let time_of_day = observance.onset.rem_euclid(DAY);
    out.push((observance.onset - observance.from, observance.to));
    for rdate in &observance.rdates {
        out.push((rdate - observance.from, observance.to));
    }
    let Some(rule) = observance.yearly else { return };
    for y in (year - 1)..=(year + 1) {
        if y < onset_year {
            continue;
        }
        let day = match rule.month_day {
            Some(d) if d > 0 && d <= days_in_month(y, rule.month) => Some(days_from_civil(y, rule.month, d)),
            Some(_) => None,
            None => nth_weekday(y, rule.month, rule.nth, rule.weekday),
        };
        let Some(day) = day else { continue };
        let utc = day * DAY + time_of_day - observance.from;
        if observance.until.is_none_or(|until| utc <= until) {
            out.push((utc, observance.to));
        }
    }
}

/// Wall-clock `wall` in `zone`, as UTC seconds: the offset of the latest onset at or before the moment it names. A time
/// a change of clocks skips is read in the offset before it, one it repeats in the offset after.
fn to_utc(wall: i64, zone: Option<&Zone>) -> i64 {
    let Some(zone) = zone.filter(|z| !z.is_empty()) else { return wall };
    let year = civil_from_days(wall.div_euclid(DAY)).0;
    let mut all = Vec::new();
    for observance in zone {
        onsets(observance, year, &mut all);
    }
    match all.iter().filter(|(at, to)| *at <= wall - to).max_by_key(|(at, _)| *at) {
        Some((_, to)) => wall - to,
        // Before every onset the invite gives: the earliest observance's offset from before it began.
        None => zone.iter().min_by_key(|o| o.onset).map_or(wall, |o| wall - o.from),
    }
}

/// A VTIMEZONE block as observances.
fn zone_of(block: &Component) -> Zone {
    let mut zone = Vec::new();
    for child in block.children.iter().filter(|c| c.name == "STANDARD" || c.name == "DAYLIGHT") {
        let (Some(onset), Some(from), Some(to)) = (
            child.value("DTSTART").and_then(date_time).map(|(t, _)| t),
            child.value("TZOFFSETFROM").and_then(offset),
            child.value("TZOFFSETTO").and_then(offset),
        ) else {
            continue;
        };
        let (mut yearly, mut until) = (None, None);
        if let Some(rule) = child.value("RRULE") {
            let parts = rule_parts(rule);
            if parts.get("FREQ").map(String::as_str) == Some("YEARLY") {
                let month = parts.get("BYMONTH").and_then(|m| m.parse().ok());
                let day = parts.get("BYDAY").and_then(|d| by_day(d.split(',').next().unwrap_or(d)));
                let month_day = parts.get("BYMONTHDAY").and_then(|d| d.parse().ok());
                yearly = match (month, day, month_day) {
                    (Some(month), Some((nth, weekday)), _) if nth != 0 => Some(Yearly { month, nth, weekday, month_day: None }),
                    (Some(month), _, Some(d)) => Some(Yearly { month, nth: 0, weekday: 0, month_day: Some(d) }),
                    _ => None,
                };
                until = parts.get("UNTIL").and_then(|u| date_time(u).map(|(t, utc)| if utc { t } else { t - from }));
            }
        }
        let rdates = child.all("RDATE").flat_map(|p| p.value.split(',').filter_map(date_time).map(|(t, _)| t).collect::<Vec<_>>()).collect();
        zone.push(Observance { onset, from, to, yearly, until, rdates });
    }
    zone
}

/// A zone for a common IANA name, for an invite that names one and carries no VTIMEZONE for it. Google always carries
/// one; this is for the calendars that do not. Each is the zone's rule today: US daylight time (the second Sunday of
/// March to the first of November, at 2:00), the EU's (the last Sunday of March to the last of October, at 1:00 UTC),
/// or none.
fn fallback_zone(name: &str) -> Option<Zone> {
    enum Rule {
        None,
        Us,
        Eu,
    }
    const H: i64 = 3600;
    let (standard, rule) = match name {
        "UTC" | "Etc/UTC" | "GMT" | "Etc/GMT" => (0, Rule::None),
        "America/New_York" | "America/Toronto" | "America/Detroit" | "US/Eastern" => (-5 * H, Rule::Us),
        "America/Chicago" | "US/Central" => (-6 * H, Rule::Us),
        "America/Denver" | "US/Mountain" => (-7 * H, Rule::Us),
        "America/Phoenix" => (-7 * H, Rule::None),
        "America/Los_Angeles" | "America/Vancouver" | "US/Pacific" => (-8 * H, Rule::Us),
        "America/Anchorage" => (-9 * H, Rule::Us),
        "Pacific/Honolulu" => (-10 * H, Rule::None),
        "Europe/London" | "Europe/Dublin" | "Europe/Lisbon" => (0, Rule::Eu),
        "Europe/Paris" | "Europe/Berlin" | "Europe/Madrid" | "Europe/Rome" | "Europe/Amsterdam" | "Europe/Brussels" | "Europe/Vienna"
        | "Europe/Stockholm" | "Europe/Oslo" | "Europe/Copenhagen" | "Europe/Zurich" | "Europe/Warsaw" | "Europe/Prague" => (H, Rule::Eu),
        "Europe/Athens" | "Europe/Helsinki" | "Europe/Kiev" | "Europe/Kyiv" => (2 * H, Rule::Eu),
        "Asia/Kolkata" | "Asia/Calcutta" => (5 * H + 30 * 60, Rule::None),
        "Asia/Singapore" | "Asia/Shanghai" | "Asia/Hong_Kong" => (8 * H, Rule::None),
        "Asia/Tokyo" => (9 * H, Rule::None),
        _ => return None,
    };
    let observance = |onset, from, to, rule: Option<(i64, i64)>| Observance {
        onset,
        from,
        to,
        yearly: rule.map(|(month, nth)| Yearly { month, nth, weekday: 0, month_day: None }),
        until: None,
        rdates: Vec::new(),
    };
    let dst = standard + H;
    Some(match rule {
        Rule::None => vec![observance(0, standard, standard, None)],
        Rule::Us => vec![observance(2 * H, standard, dst, Some((3, 2))), observance(2 * H, dst, standard, Some((11, 1)))],
        // At 1:00 UTC, written as the wall-clock time each change is made from.
        Rule::Eu => vec![observance(H + standard, standard, dst, Some((3, -1))), observance(H + dst, dst, standard, Some((10, -1)))],
    })
}

// --- events --------------------------------------------------------------------------------------

/// `FREQ=WEEKLY;BYDAY=MO,WE` as its parts, upper-cased.
fn rule_parts(rule: &str) -> HashMap<String, String> {
    rule.split(';').filter_map(|part| part.split_once('=')).map(|(k, v)| (k.trim().to_ascii_uppercase(), v.trim().to_ascii_uppercase())).collect()
}

/// A start or an end as the invite gives it: wall-clock seconds and the zone they are in (none: UTC, or floating).
#[derive(Clone, Copy)]
struct Moment<'z> {
    wall: i64,
    zone: Option<&'z Zone>,
}

impl Moment<'_> {
    fn utc(&self) -> i64 {
        to_utc(self.wall, self.zone)
    }
}

/// A DTSTART-like property: a moment, or a date (all day).
enum When<'z> {
    At(Moment<'z>),
    Date,
}

fn when<'z>(prop: &Prop, zones: &'z HashMap<String, Zone>) -> Option<When<'z>> {
    if prop.param("VALUE").is_some_and(|v| v.eq_ignore_ascii_case("DATE")) || date_value(&prop.value).is_some() {
        return date_value(&prop.value).map(|_| When::Date);
    }
    let (wall, utc) = date_time(&prop.value)?;
    let zone = match (utc, prop.param("TZID")) {
        (false, Some(tzid)) => zones.get(tzid.trim().trim_start_matches('/')),
        _ => None,
    };
    Some(When::At(Moment { wall, zone }))
}

/// The next occurrence of a recurring meeting that starts after `after` (when given) and has not ended at `now` (UTC
/// seconds, both), as UTC seconds, skipping `skip` (the starts the invite removes or books separately); none when the
/// rule is done. The header says what is read.
fn next_occurrence(start: Moment<'_>, length: i64, rule: &str, skip: &[i64], after: Option<i64>, now: i64) -> Option<(i64, i64)> {
    let parts = rule_parts(rule);
    let usable = |at: i64| !skip.contains(&at) && after.is_none_or(|after| at > after);
    let first = start.utc();
    let known = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "BYMONTHDAY", "BYMONTH", "WKST"];
    let freq = parts.get("FREQ").map(String::as_str).unwrap_or("");
    if parts.keys().any(|k| !known.contains(&k.as_str())) || !["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(&freq) {
        // A rule this does not read: its first occurrence, if that is still to come.
        return (first + length > now && usable(first)).then_some((first, first + length));
    }
    let interval = parts.get("INTERVAL").and_then(|i| i.parse::<i64>().ok()).filter(|i| *i > 0).unwrap_or(1);
    let count = parts.get("COUNT").and_then(|c| c.parse::<i64>().ok());
    let until = parts.get("UNTIL").and_then(|u| match date_time(u) {
        Some((t, true)) => Some(t),
        Some((t, false)) => Some(to_utc(t, start.zone)),
        None => date_value(u).map(|d| to_utc(d * DAY + DAY - 1, start.zone)),
    });
    let days: Vec<(i64, i64)> = parts.get("BYDAY").map(|d| d.split(',').filter_map(by_day).collect()).unwrap_or_default();
    let month_days: Vec<i64> = parts.get("BYMONTHDAY").map(|d| d.split(',').filter_map(|x| x.trim().parse().ok()).collect()).unwrap_or_default();
    let months: Vec<i64> = parts.get("BYMONTH").map(|d| d.split(',').filter_map(|x| x.trim().parse().ok()).collect()).unwrap_or_default();

    let start_day = start.wall.div_euclid(DAY);
    let time_of_day = start.wall.rem_euclid(DAY);
    let (sy, sm, sd) = civil_from_days(start_day);
    // The days of one month a MONTHLY or YEARLY rule falls on, in order.
    let month_hits = |y: i64, m: i64| -> Vec<i64> {
        let mut hits: Vec<i64> = Vec::new();
        let length = days_in_month(y, m);
        let first = days_from_civil(y, m, 1);
        for &(nth, wd) in &days {
            if nth == 0 {
                hits.extend((0..length).map(|i| first + i).filter(|d| weekday(*d) == wd));
            } else if let Some(d) = nth_weekday(y, m, nth, wd) {
                hits.push(d);
            }
        }
        for &md in &month_days {
            let d = if md > 0 { md } else { length + md + 1 };
            if d >= 1 && d <= length {
                hits.push(first + d - 1);
            }
        }
        if days.is_empty() && month_days.is_empty() && sd <= length {
            hits.push(first + sd - 1);
        }
        hits.sort_unstable();
        hits.dedup();
        hits
    };

    // DTSTART is the first occurrence whether or not the rule would make it (RFC 5545 3.8.5.3), and counts toward
    // COUNT; EXDATEs remove occurrences after COUNT has counted them.
    let mut seen = 0i64;
    let mut consider = |day: i64| -> Option<Option<(i64, i64)>> {
        let at = to_utc(day * DAY + time_of_day, start.zone);
        seen += 1;
        if count.is_some_and(|c| seen > c) || until.is_some_and(|u| at > u) {
            return Some(None);
        }
        (at + length > now && usable(at)).then_some(Some((at, at + length)))
    };
    if let Some(found) = consider(start_day) {
        return found;
    }
    // Enough periods for a daily meeting for thirty years; a rule that runs on past that books nothing.
    for period in 0..11_000i64 {
        let mut hits: Vec<i64> = Vec::new();
        match freq {
            "DAILY" => {
                let day = start_day + period * interval;
                if days.is_empty() || days.iter().any(|(_, wd)| weekday(day) == *wd) {
                    hits.push(day);
                }
            }
            "WEEKLY" => {
                let monday = start_day - (weekday(start_day) + 6) % 7 + period * interval * 7;
                let wanted: Vec<i64> = if days.is_empty() { vec![weekday(start_day)] } else { days.iter().map(|(_, wd)| *wd).collect() };
                hits.extend(wanted.iter().map(|wd| monday + (wd + 6) % 7));
                hits.sort_unstable();
            }
            "MONTHLY" => {
                let index = (sy * 12 + sm - 1) + period * interval;
                let (y, m) = (index.div_euclid(12), index.rem_euclid(12) + 1);
                if months.is_empty() || months.contains(&m) {
                    hits = month_hits(y, m);
                }
            }
            _ => {
                let y = sy + period * interval;
                for m in if months.is_empty() { vec![sm] } else { months.clone() } {
                    hits.extend(month_hits(y, m));
                }
                hits.sort_unstable();
            }
        }
        for day in hits.into_iter().filter(|d| *d > start_day) {
            if let Some(found) = consider(day) {
                return found;
            }
        }
    }
    None
}

/// What expanding a recurring meeting needs, and nothing else: kept on the series' booking (meet.rs, as JSON) so each
/// occurrence after the next is booked with no new mail. No names: the organizer and the guests are not in it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Series {
    /// The RRULE's value.
    rule: String,
    /// DTSTART's wall-clock time, as seconds since the epoch as though it were UTC...
    start: i64,
    /// ...and the zone it is in, as the invite's VTIMEZONE (or the fallback table) gave it; none for UTC or floating.
    zone: Option<Zone>,
    /// Seconds.
    length: i64,
    /// The starts the series does not book, UTC seconds: its EXDATEs, and the RECURRENCE-IDs of the occurrences the
    /// invite changed separately.
    skip: Vec<i64>,
}

impl Series {
    /// The first occurrence that starts after `after` (ms; none, from the first) and has not ended at `now` (ms), in ms;
    /// none once the rule is done (COUNT, UNTIL).
    pub fn next(&self, after: Option<i64>, now: i64) -> Option<(i64, i64)> {
        let start = Moment { wall: self.start, zone: self.zone.as_ref() };
        let after = after.map(|a| a.div_euclid(1000));
        next_occurrence(start, self.length, &self.rule, &self.skip, after, now.div_euclid(1000)).map(|(s, e)| (s * 1000, e * 1000))
    }

    /// Whether an occurrence of the series starts at `at` (ms).
    pub fn occurs(&self, at: i64) -> bool {
        self.next(Some(at - 1000), i64::MIN / 2).is_some_and(|(s, _)| s == at)
    }
}

/// The first Google Meet link in `text`, as `https://meet.google.com/abc-defg-hij`: a code of three, four and three
/// lower-case letters. Anything else - another service's link, a Meet "lookup" link - is none.
pub fn meet_url(text: &str) -> Option<String> {
    let lower = text.to_ascii_lowercase();
    let mut from = 0;
    while let Some(at) = lower[from..].find("meet.google.com/") {
        let start = from + at + "meet.google.com/".len();
        // The host must be meet.google.com itself, not the tail of another (`notmeet.google.com`).
        let host_start = from + at;
        let own_host = host_start == 0 || !lower.as_bytes()[host_start - 1].is_ascii_alphanumeric() && lower.as_bytes()[host_start - 1] != b'.' && lower.as_bytes()[host_start - 1] != b'-';
        let code: String = lower[start..].chars().take_while(|c| c.is_ascii_lowercase() || *c == '-').collect();
        let pieces: Vec<&str> = code.split('-').collect();
        if own_host && pieces.len() == 3 && pieces[0].len() == 3 && pieces[1].len() == 4 && pieces[2].len() == 3 {
            return Some(format!("https://meet.google.com/{code}"));
        }
        from = start;
    }
    None
}

/// A Meet link a person typed or pasted, checked whole: `meet.google.com/abc-defg-hij`, with or without `https://`, a
/// query or a trailing slash. Unlike `meet_url`, nothing else may be around it.
pub fn typed_meet_url(typed: &str) -> Option<String> {
    let t = typed.trim().to_ascii_lowercase();
    let t = t.strip_prefix("https://").or_else(|| t.strip_prefix("http://")).unwrap_or(&t);
    let path = t.strip_prefix("meet.google.com/")?;
    let code = path.split(['?', '#']).next().unwrap_or(path).trim_end_matches('/');
    meet_url(&format!("meet.google.com/{code}")).filter(|url| url.ends_with(&format!("/{code}")))
}

/// Every meeting the calendar text books, moves or calls off, at `now` (ms). All-day events, and events with no UID or
/// no start, are left out. A recurring meeting with no occurrence still to come is read as `over`.
pub fn invites(calendar: &str, now: i64) -> Vec<Invite> {
    let now_secs = now.div_euclid(1000);
    let mut out = Vec::new();
    for cal in components(calendar).iter().filter(|c| c.name == "VCALENDAR") {
        let method_cancel = cal.value("METHOD").is_some_and(|m| m.trim().eq_ignore_ascii_case("CANCEL"));
        let mut zones: HashMap<String, Zone> = HashMap::new();
        for block in cal.children.iter().filter(|c| c.name == "VTIMEZONE") {
            if let Some(tzid) = block.value("TZID") {
                zones.insert(tzid.trim().trim_start_matches('/').to_string(), zone_of(block));
            }
        }
        let events: Vec<&Component> = cal.children.iter().filter(|c| c.name == "VEVENT").collect();
        // A TZID the invite names with no block of its own: the fallback table's zone, if it has that name.
        for event in &events {
            for prop in ["DTSTART", "DTEND", "RECURRENCE-ID", "EXDATE"].into_iter().flat_map(|n| event.all(n)) {
                if let Some(tzid) = prop.param("TZID").map(|t| t.trim().trim_start_matches('/').to_string()) {
                    if let std::collections::hash_map::Entry::Vacant(slot) = zones.entry(tzid) {
                        if let Some(zone) = fallback_zone(slot.key()) {
                            slot.insert(zone);
                        }
                    }
                }
            }
        }
        for event in &events {
            let Some(uid) = event.value("UID").map(str::trim).filter(|u| !u.is_empty()) else { continue };
            let Some(When::At(start)) = event.prop("DTSTART").and_then(|p| when(p, &zones)) else { continue };
            let first = start.utc();
            let length = match event.prop("DTEND").and_then(|p| when(p, &zones)) {
                Some(When::At(end)) => end.utc() - first,
                _ => event.value("DURATION").and_then(duration).unwrap_or(3600),
            }
            .max(0);
            let recurrence_id = match event.prop("RECURRENCE-ID").and_then(|p| when(p, &zones)) {
                Some(When::At(at)) => Some(at.utc()),
                _ => None,
            };
            let rule = event.value("RRULE").filter(|_| recurrence_id.is_none());
            let (series, (starts_at, ends_at), over) = match rule {
                Some(rule) => {
                    // EXDATEs, and the occurrences this invite books on their own, are not the series' to book.
                    let mut skip: Vec<i64> = event
                        .all("EXDATE")
                        .flat_map(|p| {
                            let zone = p.param("TZID").and_then(|t| zones.get(t.trim().trim_start_matches('/')));
                            p.value.split(',').filter_map(|v| date_time(v).map(|(t, utc)| if utc { t } else { to_utc(t, zone) })).collect::<Vec<_>>()
                        })
                        .collect();
                    for other in events.iter().filter(|o| o.value("UID").map(str::trim) == Some(uid)) {
                        if let Some(When::At(at)) = other.prop("RECURRENCE-ID").and_then(|p| when(p, &zones)) {
                            skip.push(at.utc());
                        }
                    }
                    let series = Series { rule: rule.to_string(), start: start.wall, zone: start.zone.cloned(), length, skip };
                    // None to come: read all the same, so a booking of the series hears that it is over.
                    let (occurrence, over) = match next_occurrence(start, length, rule, &series.skip, None, now_secs) {
                        Some(found) => (found, false),
                        None => ((first, first + length), true),
                    };
                    (Some(series), occurrence, over)
                }
                None => (None, (first, first + length), false),
            };
            let status_cancelled = event.value("STATUS").is_some_and(|s| s.trim().eq_ignore_ascii_case("CANCELLED"));
            let url = ["X-GOOGLE-CONFERENCE", "DESCRIPTION", "LOCATION", "URL"].into_iter().find_map(|name| event.all(name).find_map(|p| meet_url(&text(&p.value))));
            let title = event.value("SUMMARY").map(|s| text(s).trim().to_string()).filter(|s| !s.is_empty());
            let organizer = event.value("ORGANIZER").map(|o| {
                let o = o.trim();
                o.get(..7).filter(|p| p.eq_ignore_ascii_case("mailto:")).map_or(o, |_| &o[7..]).to_string()
            });
            out.push(Invite {
                uid: match recurrence_id {
                    Some(at) => format!("{uid}#{}", at * 1000),
                    None => uid.to_string(),
                },
                recurrence_id: recurrence_id.map(|at| at * 1000),
                title,
                url,
                starts_at: starts_at * 1000,
                ends_at: ends_at * 1000,
                sequence: event.value("SEQUENCE").and_then(|s| s.trim().parse().ok()).unwrap_or(0),
                cancelled: method_cancel || status_cancelled,
                series,
                over,
                organizer,
            });
        }
    }
    out
}

#[cfg(test)]
pub mod tests {
    use super::*;

    /// Milliseconds of a UTC civil time, for the expectations.
    pub fn utc(y: i64, mo: i64, d: i64, h: i64, mi: i64) -> i64 {
        (days_from_civil(y, mo, d) * DAY + h * 3600 + mi * 60) * 1000
    }

    /// Google's invite as Google Calendar mails one to a guest: America/New_York with its VTIMEZONE, the Meet link in
    /// X-GOOGLE-CONFERENCE and in the description, folded lines, escaped commas and a quoted CN.
    pub fn google_invite(method: &str, sequence: i64, start: &str, end: &str, status: &str) -> String {
        format!(
            "BEGIN:VCALENDAR\r\n\
PRODID:-//Google Inc//Google Calendar 70.9054//EN\r\n\
VERSION:2.0\r\n\
CALSCALE:GREGORIAN\r\n\
METHOD:{method}\r\n\
BEGIN:VTIMEZONE\r\n\
TZID:America/New_York\r\n\
X-LIC-LOCATION:America/New_York\r\n\
BEGIN:DAYLIGHT\r\n\
TZOFFSETFROM:-0500\r\n\
TZOFFSETTO:-0400\r\n\
TZNAME:EDT\r\n\
DTSTART:19700308T020000\r\n\
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU\r\n\
END:DAYLIGHT\r\n\
BEGIN:STANDARD\r\n\
TZOFFSETFROM:-0400\r\n\
TZOFFSETTO:-0500\r\n\
TZNAME:EST\r\n\
DTSTART:19701101T020000\r\n\
RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU\r\n\
END:STANDARD\r\n\
END:VTIMEZONE\r\n\
BEGIN:VEVENT\r\n\
DTSTART;TZID=America/New_York:{start}\r\n\
DTEND;TZID=America/New_York:{end}\r\n\
DTSTAMP:20261018T120000Z\r\n\
ORGANIZER;CN=\"Lee, Sam\":mailto:sam@example.com\r\n\
UID:7kukuqrfedlm2f9t0vd0b2gscq@google.com\r\n\
ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=\r\n \
TRUE;CN=k7m2q9xh4t3vbn8p@in.ghostmarkdown.com;X-NUM-GUESTS=0:mailto:k7m2q9xh4t3vbn8p@\r\n \
in.ghostmarkdown.com\r\n\
X-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij\r\n\
CREATED:20261018T115900Z\r\n\
DESCRIPTION:Plans\\, and the budget.\\n\\n-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~\r\n \
:~::-\\nJoin with Google Meet: https://meet.google.com/abc-defg-hij\\n\\nJoin by phon\r\n \
e\\n(US) +1 555-0100 PIN: 123456789#\\n\r\n\
LAST-MODIFIED:20261018T120000Z\r\n\
LOCATION:\r\n\
SEQUENCE:{sequence}\r\n\
STATUS:{status}\r\n\
SUMMARY:Roadmap review\\, Q4\r\n\
TRANSP:OPAQUE\r\n\
END:VEVENT\r\n\
END:VCALENDAR\r\n"
        )
    }

    #[test]
    fn a_google_invite_in_new_york_reads_its_meeting_in_both_halves_of_the_year() {
        // 11:00 in New York is 15:00 UTC in October (EDT) and 16:00 in December (EST).
        let october = invites(&google_invite("REQUEST", 0, "20261020T110000", "20261020T120000", "CONFIRMED"), 0);
        assert_eq!(october.len(), 1);
        let one = &october[0];
        assert_eq!(one.uid, "7kukuqrfedlm2f9t0vd0b2gscq@google.com");
        assert_eq!((one.starts_at, one.ends_at), (utc(2026, 10, 20, 15, 0), utc(2026, 10, 20, 16, 0)));
        assert_eq!(one.title.as_deref(), Some("Roadmap review, Q4"));
        assert_eq!(one.url.as_deref(), Some("https://meet.google.com/abc-defg-hij"));
        assert_eq!(one.organizer.as_deref(), Some("sam@example.com"));
        assert!(!one.cancelled && one.series.is_none());
        let december = invites(&google_invite("REQUEST", 0, "20261210T110000", "20261210T113000", "CONFIRMED"), 0);
        assert_eq!((december[0].starts_at, december[0].ends_at), (utc(2026, 12, 10, 16, 0), utc(2026, 12, 10, 16, 30)));
        // Either side of the change of clocks on 2026-11-01 (2:00 EDT becomes 1:00 EST).
        let before = invites(&google_invite("REQUEST", 0, "20261031T090000", "20261031T100000", "CONFIRMED"), 0);
        assert_eq!(before[0].starts_at, utc(2026, 10, 31, 13, 0));
        let after = invites(&google_invite("REQUEST", 0, "20261101T090000", "20261101T100000", "CONFIRMED"), 0);
        assert_eq!(after[0].starts_at, utc(2026, 11, 1, 14, 0));
        // And in spring: 2027-03-14 is the second Sunday of March.
        let spring = invites(&google_invite("REQUEST", 0, "20270314T090000", "20270314T100000", "CONFIRMED"), 0);
        assert_eq!(spring[0].starts_at, utc(2027, 3, 14, 13, 0));
        let saturday = invites(&google_invite("REQUEST", 0, "20270313T090000", "20270313T100000", "CONFIRMED"), 0);
        assert_eq!(saturday[0].starts_at, utc(2027, 3, 13, 14, 0));
    }

    /// Google's Europe/London block, with an event at `start` to `finish` whose link is only in its description.
    fn london(start: &str, finish: &str) -> Invite {
        let cal = format!(
            "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VTIMEZONE\r\nTZID:Europe/London\r\nX-LIC-LOCATION:Europe/London\r\n\
BEGIN:DAYLIGHT\r\nTZOFFSETFROM:+0000\r\nTZOFFSETTO:+0100\r\nTZNAME:BST\r\nDTSTART:19700329T010000\r\nRRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU\r\nEND:DAYLIGHT\r\n\
BEGIN:STANDARD\r\nTZOFFSETFROM:+0100\r\nTZOFFSETTO:+0000\r\nTZNAME:GMT\r\nDTSTART:19701025T020000\r\nRRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n\
BEGIN:VEVENT\r\nDTSTART;TZID=Europe/London:{start}\r\nDTEND;TZID=Europe/London:{finish}\r\nUID:london@google.com\r\nSEQUENCE:0\r\nSUMMARY:Stand-up\r\n\
DESCRIPTION:Join: https://meet.google.com/xyz-abcd-efg\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        );
        invites(&cal, 0).remove(0)
    }

    #[test]
    fn london_is_an_hour_ahead_of_utc_in_summer_and_at_it_in_winter_with_the_link_from_the_description() {
        let summer = london("20260715T093000", "20260715T094500");
        assert_eq!((summer.starts_at, summer.ends_at), (utc(2026, 7, 15, 8, 30), utc(2026, 7, 15, 8, 45)));
        assert_eq!(summer.url.as_deref(), Some("https://meet.google.com/xyz-abcd-efg"), "no X-GOOGLE-CONFERENCE: the description's");
        assert_eq!(london("20261125T093000", "20261125T100000").starts_at, utc(2026, 11, 25, 9, 30));
        // 2026's last Sunday of October is the 25th: the Saturday is still BST, the Monday GMT.
        assert_eq!(london("20261024T093000", "20261024T100000").starts_at, utc(2026, 10, 24, 8, 30));
        assert_eq!(london("20261026T093000", "20261026T100000").starts_at, utc(2026, 10, 26, 9, 30));
    }

    #[test]
    fn utc_times_all_day_events_and_links_not_to_meet() {
        let cal = "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\n\
BEGIN:VEVENT\r\nUID:a\r\nDTSTART:20261020T150000Z\r\nDURATION:PT45M\r\nSUMMARY:In UTC\r\nX-GOOGLE-CONFERENCE:https://meet.google.com/aaa-bbbb-ccc\r\nEND:VEVENT\r\n\
BEGIN:VEVENT\r\nUID:b\r\nDTSTART;VALUE=DATE:20261020\r\nDTEND;VALUE=DATE:20261021\r\nSUMMARY:Holiday\r\nX-GOOGLE-CONFERENCE:https://meet.google.com/aaa-bbbb-ccc\r\nEND:VEVENT\r\n\
BEGIN:VEVENT\r\nUID:c\r\nDTSTART:20261020T150000Z\r\nDTEND:20261020T160000Z\r\nLOCATION:https://zoom.us/j/123456789\r\nDESCRIPTION:https://meet.google.com/lookup/abcdefg and https://notmeet.google.com/abc-defg-hij\r\nEND:VEVENT\r\n\
END:VCALENDAR\r\n";
        let found = invites(cal, 0);
        assert_eq!(found.len(), 2, "the all-day event is left out");
        assert_eq!((found[0].uid.as_str(), found[0].starts_at, found[0].ends_at), ("a", utc(2026, 10, 20, 15, 0), utc(2026, 10, 20, 15, 45)));
        assert_eq!(found[0].url.as_deref(), Some("https://meet.google.com/aaa-bbbb-ccc"));
        assert_eq!(found[1].url, None, "a Zoom link, a Meet lookup link and another host are not a Meet code");
    }

    #[test]
    fn a_cancellation_and_a_newer_sequence_are_read_as_such() {
        let cancel = invites(&google_invite("CANCEL", 2, "20261020T110000", "20261020T120000", "CANCELLED"), 0);
        assert!(cancel[0].cancelled);
        assert_eq!(cancel[0].sequence, 2);
        let status_only = invites(&google_invite("REQUEST", 3, "20261020T110000", "20261020T120000", "CANCELLED"), 0);
        assert!(status_only[0].cancelled, "STATUS:CANCELLED alone calls it off too");
        assert_eq!(invites(&google_invite("REQUEST", 1, "20261020T110000", "20261020T120000", "CONFIRMED"), 0)[0].sequence, 1);
    }

    #[test]
    fn a_tzid_without_a_block_falls_back_to_the_table_and_an_unknown_one_to_utc() {
        let cal = |tz: &str| format!("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nDTSTART;TZID={tz}:20260715T090000\r\nDTEND;TZID={tz}:20260715T100000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
        assert_eq!(invites(&cal("America/Los_Angeles"), 0)[0].starts_at, utc(2026, 7, 15, 16, 0));
        assert_eq!(invites(&cal("Europe/Berlin"), 0)[0].starts_at, utc(2026, 7, 15, 7, 0));
        assert_eq!(invites(&cal("Asia/Kolkata"), 0)[0].starts_at, utc(2026, 7, 15, 3, 30));
        assert_eq!(invites(&cal("Mars/Olympus_Mons"), 0)[0].starts_at, utc(2026, 7, 15, 9, 0));
        let winter = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nDTSTART;TZID=America/New_York:20261210T090000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        let one = &invites(winter, 0)[0];
        assert_eq!((one.starts_at, one.ends_at), (utc(2026, 12, 10, 14, 0), utc(2026, 12, 10, 15, 0)), "no end: an hour");
    }

    #[test]
    fn a_weekly_meeting_books_the_next_occurrence_not_yet_over_at_its_own_wall_clock_time() {
        // Tuesdays and Thursdays at 11:00 New York time from 2026-10-20, but not 2026-11-05.
        let base = google_invite("REQUEST", 0, "20261020T110000", "20261020T120000", "CONFIRMED");
        let weekly = base.replace("SEQUENCE:0\r\n", "SEQUENCE:0\r\nRRULE:FREQ=WEEKLY;BYDAY=TU,TH\r\nEXDATE;TZID=America/New_York:20261105T110000\r\n");
        let at = |now| invites(&weekly, now).into_iter().find(|i| i.recurrence_id.is_none()).unwrap();
        let first = at(utc(2026, 10, 1, 0, 0));
        assert!(first.series.is_some() && !first.over);
        assert_eq!(first.starts_at, utc(2026, 10, 20, 15, 0));
        assert_eq!(at(utc(2026, 10, 20, 15, 30)).starts_at, utc(2026, 10, 20, 15, 0), "still on: that one");
        assert_eq!(at(utc(2026, 10, 20, 16, 0)).starts_at, utc(2026, 10, 22, 15, 0), "over: the Thursday");
        // Past the change of clocks the meeting stays at 11:00 in New York, 16:00 UTC; the EXDATE is skipped.
        assert_eq!(at(utc(2026, 11, 3, 17, 0)).starts_at, utc(2026, 11, 10, 16, 0), "the 5th is excluded");
        // An occurrence the invite moves (RECURRENCE-ID) is booked on its own, and the series skips it.
        let moved = weekly.replace(
            "END:VCALENDAR\r\n",
            "BEGIN:VEVENT\r\nUID:7kukuqrfedlm2f9t0vd0b2gscq@google.com\r\nRECURRENCE-ID;TZID=America/New_York:20261022T110000\r\nDTSTART;TZID=America/New_York:20261023T140000\r\nDTEND;TZID=America/New_York:20261023T150000\r\nSEQUENCE:1\r\nSUMMARY:Moved\r\nX-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
        );
        let found = invites(&moved, utc(2026, 10, 20, 16, 0));
        let series = found.iter().find(|i| i.recurrence_id.is_none()).unwrap();
        assert_eq!(series.starts_at, utc(2026, 10, 27, 15, 0), "the 22nd is booked by its own VEVENT");
        let one = found.iter().find(|i| i.recurrence_id.is_some()).unwrap();
        assert_eq!(one.uid, format!("7kukuqrfedlm2f9t0vd0b2gscq@google.com#{}", utc(2026, 10, 22, 15, 0)));
        assert_eq!((one.starts_at, one.title.as_deref(), one.series.is_some()), (utc(2026, 10, 23, 18, 0), Some("Moved"), false));
    }

    #[test]
    fn monthly_by_ordinal_daily_with_count_and_a_series_that_is_over() {
        let cal = |rule: &str| format!("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:r\r\nDTSTART:20261013T150000Z\r\nDTEND:20261013T160000Z\r\nRRULE:{rule}\r\nX-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
        let after = utc(2026, 10, 14, 0, 0);
        // The second Tuesday of each month: 2026-10-13, then 2026-11-10.
        assert_eq!(invites(&cal("FREQ=MONTHLY;BYDAY=2TU"), after)[0].starts_at, utc(2026, 11, 10, 15, 0));
        assert_eq!(invites(&cal("FREQ=MONTHLY;BYDAY=-1FR"), after)[0].starts_at, utc(2026, 10, 30, 15, 0));
        assert_eq!(invites(&cal("FREQ=MONTHLY"), after)[0].starts_at, utc(2026, 11, 13, 15, 0));
        assert_eq!(invites(&cal("FREQ=DAILY;INTERVAL=2"), after)[0].starts_at, utc(2026, 10, 15, 15, 0));
        assert_eq!(invites(&cal("FREQ=YEARLY"), after)[0].starts_at, utc(2027, 10, 13, 15, 0));
        assert!(invites(&cal("FREQ=DAILY;COUNT=2"), utc(2026, 10, 20, 0, 0))[0].over, "two days and done");
        assert!(invites(&cal("FREQ=WEEKLY;UNTIL=20261021T000000Z"), utc(2026, 10, 21, 0, 0))[0].over);
        // A rule part this does not read: the first occurrence only, while it is to come.
        assert_eq!(invites(&cal("FREQ=MONTHLY;BYSETPOS=-1;BYDAY=MO,TU"), utc(2026, 10, 1, 0, 0))[0].starts_at, utc(2026, 10, 13, 15, 0));
        assert!(invites(&cal("FREQ=MONTHLY;BYSETPOS=-1;BYDAY=MO,TU"), after)[0].over);
    }

    #[test]
    fn a_series_kept_as_json_books_each_occurrence_after_the_last_in_its_own_wall_clock_time() {
        // 9:00 in New York on weekdays from Friday 2030-03-08, not Tuesday the 12th; the clocks change on the 10th.
        let base = google_invite("REQUEST", 0, "20300308T090000", "20300308T091500", "CONFIRMED");
        let weekdays = base.replace("SEQUENCE:0\r\n", "SEQUENCE:0\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;COUNT=5\r\nEXDATE;TZID=America/New_York:20300312T090000\r\n");
        let invite = invites(&weekdays, utc(2030, 3, 1, 0, 0)).remove(0);
        assert_eq!((invite.starts_at, invite.over), (utc(2030, 3, 8, 14, 0), false));
        // What a booking keeps, and reads back: the rule, the start, New York's observances, the length, the EXDATE.
        let kept = serde_json::to_string(invite.series.as_ref().unwrap()).unwrap();
        assert!(!kept.contains("sam@example.com") && !kept.contains("in.ghostmarkdown.com"), "no names: {kept}");
        let series: Series = serde_json::from_str(&kept).unwrap();
        assert_eq!(Some(&series), invite.series.as_ref());
        // Each after the one before, whatever the time: Monday at 13:00 UTC (EDT), the 12th passed over, and COUNT
        // (five, the EXDATE among them) ending it after Thursday.
        let mut seen = Vec::new();
        let mut after = invite.starts_at;
        while let Some((start, end)) = series.next(Some(after), 0) {
            assert_eq!(end - start, 15 * 60 * 1000);
            seen.push(start);
            after = start;
        }
        assert_eq!(seen, vec![utc(2030, 3, 11, 13, 0), utc(2030, 3, 13, 13, 0), utc(2030, 3, 14, 13, 0)]);
        // Not ended at `now`: the one under way, then the next.
        assert_eq!(series.next(None, utc(2030, 3, 11, 13, 10)), Some((utc(2030, 3, 11, 13, 0), utc(2030, 3, 11, 13, 15))));
        assert_eq!(series.next(None, utc(2030, 3, 11, 13, 15)).map(|o| o.0), Some(utc(2030, 3, 13, 13, 0)));
        assert!(series.occurs(utc(2030, 3, 13, 13, 0)));
        assert!(!series.occurs(utc(2030, 3, 12, 13, 0)), "the EXDATE");
        assert!(!series.occurs(utc(2030, 3, 13, 14, 0)), "an hour off");
        assert!(!series.occurs(utc(2030, 3, 15, 13, 0)), "past COUNT");
    }

    #[test]
    fn a_meet_link_is_found_only_in_its_one_shape() {
        assert_eq!(meet_url("Join: <https://meet.google.com/abc-defg-hij?hs=224>").as_deref(), Some("https://meet.google.com/abc-defg-hij"));
        assert_eq!(meet_url("HTTPS://MEET.GOOGLE.COM/ABC-DEFG-HIJ").as_deref(), Some("https://meet.google.com/abc-defg-hij"));
        assert_eq!(meet_url("meet.google.com/abc-defg-hijk"), None);
        assert_eq!(meet_url("https://meet.google.com.evil.example/abc-defg-hij"), None);
        assert_eq!(meet_url("https://evil.meet.google.com/abc-defg-hij"), None);
        assert_eq!(typed_meet_url(" meet.google.com/abc-defg-hij/ ").as_deref(), Some("https://meet.google.com/abc-defg-hij"));
        assert_eq!(typed_meet_url("https://meet.google.com/abc-defg-hij?authuser=1").as_deref(), Some("https://meet.google.com/abc-defg-hij"));
        assert_eq!(typed_meet_url("https://evil.example/?meet.google.com/abc-defg-hij"), None);
        assert_eq!(typed_meet_url("https://meet.google.com/abc-defg-hij-x"), None);
        assert_eq!(typed_meet_url("https://meet.google.com/abc-defg-hij/more"), None);
    }

    #[test]
    fn the_calendar_arithmetic_holds() {
        for days in [-1000, 0, 365, 20_000, 21_000] {
            let (y, m, d) = civil_from_days(days);
            assert_eq!(days_from_civil(y, m, d), days);
        }
        assert_eq!(weekday(days_from_civil(2026, 10, 18)), 0, "2026-10-18 is a Sunday");
        assert_eq!(nth_weekday(2026, 3, 2, 0), Some(days_from_civil(2026, 3, 8)));
        assert_eq!(nth_weekday(2026, 10, -1, 0), Some(days_from_civil(2026, 10, 25)));
        assert_eq!(nth_weekday(2026, 2, 5, 1), None, "no fifth Monday in February 2026");
        assert_eq!(duration("PT1H30M"), Some(5400));
        assert_eq!(duration("P1W"), Some(7 * DAY));
        assert_eq!(offset("+0530"), Some(19_800));
        assert_eq!(text("a\\, b\\; c\\nd\\\\"), "a, b; c\nd\\");
        let prop = content_line("ORGANIZER;CN=\"Lee, Sam: CEO\";ROLE=CHAIR:mailto:sam@example.com").unwrap();
        assert_eq!((prop.param("CN"), prop.param("ROLE"), prop.value.as_str()), (Some("Lee, Sam: CEO"), Some("CHAIR"), "mailto:sam@example.com"));
    }
}
