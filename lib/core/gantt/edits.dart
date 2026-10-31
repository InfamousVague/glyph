/// What each thing done to a Gantt chart writes into its ```gantt fence (format.dart): a bar carried or its ends, a
/// wait drawn or taken off, a task added, taken out, renamed or moved to another row, a person, a colour, how far
/// along. Each answers a [GanttChange]: the lines it writes, by their place in the fence's body, and nothing else, so
/// a bar carried writes over the days between its brackets and the rest of its line, and every other line, stays
/// as it was typed. A ticket's days (`[[KLN-12]]` with no brackets of its own) are the ticket's, and are written into
/// its front matter instead ([GanttTicketWrite]).
///
/// Days are written the way the line had them: a range stays a range, `[2026-11-02 +5d]` keeps its length's form (a
/// bar made longer is `+7d`), and `[+4d]`, which starts after what it waits on, keeps that start while only its end
/// is carried. Pure (test/gantt/edits_test.dart).
library;

import '../item_syntax.dart' show jsTrim;
import 'format.dart';
import 'plan.dart';

/// Lines of a fence's body changed: [remove] of them at [at] (from 0, in the body as it was), [insert] in their place.
class GanttLineChange {
  const GanttLineChange(this.at, this.remove, this.insert);
  final int at;
  final int remove;
  final List<String> insert;

  @override
  bool operator ==(Object other) => other is GanttLineChange && other.at == at && other.remove == remove && other.insert.join('\n') == insert.join('\n');

  @override
  int get hashCode => Object.hash(at, remove, insert.join('\n'));

  @override
  String toString() => 'GanttLineChange($at, $remove, $insert)';
}

/// A ticket's front matter written: each field set, or taken off with null.
class GanttTicketWrite {
  const GanttTicketWrite(this.ticket, this.fields);
  final GanttTicket ticket;
  final Map<String, String?> fields;
}

/// What one thing done to the chart writes: the fence's lines, the tickets' fields; or why it was not done.
class GanttChange {
  const GanttChange({this.lines = const <GanttLineChange>[], this.tickets = const <GanttTicketWrite>[], this.refused, this.select});
  const GanttChange.refused(String this.refused) : lines = const <GanttLineChange>[], tickets = const <GanttTicketWrite>[], select = null;

  final List<GanttLineChange> lines;
  final List<GanttTicketWrite> tickets;

  /// Why nothing was written, in a sentence to show.
  final String? refused;

  /// The line, in the body as it will be, of the task to select once it is written: one added, or moved.
  final int? select;

  bool get isEmpty => lines.isEmpty && tickets.isEmpty;
}

/// [lines] with [change]'s lines written in.
List<String> appliedLines(List<String> lines, GanttChange change) {
  final out = <String>[];
  var at = 0;
  final ordered = [...change.lines]..sort((a, b) => a.at - b.at);
  for (final each in ordered) {
    while (at < each.at && at < lines.length) {
      out.add(lines[at]);
      at += 1;
    }
    out.addAll(each.insert);
    at += each.remove;
  }
  while (at < lines.length) {
    out.add(lines[at]);
    at += 1;
  }
  return out;
}

/// [body] with [change]'s lines written in.
String appliedGantt(String body, GanttChange change) => appliedLines(body.split('\n'), change).join('\n');

