/// A notebook's cycles, sprints by another name (Matt, 2026-10-31, of the ticket features he chose: "Sprints /
/// cycles … two weeks by default"; docs/TICKETS.md). A cycle is a run of days a notebook's tickets are planned in,
/// and everything about one is plain front matter that any other app shows as it is:
///
///     ---                                   ---
///     book: true                            type: ticket
///     key: KLN                              id: KLN-12
///     cycles: {length: 2w, start: 2026-11-02}   cycle: 2026-C45
///     ---                                   ---
///
/// The notebook says how long its cycles are and the day the first began, and every cycle after it follows on, each
/// named by the year and the ISO week it starts in, `2026-C45`, so a name is a date a person can read and two
/// notebooks that start their cycles the same Monday name them alike. Every notebook has cycles, two weeks long from
/// a Monday all of them share ([cycleAnchor]), unless it says otherwise: `cycles:` as a map across, as a length
/// alone (`cycles: 2w`), or `cycles: off` for none; a length is days or weeks (`14d`, `2w`, `10`). A cycle
/// may be made by hand too: a note with `type: cycle`, a `start:` and an `end:` (or `due:`), whose title is its name
/// (`Sprint 12`), which a ticket names as `cycle: "[[Sprint 12]]"`. Where a note made by hand and a run of the
/// notebook's own cover the same day, the note is the one that day is in.
///
/// A ticket is in one cycle, its `cycle:`: a name, a note link, or nothing. A name of the year-and-week kind is a
/// cycle whatever the notebook says, its days counted from that week's Monday by the notebook's length; any other
/// name that no cycle note has is a cycle with no days, which still groups and filters by its name but is never the
/// current one.
///
/// Pure: the notebook's words and its cycle notes are given, and so is today (test/core/planning/cycles_test.dart).
library;

import '../days.dart' show dateOfDay, daysBetween, isIsoDay, isoDayAfter;
import '../front_matter.dart' show frontMatterValue, unquoted;
import '../item_syntax.dart' show jsTrim;
import '../properties.dart' show linkTargets, withProperty;
import '../title_key.dart' show titleKey;

/// How long a cycle is where the notebook does not say: two weeks.
const int defaultCycleDays = 14;

/// The Monday a notebook's cycles are counted from where it names no start: 1 January 2024, so the cycles of every
/// notebook that says only its length line up, a fortnight's falling on 2 November 2026 (`2026-C45`).
const String cycleAnchor = '2024-01-01';

final RegExp _length = RegExp(r'^(\d+(?:\.\d+)?)\s*(d|day|days|w|wk|wks|week|weeks)?$', caseSensitive: false);

/// A length as a front matter value writes it, in whole days: `14d`, `2w`, `2 weeks`, `10` (days). Null for anything
/// else, and for no days at all.
int? daysOf(String? written) {
  final found = _length.firstMatch(jsTrim(written ?? ''));
  if (found == null) return null;
  final count = double.parse(found.group(1)!);
  final unit = (found.group(2) ?? 'd').toLowerCase();
  final days = (unit.startsWith('w') ? count * 7 : count).round();
  return days > 0 ? days : null;
}

/// How a notebook's cycles run: [days] long, the first starting on [start].
class CycleRule {
  const CycleRule({this.days = defaultCycleDays, this.start = cycleAnchor});
  final int days;
  final String start;

  @override
  bool operator ==(Object other) => other is CycleRule && other.days == days && other.start == start;

  @override
  int get hashCode => Object.hash(days, start);

  @override
  String toString() => 'CycleRule($days days from $start)';
}

const Set<String> _off = {'off', 'no', 'false', 'none', 'never'};
const Set<String> _on = {'on', 'yes', 'true'};
final RegExp _pair = RegExp(r'^\s*([\w-]+)\s*:\s*(.*?)\s*$');

/// The keys of a map written across, `{length: 2w, start: 2026-11-02}`, or under its key, indented.
Map<String, String> _mapOf(String written) {
  final inside = written.startsWith('{') && written.endsWith('}') ? written.substring(1, written.length - 1) : written;
  final map = <String, String>{};
  for (final part in inside.split(RegExp(r'[,\n]'))) {
    final found = _pair.firstMatch(part);
    if (found != null) map[found.group(1)!.toLowerCase()] = unquoted(found.group(2)!);
  }
  return map;
}

/// How a notebook's `cycles:` says its cycles run: two weeks from [cycleAnchor] where it says nothing (every notebook
/// has cycles, as Matt chose, "two weeks by default"), a length alone (`2w`), or a map across (`{length: 2w, start:
/// 2026-11-02}`); null for `off`. A map written under the key, indented, is not read: front matter is read a line at a
/// time here, as Obsidian's properties are, so the map is written across.
CycleRule? cycleRuleFrom(String? written) {
  final said = jsTrim(written ?? '');
  if (_off.contains(said.toLowerCase())) return null;
  if (said.isEmpty || _on.contains(said.toLowerCase())) return const CycleRule();
  final alone = daysOf(said);
  if (alone != null) return CycleRule(days: alone);
  final map = _mapOf(said);
  final days = daysOf(map['length'] ?? map['days'] ?? map['every']) ?? defaultCycleDays;
  final start = jsTrim(map['start'] ?? map['from'] ?? '');
  return CycleRule(days: days, start: isIsoDay(start) ? start : cycleAnchor);
}

