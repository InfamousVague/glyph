/// A to-do from another app as the app writes one (lib/core/task_fields.dart): what Todoist's and Things' imports
/// (lib/importer/todoist.dart, things.dart) both write their lists with.
///
///     - [ ] Call the client #work ⏫ 🔁 every week ⏳ 2026-10-18 📅 2026-10-20
///       What to ask: the dates.
///       - [ ] A sub-task, or one of Things' checklist items
///
/// The words first, then the tags, then Obsidian Tasks' fields in the order Tasks writes them ([tasksOrder]:
/// priority, recurrence, scheduled, due, cancelled, done), so Tasks reads every one of them; a field Tasks has no
/// sign for (`[deadline:: 2026-10-24]`) goes before that run, never inside it. A note under a to-do is indented
/// text, a line at a time, two spaces deeper than its box, as a sub-task is: the list item's own, in CommonMark and
/// in the editor. Pure, so every shape of line is a test (test/importer/todoist_test.dart, things_test.dart).
library;

import 'evernote.dart' show tagMark;

/// How deep one level of a list is indented.
const String listIndent = '  ';

/// One to-do, as the importer read it.
class TaskLine {
  TaskLine({
    required this.words,
    this.depth = 0,
    this.done = false,
    this.cancelled = false,
    this.tags = const [],
    this.priority,
    this.recurs,
    this.scheduled,
    this.due,
    this.doneOn,
    this.cancelledOn,
    this.fields = const {},
    this.notes,
  });

  final String words;

  /// 0 for a to-do at the top of its list, 1 for one under it, and on.
  final int depth;

  /// Ticked: done, or (with [cancelled]) let go.
  final bool done;
  final bool cancelled;

  /// The tags as the other app names them (`Quick wins`), written as the app's marks (`#Quick-wins`).
  final List<String> tags;

  /// The priority's sign: ⏫, 🔼 or 🔽; null for none.
  final String? priority;

  /// A recurrence in the other app's words: `every friday`.
  final String? recurs;

  /// Days, `YYYY-MM-DD`: ⏳ scheduled (Things' When), 📅 due (Todoist's due, Things' deadline), ❌ cancelled and ✅
  /// done.
  final String? scheduled;
  final String? due;
  final String? doneOn;
  final String? cancelledOn;

  /// Fields Tasks has no sign for, by name: `deadline`.
  final Map<String, String> fields;

  /// Words under the to-do, a line of text each.
  final String? notes;
}

/// [text] on one line: its breaks and runs of spaces one space.
String oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The lines of [line]: the to-do itself, then its notes.
List<String> taskLines(TaskLine line) {
  final lead = listIndent * line.depth;
  final words = oneLine(line.words);
  final parts = <String>[
    words.isEmpty ? 'Untitled' : words,
    for (final MapEntry(:key, :value) in line.fields.entries) '[$key:: $value]',
    for (final tag in line.tags) ?tagMark(tag),
    ?line.priority,
    if (line.recurs case final recurs? when oneLine(recurs).isNotEmpty) '🔁 ${oneLine(recurs)}',
    if (line.scheduled case final day?) '⏳ $day',
    if (line.due case final day?) '📅 $day',
    if (line.cancelled && line.cancelledOn != null) '❌ ${line.cancelledOn}',
    if (line.done && !line.cancelled && line.doneOn != null) '✅ ${line.doneOn}',
  ];
  return [
    '$lead- [${line.done || line.cancelled ? 'x' : ' '}] ${parts.join(' ')}',
    ...noteLines(line.notes, line.depth + 1),
  ];
}

/// [notes] as text under a list item at [depth]: each line indented to it, the empty ones left out (an empty line
/// would end the item where a reader is strict about it).
List<String> noteLines(String? notes, int depth) {
  if (notes == null) return const [];
  final lead = listIndent * depth;
  return [
    for (final raw in notes.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (raw.trim().isNotEmpty) '$lead${raw.trimRight()}',
  ];
}

/// A day as the fields write one: `2026-10-20`.
String isoDay(DateTime at) => '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';

final RegExp _isoDayStart = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// The day an ISO date or date and time starts with (`2026-10-20`, `2026-10-20T09:00:00Z`), or null.
String? isoDayOf(String? said) {
  final match = _isoDayStart.firstMatch(said?.trim() ?? '');
  if (match == null) return null;
  final month = int.parse(match.group(2)!), day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return match.group(0);
}

/// A title as a notebook's index links it: what a `[[link]]` cannot hold taken out (book.dart's `_link`).
String linkTitle(String title) {
  final clean = title.replaceAll(RegExp(r'[\[\]|#^\n]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length > 120 ? clean.substring(0, 120).trim() : clean;
}

/// A note's title as its first line writes it: on one line, `Untitled` for none.
String headingTitle(String title) {
  final clean = oneLine(title);
  return clean.isEmpty ? 'Untitled' : clean;
}
