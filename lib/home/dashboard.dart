/// What the home page gathers from the notes: the pinned ones, the tapes, the ones touched last, every to-do not yet
/// ticked, and the digest line that says what is waiting. A port of `src/app/home/dashboard.ts` (docs/DESIGN.md §132),
/// under the web's own names. Pure, so each rule is a test (test/home/dashboard_test.dart, the web's cases).
///
/// The page that drew most of this - the digest, the To do card, the shelf of tapes - went with the dashboard (§147):
/// today's home page asks only `home_layout.dart`. The rules are kept as the web keeps them, for whoever lists a tape
/// or a to-do next.
///
/// What differs:
/// - [openTasks] takes a to-do's fields off with a reduced reading of `core/taskFields.ts` (a person, a priority's
///   sign, Tasks' emoji fields with their values, a `[key:: value]` field): the whole grammar, with what it leaves
///   alone inside code and links, comes with the editor.
/// - [tapesWaiting] is handed the queues as plain sets ([SummariesState]); the queues themselves are the AI's.
library;

import 'package:flutter/foundation.dart';

import '../core/book.dart';
import '../core/note.dart';
import '../core/note_text.dart';

/// The pages that are not the person's notes to show among theirs: the Guide's, and the pages of a Templates notebook.
Set<String> _pagesApart(List<Note> notes) => {...guidePages(notes), ...templatePages(notes)};

List<Note> _by(Iterable<Note> notes, int Function(Note note) key) {
  final indexed = notes.indexed.toList();
  indexed.sort((a, b) {
    final by = key(b.$2).compareTo(key(a.$2));
    return by != 0 ? by : a.$1.compareTo(b.$1);
  });
  return [for (final (_, note) in indexed) note];
}

/// Pinned notes, newest first. The archive is never on the home page.
List<Note> pinnedNotes(List<Note> notes) => _by(notes.where((n) => n.starred && n.archivedAt == null), (n) => n.updatedAt);

/// The notebooks, newest change first. The archive stays out.
List<Note> bookNotes(List<Note> notes) => _by(notes.where((n) => n.archivedAt == null && isBookBody(n.body)), (n) => n.updatedAt);

/// The meetings, by note id (`Meetings`): which notes are meetings.
typedef Meetings = Map<String, int>;

/// A tape: a note with a recording that the recorder made (`source: capture`), or a meeting. A note that was written
/// and then talked into is a note, not a tape.
bool isTape(Note note, Meetings meetings) => note.archivedAt == null && hasTape(note) && (note.source == NoteSource.capture || meetings.containsKey(note.id));

/// Which write-up a tape is asked for (`SummaryKind`, the two the home page asks).
enum SummaryKind { meeting, recording }

SummaryKind summaryKindOf(Note note, Meetings meetings) => meetings.containsKey(note.id) ? SummaryKind.meeting : SummaryKind.recording;

/// Every tape, the Guide's pages out, the last recorded first: by `createdAt`, so a summary landing later does not
/// move a tape along the row. The meeting being recorded now ([live]) is first: it is a tape while it is being made.
List<Note> tapedNotes(List<Note> notes, Meetings meetings, [String? live]) {
  final guide = guidePages(notes);
  Note? recording;
  if (live != null) {
    for (final n in notes) {
      if (n.id == live && n.archivedAt == null) {
        recording = n;
        break;
      }
    }
  }
  final shelf = _by(notes.where((n) => n.id != live && isTape(n, meetings) && !guide.contains(n.id)), (n) => n.createdAt);
  return recording != null ? [recording, ...shelf] : shelf;
}

/// The notes touched last: pinned ones, books and tapes left to their own rows so nothing shows twice, and the
/// Guide's pages and a journal's entries out.
List<Note> recentNotes(List<Note> notes, int count, Meetings meetings, [String? live]) {
  final guide = _pagesApart(notes);
  final entries = entryPages(notes);
  return _by(
    notes.where((n) => n.id != live && !n.starred && n.archivedAt == null && !isBookBody(n.body) && !guide.contains(n.id) && !entries.contains(n.id) && !isTape(n, meetings)),
    (n) => n.updatedAt,
  ).take(count).toList();
}

