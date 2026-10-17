/// An iCalendar file read (RFC 5545), and its events laid out over the days the app shows (docs/CALENDAR.md, "Reading
/// a calendar, with nothing to set up"). Matt, 2026-10-17: "add Google calendar support"; a calendar's secret iCal
/// address is the way that works the day it ships, and any calendar that publishes one works the same.
///
/// What is read:
/// - **The lines**, unfolded: a line that starts with a space or a tab goes on the one before it, less that one
///   character ([unfoldIcs]). A property is its name, its parameters (a quoted value may hold `;`, `:` and `,`) and
///   its value ([IcsProperty.parse]); a text value has its escapes undone (`\n`, `\,`, `\;`, `\\`: [icsText]).
/// - **The components**, nested as written ([IcsComponent]): VCALENDAR, VEVENT, VTIMEZONE with its STANDARD and
///   DAYLIGHT, and anything else kept and not read.
/// - **An event**: UID, SUMMARY, LOCATION, DESCRIPTION, STATUS (a cancelled one is not shown), DTSTART and DTEND or
///   DURATION, RRULE, RDATE, EXDATE and RECURRENCE-ID.
/// - **Times** as the file writes them: a DATE (`20261017`, all day), a DATE-TIME in UTC (`…T090000Z`), one with a
///   TZID, read through the file's own VTIMEZONE where it has one ([IcsZone]), and a floating one, read on this
///   device's clock. A TZID the file does not describe is UTC where it names UTC, and this device's clock otherwise.
/// - **A rule** (RRULE): FREQ DAILY, WEEKLY, MONTHLY or YEARLY, INTERVAL, COUNT, UNTIL, BYDAY (with an ordinal for
///   a month or a year: `2SU`, `-1FR`), BYMONTH, BYMONTHDAY and WKST. The first instance is DTSTART, as RFC 5545
///   says; COUNT counts it, and EXDATE takes instances out after they are counted.
/// - **A changed instance** of a repeating event (an event with the same UID and a RECURRENCE-ID, which is how Google
///   writes one moved or retitled) takes the place of the instance it names.
///
/// What is laid out ([icsEvents]) is every instance that overlaps the window it is asked for: the app asks for 60
/// days back and 400 ahead ([calendarWindow]). Pure, so every shape of file is a test (test/calendar/ics_test.dart).
library;

/// The days the app keeps events for, around [now]: 60 days back and 400 ahead (docs/CALENDAR.md).
({DateTime from, DateTime to}) calendarWindow(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  return (from: DateTime(day.year, day.month, day.day - 60), to: DateTime(day.year, day.month, day.day + 401));
}

// ---- lines ------------------------------------------------------------------------------------------------------

/// The file's lines, each folded line put back together (RFC 5545 §3.1). Empty lines are left out.
List<String> unfoldIcs(String text) {
  final lines = <String>[];
  final buffer = StringBuffer();
  var has = false;
  for (final raw in text.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.isNotEmpty && (line[0] == ' ' || line[0] == '\t')) {
      buffer.write(line.substring(1));
      continue;
    }
    if (has && buffer.isNotEmpty) lines.add(buffer.toString());
    buffer.clear();
    buffer.write(line);
    has = true;
  }
  if (has && buffer.isNotEmpty) lines.add(buffer.toString());
  return lines;
}

