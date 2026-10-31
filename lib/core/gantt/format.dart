/// A ```gantt fence read as what it says (docs/GANTT.md; Matt, 2026-10-31: "work on making a better gannt chart
/// implementation in markdown replacing the one we have now that's quite hard to interact with"). The fence is a
/// project written as a Markdown list, so it reads as one in any viewer that shows it as text:
///
///     ```gantt
///     title: Waitlist launch
///     workdays: true
///
///     ## Research
///     - Interview five users [2026-11-02 → 2026-11-04] @matt #research 100%
///     - Read the competition [2026-11-03 +3d] @sam
///
///     ## Build
///     - Design the waitlist [2026-11-05 → 2026-11-11] @matt #design after: Interview five users 60%
///     - Build the signup page [+4d] after: Design the waitlist
///     - ◆ Launch [2026-11-20] after: Build the signup page
///     - [[KLN-12]] after: Design the waitlist
///     ```
///
/// - **Front lines** (`title:`, `start:`, `zoom:`, `workdays:`, `today:`, `follow:`, `colour:`), a key and its value on
///   a line of their own, anywhere outside a task.
/// - **Sections** are headings (`## Build`) or a name and a colon alone on a line (`Build:`).
/// - **A task** is a list item: its name, then what it has, each its own mark, in any order: its days in brackets, a
///   person `@matt`, a tag `#design`, `after:` and the names of what it waits on (commas between), `colour: teal`,
///   and how far along it is, `60%`. A name that starts `◆` is a milestone. A name that is a `[[link]]` alone is a
///   ticket, whose days, person and status are the ticket's own until the line gives some of its own.
/// - **Days** are `[start → end]` (both days in it), `[start +5d]` (or `+2w`), `[start]` (one day), or `[+5d]`, which
///   starts the working day after what it waits on ends. `->`, `–`, `..` and `to` are read as the arrow too.
/// - Every other line (a blank, a sentence, a `%%` comment) is kept as it is and drawn as nothing.
///
/// Each mark's place in its line is kept ([GanttSpan]), so a change writes over the one mark it changes and leaves
/// the rest of the line exactly as it was typed (edits.dart). Pure (test/gantt/format_test.dart).
library;

import '../days.dart' show isIsoDay;
import '../item_syntax.dart' show jsTrim;

/// A stretch of a line, [from] to [to], in UTF-16 units.
class GanttSpan {
  const GanttSpan(this.from, this.to);
  final int from;
  final int to;

  @override
  bool operator ==(Object other) => other is GanttSpan && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => '$from-$to';
}

/// How wide a day opens: a week's (a day a column, each dated), a month's (Mondays dated), a quarter's (months named).
enum GanttZoom { week, month, quarter }

/// How a bar is coloured where its line names no colour of its own: by its section, or by its person.
enum GanttColourBy { section, person }

/// How a task's days are written between its brackets.
enum DatesForm {
  /// `[2026-11-02 → 2026-11-06]`: both days in the task.
  range,

  /// `[2026-11-02 +5d]`: a start and a length.
  length,

  /// `[2026-11-02]`: one day, or a milestone's.
  day,

  /// `[+5d]`: a length, from the working day after what it waits on ends.
  lengthOnly,
}

/// A task's days as its brackets have them.
class GanttDates {
  const GanttDates({required this.span, required this.form, this.start, this.end, this.length, this.unit = 'd', this.weeks = false, this.arrow = '→'});

  /// The brackets and what is between them.
  final GanttSpan span;
  final DatesForm form;
  final String? start;

  /// The last day, in the task: `[2026-11-02 → 2026-11-06]` runs five days.
  final String? end;

  /// A length's count and its unit as written (`d`, `w`, `days`, `weeks`), and whether it counts weeks.
  final int? length;
  final String unit;
  final bool weeks;

  /// The arrow as written between the two days, kept when they are written again.
  final String arrow;
}

/// One of a task's marks: its words and where it is.
class GanttMark {
  const GanttMark(this.value, this.span);
  final String value;
  final GanttSpan span;
}

/// A task's line, read.
class GanttTaskLine {
  const GanttTaskLine({
    required this.line,
    required this.text,
    required this.name,
    required this.nameSpan,
    required this.milestone,
    required this.link,
    required this.alias,
    required this.dates,
    required this.people,
    required this.tags,
    required this.after,
    required this.afterSpan,
    required this.progress,
    required this.progressSpan,
    required this.colour,
    required this.colourSpan,
    required this.section,
  });