/// The fewest lines that make [from] into [to]: what the two share at either end left alone, and in between each
/// line that stayed kept by the longest run the two have in common.
List<GanttLineChange> lineDiff(List<String> from, List<String> to) {
  var head = 0;
  while (head < from.length && head < to.length && from[head] == to[head]) {
    head += 1;
  }
  var tail = 0;
  while (tail < from.length - head && tail < to.length - head && from[from.length - 1 - tail] == to[to.length - 1 - tail]) {
    tail += 1;
  }
  final a = from.sublist(head, from.length - tail);
  final b = to.sublist(head, to.length - tail);
  if (a.isEmpty && b.isEmpty) return const <GanttLineChange>[];
  if (a.isEmpty || b.isEmpty || a.length * b.length > 250000) return <GanttLineChange>[GanttLineChange(head, a.length, b)];
  // The longest run in common, kept; what is between its lines changed.
  final n = a.length, m = b.length;
  final best = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i -= 1) {
    for (var j = m - 1; j >= 0; j -= 1) {
      best[i][j] = a[i] == b[j] ? best[i + 1][j + 1] + 1 : (best[i + 1][j] >= best[i][j + 1] ? best[i + 1][j] : best[i][j + 1]);
    }
  }
  final changes = <GanttLineChange>[];
  var i = 0, j = 0;
  int? openAt;
  var removed = 0;
  final inserted = <String>[];
  void close() {
    // Lines written over one for one are a change each, so a line next to one that changed is never written too.
    if (openAt != null && removed == inserted.length) {
      for (var k = 0; k < removed; k += 1) {
        changes.add(GanttLineChange(head + openAt! + k, 1, <String>[inserted[k]]));
      }
    } else if (openAt != null) {
      changes.add(GanttLineChange(head + openAt!, removed, <String>[...inserted]));
    }
    openAt = null;
    removed = 0;
    inserted.clear();
  }

  while (i < n || j < m) {
    if (i < n && j < m && a[i] == b[j]) {
      close();
      i += 1;
      j += 1;
    } else if (j < m && (i == n || best[i][j + 1] >= best[i + 1][j])) {
      openAt ??= i;
      inserted.add(b[j]);
      j += 1;
    } else {
      openAt ??= i;
      removed += 1;
      i += 1;
    }
  }
  close();
  return changes;
}

/// The change that makes [body] into [lines], the line to select with it.
GanttChange _to(GanttBody body, List<String> lines, {int? select, List<GanttTicketWrite> tickets = const <GanttTicketWrite>[]}) =>
    GanttChange(lines: lineDiff(body.lines, lines), tickets: tickets, select: select);

/// Which end of a bar was carried: both (the bar), its start, or its end.
enum GanttGrip { move, start, end }

/// The rank a mark has in a line, for one put in where there was none: days, people, tags, a colour, `after:`, how
/// far along.
const Map<String, int> _rank = <String, int>{'dates': 0, 'person': 1, 'tag': 2, 'colour': 3, 'after': 4, 'progress': 5};

/// Where a new mark of [kind] goes in [task]'s line: after the last mark that comes before it, else after the name.
int _placeFor(GanttTaskLine task, String kind) {
  final rank = _rank[kind]!;
  var at = task.nameSpan.to;
  void after(String other, GanttSpan? span) {
    if (span != null && _rank[other]! < rank && span.to > at) at = span.to;
  }

  after('dates', task.dates?.span);
  for (final person in task.people) {
    after('person', person.span);
  }
  for (final tag in task.tags) {
    after('tag', tag.span);
  }
  after('colour', task.colourSpan);
  after('after', task.afterSpan);
  // `after:` reads names to the next mark: a mark put in after it must not be taken for one of them.
  return at;
}

/// [task]'s line with a mark of [kind] set to [words], or taken off with null.
String _withMark(GanttTaskLine task, String kind, GanttSpan? span, String? words) {
  if (span != null) return words == null ? withoutSpan(task.text, span) : withSpan(task.text, span, words);
  if (words == null) return task.text;
  final at = _placeFor(task, kind);
  // Before the first mark after it that comes later in the order, so `@sam after: Design 60%` keeps its order.
  final rank = _rank[kind]!;
  var before = task.text.length + 1;
  void later(String other, GanttSpan? span) {
    if (span != null && _rank[other]! > rank && span.from >= at && span.from < before) before = span.from;
  }

  for (final person in task.people) {
    later('person', person.span);
  }
  for (final tag in task.tags) {
    later('tag', tag.span);
  }
  later('colour', task.colourSpan);
  later('after', task.afterSpan);
  later('progress', task.progressSpan);
  return withInsert(task.text, before <= task.text.length ? before : at, words);
}

