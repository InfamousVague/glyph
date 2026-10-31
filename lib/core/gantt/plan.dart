/// A Gantt chart worked out in days, from a ```gantt fence (format.dart) or from a query's rows (query.dart): every
/// task's first and last day, what it waits on, its section and its colour, and the days the chart shows. The chart
/// (lib/editor/gantt/gantt_chart.dart) draws a [GanttModel] and nothing else, so a fence and a query are one chart.
///
/// - **A task's days.** Its own when its brackets give them. A length alone (`[+4d]`) or no days at all starts the
///   (working) day after the last of what it waits on ends; with nothing to wait on, on the chart's `start:`, or
///   today. A ticket's line with no days of its own has the ticket's `start:` and `due:`.
/// - **Working days.** With `workdays: true` a length counts Monday to Friday, a start that waits on something skips
///   the weekend, and the weekends are shaded.
/// - **Loops.** A task that waits, however far round, on itself cannot be drawn so: the wait that closes the loop is
///   left out and said ([GanttModel.problems]).
/// - **Following** ([followed]): a task moved later pushes what waits on it along, just far enough to start after it,
///   and so on down; one whose start is its waits' own moves with them either way.
///
/// Pure (test/gantt/plan_test.dart).
library;

import '../days.dart' show dateOfDay, daysBetween, isoDayAfter;
import 'format.dart';

/// A ticket a `[[link]]` names, as the library has it.
class GanttTicket {
  const GanttTicket({required this.noteId, required this.title, this.key, this.start, this.due, this.assignee, this.done = false, this.status});
  final String noteId;
  final String title;
  final String? key;
  final String? start;
  final String? due;
  final String? assignee;
  final bool done;
  final String? status;
}

/// Finds the ticket a link names, by its title or its key; null for none.
typedef GanttTickets = GanttTicket? Function(String title);

/// One bar of the chart.
class GanttItem {
  const GanttItem({
    required this.key,
    required this.name,
    required this.start,
    required this.end,
    required this.group,
    this.label,
    this.milestone = false,
    this.undated = false,
    this.done = false,
    this.late = false,
    this.progress,
    this.person,
    this.colour,
    this.after = const <String>[],
    this.derivedStart = false,
    this.ticket,
    this.line,
    this.tags = const <String>[],
  });

  /// What it is known by while it stays where it is: its line's (`L12`) in a fence, its row's in a query.
  final String key;
  final String name;

  /// A ticket's key shown before its name, `KLN-12`.
  final String? label;

  /// Its first and last days, both in it.
  final String start;
  final String end;

  /// Its section, by its place in [GanttModel.groups].
  final int group;
  final bool milestone;

  /// No days were given and none could be worked out: drawn where it would start, dashed, to be dragged somewhere.
  final bool undated;
  final bool done;
  final bool late;
  final int? progress;
  final String? person;
  final String? colour;

  /// The keys of what it waits on.
  final List<String> after;

  /// Whether its start is its waits' (a length alone, or no days), so it moves with them and its line never needs to.
  final bool derivedStart;

  /// The ticket it is, where its days are the ticket's.
  final GanttTicket? ticket;

  /// Its line in the fence, from 0; null for a query's row.
  final int? line;
  final List<String> tags;

  /// How many days it spans, both ends in.
  int get days => (daysBetween(start, end) ?? 0) + 1;

  GanttItem withDays(String start, String end) => GanttItem(
    key: key,
    name: name,
    start: start,
    end: end,
    group: group,
    label: label,
    milestone: milestone,
    undated: false,
    done: done,
    late: late,
    progress: progress,
    person: person,
    colour: colour,
    after: after,
    derivedStart: derivedStart,
    ticket: ticket,
    line: line,
    tags: tags,
  );
}

/// A section of the chart, and its line in the fence (null for the rows above every section, and for a query's group).
class GanttGroup {
  const GanttGroup({required this.name, required this.items, this.line});
  final String name;
  final List<GanttItem> items;
  final int? line;
}

/// The chart, worked out.
class GanttModel {
  GanttModel({
    required this.groups,
    required this.today,
    this.title,
    this.workdays = false,
    this.follow = true,
    this.zoom,
    this.colourBy = GanttColourBy.section,
    this.problems = const <String>[],
  });