/// A notebook's cycles, as its front matter's `cycles:` says ([cycleRuleFrom]); the default for no notebook.
CycleRule? cycleRuleOf(String? notebook) => cycleRuleFrom(notebook == null ? null : frontMatterValue(notebook, 'cycles'));

/// One cycle: its name, its first and last days (null for a name with no days), and the note it was made as, if it
/// was.
class Cycle {
  const Cycle({required this.name, required this.start, required this.end, this.noteId});
  final String name;
  final String? start;

  /// Its last day, in it.
  final String? end;
  final String? noteId;

  /// Whether it has days at all.
  bool get dated => start != null && end != null;

  /// What says it is this cycle and no other: its note, or its name.
  String get key => noteId != null ? 'note:$noteId' : 'name:${titleKey(name)}';

  /// Whether [day] is one of its days.
  bool holds(String day) => dated && day.compareTo(start!) >= 0 && day.compareTo(end!) <= 0;

  /// Whether its last day is before [today].
  bool endedBy(String today) => dated && end!.compareTo(today) < 0;

  /// Its days, first to last; none for a cycle with no days.
  List<String> get days {
    if (!dated) return const [];
    final count = daysBetween(start!, end!) ?? -1;
    return [for (var at = 0; at <= count; at += 1) isoDayAfter(start!, at)!];
  }

  /// How a ticket's `cycle:` names it: its name, or a link to its note.
  String get written => noteId != null ? '[[$name]]' : name;

  @override
  bool operator ==(Object other) => other is Cycle && other.name == name && other.start == start && other.end == end && other.noteId == noteId;

  @override
  int get hashCode => Object.hash(name, start, end, noteId);

  @override
  String toString() => 'Cycle($name, $start…$end${noteId == null ? '' : ', note $noteId'})';
}

// ---- names --------------------------------------------------------------------------------------------------------

/// The ISO week [day] is in, and the year that week is counted in.
({int year, int week}) isoWeekOf(String day) {
  final at = dateOfDay(day)!;
  final date = DateTime.utc(at.year, at.month, at.day);
  // The Thursday of the same week names its year, as ISO 8601 counts weeks.
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final first = DateTime.utc(thursday.year, 1, 1);
  final week = 1 + thursday.difference(first).inDays ~/ 7;
  return (year: thursday.year, week: week);
}

/// The Monday of ISO week [week] of [year].
String? mondayOfWeek(int year, int week) {
  final jan4 = DateTime.utc(year, 1, 4);
  final monday = jan4.subtract(Duration(days: jan4.weekday - 1)).add(Duration(days: 7 * (week - 1)));
  final day = '${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  return isoWeekOf(day).week == week ? day : null;
}

/// The name a cycle starting on [start] has: `2026-C45`.
String cycleNameOn(String start) {
  final week = isoWeekOf(start);
  return '${week.year}-C${week.week.toString().padLeft(2, '0')}';
}

final RegExp _cycleName = RegExp(r'^(\d{4})-C(\d{1,2})$', caseSensitive: false);

/// Whether [name] is a cycle's year-and-week name, in any case.
bool isCycleName(String name) => _cycleName.hasMatch(jsTrim(name));

/// The cycle [rule] makes that [day] is in.
Cycle ruledCycleOn(CycleRule rule, String day) {
  final from = daysBetween(rule.start, day) ?? 0;
  final index = (from / rule.days).floor();
  final start = isoDayAfter(rule.start, index * rule.days)!;
  return Cycle(name: cycleNameOn(start), start: start, end: isoDayAfter(start, rule.days - 1));
}

/// The cycle a year-and-week [name] is: from its week's Monday for [days]. Null for any other name.
Cycle? namedCycle(String name, {int days = defaultCycleDays}) {
  final found = _cycleName.firstMatch(jsTrim(name));
  if (found == null) return null;
  final start = mondayOfWeek(int.parse(found.group(1)!), int.parse(found.group(2)!));
  if (start == null) return null;
  return Cycle(name: cycleNameOn(start), start: start, end: isoDayAfter(start, days - 1));
}

// ---- a notebook's cycles ------------------------------------------------------------------------------------------

/// A cycle made by hand: a note with `type: cycle`, its title its name, its `start:` and its `end:` or `due:`.
Cycle? cycleNoteOf({required String id, required String title, required Map<String, String> props}) {
  if (jsTrim(props['type'] ?? '').toLowerCase() != 'cycle') return null;
  final start = jsTrim(props['start'] ?? '');
  final end = jsTrim(props['end'] ?? props['due'] ?? '');
  final dated = isIsoDay(start) && isIsoDay(end) && end.compareTo(start) >= 0;
  return Cycle(name: jsTrim(title).isEmpty ? id : jsTrim(title), start: dated ? start : null, end: dated ? end : null, noteId: id);
}