/// A length's words for [start] to [end] in the form [dates] had: in weeks where it was and still comes to whole weeks.
({int length, String unit, bool weeks}) _lengthFor(GanttDates? dates, String start, String end, bool workdays) {
  final days = lengthOf(start, end, workdays: workdays);
  final per = workdays ? 5 : 7;
  if (dates != null && dates.weeks && days % per == 0) return (length: days ~/ per, unit: dates.unit, weeks: true);
  final unit = dates == null || dates.weeks ? 'd' : dates.unit;
  return (length: days, unit: unit, weeks: false);
}

/// [task]'s line with its days [start] to [end], written as it had them; [how] says which end moved.
String datesLine(GanttTaskLine task, String start, String end, GanttGrip how, {required bool workdays, bool derived = false}) {
  final dates = task.dates;
  String words;
  if (dates == null) {
    words = task.milestone || start == end ? writeDates(form: DatesForm.day, start: start) : writeDates(form: DatesForm.range, start: start, end: end);
    return withInsert(task.text, task.nameSpan.to, words);
  }
  switch (dates.form) {
    case DatesForm.range:
      words = writeDates(form: DatesForm.range, start: start, end: end, arrow: dates.arrow);
    case DatesForm.day:
      words = task.milestone || start == end ? writeDates(form: DatesForm.day, start: start) : writeDates(form: DatesForm.range, start: start, end: end);
    case DatesForm.length:
      final length = _lengthFor(dates, start, end, workdays);
      words = writeDates(form: DatesForm.length, start: start, length: length.length, unit: length.unit, weeks: length.weeks);
    case DatesForm.lengthOnly:
      final length = _lengthFor(dates, start, end, workdays);
      // Its start is still its waits' while only its end was carried.
      final keep = derived && how == GanttGrip.end;
      words = keep
          ? writeDates(form: DatesForm.lengthOnly, length: length.length, unit: length.unit, weeks: length.weeks)
          : writeDates(form: DatesForm.length, start: start, length: length.length, unit: length.unit, weeks: length.weeks);
  }
  return withSpan(task.text, dates.span, words);
}

/// [key] given the days [start] to [end] by [how], and what waits on it pushed along where the chart follows: every
/// line whose days change, and every ticket's.
GanttChange moveDays(GanttBody body, GanttModel model, String key, String start, String end, {GanttGrip how = GanttGrip.move, bool? follow}) {
  final item = model.byKey[key];
  if (item == null) return const GanttChange();
  if (end.compareTo(start) < 0) (start, end) = (end, start);
  final moves = followed(model, <String, ({String start, String end})>{key: (start: start, end: end)}, follow: follow);
  return _written(body, model, moves, primary: key, how: how);
}

/// The lines and tickets [moves] write.
GanttChange _written(GanttBody body, GanttModel model, Map<String, ({String start, String end})> moves, {String? primary, GanttGrip how = GanttGrip.move, List<String>? lines}) {
  final out = <String>[...(lines ?? body.lines)];
  final tickets = <GanttTicketWrite>[];
  for (final MapEntry(key: key, value: days) in moves.entries) {
    final item = model.byKey[key];
    if (item == null) continue;
    final moved = days.start != item.start || days.end != item.end;
    if (!moved && !item.undated) continue;
    final ticket = item.ticket;
    if (ticket != null) {
      tickets.add(GanttTicketWrite(ticket, <String, String?>{'start': days.start, 'due': days.end}));
      continue;
    }
    final line = item.line;
    if (line == null) continue;
    final task = readTaskLine(out[line], line, -1);
    if (task == null) continue;
    final grip = key == primary ? how : GanttGrip.move;
    // A start that is its waits' moves with them, and its line says nothing of it.
    if (key != primary && item.derivedStart && days.end == _endFor(item, days.start, model.workdays)) continue;
    out[line] = datesLine(task, days.start, days.end, grip, workdays: model.workdays, derived: item.derivedStart);
  }
  return _to(body, out, tickets: tickets);
}