  /// Its line in the fence's body, from 0.
  final int line;
  final String text;

  /// Its name as written, the milestone's mark taken off, and where the name is (the mark included).
  final String name;
  final GanttSpan nameSpan;
  final bool milestone;

  /// The title a name that is a `[[link]]` alone names, and what it shows (`[[KLN-12|Login]]`); null for words.
  final String? link;
  final String? alias;
  final GanttDates? dates;
  final List<GanttMark> people;
  final List<GanttMark> tags;

  /// The names it waits on, in order, and where `after:` and its names are.
  final List<String> after;
  final GanttSpan? afterSpan;
  final int? progress;
  final GanttSpan? progressSpan;
  final String? colour;
  final GanttSpan? colourSpan;

  /// The section it is under, by its place in [GanttBody.sections]; -1 for one above every section.
  final int section;

  /// Its name as a reader shows it: a link's alias or title, the brackets of any other link off.
  String get shown => alias ?? link ?? name.replaceAllMapped(_linkWords, (m) => m.group(2) ?? m.group(1)!);

  /// The first person, who a bar is coloured by where the chart says so.
  String? get person => people.isEmpty ? null : people.first.value;
}

/// A section: a heading's or a `Name:` line's.
class GanttSection {
  const GanttSection({required this.name, required this.line, required this.heading});
  final String name;
  final int line;

  /// Whether it is a heading (`## Build`) rather than a `Build:` line.
  final bool heading;
}

/// What the front lines say, each already read; null where unsaid.
class GanttFront {
  const GanttFront({this.title, this.start, this.zoom, this.workdays = false, this.today, this.follow = true, this.colourBy = GanttColourBy.section});
  final String? title;
  final String? start;
  final GanttZoom? zoom;
  final bool workdays;
  final String? today;

  /// Whether moving a task pushes along what waits on it (`follow: true`, the default).
  final bool follow;
  final GanttColourBy colourBy;
}

/// A fence's body, read: every line kept, the tasks and sections in order, the front lines by key.
class GanttBody {
  const GanttBody({required this.lines, required this.tasks, required this.sections, required this.front, required this.frontLines, required this.problems});

  final List<String> lines;
  final List<GanttTaskLine> tasks;
  final List<GanttSection> sections;
  final GanttFront front;

  /// The line each front key is on, lower case (`color` as `colour`).
  final Map<String, int> frontLines;

  /// What could not be read, a sentence each, with its line.
  final List<String> problems;

  String get text => lines.join('\n');

  /// The task on [line], or null.
  GanttTaskLine? taskOn(int line) {
    for (final task in tasks) {
      if (task.line == line) return task;
    }
    return null;
  }
}

/// The front lines' keys, as a fence writes them.
const List<String> ganttKeys = <String>['title', 'start', 'zoom', 'workdays', 'today', 'follow', 'colour'];

final RegExp _front = RegExp(r'^\s*(title|start|zoom|workdays|today|follow|colou?r)\s*:\s*(.*?)\s*$', caseSensitive: false);
final RegExp _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$');
final RegExp _colonSection = RegExp(r'^\s*([^\s\-*+#>|`@\[%][^:]*?)\s*:\s*$');
final RegExp _lead = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])(\s+)');
final RegExp _bracket = RegExp(r'\[([^\[\]\n]*)\]');
final RegExp _linkWords = RegExp(r'\[\[([^\[\]|\n]+)(?:\|([^\[\]\n]+))?\]\]');
final RegExp _person = RegExp(r'(?<=^|\s)@([^\s@#\[\],]+)');
final RegExp _tag = RegExp(r'(?<=^|\s)#([^\s@#\[\],%]+)');
final RegExp _progress = RegExp(r'(?<=^|\s)(\d{1,3})\s?%(?=\s|$)');
final RegExp _colour = RegExp(r'(?<=^|\s)colou?r:\s*([A-Za-z]+)(?=\s|$)', caseSensitive: false);
final RegExp _after = RegExp(r'(?<=^|\s)after:', caseSensitive: false);
final RegExp _milestone = RegExp(r'^(◆|◇|<>)\s*');

