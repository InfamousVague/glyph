/// A query shown as a gantt (`show: gantt`): its records turned into the text of a Mermaid gantt chart
/// (../glyph docs/QUERIES.md, docs/DESIGN.md §159). A port of `src/app/core/query/gantt.ts`.
///
///     gantt
///       dateFormat YYYY-MM-DD
///       axisFormat %e %b
///       section In progress
///       Fix the login loop :active, 2026-09-28, 2026-10-04
///
/// A record is a bar from its start to its due day, the due day drawn whole (Mermaid's end is the start of the day
/// it names, so the bar ends the day after). One with only a due day, or only a start, is a bar of that one day; one
/// with neither is not on the chart, and is counted for the page to say so. Each group is a section; a query not
/// grouped has none, so its bars have the width a section's name would take. A bar is `done` when its record is
/// finished with, `active` when it is under way, and `crit` when it is overdue, which are Mermaid's own words for
/// those, and the chart marks today.
///
/// Laid out for a card on a phone: the ticks a day, a week or a month apart as the bars span days, weeks or months,
/// so their dates never run into each other, and the room Mermaid keeps either side for a desktop's page cut down,
/// in a directive at the top that any other renderer of Mermaid reads too.
///
/// The words are a record's own, so they are made safe for Mermaid's grammar, which reads `:` as the end of a bar's
/// name, `;` and `#` as its own, `%%` as a comment, and a line that starts `section` or `title` as one of those:
/// each is taken out or set apart. Pure (test/query/gantt_test.dart).
///
/// What differs: nothing in what is written. The page hands this text to Mermaid; this app draws a gantt with a
/// painter of its own (docs/STAGES_5_6_8_9.md), which reads the same rows, and the text is what a note keeps when a
/// gantt is copied out, so it is written the same to the letter. What `ganttOf` answers is a [Gantt].
library;

import 'dart:convert';

import '../days.dart' show daysBetween, isoDayAfter;
import '../item_syntax.dart' show jsTrim;
import '../properties.dart' show StatusCategory;
import 'read.dart' show QueryData;
import 'run.dart' show QueryGroup;

/// A gantt's Mermaid text, and how many records it places.
class Gantt extends QueryData {
  const Gantt({required this.code, required this.placed});
  final String code;
  final int placed;
  @override
  Object? toJson() => {'code': code, 'placed': placed};
}

/// The words Mermaid's gantt reads at the start of a line as its own.
final RegExp _keywords = RegExp(
  r'^(?:section|title|dateformat|axisformat|tickinterval|excludes|includes|todaymarker|weekday|weekend|click|acctitle|accdescr|inclusiveenddates|topaxis|displaymode)\b',
  caseSensitive: false,
);
final RegExp _signs = RegExp(r'[:;#\n\r]+');
final RegExp _spaces = RegExp(r'\s+');

/// A record's words as a bar's name, or a group's as a section's: one line Mermaid reads as words.
String ganttWords(String words, String fallback) {
  final lined = jsTrim(words.replaceAll('%%', '%').replaceAll(_signs, ' ').replaceAll(_spaces, ' '));
  final clean = jsTrim(lined.length > 80 ? lined.substring(0, 80) : lined);
  if (clean.isEmpty) return fallback;
  // A no-break space before a name that starts like one of Mermaid's lines keeps it a name.
  return _keywords.hasMatch(clean) ? '\u00a0$clean' : clean;
}

/// The Mermaid text for [groups]' records, and how many it places; empty text where it places none. [kind] names a
/// section whose group has no words of its own: "To-dos", "Tickets", "Notes".
Gantt ganttOf(List<QueryGroup> groups, [String kind = 'Records']) {
  final body = <String>[];
  final sections = groups.length > 1 || groups.any((group) => group.label.isNotEmpty);
  var placed = 0;
  // The days the bars run from and to, all of them: what the ticks are spaced for.
  String? from;
  String? to;
  for (final group in groups) {
    final bars = <String>[];
    for (final row in group.rows) {
      final first = row.start ?? row.due;
      final last = row.due ?? row.start;
      if (first == null || first.isEmpty || last == null || last.isEmpty) continue;
      // A start written after the due day is the two the wrong way round: the bar still runs between them.
      final ordered = first.compareTo(last) <= 0;
      final start = ordered ? first : last;
      final end = isoDayAfter(ordered ? last : first, 1);
      if (end == null || end.isEmpty) continue;
      if (from == null || start.compareTo(from) < 0) from = start;
      if (to == null || end.compareTo(to) > 0) to = end;
      final tags = [
        if (row.category == StatusCategory.done || row.done == true) 'done' else if (row.category == StatusCategory.doing) 'active',
        if (row.overdue) 'crit',
      ];
      final id = row.id;
      final name = ganttWords(id != null && id.isNotEmpty ? '$id ${row.name}' : row.name, 'Untitled');
      bars.add('  $name :${[...tags, start, end].join(', ')}');
    }
    if (bars.isEmpty) continue;
    if (sections) body.add('  section ${ganttWords(group.label, kind)}');
    body.addAll(bars);
    placed += bars.length;
  }
  if (placed == 0 || from == null || to == null) return const Gantt(code: '', placed: 0);
  final (:tick, :axis) = ticksFor(daysBetween(from, to) ?? 0);
  // Mermaid's own top and grid padding are kept: its axis is drawn a fixed distance up from the foot, and less room
  // above put the dates over the last bar.
  final layout = {
    'gantt': {'leftPadding': sections ? 80 : 8, 'rightPadding': 16, 'barHeight': 22, 'barGap': 6, 'fontSize': 12, 'sectionFontSize': 12},
  };
  final lines = ['%%{init: ${jsonEncode(layout)}}%%', 'gantt', '  dateFormat YYYY-MM-DD', '  axisFormat $axis', '  tickInterval $tick', ...body];
  return Gantt(code: lines.join('\n'), placed: placed);
}

/// How far apart the ticks are, and how each is dated, for bars that span [days]: few enough that no two dates
/// touch.
({String tick, String axis}) ticksFor(int days) {
  if (days <= 10) return (tick: '1day', axis: '%e');
  if (days <= 70) return (tick: '1week', axis: '%e %b');
  if (days <= 400) return (tick: '1month', axis: '%b');
  return (tick: '3month', axis: '%b %Y');
}