/// The end [item] has from [start], its length kept.
String _endFor(GanttItem item, String start, bool workdays) =>
    item.milestone ? start : endAfter(start, lengthOf(item.start, item.end, workdays: workdays), workdays: workdays);

/// The name [on] is written by in an `after:`: its line's own words, the milestone's mark off.
String _nameFor(GanttBody body, GanttItem on) {
  final line = on.line;
  final task = line == null ? null : body.taskOn(line);
  return task == null ? on.name : jsTrim(task.name);
}

/// [line] of [body] with its `after:` naming [names], or without one for none.
String _withWaits(GanttTaskLine task, List<String> names) => _withMark(task, 'after', task.afterSpan, names.isEmpty ? null : 'after: ${names.join(', ')}');

/// [key] waits on [on]: its `after:` names it, and, where the chart follows, it is pushed along to start after it.
/// Refused, with why, where it would make a loop or already waits on it.
GanttChange addWait(GanttBody body, GanttModel model, String key, String on, {GanttTickets? tickets}) {
  final problem = waitProblem(model, key, on);
  if (problem != null) return GanttChange.refused(problem);
  final item = model.byKey[key]!;
  final other = model.byKey[on]!;
  final task = item.line == null ? null : body.taskOn(item.line!);
  if (task == null) return const GanttChange.refused('That task isn’t one of the fence’s lines.');
  final name = _nameFor(body, other);
  if (name.contains(',')) return GanttChange.refused('“$name” has a comma in its name, which after: can’t name: rename it first.');
  final lines = <String>[...body.lines];
  lines[task.line] = _withWaits(task, <String>[...task.after, name]);
  // Read again with the new wait, and what it moves written over that.
  final again = readGantt(lines.join('\n'));
  final model2 = ganttModelOf(again, today: model.today, tickets: tickets);
  if (!model2.follow) return _to(body, lines);
  final pushed = followed(model2, <String, ({String start, String end})>{on: (start: other.start, end: other.end)});
  pushed.remove(on);
  final written = _written(again, model2, pushed);
  return GanttChange(lines: lineDiff(body.lines, appliedLines(again.lines, written)), tickets: written.tickets);
}

/// [key] no longer waits on [on]: its name taken out of the `after:`, and the `after:` with it where it named only that.
GanttChange removeWait(GanttBody body, GanttModel model, String key, String on) {
  final item = model.byKey[key];
  final other = model.byKey[on];
  if (item == null || other == null || item.line == null || other.line == null) return const GanttChange();
  final task = body.taskOn(item.line!);
  final target = body.taskOn(other.line!);
  if (task == null || target == null) return const GanttChange();
  final names = namesOf(target, other.ticket);
  final kept = [for (final name in task.after) if (!names.contains(ganttKey(name))) name];
  if (kept.length == task.after.length) return const GanttChange();
  final lines = <String>[...body.lines];
  lines[task.line] = _withWaits(task, kept);
  return _to(body, lines);
}