/// A TEXT value with its escapes undone: `\n` and `\N` a new line, `\,` `\;` and `\\` themselves.
String icsText(String value) {
  if (!value.contains(r'\')) return value;
  final out = StringBuffer();
  for (var i = 0; i < value.length; i += 1) {
    final c = value[i];
    if (c != r'\' || i + 1 >= value.length) {
      out.write(c);
      continue;
    }
    final next = value[i + 1];
    i += 1;
    out.write(next == 'n' || next == 'N' ? '\n' : next);
  }
  return out.toString();
}

/// One content line: `DTSTART;TZID=Europe/London:20261017T090000`.
class IcsProperty {
  const IcsProperty(this.name, this.params, this.value);

  /// Upper case.
  final String name;

  /// By upper-case name, the value's quotes off.
  final Map<String, String> params;
  final String value;

  /// [line] read, or null where it has no colon after a name.
  static IcsProperty? parse(String line) {
    var at = 0;
    while (at < line.length && line[at] != ';' && line[at] != ':') {
      at += 1;
    }
    if (at >= line.length || at == 0) return null;
    final name = line.substring(0, at).toUpperCase();
    final params = <String, String>{};
    while (at < line.length && line[at] == ';') {
      at += 1;
      final eq = line.indexOf('=', at);
      if (eq < 0) return null;
      final key = line.substring(at, eq).toUpperCase();
      at = eq + 1;
      final value = StringBuffer();
      // A parameter may hold several values, each quoted or not: kept as written between them, quotes off.
      while (at < line.length && line[at] != ';' && line[at] != ':') {
        if (line[at] == '"') {
          final close = line.indexOf('"', at + 1);
          if (close < 0) return null;
          value.write(line.substring(at + 1, close));
          at = close + 1;
        } else {
          value.write(line[at]);
          at += 1;
        }
      }
      params[key] = value.toString();
    }
    if (at >= line.length || line[at] != ':') return null;
    return IcsProperty(name, params, line.substring(at + 1));
  }
}

/// A component and what is in it, as written: `BEGIN:VEVENT` … `END:VEVENT`.
class IcsComponent {
  IcsComponent(this.name);

  /// Upper case.
  final String name;
  final List<IcsProperty> properties = [];
  final List<IcsComponent> children = [];

  /// The first property named [name], or null.
  IcsProperty? first(String name) {
    for (final property in properties) {
      if (property.name == name) return property;
    }
    return null;
  }

  Iterable<IcsProperty> all(String name) => properties.where((property) => property.name == name);

  /// The children named [name], all the way down.
  Iterable<IcsComponent> within(String name) sync* {
    for (final child in children) {
      if (child.name == name) yield child;
      yield* child.within(name);
    }
  }
}

/// The file's components, nested as written, under one root of no name. A component never closed is closed at the
/// end of the file; an END for one that is not open is passed over.
IcsComponent readIcs(String text) {
  final root = IcsComponent('');
  final open = <IcsComponent>[root];
  for (final line in unfoldIcs(text)) {
    final property = IcsProperty.parse(line);
    if (property == null) continue;
    if (property.name == 'BEGIN') {
      final child = IcsComponent(property.value.trim().toUpperCase());
      open.last.children.add(child);
      open.add(child);
    } else if (property.name == 'END') {
      final name = property.value.trim().toUpperCase();
      final at = open.lastIndexWhere((each) => each.name == name);
      if (at > 0) open.removeRange(at, open.length);
    } else {
      open.last.properties.add(property);
    }
  }
  return root;
}

// ---- times ------------------------------------------------------------------------------------------------------

/// A wall clock's reading, held in a UTC [DateTime] so that adding days never meets a change of the clocks.
typedef Wall = DateTime;

final RegExp _dateTime = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$');

/// What a DATE or DATE-TIME value says: the wall clock's reading, and whether it is UTC or a date alone.
({Wall wall, bool utc, bool date})? _readTime(String value) {
  final found = _dateTime.firstMatch(value.trim());
  if (found == null) return null;
  final year = int.parse(found.group(1)!), month = int.parse(found.group(2)!), day = int.parse(found.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (found.group(4) == null) return (wall: DateTime.utc(year, month, day), utc: false, date: true);
  final wall = DateTime.utc(year, month, day, int.parse(found.group(4)!), int.parse(found.group(5)!), found.group(6) == null ? 0 : int.parse(found.group(6)!));
  return (wall: wall, utc: found.group(7) != null, date: false);
}

/// Where a wall clock is: what turns its reading into a moment.
abstract class IcsZone {
  const IcsZone();

  /// The moment, in UTC, that [wall] is on this clock.
  DateTime toUtc(Wall wall);

  /// What this clock reads at [moment].
  Wall wallAt(DateTime moment);

  static const IcsZone utc = _Utc();

  /// This device's own clock: a floating time's.
  static const IcsZone device = _Device();
}

class _Utc extends IcsZone {
  const _Utc();
  @override
  DateTime toUtc(Wall wall) => wall;
  @override
  Wall wallAt(DateTime moment) => moment.toUtc();
}

class _Device extends IcsZone {
  const _Device();
  @override
  DateTime toUtc(Wall wall) => DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second).toUtc();
  @override
  Wall wallAt(DateTime moment) {
    final local = moment.toLocal();
    return DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second);
  }
}

/// A change of a VTIMEZONE's clocks: from [at] on, the clock is [offset] ahead of UTC.
typedef _Change = ({DateTime at, Duration offset});

/// A VTIMEZONE: its STANDARD and DAYLIGHT parts, each a change of the clocks at its DTSTART and as its RRULE and
/// RDATEs repeat it. The changes are worked out for the years asked about, and kept.
class VTimezone extends IcsZone {
  VTimezone(this.id, List<IcsComponent> parts) : _parts = parts;

  final String id;
  final List<IcsComponent> _parts;
  final Map<int, List<_Change>> _years = {};

  static Duration? _offset(String? value) {
    final found = RegExp(r'^([+-])(\d{2})(\d{2})(\d{2})?$').firstMatch((value ?? '').trim());
    if (found == null) return null;
    final size = Duration(hours: int.parse(found.group(2)!), minutes: int.parse(found.group(3)!), seconds: found.group(4) == null ? 0 : int.parse(found.group(4)!));
    return found.group(1) == '-' ? -size : size;
  }

  /// Every change from the year before [year] to the year after, in order.
  List<_Change> _around(int year) => _years[year] ??= () {
        final changes = <_Change>[];
        final from = DateTime.utc(year - 1), to = DateTime.utc(year + 2);
        for (final part in _parts) {
          final before = _offset(part.first('TZOFFSETFROM')?.value);
          final after = _offset(part.first('TZOFFSETTO')?.value);
          final start = _readTime(part.first('DTSTART')?.value ?? '');
          if (after == null || start == null) continue;
          final onsets = <Wall>[start.wall];
          final rule = part.first('RRULE');
          if (rule != null) {
            final read = RecurRule.parse(rule.value);
            if (read != null) {
              onsets
                ..clear()
                ..addAll(read.instances(start.wall, IcsZone.utc, until: to.add(const Duration(days: 400))).where((wall) => !wall.isBefore(from)));
            }
          }
          for (final rdate in part.all('RDATE')) {
            for (final value in rdate.value.split(',')) {
              final read = _readTime(value);
              if (read != null) onsets.add(read.wall);
            }
          }
          for (final onset in onsets) {
            if (onset.isBefore(from) && rule != null) continue;
            // An onset is written on the clock as it was before the change.
            changes.add((at: onset.subtract(before ?? after), offset: after));
          }
        }
        changes.sort((a, b) => a.at.compareTo(b.at));
        return changes;
      }();

  Duration _offsetAtMoment(DateTime moment) {
    final changes = _around(moment.year);
    if (changes.isEmpty) return Duration.zero;
    var offset = _firstFrom() ?? changes.first.offset;
    for (final change in changes) {
      if (change.at.isAfter(moment)) break;
      offset = change.offset;
    }
    return offset;
  }

  /// The clock before any change is known: the earliest part's TZOFFSETFROM.
  Duration? _firstFrom() {
    Wall? earliest;
    Duration? from;
    for (final part in _parts) {
      final start = _readTime(part.first('DTSTART')?.value ?? '');
      if (start == null) continue;
      if (earliest == null || start.wall.isBefore(earliest)) {
        earliest = start.wall;
        from = _offset(part.first('TZOFFSETFROM')?.value);
      }
    }
    return from;
  }

  @override
  DateTime toUtc(Wall wall) {
    // The offset of the moment the wall's reading would be under the offset in force a day before, then once more
    // under the offset that moment has: across a change, the second answer is the clock's after it.
    var offset = _offsetAtMoment(wall.subtract(const Duration(days: 1)));
    for (var i = 0; i < 2; i += 1) {
      final next = _offsetAtMoment(wall.subtract(offset));
      if (next == offset) break;
      offset = next;
    }
    return wall.subtract(offset);
  }

  @override
  Wall wallAt(DateTime moment) {
    final utc = moment.toUtc();
    return utc.add(_offsetAtMoment(utc));
  }
}

const Set<String> _utcNames = {'UTC', 'GMT', 'Z', 'ETC/UTC', 'ETC/GMT', 'ETC/UCT', 'UCT', 'ZULU', 'ETC/ZULU', 'UNIVERSAL', 'ETC/UNIVERSAL', 'COORDINATED UNIVERSAL TIME', 'GREENWICH MEAN TIME'};

/// A time as one of a file's events writes it.
class IcsTime {
  const IcsTime(this.wall, this.zone, {required this.date});

  /// The clock's reading; a date alone at midnight.
  final Wall wall;

  /// Where the clock is; null for a date, which is a day wherever it is read.
  final IcsZone? zone;
  final bool date;

  /// The moment, for a time; a date's midnight on this device's clock.
  DateTime get moment => date ? DateTime(wall.year, wall.month, wall.day) : zone!.toUtc(wall);
}

/// A property's time, read with the zones the file describes: null for one that cannot be read.
IcsTime? icsTime(IcsProperty? property, Map<String, IcsZone> zones) {
  if (property == null) return null;
  final read = _readTime(property.value);
  if (read == null) return null;
  final valueType = property.params['VALUE']?.toUpperCase();
  if (read.date || valueType == 'DATE') return IcsTime(DateTime.utc(read.wall.year, read.wall.month, read.wall.day), null, date: true);
  if (read.utc) return IcsTime(read.wall, IcsZone.utc, date: false);
  return IcsTime(read.wall, zoneNamed(property.params['TZID'], zones), date: false);
}

/// The clock a TZID names: the file's own VTIMEZONE, UTC by one of its names, else this device's.
IcsZone zoneNamed(String? tzid, Map<String, IcsZone> zones) {
  if (tzid == null || tzid.trim().isEmpty) return IcsZone.device;
  final name = tzid.trim();
  final own = zones[name] ?? zones[name.replaceFirst(RegExp(r'^/+'), '')];
  if (own != null) return own;
  if (_utcNames.contains(name.toUpperCase())) return IcsZone.utc;
  return IcsZone.device;
}

/// The VTIMEZONEs a file describes, by their TZID.
Map<String, IcsZone> zonesOf(IcsComponent root) => {
      for (final zone in root.within('VTIMEZONE'))
        if (zone.first('TZID')?.value.trim() case final id? when id.isNotEmpty) id: VTimezone(id, [for (final part in zone.children) if (part.name == 'STANDARD' || part.name == 'DAYLIGHT') part]),
    };

/// A DURATION value (`PT1H30M`, `P1D`, `-PT15M`, `P2W`), or null.
Duration? icsDuration(String value) {
  final found = RegExp(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(value.trim());
  if (found == null || value.trim() == 'P' || value.trim().endsWith('T')) return null;
  int at(int group) => found.group(group) == null ? 0 : int.parse(found.group(group)!);
  final size = Duration(days: at(2) * 7 + at(3), hours: at(4), minutes: at(5), seconds: at(6));
  return found.group(1) == '-' ? -size : size;
}

// ---- rules ------------------------------------------------------------------------------------------------------

/// How often a rule repeats.
enum Freq { daily, weekly, monthly, yearly }

const List<String> _weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// A BYDAY entry: a weekday (1 Monday … 7 Sunday, as [DateTime.weekday]) and, for a month or a year, which of them
/// (`2` the second, `-1` the last); 0 for every one.
typedef ByDay = ({int weekday, int nth});

/// An RRULE read (RFC 5545 §3.3.10), the parts the app lays out.
class RecurRule {
  const RecurRule({required this.freq, this.interval = 1, this.count, this.until, this.untilDate = false, this.byDay = const [], this.byMonth = const [], this.byMonthDay = const [], this.weekStart = DateTime.monday});

  final Freq freq;
  final int interval;
  final int? count;

  /// The last moment an instance may start: a UTC moment, or a wall reading where [untilDate] says it is a date.
  final DateTime? until;
  final bool untilDate;
  final List<ByDay> byDay;
  final List<int> byMonth;
  final List<int> byMonthDay;
  final int weekStart;

  /// [value] read, or null for a rule with no frequency the app lays out (SECONDLY, HOURLY, …).
  static RecurRule? parse(String value) {
    final parts = <String, String>{};
    for (final part in value.split(';')) {
      final eq = part.indexOf('=');
      if (eq > 0) parts[part.substring(0, eq).trim().toUpperCase()] = part.substring(eq + 1).trim();
    }
    final freq = switch (parts['FREQ']?.toUpperCase()) {
      'DAILY' => Freq.daily,
      'WEEKLY' => Freq.weekly,
      'MONTHLY' => Freq.monthly,
      'YEARLY' => Freq.yearly,
      _ => null,
    };
    if (freq == null) return null;
    final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
    final count = int.tryParse(parts['COUNT'] ?? '');
    DateTime? until;
    var untilDate = false;
    final untilRead = _readTime(parts['UNTIL'] ?? '');
    if (untilRead != null) {
      until = untilRead.wall;
      untilDate = untilRead.date || !untilRead.utc;
    }
    final byDay = <ByDay>[];
    for (final day in (parts['BYDAY'] ?? '').split(',')) {
      final found = RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(day.trim().toUpperCase());
      if (found == null) continue;
      byDay.add((weekday: _weekdays.indexOf(found.group(2)!) + 1, nth: int.tryParse(found.group(1) ?? '') ?? 0));
    }
    List<int> numbers(String key) => [
          for (final each in (parts[key] ?? '').split(','))
            if (int.tryParse(each.trim()) case final n? when n != 0) n,
        ];
    final weekStart = _weekdays.indexOf((parts['WKST'] ?? 'MO').toUpperCase());
    return RecurRule(
      freq: freq,
      interval: interval < 1 ? 1 : interval,
      count: count != null && count > 0 ? count : null,
      until: until,
      untilDate: untilDate,
      byDay: byDay,
      byMonth: [for (final m in numbers('BYMONTH')) if (m >= 1 && m <= 12) m],
      byMonthDay: [for (final d in numbers('BYMONTHDAY')) if (d.abs() <= 31) d],
      weekStart: weekStart < 0 ? DateTime.monday : weekStart + 1,
    );
  }

  static int _daysIn(int year, int month) => DateTime.utc(year, month + 1, 0).day;

  /// The [nth] [weekday] of a month (from the end where it is below 0), or null where it has none.
  static int? _nthOfMonth(int year, int month, int weekday, int nth) {
    final days = _daysIn(year, month);
    if (nth > 0) {
      final first = DateTime.utc(year, month, 1).weekday;
      final day = 1 + (weekday - first + 7) % 7 + (nth - 1) * 7;
      return day <= days ? day : null;
    }
    final last = DateTime.utc(year, month, days).weekday;
    final day = days - (last - weekday + 7) % 7 + (nth + 1) * 7;
    return day >= 1 ? day : null;
  }

  /// The days of a month the rule names (BYMONTHDAY, then BYDAY), or [fallback] where it names none.
  List<int> _daysOfMonth(int year, int month, int fallback) {
    final days = _daysIn(year, month);
    if (byMonthDay.isNotEmpty) {
      final named = <int>{
        for (final d in byMonthDay)
          if ((d > 0 ? d : days + d + 1) case final day when day >= 1 && day <= days) day,
      };
      // BYDAY as well only keeps the ones on its weekdays.
      if (byDay.isNotEmpty) named.removeWhere((day) => !byDay.any((each) => each.weekday == DateTime.utc(year, month, day).weekday));
      return named.toList()..sort();
    }
    if (byDay.isNotEmpty) {
      final named = <int>{};
      for (final each in byDay) {
        if (each.nth == 0) {
          for (var day = 1; day <= days; day += 1) {
            if (DateTime.utc(year, month, day).weekday == each.weekday) named.add(day);
          }
        } else if (_nthOfMonth(year, month, each.weekday, each.nth) case final day?) {
          named.add(day);
        }
      }
      return named.toList()..sort();
    }
    return fallback <= days ? [fallback] : const [];
  }

  /// The days of a year a yearly rule with BYDAY and no BYMONTH names: the [nth] weekday of the year.
  List<Wall> _daysOfYear(int year, Wall time) {
    final named = <Wall>[];
    for (final each in byDay) {
      final all = <Wall>[];
      for (var day = DateTime.utc(year); day.year == year; day = day.add(const Duration(days: 1))) {
        if (day.weekday == each.weekday) all.add(day);
      }
      if (each.nth == 0) {
        named.addAll(all);
      } else {
        final at = each.nth > 0 ? each.nth - 1 : all.length + each.nth;
        if (at >= 0 && at < all.length) named.add(all[at]);
      }
    }
    return [for (final day in named) DateTime.utc(day.year, day.month, day.day, time.hour, time.minute, time.second)]..sort();
  }

  /// The instances of one period, from the [k]th after [start]'s, in order.
  List<Wall> _period(Wall start, int k) {
    Wall at(int year, int month, int day) => DateTime.utc(year, month, day, start.hour, start.minute, start.second);
    switch (freq) {
      case Freq.daily:
        final day = start.add(Duration(days: k * interval));
        if (byMonth.isNotEmpty && !byMonth.contains(day.month)) return const [];
        if (byMonthDay.isNotEmpty) {
          final days = _daysIn(day.year, day.month);
          if (!byMonthDay.any((d) => (d > 0 ? d : days + d + 1) == day.day)) return const [];
        }
        if (byDay.isNotEmpty && !byDay.any((each) => each.weekday == day.weekday)) return const [];
        return [day];
      case Freq.weekly:
        final back = (start.weekday - weekStart + 7) % 7;
        final week = DateTime.utc(start.year, start.month, start.day - back + k * 7 * interval, start.hour, start.minute, start.second);
        final days = byDay.isEmpty ? [start.weekday] : {for (final each in byDay) each.weekday}.toList();
        final out = <Wall>[
          for (final weekday in days) DateTime.utc(week.year, week.month, week.day + (weekday - weekStart + 7) % 7, start.hour, start.minute, start.second),
        ];
        return [
          for (final day in out..sort())
            if (byMonth.isEmpty || byMonth.contains(day.month)) day,
        ];
      case Freq.monthly:
        final months = start.year * 12 + start.month - 1 + k * interval;
        final year = months ~/ 12, month = months % 12 + 1;
        if (byMonth.isNotEmpty && !byMonth.contains(month)) return const [];
        return [for (final day in _daysOfMonth(year, month, start.day)) at(year, month, day)];
      case Freq.yearly:
        final year = start.year + k * interval;
        if (byMonth.isEmpty && byMonthDay.isEmpty && byDay.isNotEmpty) return _daysOfYear(year, start);
        final months = byMonth.isNotEmpty ? ([...byMonth]..sort()) : [start.month];
        return [
          for (final month in months)
            for (final day in (byMonthDay.isEmpty && byDay.isEmpty ? (start.day <= _daysIn(year, month) ? [start.day] : const <int>[]) : _daysOfMonth(year, month, start.day))) at(year, month, day),
        ];
    }
  }

  /// Whether an instance at [wall] is past UNTIL.
  bool _pastUntil(Wall wall, IcsZone zone) {
    final until = this.until;
    if (until == null) return false;
    if (untilDate) {
      // A date is the whole of that day; a floating UNTIL is the wall clock's own reading.
      final end = until.hour == 0 && until.minute == 0 && until.second == 0 ? DateTime.utc(until.year, until.month, until.day, 23, 59, 59) : until;
      return wall.isAfter(end);
    }
    return zone.toUtc(wall).isAfter(until);
  }

  /// Every instance from [start] (the first, DTSTART), in order, on [zone]'s clock, until the rule ends, COUNT is
  /// reached, or an instance would be past [until] on the wall's own clock. Never more than [most].
  Iterable<Wall> instances(Wall start, IcsZone zone, {required Wall until, int most = 100000}) sync* {
    var made = 0;
    yield start;
    made += 1;
    if (count != null && made >= count!) return;
    // Periods with nothing in them (a 31st, a February 30th) are passed over, but not forever.
    var empty = 0;
    for (var k = 0; made < most && empty < 2000; k += 1) {
      final period = _period(start, k);
      if (period.isEmpty) {
        empty += 1;
        // A period whose start is past the end has nothing more to give.
        if (k > 0 && _periodStart(start, k).isAfter(until)) return;
        continue;
      }
      empty = 0;
      for (final wall in period) {
        if (!wall.isAfter(start)) continue;
        if (wall.isAfter(until) || _pastUntil(wall, zone)) return;
        yield wall;
        made += 1;
        if (count != null && made >= count!) return;
      }
    }
  }

  Wall _periodStart(Wall start, int k) => switch (freq) {
        Freq.daily => start.add(Duration(days: k * interval)),
        Freq.weekly => start.add(Duration(days: 7 * k * interval)),
        Freq.monthly => DateTime.utc(start.year, start.month + k * interval),
        Freq.yearly => DateTime.utc(start.year + k * interval),
      };
}

// ---- events -----------------------------------------------------------------------------------------------------

/// One instance of an event, laid out.
class IcsEvent {
  const IcsEvent({required this.uid, required this.title, required this.start, required this.end, required this.allDay, this.location, this.description});

  /// The event's UID and, for an instance of a repeating one, its start: one instance's key.
  final String uid;
  final String title;

  /// A time's moment in UTC; a day's midnight on this device's clock. [end] is where it stops, not in it: an
  /// all-day event of one day ends at the next midnight.
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? description;

  @override
  String toString() => 'IcsEvent($uid, $title, $start → $end${allDay ? ', all day' : ''})';
}

/// A file read: its name (`X-WR-CALNAME`) and every instance of its events in the window.
class IcsCalendar {
  const IcsCalendar({required this.name, required this.events});
  final String? name;
  final List<IcsEvent> events;
}

String _key(IcsTime time) => time.date ? 'D${time.wall.toIso8601String().substring(0, 10)}' : 'T${time.moment.toUtc().millisecondsSinceEpoch}';

String _keyOfWall(Wall wall, IcsTime like) => like.date ? 'D${wall.toIso8601String().substring(0, 10)}' : 'T${like.zone!.toUtc(wall).millisecondsSinceEpoch}';

/// The times a property lists (EXDATE, RDATE): each value, read as the property's parameters say.
List<IcsTime> _timesIn(IcsProperty property, Map<String, IcsZone> zones) => [
      for (final value in property.value.split(','))
        ?icsTime(IcsProperty(property.name, property.params, value), zones),
    ];

/// Every instance of [root]'s events that overlaps [from] to [to], ordered by start.
List<IcsEvent> icsEvents(IcsComponent root, {required DateTime from, required DateTime to}) {
  final zones = zonesOf(root);
  final events = root.within('VEVENT').toList();
  // The instances of a repeating event that were changed, by UID and the instance they replace.
  final changed = <String, Set<String>>{};
  for (final event in events) {
    final uid = event.first('UID')?.value;
    final instance = icsTime(event.first('RECURRENCE-ID'), zones);
    if (uid != null && instance != null) (changed[uid] ??= {}).add(_key(instance));
  }
  final out = <IcsEvent>[];
  final fromUtc = from.toUtc(), toUtc = to.toUtc();
  for (final event in events) {
    if (event.first('STATUS')?.value.trim().toUpperCase() == 'CANCELLED') continue;
    final start = icsTime(event.first('DTSTART'), zones);
    if (start == null) continue;
    final uid = event.first('UID')?.value.trim() ?? '';
    final title = icsText(event.first('SUMMARY')?.value ?? '').trim();
    final location = icsText(event.first('LOCATION')?.value ?? '').trim();
    final description = icsText(event.first('DESCRIPTION')?.value ?? '').trim();
    final endTime = icsTime(event.first('DTEND'), zones);
    final duration = icsDuration(event.first('DURATION')?.value ?? '');
    // How long each instance is: to DTEND, or DURATION; a day for a date with neither, and no time for a time.
    final Duration length;
    if (endTime != null && endTime.date == start.date) {
      length = start.date ? endTime.wall.difference(start.wall) : endTime.moment.difference(start.moment);
    } else if (duration != null) {
      length = duration;
    } else {
      length = start.date ? const Duration(days: 1) : Duration.zero;
    }
    final safe = length.isNegative ? Duration.zero : length;
    final recurrenceId = icsTime(event.first('RECURRENCE-ID'), zones);
    final skip = <String>{
      for (final exdate in event.all('EXDATE'))
        for (final time in _timesIn(exdate, zones)) ...[_key(time), if (time.date && !start.date) 'D${time.wall.toIso8601String().substring(0, 10)}'],
      if (recurrenceId == null) ...?changed[uid],
    };

    void add(Wall wall) {
      final key = _keyOfWall(wall, start);
      if (skip.contains(key)) return;
      if (!start.date && skip.contains('D${wall.toIso8601String().substring(0, 10)}')) return;
      final DateTime begins, ends;
      if (start.date) {
        begins = DateTime(wall.year, wall.month, wall.day);
        final last = wall.add(safe.inDays > 0 ? Duration(days: safe.inDays) : const Duration(days: 1));
        ends = DateTime(last.year, last.month, last.day);
      } else {
        begins = start.zone!.toUtc(wall);
        ends = begins.add(safe);
      }
      final overlaps = ends.isAfter(begins) ? ends.toUtc().isAfter(fromUtc) && begins.toUtc().isBefore(toUtc) : !begins.toUtc().isBefore(fromUtc) && begins.toUtc().isBefore(toUtc);
      if (!overlaps) return;
      out.add(IcsEvent(
        uid: '$uid/${start.date ? wall.toIso8601String().substring(0, 10) : begins.toUtc().toIso8601String()}',
        title: title.isEmpty ? 'Untitled event' : title,
        start: begins,
        end: ends,
        allDay: start.date,
        location: location.isEmpty ? null : location,
        description: description.isEmpty ? null : description,
      ));
    }

    final rule = recurrenceId == null ? event.first('RRULE') : null;
    final read = rule == null ? null : RecurRule.parse(rule.value);
    // The window's end on the event's own clock, a day over for a clock ahead of this device's.
    final zone = start.zone ?? IcsZone.device;
    final until = zone.wallAt(toUtc).add(const Duration(days: 1));
    if (read == null) {
      add(start.wall);
    } else {
      for (final wall in read.instances(start.wall, zone, until: until)) {
        add(wall);
      }
    }
    if (recurrenceId == null) {
      for (final rdate in event.all('RDATE')) {
        if (rdate.params['VALUE']?.toUpperCase() == 'PERIOD') continue;
        for (final time in _timesIn(rdate, zones)) {
          // An RDATE on another clock is the same moment on this event's.
          add(start.date || time.date ? DateTime.utc(time.wall.year, time.wall.month, time.wall.day, start.wall.hour, start.wall.minute, start.wall.second) : start.zone!.wallAt(time.moment));
        }
      }
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  // An instance named twice (an RDATE that is also the rule's) is shown once.
  final seen = <String>{};
  return [
    for (final event in out)
      if (seen.add(event.uid)) event,
  ];
}

/// An .ics file's text read, and its events laid out over [from] to [to].
IcsCalendar parseIcs(String text, {required DateTime from, required DateTime to}) {
  final root = readIcs(text);
  final calendar = root.within('VCALENDAR').firstOrNull ?? root;
  final name = calendar.first('X-WR-CALNAME')?.value;
  return IcsCalendar(name: name == null || icsText(name).trim().isEmpty ? null : icsText(name).trim(), events: icsEvents(root, from: from, to: to));
}