const String _day = r'(\d{4}-\d{2}-\d{2})';
const String _arrows = r'(→|->|–|—|\.\.|to)';
const String _units = r'(d|w|days?|weeks?)';
final RegExp _range = RegExp('^\\s*$_day\\s*$_arrows\\s*$_day\\s*\$');
final RegExp _length = RegExp('^\\s*$_day\\s*\\+\\s*(\\d+)\\s*$_units?\\s*\$');
final RegExp _lengthOnly = RegExp('^\\s*(?:\\+\\s*(\\d+)\\s*$_units?|(\\d+)\\s*$_units)\\s*\$');
final RegExp _oneDay = RegExp('^\\s*$_day\\s*\$');
final RegExp _looksDated = RegExp(r'\d{4}-\d{1,2}-\d{1,2}');

/// Whether [line] is a task's: a list item.
bool isGanttTask(String line) => _lead.hasMatch(line);

/// Reads a yes or a no; null for neither.
bool? _yes(String value) => switch (value.toLowerCase()) {
  'true' || 'yes' || 'on' || 'y' => true,
  'false' || 'no' || 'off' || 'n' => false,
  _ => null,
};

/// The days between a task's brackets, or null where they are not days. [problem] is told of a day the calendar has not
/// got.
GanttDates? readDates(String inner, GanttSpan span, [void Function(String)? problem]) {
  bool ok(String day) {
    if (isIsoDay(day)) return true;
    problem?.call('$day isn’t a day on the calendar.');
    return false;
  }

  final range = _range.firstMatch(inner);
  if (range != null) {
    if (!ok(range.group(1)!) || !ok(range.group(3)!)) return null;
    return GanttDates(span: span, form: DatesForm.range, start: range.group(1), end: range.group(3), arrow: range.group(2)!);
  }
  final length = _length.firstMatch(inner);
  if (length != null) {
    if (!ok(length.group(1)!)) return null;
    final unit = length.group(3) ?? 'd';
    return GanttDates(span: span, form: DatesForm.length, start: length.group(1), length: int.parse(length.group(2)!), unit: unit, weeks: unit.startsWith('w'));
  }
  final only = _lengthOnly.firstMatch(inner);
  if (only != null) {
    final count = int.parse(only.group(1) ?? only.group(3)!);
    final unit = only.group(2) ?? only.group(4) ?? 'd';
    return GanttDates(span: span, form: DatesForm.lengthOnly, length: count, unit: unit, weeks: unit.startsWith('w'));
  }
  final day = _oneDay.firstMatch(inner);
  if (day != null) {
    if (!ok(day.group(1)!)) return null;
    return GanttDates(span: span, form: DatesForm.day, start: day.group(1), end: day.group(1));
  }
  if (_looksDated.hasMatch(inner)) problem?.call('[$inner] isn’t days a task can have: write [2026-11-02 → 2026-11-06], [2026-11-02 +5d] or [2026-11-02].');
  return null;
}

/// Whether [at] is inside one of [spans].
bool _inside(int at, List<GanttSpan> spans) => spans.any((span) => at >= span.from && at < span.to);