/// The waits [key] has, set to [names] (as typed in its panel): refused where one names no task, itself, or makes a
/// loop.
GanttChange setWaits(GanttBody body, GanttModel model, String key, List<String> names, {GanttTickets? tickets}) {
  final item = model.byKey[key];
  final task = item?.line == null ? null : body.taskOn(item!.line!);
  if (item == null || task == null) return const GanttChange();
  final wanted = [for (final name in names) if (jsTrim(name).isNotEmpty) jsTrim(name)];
  // Each name found, and the loop each would make looked for on the chart as it would be.
  final lines = <String>[...body.lines];
  lines[task.line] = _withWaits(task, wanted);
  final again = readGantt(lines.join('\n'));
  final model2 = ganttModelOf(again, today: model.today, tickets: tickets);
  for (final problem in model2.problems) {
    if (problem.startsWith('Line ${task.line + 1}:') || problem.contains('loop')) {
      if (!model.problems.contains(problem)) return GanttChange.refused(problem.replaceFirst(RegExp(r'^Line \d+: '), ''));
    }
  }
  if (!model2.follow) return _to(body, lines);
  final moved = model2.byKey[key]!;
  final pushed = <String, ({String start, String end})>{};
  for (final on in moved.after) {
    final other = model2.byKey[on]!;
    pushed.addAll(followed(model2, <String, ({String start, String end})>{on: (start: other.start, end: other.end)}));
    pushed.remove(on);
  }
  final written = _written(again, model2, pushed);
  return GanttChange(lines: lineDiff(body.lines, appliedLines(again.lines, written)), tickets: written.tickets);
}

/// The list item a new task's line starts with: the one above it's, or `- `.
String _leadFor(GanttBody body, int? near) {
  if (near != null) {
    final match = RegExp(r'^(\s*)([-*+])(\s+)').firstMatch(body.lines[near]);
    if (match != null) return '${match.group(1)}${match.group(2)} ';
  }
  for (final task in body.tasks) {
    final match = RegExp(r'^(\s*)([-*+])(\s+)').firstMatch(task.text);
    if (match != null) return '${match.group(1)}${match.group(2)} ';
  }
  return '- ';
}

/// A task added: [name] on the days [start] to [end], under [afterKey]'s line, or last in [group] of [model]. Its line
/// is selected.
GanttChange addTask(GanttBody body, GanttModel model, {String? afterKey, int? group, String name = 'New task', required String start, String? end, bool milestone = false}) {
  final last = end ?? start;
  final words = milestone || start == last ? writeDates(form: DatesForm.day, start: start) : writeDates(form: DatesForm.range, start: start, end: last);
  final after = afterKey == null ? null : model.byKey[afterKey]?.line;
  int at;
  if (after != null) {
    at = after + 1;
  } else {
    final chosen = group == null || group < 0 || group >= model.groups.length ? model.groups.length - 1 : group;
    final home = chosen < 0 ? null : model.groups[chosen];
    final lines = [for (final item in home?.items ?? const <GanttItem>[]) if (item.line != null) item.line!];
    if (lines.isNotEmpty) {
      at = lines.reduce((a, b) => a > b ? a : b) + 1;
    } else if (home?.line != null) {
      at = home!.line! + 1;
    } else {
      // The rows above every section: before the first, or at the end of a fence with none.
      at = body.sections.isEmpty ? body.lines.length : body.sections.first.line;
      while (at > 0 && jsTrim(body.lines[at - 1]).isEmpty && body.sections.isNotEmpty) {
        at -= 1;
      }
    }
  }
  // A fence's body that ends in a blank line keeps it last.
  if (after == null && at == body.lines.length && body.lines.isNotEmpty && jsTrim(body.lines.last).isEmpty && body.lines.length > 1) at -= 1;
  final line = '${_leadFor(body, after)}${milestone ? '◆ ' : ''}$name $words';
  final lines = <String>[...body.lines]..insert(at, line);
  if (body.lines.length == 1 && jsTrim(body.lines.first).isEmpty) {
    lines
      ..clear()
      ..add(line);
    return GanttChange(lines: <GanttLineChange>[GanttLineChange(0, 1, <String>[line])], select: 0);
  }
  return GanttChange(lines: <GanttLineChange>[GanttLineChange(at, 0, <String>[line])], select: at);
}