  final List<GanttGroup> groups;
  final String today;
  final String? title;
  final bool workdays;
  final bool follow;
  final GanttZoom? zoom;
  final GanttColourBy colourBy;
  final List<String> problems;

  late final Map<String, GanttItem> byKey = <String, GanttItem>{for (final group in groups) for (final item in group.items) item.key: item};

  /// Every item, in order.
  late final List<GanttItem> items = <GanttItem>[for (final group in groups) ...group.items];

  /// What waits on each item, by its key.
  late final Map<String, List<String>> waiting = () {
    final found = <String, List<String>>{};
    for (final item in items) {
      for (final on in item.after) {
        (found[on] ??= <String>[]).add(item.key);
      }
    }
    return found;
  }();

  /// The first and last days any bar has, or today for none.
  late final ({String first, String last}) span = () {
    String? first, last;
    for (final item in items) {
      if (first == null || item.start.compareTo(first) < 0) first = item.start;
      if (last == null || item.end.compareTo(last) > 0) last = item.end;
    }
    return (first: first ?? today, last: last ?? today);
  }();

  /// Whether [key] waits, however far round, on [on].
  bool waitsOn(String key, String on) {
    final seen = <String>{};
    final queue = <String>[key];
    while (queue.isNotEmpty) {
      final next = byKey[queue.removeLast()];
      if (next == null) continue;
      for (final each in next.after) {
        if (each == on) return true;
        if (seen.add(each)) queue.add(each);
      }
    }
    return false;
  }
}

// ---- working days ------------------------------------------------------------------------------------------------

/// Whether [day] is a Saturday or a Sunday.
bool isWeekend(String day) {
  final date = dateOfDay(day);
  return date != null && date.weekday >= DateTime.saturday;
}

/// [day], or the Monday after it where it is a weekend's.
String workdayFrom(String day) {
  var at = day;
  while (isWeekend(at)) {
    at = isoDayAfter(at, 1)!;
  }
  return at;
}

/// The last day of [count] days from [start] (both in), only the working days counted where [workdays]: three
/// working days from a Thursday end on the Monday.
String endAfter(String start, int count, {required bool workdays}) {
  if (count <= 1) return start;
  if (!workdays) return isoDayAfter(start, count - 1)!;
  var at = workdayFrom(start);
  var left = count - 1;
  while (left > 0) {
    at = isoDayAfter(at, 1)!;
    if (!isWeekend(at)) left -= 1;
  }
  return at;
}

/// How many days [start] to [end] is, both in; only the working days where [workdays] (one at least).
int lengthOf(String start, String end, {required bool workdays}) {
  final all = (daysBetween(start, end) ?? 0) + 1;
  if (!workdays || all <= 1) return all < 1 ? 1 : all;
  var count = 0;
  var at = start;
  for (var n = 0; n < all; n += 1) {
    if (!isWeekend(at)) count += 1;
    at = isoDayAfter(at, 1)!;
  }
  return count < 1 ? 1 : count;
}

/// The day a task that waits on something that ends on [end] can start: the next (working) day.
String dayAfter(String end, {required bool workdays}) {
  final next = isoDayAfter(end, 1)!;
  return workdays ? workdayFrom(next) : next;
}

// ---- a fence's model -------------------------------------------------------------------------------------------------

/// A fence's task's key: its line's.
String ganttLineKey(int line) => 'L$line';

/// The line a key names, or null for a query's row.
int? lineOfKey(String key) => key.startsWith('L') ? int.tryParse(key.substring(1)) : null;

/// Every name a task answers to in an `after:`: its words, its link's title and alias, its ticket's key and title.
List<String> namesOf(GanttTaskLine task, GanttTicket? ticket) => <String>{
  ganttKey(task.name),
  if (task.link != null) ganttKey(task.link!),
  if (task.alias != null) ganttKey(task.alias!),
  if (ticket?.key != null) ganttKey(ticket!.key!),
  if (ticket != null) ganttKey(ticket.title),
}.where((name) => name.isNotEmpty).toList();

