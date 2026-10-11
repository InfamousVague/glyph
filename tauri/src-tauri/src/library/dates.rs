//! Dates as front matter writes them: `created: 2026-09-14T10:32:10.123Z`,
//! and whatever Obsidian or a person may have written instead - a bare date,
//! a time without seconds, an offset rather than `Z`.
//!
//! Hand-written civil-date arithmetic (Howard Hinnant's algorithms) rather than
//! a date crate, because this is the whole of the need: milliseconds since the
//! epoch to one ISO form and back, in UTC, with no time zones to look up.

/// Milliseconds since the epoch as `2026-09-14T10:32:10.123Z`.
pub fn iso(ms: i64) -> String {
    let secs = ms.div_euclid(1000);
    let millis = ms.rem_euclid(1000);
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    // Howard Hinnant's civil-from-days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!("{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{millis:03}Z", rem / 3600, rem / 60 % 60, rem % 60)
}

/// `2026-09-14`, `2026-09-14T10:32`, `…:10.123Z` or `…+02:00` as milliseconds since the epoch.
pub fn parse_iso(text: &str) -> Option<i64> {
    let text = text.trim();
    let (date, time) = text.split_once(['T', ' ']).unwrap_or((text, ""));
    let mut parts = date.split('-');
    let (year, month, day): (i64, i64, i64) = (parts.next()?.parse().ok()?, parts.next()?.parse().ok()?, parts.next()?.parse().ok()?);
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let mp = if month > 2 { month - 3 } else { month + 9 };
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    let (clock, offset_min) = match time.find(['Z', '+']).or_else(|| time.rfind('-').filter(|&at| at > 5)) {
        Some(at) => {
            let zone = &time[at..];
            let offset = if zone.starts_with('Z') {
                0
            } else {
                let sign = if zone.starts_with('-') { -1 } else { 1 };
                let digits: String = zone[1..].chars().filter(char::is_ascii_digit).collect();
                let hours: i64 = digits.get(0..2).and_then(|h| h.parse().ok()).unwrap_or(0);
                let minutes: i64 = digits.get(2..4).and_then(|m| m.parse().ok()).unwrap_or(0);
                sign * (hours * 60 + minutes)
            };
            (&time[..at], offset)
        }
        None => (time, 0),
    };
    let mut hms = clock.split(':');
    let hours: i64 = hms.next().filter(|h| !h.is_empty()).map_or(Some(0), |h| h.parse().ok())?;
    let minutes: i64 = hms.next().map_or(Some(0), |m| m.parse().ok())?;
    let (seconds, millis) = match hms.next() {
        Some(s) => {
            let (whole, frac) = s.split_once('.').unwrap_or((s, "0"));
            let frac: String = frac.chars().chain("000".chars()).take(3).collect();
            (whole.parse::<i64>().ok()?, frac.parse::<i64>().ok()?)
        }
        None => (0, 0),
    };
    Some(((days * 86_400 + hours * 3600 + minutes * 60 + seconds - offset_min * 60) * 1000) + millis)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates_go_to_front_matter_and_come_back() {
        let at = 1_789_381_930_123;
        let text = iso(at);
        assert_eq!(text, "2026-09-14T10:32:10.123Z");
        assert_eq!(parse_iso(&text), Some(at));
        assert_eq!(parse_iso("2026-09-14"), Some(1_789_344_000_000));
        assert_eq!(parse_iso("2026-09-14T12:32:10.123+02:00"), Some(at));
        assert_eq!(parse_iso("not a date"), None);
    }

    #[test]
    fn an_offset_west_of_greenwich_is_read_as_one() {
        // A `-` in the time is an offset's sign only past `HH:MM`, where a `+` or `Z` would be.
        assert_eq!(parse_iso("2026-09-14T05:32:10.123-05:00"), Some(1_789_381_930_123));
        assert_eq!(parse_iso("2026-09-14T10:32"), Some(1_789_381_920_000), "no seconds is :00");
        assert_eq!(parse_iso("2026-09-14 10:32:10Z"), Some(1_789_381_930_000), "a space for the T, as people write it");
        assert_eq!(parse_iso("2026-13-01"), None, "no thirteenth month");
    }

    #[test]
    fn a_date_before_1970_goes_out_and_comes_back() {
        assert_eq!(iso(-1), "1969-12-31T23:59:59.999Z");
        assert_eq!(parse_iso("1969-12-31T23:59:59.999Z"), Some(-1));
        assert_eq!(iso(0), "1970-01-01T00:00:00.000Z");
        let leap_day = parse_iso("2024-02-29").unwrap();
        assert_eq!(iso(leap_day), "2024-02-29T00:00:00.000Z");
    }
}
