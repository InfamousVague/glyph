/// A Mermaid gantt (```mermaid with `gantt` first) written as a ```gantt fence (format.dart), for the Convert to
/// interactive Gantt that a drawn Mermaid gantt offers (lib/editor/diagrams/diagrams.dart). Nothing Mermaid says
/// that the fence can say is lost, and what it cannot is said, a sentence each ([MermaidGantt.notes]):
///
/// - `title` is `title:`, `excludes weekends` is `workdays: true`, `section` a `## heading`, `tickInterval` the zoom
///   it is nearest, `dateFormat` read to turn each day into the fence's `2026-11-02`.
/// - A task's `done` is `100%`, `milestone` its `◆`, `active` and `crit` tags (`#active`, `#crit`). Its id is
///   dropped and every `after id` names the task instead; a task with no start of its own, which Mermaid starts after
///   the task above it, waits on that task by name, as `after:`.
/// - Mermaid's end day is the day after a bar (unless `inclusiveEndDates`), the fence's is the bar's last: one is
///   taken off. `3d`, `2w` are lengths; hours and minutes are rounded to days, and said.
/// - `axisFormat`, `todayMarker`, `weekday`, `displayMode`, a `%%{init}%%` directive, `excludes` of single days,
///   `until`, `click` and `vert` have nothing in the fence to be: each is said, and a `click` or a `%%` comment kept
///   as a line the chart reads as nothing.
///
/// Pure (test/gantt/mermaid_test.dart).
library;

import '../days.dart' show isIsoDay, isoDayAfter;
import '../item_syntax.dart' show jsTrim;

/// A Mermaid gantt as a fence's body, and what could not come with it.
class MermaidGantt {
  const MermaidGantt({required this.body, required this.notes});

  /// What goes between the ```gantt lines.
  final String body;

  /// What Mermaid said that the fence does not, a sentence each; empty where nothing was lost.
  final List<String> notes;
}

/// Whether [code], a ```mermaid fence's, is a gantt: its first line that is not a comment or a directive says so.
bool isMermaidGantt(String code) {
  for (final line in code.split('\n')) {
    final words = jsTrim(line);
    if (words.isEmpty || words.startsWith('%%')) continue;
    return RegExp(r'^gantt\b', caseSensitive: false).hasMatch(words);
  }
  return false;
}

/// A day as `format` (Mermaid's `dateFormat`, dayjs's tokens) writes it, as the fence writes one; null where it is not
/// one, or the format has more than the year, the month and the day.
String? _dayIn(String text, String format) {
  final words = jsTrim(text);
  if (format == 'YYYY-MM-DD') return isIsoDay(words) ? words : null;
  // The format's tokens made into a pattern, each figure caught.
  final order = <String>[];
  final pattern = StringBuffer('^');
  final tokens = RegExp(r'YYYY|YY|MM|M|DD|D|HH|H|mm|m|ss|s|.');
  for (final token in tokens.allMatches(format)) {
    final t = token.group(0)!;
    switch (t) {
      case 'YYYY':
        pattern.write(r'(\d{4})');
        order.add('y');
      case 'YY':
        pattern.write(r'(\d{2})');
        order.add('yy');
      case 'MM' || 'M':
        pattern.write(r'(\d{1,2})');
        order.add('m');
      case 'DD' || 'D':
        pattern.write(r'(\d{1,2})');
        order.add('d');
      case 'HH' || 'H' || 'mm' || 'm' || 'ss' || 's':
        pattern.write(r'(\d{1,2})');
        order.add('t');
      default:
        pattern.write(RegExp.escape(t));
    }
  }
  pattern.write(r'$');
  final match = RegExp(pattern.toString()).firstMatch(words);
  if (match == null) return null;
  int? year, month, day;
  for (var index = 0; index < order.length; index += 1) {
    final value = int.parse(match.group(index + 1)!);
    switch (order[index]) {
      case 'y':
        year = value;
      case 'yy':
        year = 2000 + value;
      case 'm':
        month = value;
      case 'd':
        day = value;
    }
  }
  if (year == null || month == null || day == null) return null;
  final iso = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  return isIsoDay(iso) ? iso : null;
}

/// A Mermaid length (`3d`, `2w`, `36h`) in days, and whether it had to be rounded; null where it is not one.
({int days, bool weeks, bool rounded})? _length(String text) {
  final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(ms|s|m|h|d|w|M|y)\s*$').firstMatch(text);
  if (match == null) return null;
  final count = double.parse(match.group(1)!);
  final unit = match.group(2)!;
  final days = switch (unit) {
    'w' => count * 7,
    'd' => count,
    'h' => count / 24,
    'm' => count / 1440,
    's' => count / 86400,
    'ms' => count / 86400000,
    'M' => count * 30,
    'y' => count * 365,
    _ => count,
  };
  final whole = days.round();
  final rounded = whole != days || unit == 'M' || unit == 'y';
  if (unit == 'w' && count == count.roundToDouble()) return (days: count.round(), weeks: true, rounded: false);
  return (days: whole, weeks: false, rounded: rounded);
}