/// A task's line read, or null where [text] is not a list item.
GanttTaskLine? readTaskLine(String text, int line, int section, [void Function(String)? problem]) {
  final lead = _lead.firstMatch(text);
  if (lead == null) return null;
  final from = lead.end;
  final links = <GanttSpan>[for (final match in _linkWords.allMatches(text)) if (match.start >= from) GanttSpan(match.start, match.end)];
  // Every mark, where it starts and ends; a mark inside a link is the link's words.
  final marks = <({String kind, int from, int to, RegExpMatch match})>[];
  void find(String kind, RegExp pattern) {
    for (final match in pattern.allMatches(text)) {
      if (match.start < from || _inside(match.start, links)) continue;
      marks.add((kind: kind, from: match.start, to: match.end, match: match));
    }
  }

  GanttDates? dates;
  for (final match in _bracket.allMatches(text)) {
    if (match.start < from || _inside(match.start, links)) continue;
    // A link's own brackets are not a task's days.
    if (match.start > 0 && text.codeUnitAt(match.start - 1) == 0x5b) continue;
    if (match.end < text.length && text.codeUnitAt(match.end) == 0x5d) continue;
    final read = readDates(match.group(1)!, GanttSpan(match.start, match.end), problem);
    if (read == null) continue;
    dates ??= read;
    marks.add((kind: 'dates', from: match.start, to: match.end, match: match));
    break;
  }
  find('person', _person);
  find('tag', _tag);
  find('progress', _progress);
  find('colour', _colour);
  find('after', _after);
  marks.sort((a, b) => a.from - b.from);
  final people = <GanttMark>[];
  final tags = <GanttMark>[];
  var after = <String>[];
  GanttSpan? afterSpan;
  int? progress;
  GanttSpan? progressSpan;
  String? colour;
  GanttSpan? colourSpan;
  for (var index = 0; index < marks.length; index += 1) {
    final mark = marks[index];
    switch (mark.kind) {
      case 'person':
        people.add(GanttMark(mark.match.group(1)!, GanttSpan(mark.from, mark.to)));
      case 'tag':
        tags.add(GanttMark(mark.match.group(1)!, GanttSpan(mark.from, mark.to)));
      case 'progress':
        final value = int.parse(mark.match.group(1)!);
        progress ??= value > 100 ? 100 : value;
        progressSpan ??= GanttSpan(mark.from, mark.to);
      case 'colour':
        colour ??= mark.match.group(1)!.toLowerCase();
        colourSpan ??= GanttSpan(mark.from, mark.to);
      case 'after':
        // Its names run to the next mark, or the end of the line.
        var to = text.length;
        for (var next = index + 1; next < marks.length; next += 1) {
          if (marks[next].kind == 'after') continue;
          to = marks[next].from;
          break;
        }
        final words = text.substring(mark.to, to);
        var end = to;
        while (end > mark.to && _space(text.codeUnitAt(end - 1))) {
          end -= 1;
        }
        if (afterSpan == null) {
          after = [for (final name in words.split(',')) if (jsTrim(name).isNotEmpty) jsTrim(name)];
          afterSpan = GanttSpan(mark.from, end);
        }
        // What the names took is not marks of their own.
        marks.removeWhere((other) => other.from > mark.from && other.from < to && other.kind != 'after');
    }
  }
  final first = marks.isEmpty ? text.length : marks.first.from;
  var nameEnd = first;
  while (nameEnd > from && _space(text.codeUnitAt(nameEnd - 1))) {
    nameEnd -= 1;
  }
  var name = text.substring(from, nameEnd);
  final stone = _milestone.firstMatch(name);
  if (stone != null) name = name.substring(stone.end);
  final lone = _linkWords.firstMatch(name);
  final isLink = lone != null && lone.start == 0 && lone.end == name.length;
  return GanttTaskLine(
    line: line,
    text: text,
    name: name,
    nameSpan: GanttSpan(from, nameEnd),
    milestone: stone != null,
    link: isLink ? jsTrim(lone.group(1)!) : null,
    alias: isLink && lone.group(2) != null ? jsTrim(lone.group(2)!) : null,
    dates: dates,
    people: people,
    tags: tags,
    after: after,
    afterSpan: afterSpan,
    progress: progress,
    progressSpan: progressSpan,
    colour: colour,
    colourSpan: colourSpan,
    section: section,
  );
}

bool _space(int unit) => unit == 0x20 || unit == 0x09;