/// [key] taken out: its line, and its name from every `after:` that waits on it.
GanttChange deleteTask(GanttBody body, GanttModel model, String key) {
  final item = model.byKey[key];
  final line = item?.line;
  if (item == null || line == null) return const GanttChange();
  final target = body.taskOn(line);
  if (target == null) return const GanttChange();
  final names = namesOf(target, item.ticket);
  final lines = <String>[...body.lines];
  for (final waiting in model.waiting[key] ?? const <String>[]) {
    final other = model.byKey[waiting]?.line;
    final task = other == null ? null : body.taskOn(other);
    if (task == null) continue;
    lines[task.line] = _withWaits(task, [for (final name in task.after) if (!names.contains(ganttKey(name))) name]);
  }
  final changes = <GanttLineChange>[
    for (final change in lineDiff(body.lines, lines)) change,
    GanttLineChange(line, 1, const <String>[]),
  ];
  return GanttChange(lines: changes);
}

/// [key] renamed [name]: its name's words written over, a milestone's mark kept, and every `after:` that named it
/// renamed with it. A ticket's line keeps its link: its name is the ticket's.
GanttChange renameTask(GanttBody body, GanttModel model, String key, String name) {
  final item = model.byKey[key];
  final task = item?.line == null ? null : body.taskOn(item!.line!);
  final words = jsTrim(name);
  if (item == null || task == null || words.isEmpty || words == task.name) return const GanttChange();
  if (task.link != null) return const GanttChange.refused('A ticket’s name is its own: rename the ticket.');
  final lines = <String>[...body.lines];
  lines[task.line] = withSpan(task.text, task.nameSpan, '${task.milestone ? '◆ ' : ''}$words');
  final old = ganttKey(task.name);
  for (final waiting in model.waiting[key] ?? const <String>[]) {
    final other = model.byKey[waiting]?.line;
    final each = other == null ? null : body.taskOn(other);
    if (each == null) continue;
    lines[each.line] = _withWaits(each, [for (final name in each.after) ganttKey(name) == old ? words : name]);
  }
  return _to(body, lines);
}

/// [key]'s people set: `@` each, where its first was, or after its days. A ticket's line with none of its own writes
/// the ticket's assignee.
GanttChange setPeople(GanttBody body, GanttModel model, String key, List<String> people) {
  final item = model.byKey[key];
  final task = item?.line == null ? null : body.taskOn(item!.line!);
  if (item == null || task == null) return const GanttChange();
  final names = [for (final person in people) jsTrim(person).replaceFirst(RegExp('^@+'), '')].where((name) => name.isNotEmpty).map((name) => name.replaceAll(RegExp(r'\s+'), '-')).toList();
  final ticket = task.link == null ? null : model.byKey[key]?.ticket;
  if (task.people.isEmpty && ticket != null) {
    return GanttChange(tickets: <GanttTicketWrite>[GanttTicketWrite(ticket, <String, String?>{'assignee': names.isEmpty ? null : names.first})]);
  }
  var text = task.text;
  // Every person taken off from the last, then the new ones where the first stood.
  final at = task.people.isEmpty ? null : task.people.first.span.from;
  for (final person in task.people.reversed) {
    text = withoutSpan(text, person.span);
  }
  if (names.isEmpty) return _to(body, <String>[...body.lines]..[task.line] = text);
  final marks = names.map((name) => '@$name').join(' ');
  if (at != null) {
    final place = at > text.length ? text.length : at;
    text = withInsert(text, place, marks);
  } else {
    text = _withMark(task, 'person', null, marks);
  }
  return _to(body, <String>[...body.lines]..[task.line] = text);
}

/// [key]'s progress set, or taken off with null.
GanttChange setProgress(GanttBody body, GanttModel model, String key, int? progress) {
  final item = model.byKey[key];
  final task = item?.line == null ? null : body.taskOn(item!.line!);
  if (task == null || progress == task.progress) return const GanttChange();
  final value = progress == null ? null : '${progress.clamp(0, 100)}%';
  return _to(body, <String>[...body.lines]..[task.line] = _withMark(task, 'progress', task.progressSpan, value));
}