/// The chart a fence's [body] draws, on [today] (the fence's own `today:` first), its links' tickets found by
/// [tickets].
GanttModel ganttModelOf(GanttBody body, {required String today, GanttTickets? tickets}) {
  final front = body.front;
  final now = front.today ?? today;
  final workdays = front.workdays;
  final problems = <String>[...body.problems];
  final ticketOf = <int, GanttTicket?>{for (final task in body.tasks) task.line: task.link == null || tickets == null ? null : tickets(task.link!)};
  // Each name, the first task that answers to it.
  final named = <String, GanttTaskLine>{};
  for (final task in body.tasks) {
    for (final name in namesOf(task, ticketOf[task.line])) {
      named.putIfAbsent(name, () => task);
    }
  }
  // What each task waits on, by line, a name no task answers to said once.
  final waits = <int, List<int>>{};
  for (final task in body.tasks) {
    final on = <int>[];
    for (final name in task.after) {
      final found = named[ganttKey(name)];
      if (found == null) {
        problems.add('Line ${task.line + 1}: no task is called “$name”.');
      } else if (found.line == task.line) {
        problems.add('Line ${task.line + 1}: “${task.shown}” can’t wait on itself.');
      } else if (!on.contains(found.line)) {
        on.add(found.line);
      }
    }
    waits[task.line] = on;
  }
  // A loop's closing wait is left out: found by walking each task's waits in order.
  final state = <int, int>{};
  void walk(int line, List<int> path) {
    state[line] = 1;
    final on = waits[line]!;
    for (final next in <int>[...on]) {
      if (state[next] == 1) {
        on.remove(next);
        final looped = [...path.skipWhile((each) => each != next), line].map((each) => '“${body.taskOn(each)!.shown}”');
        problems.add('${looped.join(' waits on ')} waits on “${body.taskOn(next)!.shown}”, which is a loop: that last wait is left out.');
        continue;
      }
      if (state[next] == null) walk(next, [...path, line]);
    }
    state[line] = 2;
  }

  for (final task in body.tasks) {
    if (state[task.line] == null) walk(task.line, const <int>[]);
  }

  // Each task's days, its waits worked out first.
  final days = <int, ({String start, String end, bool derived, bool undated})>{};
  ({String start, String end, bool derived, bool undated}) daysOf(GanttTaskLine task) {
    final known = days[task.line];
    if (known != null) return known;
    final ticket = ticketOf[task.line];
    final dates = task.dates;
    String? waited;
    for (final on in waits[task.line]!) {
      final end = daysOf(body.taskOn(on)!).end;
      if (waited == null || end.compareTo(waited) > 0) waited = end;
    }
    final after = waited == null ? null : dayAfter(waited, workdays: workdays);
    final fallback = front.start ?? now;
    String start;
    String end;
    var derived = false;
    var undated = false;
    if (dates != null && dates.start != null) {
      start = dates.start!;
      if (dates.form == DatesForm.range) {
        end = dates.end!;
        if (end.compareTo(start) < 0) (start, end) = (end, start);
      } else if (dates.form == DatesForm.length) {
        end = endAfter(start, _count(dates, workdays), workdays: workdays);
      } else {
        end = start;
      }
    } else if (dates != null) {
      // A length alone: from the day after what it waits on.
      start = after ?? fallback;
      if (workdays) start = workdayFrom(start);
      end = endAfter(start, _count(dates, workdays), workdays: workdays);
      derived = after != null;
    } else if (ticket != null && (ticket.start != null || ticket.due != null)) {
      start = ticket.start ?? ticket.due!;
      end = ticket.due ?? ticket.start!;
      if (end.compareTo(start) < 0) (start, end) = (end, start);
    } else {
      start = after ?? fallback;
      end = start;
      derived = after != null;
      undated = after == null;
    }
    final found = (start: start, end: task.milestone ? start : end, derived: derived, undated: undated);
    days[task.line] = found;
    return found;
  }

  final groups = <GanttGroup>[];
  final above = body.tasks.where((task) => task.section < 0).toList();
  GanttItem itemOf(GanttTaskLine task, int group) {
    final had = daysOf(task);
    final ticket = ticketOf[task.line];
    final done = (task.progress ?? 0) >= 100 || (ticket?.done ?? false);
    return GanttItem(
      key: ganttLineKey(task.line),
      name: ticket != null && task.alias == null ? ticket.title : task.shown,
      label: ticket?.key != null && ticket!.key != ticket.title ? ticket.key : null,
      start: had.start,
      end: had.end,
      group: group,
      milestone: task.milestone,
      undated: had.undated,
      done: done,
      late: !done && had.end.compareTo(now) < 0 && !task.milestone && (task.progress != null || ticket != null),
      progress: task.progress ?? (ticket?.done ?? false ? 100 : null),
      person: task.person ?? ticket?.assignee,
      colour: task.colour,
      after: [for (final on in waits[task.line]!) ganttLineKey(on)],
      derivedStart: had.derived,
      ticket: ticket != null && (task.dates == null) ? ticket : null,
      line: task.line,
      tags: [for (final tag in task.tags) tag.value],
    );
  }

  if (above.isNotEmpty || body.sections.isEmpty) groups.add(GanttGroup(name: '', items: [for (final task in above) itemOf(task, 0)]));
  for (var index = 0; index < body.sections.length; index += 1) {
    final group = groups.length;
    groups.add(GanttGroup(name: body.sections[index].name, line: body.sections[index].line, items: [for (final task in body.tasks) if (task.section == index) itemOf(task, group)]));
  }
  return GanttModel(groups: groups, today: now, title: front.title, workdays: workdays, follow: front.follow, zoom: front.zoom, colourBy: front.colourBy, problems: problems);
}