/// The fence's body read (between its ``` lines).
GanttBody readGantt(String body) {
  final lines = body.split('\n');
  final tasks = <GanttTaskLine>[];
  final sections = <GanttSection>[];
  final frontLines = <String, int>{};
  final problems = <String>[];
  String? title, start, today;
  GanttZoom? zoom;
  var workdays = false, follow = true;
  var colourBy = GanttColourBy.section;
  for (var index = 0; index < lines.length; index += 1) {
    final text = lines[index];
    final said = 'Line ${index + 1}';
    final front = _front.firstMatch(text);
    if (front != null && !isGanttTask(text)) {
      final key = front.group(1)!.toLowerCase().replaceFirst('color', 'colour');
      final value = front.group(2)!;
      frontLines.putIfAbsent(key, () => index);
      switch (key) {
        case 'title':
          title = value.isEmpty ? null : value;
        case 'start':
          if (value.isEmpty) break;
          if (isIsoDay(value)) {
            start = value;
          } else {
            problems.add('$said: start: wants a day, like 2026-11-02.');
          }
        case 'today':
          if (value.isEmpty) break;
          if (isIsoDay(value)) {
            today = value;
          } else {
            problems.add('$said: today: wants a day, like 2026-11-02.');
          }
        case 'zoom':
          if (value.isEmpty) break;
          final found = GanttZoom.values.where((each) => each.name == value.toLowerCase()).firstOrNull;
          if (found == null) problems.add('$said: zoom: is week, month or quarter.');
          zoom = found ?? zoom;
        case 'workdays':
          final yes = _yes(value);
          if (yes == null && value.isNotEmpty) problems.add('$said: workdays: is true or false.');
          workdays = yes ?? workdays;
        case 'follow':
          final yes = _yes(value);
          if (yes == null && value.isNotEmpty) problems.add('$said: follow: is true or false.');
          follow = yes ?? follow;
        case 'colour':
          final word = value.toLowerCase();
          if (word == 'person' || word == 'people' || word == 'assignee') {
            colourBy = GanttColourBy.person;
          } else if (word == 'section' || word.isEmpty) {
            colourBy = GanttColourBy.section;
          } else {
            problems.add('$said: colour: is section or person.');
          }
      }
      continue;
    }
    final heading = _heading.firstMatch(text);
    if (heading != null && jsTrim(heading.group(2)!).isNotEmpty) {
      sections.add(GanttSection(name: jsTrim(heading.group(2)!), line: index, heading: true));
      continue;
    }
    final colon = _colonSection.firstMatch(text);
    if (colon != null && !isGanttTask(text)) {
      sections.add(GanttSection(name: jsTrim(colon.group(1)!), line: index, heading: false));
      continue;
    }
    final task = readTaskLine(text, index, sections.length - 1, (problem) => problems.add('$said: $problem'));
    if (task != null) tasks.add(task);
  }
  return GanttBody(
    lines: lines,
    tasks: tasks,
    sections: sections,
    front: GanttFront(title: title, start: start, zoom: zoom, workdays: workdays, today: today, follow: follow, colourBy: colourBy),
    frontLines: frontLines,
    problems: problems,
  );
}

/// How a name is matched: by its words, lower case, the brackets of a link and a milestone's mark off.
String ganttKey(String name) {
  var words = jsTrim(name);
  final stone = _milestone.firstMatch(words);
  if (stone != null) words = words.substring(stone.end);
  words = words.replaceAllMapped(_linkWords, (m) => m.group(1)!);
  return jsTrim(words).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// The days written between brackets, in [form]: the arrow, a length's unit as the line had them.
String writeDates({required DatesForm form, String? start, String? end, int? length, String unit = 'd', bool weeks = false, String arrow = '→'}) {
  String size() {
    final count = length ?? 1;
    if (weeks) return '+$count$unit';
    return '+$count${unit.startsWith('day') ? (count == 1 ? 'day' : 'days') : unit.startsWith('d') ? 'd' : unit}';
  }

  final space = arrow == '..' ? '' : ' ';
  return switch (form) {
    DatesForm.range => '[$start$space$arrow$space$end]',
    DatesForm.length => '[$start ${size()}]',
    DatesForm.day => '[$start]',
    DatesForm.lengthOnly => '[${size()}]',
  };
}

/// [text] with [span] written over by [insert].
String withSpan(String text, GanttSpan span, String insert) => '${text.substring(0, span.from)}$insert${text.substring(span.to)}';

/// [text] with [span] taken out, and the space before it (or after it, at the start).
String withoutSpan(String text, GanttSpan span) {
  var from = span.from, to = span.to;
  if (from > 0 && _space(text.codeUnitAt(from - 1))) {
    from -= 1;
  } else if (to < text.length && _space(text.codeUnitAt(to))) {
    to += 1;
  }
  return '${text.substring(0, from)}${text.substring(to)}';
}

/// [text] with [insert] put in at [at], a space between it and what is before it.
String withInsert(String text, int at, String insert) {
  final before = text.substring(0, at);
  final after = text.substring(at);
  final lead = before.isEmpty || _space(before.codeUnitAt(before.length - 1)) ? '' : ' ';
  final trail = after.isEmpty || _space(after.codeUnitAt(0)) ? '' : ' ';
  return '$before$lead$insert$trail$after';
}