/// A to-do not yet ticked, wherever it was written (`OpenTask`).
@immutable
class OpenTask {
  const OpenTask({required this.noteId, required this.line, required this.text, this.at, required this.touched});
  final String noteId;

  /// The line it is on, counting from 0, which is what ticking it rewrites.
  final int line;
  final String text;

  /// Its anchor, when it has one: opening the note lands on it.
  final String? at;

  /// When its note was touched, which orders the list.
  final int touched;
}

/// A code fence opening or closing: a to-do inside one is an example of a to-do, not one.
final RegExp _fence = RegExp(r'^\s*(`{3,}|~{3,})');
const String _blank = r'(?<![{\\$])\{\?(?!\?)([^{}|\n]{0,160})\}(?!\})';
final RegExp _lineTail = RegExp(r'\s+(?:\^[a-z0-9][a-z0-9_-]*|\[[a-z][a-z0-9-]*\]\(https?:\/\/[^\s)]+\)|\[\d{1,4}\/\d{1,4}\]|§§(?=\s|$))$');

/// The words of a list item, box, anchor and what ends its line off, or null where the line is not one (`itemWords`).
String? _itemWords(String line) {
  final lead = listLead(line);
  if (lead == null) return null;
  var rest = line.replaceFirst(RegExp(r'\s+$'), '');
  for (var found = _lineTail.firstMatch(rest); found != null; found = _lineTail.firstMatch(rest)) {
    rest = rest.substring(0, found.start);
  }
  return rest.length <= lead.wordsAt ? '' : rest.substring(lead.wordsAt).trim();
}

/// An item's words as a reader shows them: filled answers as their words, and a blank as its question's (`readableWords`).
String _readableWords(String text) {
  final plain = plainFills(text);
  if (!plain.contains('{?')) return plain;
  return plain.replaceAllMapped(RegExp(_blank), (m) => (m.group(1) ?? '').trim()).replaceAll(RegExp(r'\s{2,}'), ' ');
}

const String _vs = '\u{FE0F}?';
final List<RegExp> _fields = [
  // A named field, `[due:: 2026-10-03]`.
  RegExp(r'\s*\[[^\[\]\n:]+::[^\[\]\n]*\]'),
  // A date: its sign, then the day.
  RegExp('\\s*(?:➕|🛫|⏳|⌛|📅|📆|🗓|❌|✅)$_vs\\s*\\d{4}-\\d{2}-\\d{2}', unicode: true),
  // A recurrence, an id, what it waits on, what finishing it does: the sign, then its words up to the next sign.
  RegExp('\\s*(?:🔁|🆔|⛔|🏁)$_vs[^🔺⏫🔼🔽⏬➕🛫⏳⌛📅📆🗓❌✅🔁🆔⛔🏁]*', unicode: true),
  // A priority's sign.
  RegExp('\\s*(?:🔺|⏫|🔼|🔽|⏬)$_vs', unicode: true),
];
final RegExp _person = RegExp(r'(^|[\s([{])@(\p{L}[\p{L}\p{N}_.-]*)', unicode: true);

/// [text] with every field taken out and the spaces tidied (`withoutFields`, in part).
String _withoutFields(String text) {
  var out = text;
  for (final field in _fields) {
    out = out.replaceAll(field, '');
  }
  out = out.replaceAllMapped(_person, (m) => m.group(1) == null || m.group(1)!.trim().isEmpty ? '' : m.group(1)!);
  return out.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}

/// Every unticked to-do in the notes, the most recently touched note's first, in the order each note has them.
List<OpenTask> openTasks(List<Note> notes) {
  final tasks = <OpenTask>[];
  final guide = _pagesApart(notes);
  for (final note in _by(notes.where((n) => n.archivedAt == null && !guide.contains(n.id)), (n) => n.updatedAt)) {
    var fenced = false;
    final lines = note.body.split('\n');
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      if (_fence.hasMatch(line)) {
        fenced = !fenced;
        continue;
      }
      if (fenced || taskBox(line)?.done != false) continue;
      final words = _itemWords(line);
      final text = words == null ? null : _readableWords(_withoutFields(words)).trim();
      if (text == null || text.isEmpty) continue;
      tasks.add(OpenTask(noteId: note.id, line: index, text: text, at: anchorSpan(line)?.id, touched: note.updatedAt));
    }
  }
  return tasks;
}