/// How many days a length counts: a week five working days, or seven.
int _count(GanttDates dates, bool workdays) {
  final count = dates.length ?? 1;
  return dates.weeks ? count * (workdays ? 5 : 7) : count;
}

// ---- following --------------------------------------------------------------------------------------------------

/// What moves where when [moved] are given new days: those, and, where the chart follows, every task that waits on
/// one of them pushed along just far enough to start after the last of what it waits on, its length kept, and so on
/// down. A task whose start is its waits' ([GanttItem.derivedStart]) goes with them either way. Answers every
/// task's new days, the moved ones' included, by key.
Map<String, ({String start, String end})> followed(GanttModel model, Map<String, ({String start, String end})> moved, {bool? follow}) {
  final next = <String, ({String start, String end})>{...moved};
  if (!(follow ?? model.follow)) return next;
  final workdays = model.workdays;
  ({String start, String end}) daysOf(String key) {
    final item = model.byKey[key]!;
    return next[key] ?? (start: item.start, end: item.end);
  }

  // In order of what waits on what, so a task is placed once everything it waits on is.
  final queue = <String>[...moved.keys];
  var guard = 0;
  while (queue.isNotEmpty && guard < 100000) {
    guard += 1;
    final key = queue.removeAt(0);
    for (final waiting in model.waiting[key] ?? const <String>[]) {
      final item = model.byKey[waiting];
      if (item == null || moved.containsKey(waiting)) continue;
      String? latest;
      for (final on in item.after) {
        if (model.byKey[on] == null) continue;
        final end = daysOf(on).end;
        if (latest == null || end.compareTo(latest) > 0) latest = end;
      }
      if (latest == null) continue;
      final earliest = dayAfter(latest, workdays: workdays);
      final had = daysOf(waiting);
      String start;
      if (item.derivedStart) {
        start = earliest;
      } else if (had.start.compareTo(earliest) < 0) {
        start = earliest;
      } else {
        continue;
      }
      if (start == had.start) continue;
      final length = lengthOf(had.start, had.end, workdays: workdays);
      final end = item.milestone ? start : (workdays ? endAfter(start, length, workdays: true) : isoDayAfter(start, (daysBetween(had.start, had.end) ?? 0))!);
      next[waiting] = (start: start, end: end);
      queue.add(waiting);
    }
  }
  return next;
}

/// Why [key] cannot wait on [on], in a sentence; null where it can.
String? waitProblem(GanttModel model, String key, String on) {
  final item = model.byKey[key];
  final other = model.byKey[on];
  if (item == null || other == null) return 'That task isn’t on the chart.';
  if (key == on) return '“${item.name}” can’t wait on itself.';
  if (item.after.contains(on)) return '“${item.name}” already waits on “${other.name}”.';
  if (model.waitsOn(on, key)) return 'That would make a loop: “${other.name}” already waits on “${item.name}”.';
  return null;
}
