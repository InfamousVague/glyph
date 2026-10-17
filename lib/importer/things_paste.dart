/// The text Things copies, brought in (Settings › Import › Paste from Things): on any device, what Things' Share ›
/// Copy (or ⌘C on a Mac) put on the clipboard for a list, read from the clipboard and made one note, at the top of
/// the import's workspace, as a project read from Things' database is (lib/importer/things.dart `thingsBody`).
///
/// Cultured Code documents only that the text is plain, and that a list shared whole leaves out each to-do's
/// details (its notes, tags and dates). So the reading is lenient, taking each shape the text is seen in:
///
///     Launch                     the list's name, the first line before any to-do
///     Everything for Friday.     its notes, the lines after it before any to-do
///
///     - Write the post           a to-do: `-`, `*`, `•`, or a box, `- [ ]`, `☐` (`- [x]`, `✓`, `✔`, `☑` done;
///       Two paragraphs.          `- [~]` cancelled); a line indented under it is its notes,
///       - [ ] Draft              and an indented to-do one of its checklist's items
///
///     Press:                     a heading: a line ending with `:`, a `#` line, or a line of words with to-dos
///     - Call the paper           after it
///
/// A text with no marks at all (⌘C of a few to-dos on a Mac gives their titles, one a line) is a to-do a line,
/// headings and indented notes aside, in a note called "From Things".
library;

import 'import_report.dart';
import 'import_target.dart';
import 'things.dart';

final RegExp _boxed = RegExp(r'^(\s*)(?:[-*+•◦▪]\s+)?(\[[ xX~\-]\]|☐|☑️?|✓|✔️?|✅|⬜️?|◻️?)\s*(.*)$');
final RegExp _bullet = RegExp(r'^(\s*)[-*+•◦▪]\s+(.*)$');
final RegExp _hashHeading = RegExp(r'^#{1,6}\s+(.*)$');

/// A line as a to-do: how far it is indented, its state and its words; null for a line that is not one.
({int indent, ThingsStatus status, String words})? _todo(String line) {
  final boxed = _boxed.firstMatch(line);
  if (boxed != null && boxed.group(3)!.trim().isNotEmpty) {
    final box = boxed.group(2)!;
    final status = switch (box) {
      '[x]' || '[X]' || '☑' || '☑️' || '✓' || '✔' || '✔️' || '✅' => ThingsStatus.done,
      '[~]' || '[-]' => ThingsStatus.cancelled,
      _ => ThingsStatus.open,
    };
    return (indent: boxed.group(1)!.length, status: status, words: boxed.group(3)!.trim());
  }
  final bullet = _bullet.firstMatch(line);
  if (bullet != null && bullet.group(2)!.trim().isNotEmpty) return (indent: bullet.group(1)!.length, status: ThingsStatus.open, words: bullet.group(2)!.trim());
  return null;
}

/// A line as a heading's words, or null: `## Press`, `Press:`.
String? _heading(String line) {
  if (line.startsWith(RegExp(r'\s'))) return null;
  final hashed = _hashHeading.firstMatch(line.trim());
  if (hashed != null) return hashed.group(1)!.trim();
  final trimmed = line.trim();
  if (trimmed.length > 1 && trimmed.endsWith(':') && !trimmed.contains(RegExp(r'https?://'))) return trimmed.substring(0, trimmed.length - 1).trim();
  return null;
}

class _Todo {
  _Todo(this.words, this.status);
  final String words;
  final ThingsStatus status;
  final List<String> notes = [];
  final List<ThingsCheck> checks = [];

  ThingsItem item(int order) => ThingsItem(
        id: 'p$order',
        kind: ThingsKind.todo,
        title: words,
        status: status,
        notes: notes.join('\n'),
        order: order,
        checklist: checks,
      );
}

/// What a pasted [text] is: its title (null where it names none), its notes, its to-dos outside a heading, and
/// each heading's.
({String? title, String notes, List<ThingsItem> todos, List<(ThingsItem, List<ThingsItem>)> headings}) readThingsPaste(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final marked = lines.any((line) => _todo(line) != null && !line.startsWith(RegExp(r'\s')));
  String? title;
  final notes = <String>[];
  final loose = <_Todo>[];
  final headed = <(String, List<_Todo>)>[];
  List<_Todo> current() => headed.isEmpty ? loose : headed.last.$2;
  _Todo? last;
  var begun = false;

  bool todoNext(int from) {
    for (var n = from; n < lines.length; n += 1) {
      if (lines[n].trim().isEmpty) continue;
      return _todo(lines[n]) != null && !lines[n].startsWith(RegExp(r'\s'));
    }
    return false;
  }

  for (var n = 0; n < lines.length; n += 1) {
    final line = lines[n];
    if (line.trim().isEmpty) continue;
    final indented = line.startsWith(RegExp(r'\s'));
    final todo = _todo(line);
    if (indented && last != null) {
      // Under a to-do: an item of its checklist, or a line of its notes.
      if (todo != null) {
        last.checks.add(ThingsCheck(title: todo.words, status: todo.status, order: last.checks.length));
      } else {
        last.notes.add(line.trim());
      }
      continue;
    }
    if (todo != null) {
      begun = true;
      last = _Todo(todo.words, todo.status);
      current().add(last);
      continue;
    }
    if (!begun && title == null) {
      // The first line: the list's name, `# Launch` or `Launch` (where to-dos are marked; where none is, a line
      // is a to-do, and only a `#` line names the list).
      final hashed = _hashHeading.firstMatch(line.trim());
      if (hashed != null || (marked && _heading(line) == null)) {
        title = hashed?.group(1)!.trim() ?? line.trim();
        continue;
      }
    }
    final heading = _heading(line);
    if (heading != null) {
      begun = true;
      headed.add((heading, []));
      last = null;
      continue;
    }
    if (marked) {
      if (!begun) {
        // Before the first to-do: the list's notes.
        notes.add(line.trim());
      } else if (todoNext(n + 1)) {
        // A line of words with to-dos after it: a heading.
        headed.add((line.trim(), []));
        last = null;
      } else if (last != null) {
        last.notes.add(line.trim());
      } else {
        notes.add(line.trim());
      }
      continue;
    }
    // No marks anywhere: each line a to-do.
    begun = true;
    last = _Todo(line.trim(), ThingsStatus.open);
    current().add(last);
  }

  var order = 0;
  return (
    title: title,
    notes: notes.join('\n'),
    todos: [for (final todo in loose) todo.item(order++)],
    headings: [
      for (final (words, list) in headed) (ThingsItem(id: 'h${order++}', kind: ThingsKind.heading, title: words), [for (final todo in list) todo.item(order++)]),
    ],
  );
}

/// The note's title where the text names none.
const String thingsPasteTitle = 'From Things';

/// Imports the pasted [text] through [target]: one note. Throws, before anything is made, where it holds nothing.
Future<ImportReport> importThingsPaste(String text, ImportTarget target, {bool done = true}) async {
  final read = readThingsPaste(text);
  if (read.title == null && read.todos.isEmpty && read.headings.isEmpty) throw StateError('Nothing from Things is copied. In Things, open a list, choose Share › Copy, and come back.');
  final run = target.begin('Things');
  final report = run.report;
  try {
    final title = read.title ?? thingsPasteTitle;
    var counted = 0;
    final body = thingsBody(title: title, notes: read.notes, todos: read.todos, headings: read.headings, done: done, counted: () => counted += 1);
    await run.note(body: body, path: run.paths.place(const [], title));
    report.tasks = counted;
  } finally {
    run.finish();
  }
  return report;
}