/// Midnight at the start of the local day [now] is in.
int startOfToday([int? now]) {
  final day = DateTime.fromMillisecondsSinceEpoch(now ?? DateTime.now().millisecondsSinceEpoch);
  return DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
}

/// How many of the notes were touched since the local day began, out of the archive and the Guide, its pages and its
/// book alike: the digest's "N notes touched today".
int touchedToday(List<Note> notes, [int? now]) {
  final since = startOfToday(now);
  final guide = _pagesApart(notes);
  return notes.where((n) => n.archivedAt == null && !guide.contains(n.id) && !isGuideBook(n) && n.updatedAt >= since).length;
}

/// The queues a tape can be waiting in, by note id (`SummariesState`, as sets).
@immutable
class SummariesState {
  const SummariesState({this.pending = const {}, this.native = const {}, this.waiting = const {}, this.failed = const {}, this.needsModel = const {}});
  final Set<String> pending;
  final Set<String> native;
  final Set<String> waiting;
  final Set<String> failed;
  final Set<String> needsModel;
}

/// What is waiting on the tapes (`Waiting`).
typedef Waiting = ({int working, int needsModel, int failed});

/// The tapes something is happening to, counted once each in the caption's own order: working before needing a model
/// before failed.
Waiting tapesWaiting(List<Note> tapes, {required Set<String> refining, required SummariesState summaries}) {
  var working = 0, needsModel = 0, failed = 0;
  for (final tape in tapes) {
    final id = tape.id;
    if (refining.contains(id) || summaries.native.contains(id) || summaries.waiting.contains(id) || summaries.pending.contains(id)) {
      working += 1;
    } else if (summaries.needsModel.contains(id)) {
      needsModel += 1;
    } else if (summaries.failed.contains(id)) {
      failed += 1;
    }
  }
  return (working: working, needsModel: needsModel, failed: failed);
}

/// Where a digest phrase goes: a group on the page, or Settings › Recording › Model for a missing model.
enum DigestGo { tasks, tapes, model }

/// One phrase of the digest (`DigestPhrase`). [go] is null for a phrase that is only said.
typedef DigestPhrase = ({String text, DigestGo? go});

/// The digest's phrases in order, each with where it goes: only the phrases that are true, and "Nothing waiting on
/// you" first when none of the waiting ones are. No full stops: the digest is a row of fragments.
List<DigestPhrase> digest({required int open, required Waiting waiting, required int touched}) {
  final phrases = <DigestPhrase>[];
  if (open > 0) phrases.add((text: '$open to-do${open == 1 ? '' : 's'} open', go: DigestGo.tasks));
  if (waiting.working > 0) phrases.add((text: 'Working on ${waiting.working} tape${waiting.working == 1 ? '' : 's'}', go: DigestGo.tapes));
  if (waiting.needsModel > 0) phrases.add((text: waiting.needsModel == 1 ? '1 tape needs a model' : '${waiting.needsModel} tapes need a model', go: DigestGo.model));
  if (waiting.failed > 0) phrases.add((text: waiting.failed == 1 ? '1 summary didn’t come' : '${waiting.failed} summaries didn’t come', go: DigestGo.tapes));
  if (phrases.isEmpty) phrases.add((text: 'Nothing waiting on you', go: null));
  if (touched > 0) phrases.add((text: '$touched note${touched == 1 ? '' : 's'} touched today', go: null));
  return phrases;
}

/// How many to-dos are ticked in the notes, outside code fences, the archive and the Guide's pages.
int tickedTasks(List<Note> notes) {
  var count = 0;
  final guide = _pagesApart(notes);
  for (final note in notes) {
    if (note.archivedAt != null || guide.contains(note.id)) continue;
    var fenced = false;
    for (final line in note.body.split('\n')) {
      if (_fence.hasMatch(line)) {
        fenced = !fenced;
      } else if (!fenced) {
        final box = taskBox(line);
        if (box != null && box.done && RegExp(r'\S').hasMatch(line.substring(box.at + 3))) count += 1;
      }
    }
  }
  return count;
}