/// [key]'s colour set, or taken off with null for its section's (or person's).
GanttChange setColour(GanttBody body, GanttModel model, String key, String? colour) {
  final item = model.byKey[key];
  final task = item?.line == null ? null : body.taskOn(item!.line!);
  if (task == null || colour == task.colour) return const GanttChange();
  final word = task.colourSpan == null ? 'colour' : RegExp('^colou?r', caseSensitive: false).firstMatch(task.text.substring(task.colourSpan!.from))!.group(0)!;
  return _to(body, <String>[...body.lines]..[task.line] = _withMark(task, 'colour', task.colourSpan, colour == null ? null : '$word: $colour'));
}

/// [key] made a milestone (its mark before its name, one day long) or a task again.
GanttChange setMilestone(GanttBody body, GanttModel model, String key, bool milestone) {
  final item = model.byKey[key];
  final task = item?.line == null ? null : body.taskOn(item!.line!);
  if (item == null || task == null || task.milestone == milestone) return const GanttChange();
  var text = withSpan(task.text, task.nameSpan, '${milestone ? '◆ ' : ''}${task.name}');
  if (milestone && task.dates != null && task.dates!.form != DatesForm.day) {
    final again = readTaskLine(text, task.line, task.section)!;
    text = withSpan(text, again.dates!.span, writeDates(form: DatesForm.day, start: item.start));
  }
  return _to(body, <String>[...body.lines]..[task.line] = text);
}

/// [key]'s days set from its panel: the two days as typed, written in the form its line has.
GanttChange setDays(GanttBody body, GanttModel model, String key, String start, String end) => moveDays(body, model, key, start, end);

/// [key]'s line moved to [group], before [beforeKey]'s line there, or last in it. The line is selected where it lands.
GanttChange moveRow(GanttBody body, GanttModel model, String key, {required int group, String? beforeKey}) {
  final item = model.byKey[key];
  final line = item?.line;
  if (item == null || line == null || group < 0 || group >= model.groups.length) return const GanttChange();
  final before = beforeKey == null ? null : model.byKey[beforeKey]?.line;
  int to;
  if (before != null) {
    to = before;
  } else {
    final home = model.groups[group];
    final lines = [for (final each in home.items) if (each.line != null && each.key != key) each.line!];
    if (lines.isNotEmpty) {
      to = lines.reduce((a, b) => a > b ? a : b) + 1;
    } else if (home.line != null) {
      to = home.line! + 1;
    } else {
      to = body.sections.isEmpty ? body.lines.length : body.sections.first.line;
    }
  }
  if (to == line || to == line + 1) return const GanttChange();
  final text = body.lines[line];
  // Taken out where it was and put in where it goes: two lines, in the body as it was.
  final changes = <GanttLineChange>[GanttLineChange(line, 1, const <String>[]), GanttLineChange(to, 0, <String>[text])]..sort((a, b) => a.at - b.at);
  return GanttChange(lines: changes, select: to > line ? to - 1 : to);
}

/// A front line set (`follow: false`), or taken off with null: where it is, or put in after the front lines at the top.
GanttChange setFront(GanttBody body, String key, String? value) {
  final at = body.frontLines[key];
  final lines = <String>[...body.lines];
  if (at != null) {
    if (value == null) {
      lines.removeAt(at);
    } else {
      final had = RegExp(r'^(\s*)([A-Za-z]+)(\s*:\s*)').firstMatch(lines[at]);
      lines[at] = had == null ? '$key: $value' : '${had.group(1)}${had.group(2)}${had.group(3)}$value';
    }
    return _to(body, lines);
  }
  if (value == null) return const GanttChange();
  var put = 0;
  while (put < lines.length && body.frontLines.containsValue(put)) {
    put += 1;
  }
  return GanttChange(lines: <GanttLineChange>[GanttLineChange(put, 0, <String>['$key: $value'])]);
}