/// A notebook's cycles: its rule, if it has one, and the cycle notes it holds (`CycleBook`). What every question
/// about a ticket's cycle is asked of.
class CycleBook {
  CycleBook({this.rule, List<Cycle> notes = const []}) : notes = [...notes]..sort(_byStart);

  /// A notebook that says nothing of cycles still reads a ticket's `2026-C45`, two weeks from that Monday.
  final CycleRule? rule;

  /// The cycles made as notes, the earliest first; those with no days last.
  final List<Cycle> notes;

  static int _byStart(Cycle a, Cycle b) {
    if (a.start == null || b.start == null) return (a.start == null ? 1 : 0) - (b.start == null ? 1 : 0);
    return a.start!.compareTo(b.start!);
  }

  int get _days => rule?.days ?? defaultCycleDays;

  /// Whether the notebook has cycles at all: a rule, or a dated cycle note.
  bool get hasCycles => rule != null || notes.any((cycle) => cycle.dated);

  /// The cycle [day] is in: a note's, else the rule's; null where the notebook has neither.
  Cycle? on(String day) {
    for (final cycle in notes) {
      if (cycle.holds(day)) return cycle;
    }
    final ruled = rule;
    return ruled == null ? null : ruledCycleOn(ruled, day);
  }

  /// The cycle today is in.
  Cycle? current(String today) => on(today);

  /// The cycle after [cycle]: the first note's that starts after it ends, or the rule's that day.
  Cycle? after(Cycle cycle) {
    if (!cycle.dated) return null;
    final next = isoDayAfter(cycle.end!, 1)!;
    for (final each in notes) {
      if (each.dated && each.start!.compareTo(cycle.end!) > 0) return on(next) ?? each;
    }
    return on(next) ?? (rule == null && cycle.noteId == null ? namedCycle(cycleNameOn(next), days: _days) : null);
  }

  /// The cycle before [cycle].
  Cycle? before(Cycle cycle) {
    if (!cycle.dated) return null;
    final last = isoDayAfter(cycle.start!, -1)!;
    final found = on(last);
    if (found != null) return found;
    for (final each in notes.reversed) {
      if (each.dated && each.end!.compareTo(cycle.start!) < 0) return each;
    }
    return null;
  }

  /// The cycle a ticket's `cycle:` names: a cycle note by its title, a year-and-week name (the notebook's length
  /// from that Monday), or a cycle of that name with no days. Null for nothing written.
  Cycle? named(String? written) {
    final targets = linkTargets(written);
    if (targets.isEmpty) return null;
    final target = targets.first;
    final key = titleKey(target);
    for (final cycle in notes) {
      if (titleKey(cycle.name) == key) return cycle;
    }
    final ruled = namedCycle(target, days: _days);
    if (ruled != null) {
      // The rule's own cycle that week, where it has one starting then: its days are the rule's.
      final own = rule == null ? null : ruledCycleOn(rule!, ruled.start!);
      return own != null && own.start == ruled.start ? own : ruled;
    }
    return Cycle(name: target, start: null, end: null);
  }

  /// Whether a ticket's [cycle] is [other]: the same note, or the same days, or the same name.
  static bool same(Cycle? cycle, Cycle? other) {
    if (cycle == null || other == null) return false;
    if (cycle.noteId != null || other.noteId != null) return cycle.noteId == other.noteId;
    if (cycle.dated && other.dated) return cycle.start == other.start && cycle.end == other.end;
    return titleKey(cycle.name) == titleKey(other.name);
  }

  /// The cycles a view of this notebook names, the earliest first: [count] that have ended before today's, today's,
  /// and the next one.
  List<Cycle> around(String today, {int count = 6}) {
    final now = current(today);
    if (now == null) return [for (final cycle in notes) if (cycle.dated) cycle];
    final back = <Cycle>[];
    var at = now;
    for (var i = 0; i < count; i += 1) {
      final was = before(at);
      if (was == null) break;
      back.insert(0, was);
      at = was;
    }
    final next = after(now);
    return [...back, now, ?next];
  }
}

/// A ticket's body moved to [cycle]: its `cycle:` set to the name, or a link to the cycle's note.
String withCycle(String body, Cycle? cycle) => withProperty(body, 'cycle', cycle?.written);

/// "Move 4 unfinished to 2026-C47": what the one action that carries a cycle's unfinished tickets on is called.
String carryWords(int count, Cycle to) => 'Move $count unfinished to ${to.name}';

const List<String> _monthWords = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A cycle's days in words: `2–15 Nov`, `26 Oct – 8 Nov`, `28 Dec 2026 – 10 Jan 2027`; '' for a cycle with none.
String cycleDaysWords(Cycle cycle) {
  if (!cycle.dated) return '';
  final from = dateOfDay(cycle.start!)!, to = dateOfDay(cycle.end!)!;
  if (from.year != to.year) return '${from.day} ${_monthWords[from.month - 1]} ${from.year} – ${to.day} ${_monthWords[to.month - 1]} ${to.year}';
  if (from.month != to.month) return '${from.day} ${_monthWords[from.month - 1]} – ${to.day} ${_monthWords[to.month - 1]}';
  return '${from.day}–${to.day} ${_monthWords[to.month - 1]}';
}