class _Task {
  _Task(this.name);
  final String name;
  String? id;
  final List<String> tags = <String>[];
  bool done = false;
  bool milestone = false;
  String? start;
  List<String> after = <String>[];
  String? end;
  int? length;
  bool weeks = false;
  String section = '';
}

/// [code], a Mermaid gantt, as a ```gantt fence's body.
MermaidGantt mermaidToGantt(String code) {
  final notes = <String>[];
  void say(String note) {
    if (!notes.contains(note)) notes.add(note);
  }

  var format = 'YYYY-MM-DD';
  var inclusive = false;
  String? title;
  var workdays = false;
  String? zoom;
  final kept = <String>[];
  final tasks = <_Task>[];
  final sections = <String>[];
  var section = '';
  final lines = code.split('\n');
  var first = true;
  for (final raw in lines) {
    final line = jsTrim(raw);
    if (line.isEmpty) continue;
    if (line.startsWith('%%{')) {
      say('Mermaid’s own settings (%%{init}%%) aren’t part of the chart.');
      continue;
    }
    if (line.startsWith('%%')) {
      kept.add(line);
      continue;
    }
    if (first) {
      first = false;
      if (RegExp(r'^gantt\b', caseSensitive: false).hasMatch(line)) continue;
    }
    final keyword = RegExp(r'^(\w+)\b\s*(.*)$').firstMatch(line);
    final word = keyword?.group(1)?.toLowerCase();
    final rest = jsTrim(keyword?.group(2) ?? '');
    switch (word) {
      case 'title':
        title = rest;
        continue;
      case 'dateformat':
        format = rest;
        continue;
      case 'axisformat':
        say('The axis’s format (axisFormat $rest) is the chart’s own now.');
        continue;
      case 'tickinterval':
        final unit = RegExp(r'(day|week|month)').firstMatch(rest)?.group(1);
        zoom = switch (unit) {
          'day' => 'week',
          'week' => 'month',
          'month' => 'quarter',
          _ => null,
        };
        continue;
      case 'excludes':
        for (final part in rest.split(RegExp(r'[,\s]+'))) {
          final what = part.toLowerCase();
          if (what.isEmpty) continue;
          if (what == 'weekends') {
            workdays = true;
          } else {
            say('Days left out one at a time (excludes $part) can’t be: only weekends can, as workdays: true.');
          }
        }
        continue;
      case 'includes':
        say('Days put back in (includes $rest) can’t be.');
        continue;
      case 'inclusiveenddates':
        inclusive = true;
        continue;
      case 'todaymarker':
        if (rest.toLowerCase() == 'off') say('The line at today can’t be turned off.');
        continue;
      case 'weekday' || 'weekend':
        say('Which day starts the week ($word $rest) can’t be set: weeks start on a Monday.');
        continue;
      case 'topaxis':
        say('The days are always along the top.');
        continue;
      case 'section':
        section = rest;
        sections.add(rest);
        continue;
      case 'click':
        kept.add(line);
        say('A click on a bar (click …) does nothing here: the line is kept as words.');
        continue;
      case 'acctitle' || 'accdescr':
        kept.add(line);
        continue;
    }
    if (RegExp(r'^displayMode\s*:', caseSensitive: false).hasMatch(line)) {
      say('Mermaid’s compact rows (displayMode) aren’t: each task has a row.');
      continue;
    }
    if (RegExp(r'^vert\b', caseSensitive: false).hasMatch(line)) {
      say('A line down the days (vert) can’t be: make it a milestone.');
      continue;
    }
    final colon = line.indexOf(':');
    if (colon <= 0) {
      kept.add(line);
      continue;
    }
    final task = _Task(jsTrim(line.substring(0, colon)))..section = section;
    final parts = [for (final part in line.substring(colon + 1).split(',')) jsTrim(part)]..removeWhere((part) => part.isEmpty);
    // The tags first, then an id where three are left, then the start and the end.
    while (parts.isNotEmpty && const <String>['done', 'active', 'crit', 'milestone'].contains(parts.first.toLowerCase())) {
      final tag = parts.removeAt(0).toLowerCase();
      if (tag == 'done') {
        task.done = true;
      } else if (tag == 'milestone') {
        task.milestone = true;
      } else {
        task.tags.add(tag);
      }
    }
    // As Mermaid reads them: three are an id, a start and an end; two a start and an end; one an end.
    if (parts.length >= 3) task.id = parts.removeAt(0);
    String? startWords;
    String? endWords;
    if (parts.length >= 2) {
      startWords = parts[0];
      endWords = parts[1];
    } else if (parts.length == 1) {
      endWords = parts[0];
    }
    if (startWords != null) {
      if (startWords.toLowerCase().startsWith('after ')) {
        task.after = startWords.substring(6).split(RegExp(r'\s+')).where((id) => id.isNotEmpty).toList();
      } else {
        final day = _dayIn(startWords, format);
        if (day == null) {
          say('“$startWords” (${task.name}) isn’t a day in $format: the task starts after the one above it.');
        } else {
          task.start = day;
        }
      }
    }
    if (endWords != null) {
      final length = _length(endWords);
      final day = _dayIn(endWords, format);
      if (length != null) {
        task.length = length.days;
        task.weeks = length.weeks;
        if (length.rounded) say('A length of $endWords (${task.name}) is rounded to whole days.');
      } else if (day != null) {
        // Mermaid's end is the day after the bar, unless its dates are said to be inclusive.
        task.end = inclusive ? day : isoDayAfter(day, -1);
      } else if (endWords.toLowerCase().startsWith('until ')) {
        say('Running until another task starts (${task.name}: $endWords) can’t be: it is a day long.');
      } else {
        say('“$endWords” (${task.name}) isn’t a day or a length.');
      }
    }
    tasks.add(task);
  }
  if (format != 'YYYY-MM-DD' && RegExp(r'[Hhms]').hasMatch(format.replaceAll('MM', '').replaceAll('M', ''))) say('Times of day ($format) aren’t kept: only the days are.');

  // An id named, the task it is; a task with no start waits on the one above it, as Mermaid starts it.
  final byId = <String, _Task>{for (final task in tasks) if (task.id != null) task.id!: task};
  final out = <String>[
    if (title != null && title.isNotEmpty) 'title: $title',
    if (workdays) 'workdays: true',
    if (zoom != null) 'zoom: $zoom',
  ];
  String nameOf(_Task task) => task.name.replaceAll(',', ' ');
  String? lastSection;
  for (var index = 0; index < tasks.length; index += 1) {
    final task = tasks[index];
    if (task.section != (lastSection ?? '') || (lastSection == null && task.section.isNotEmpty)) {
      if (out.isNotEmpty) out.add('');
      if (task.section.isNotEmpty) out.add('## ${task.section}');
      lastSection = task.section;
    }
    lastSection ??= task.section;
    final waits = <String>[];
    for (final id in task.after) {
      final found = byId[id];
      if (found == null) {
        say('“${task.name}” waits on $id, which no task is.');
      } else {
        waits.add(nameOf(found));
      }
    }
    if (task.start == null && task.after.isEmpty && index > 0) waits.add(nameOf(tasks[index - 1]));
    final marks = <String>[];
    final milestone = task.milestone || (task.length == 0 && task.end == null);
    if (task.start != null && task.end != null) {
      marks.add(milestone || task.start == task.end ? '[${task.start}]' : '[${task.start} → ${task.end}]');
    } else if (task.start != null) {
      final count = task.length ?? 1;
      marks.add(milestone ? '[${task.start}]' : (count <= 1 && !task.weeks ? '[${task.start}]' : '[${task.start} +$count${task.weeks ? 'w' : 'd'}]'));
    } else if (task.length != null && !milestone) {
      marks.add('[+${task.length}${task.weeks ? 'w' : 'd'}]');
    } else if (task.end != null) {
      marks.add('[${task.end}]');
    }
    for (final tag in task.tags) {
      marks.add('#$tag');
    }
    if (waits.isNotEmpty) marks.add('after: ${waits.join(', ')}');
    if (task.done) marks.add('100%');
    if (task.name.contains(',')) say('“${task.name}” has a comma in its name, which after: can’t name: it is a space.');
    out.add('- ${milestone ? '◆ ' : ''}${nameOf(task)}${marks.isEmpty ? '' : ' ${marks.join(' ')}'}');
  }
  if (sections.isNotEmpty && tasks.isEmpty) {
    for (final name in sections) {
      out.addAll(<String>['', '## $name']);
    }
  }
  if (kept.isNotEmpty) out.addAll(<String>['', ...kept]);
  while (out.isNotEmpty && out.first.isEmpty) {
    out.removeAt(0);
  }
  return MermaidGantt(body: out.join('\n'), notes: notes);
}
