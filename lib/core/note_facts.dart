/// What a note's body says about it, read once and kept: its title and the key it is matched by, whether it is a
/// notebook, a journal, a canvas or a ticket, its chapters, how it starts, and what its card draws small.
///
/// Everything a list shows of a note is read from its body, as on the web (lib/core/note.dart). The web reads it
/// again at every render and so did this port, which is what the home page's time went to: measured walking a
/// library of 354 notes (tool/perf.sh, 2026-10-10), `frontMatterValue`, `isCanvasBody`, `noteTitle`, `ticketOf`
/// and `chaptersOf` were over half of every frame the page was built in, each asked of every note three and four
/// times a build. A body does not change under a reading of it, so each is read once here and the answer kept:
///
///     final facts = NoteFacts.of(note);
///     facts.title; facts.isBook; facts.chapters; facts.firstLine; facts.peek;
///
/// **Kept by the note.** One reading for each note's id, for the body it has now: a note that is edited is read
/// again and the reading of its old words is dropped at once, so no more bodies are held than the library holds
/// (and where the library hands back the same words in a new string, the reading takes the new string and lets
/// the old go). Each fact is worked out the first time it is asked for, so a note no list ever draws costs its
/// front matter's first line. No more than [NoteFacts.most] readings are kept; past that, the ones asked for
/// longest ago go, which is the notes that were deleted.
///
/// **The same answers.** Every fact here is the answer of the function a caller with only a body asks
/// (`noteTitle`, `isBookBody`, `isCanvasBody`, `chaptersOf`, `ticketOf`, `firstLine`, `peekMarkdown`), which stay
/// as they are for a body that is no note's; test/core/note_facts_test.dart holds the two to one answer and counts
/// the readings.
///
/// And two helpers for whoever works something out from every note at once: [sameNotes], whether two lists are
/// the same notes, and [NotesMemo], the last few answers kept by the list they were worked out from, so a page
/// that is built again with the notes it had does none of it again.
library;

import '../book/journal.dart' show stampOf;
import '../canvas/json_canvas.dart' show canvasOf, isCanvasBody;
import 'book.dart' show Chapter, chaptersOf, saysYes;
import 'front_matter.dart';
import 'note.dart';
import 'note_text.dart' show noteTitleIn, peekMarkdown;
import 'note_text.dart' as words show firstLine;
import 'properties.dart' show StatusCategory, Ticket, statusCategory, statusesOf, ticketOf, ticketType;
import 'short_url.dart' show shortenUrls;
import 'title_key.dart' show titleKey;

final RegExp _page = RegExp(r'^page$', caseSensitive: false);

/// One note's body, read (see the library's doc). Made by [NoteFacts.of] for a note, which keeps it, or by
/// [NoteFacts.read] for a body alone, which does not.
class NoteFacts {
  NoteFacts._(this._body) {
    debugReadings += 1;
  }

  /// A body read and not kept: for words that are no note's, or not yet.
  factory NoteFacts.read(String body) => NoteFacts._(body);

  // ---- the keeping -------------------------------------------------------------------------------------------------

  /// The most readings kept at once.
  static int most = 32768;

  static final Map<String, NoteFacts> _kept = <String, NoteFacts>{};
  static int _tick = 0;

  /// How many bodies have been read since the app began (or [debugForget]): one for each note and each body it
  /// has had, however often it is asked about. For a test, and for the measured walk.
  static int debugReadings = 0;

  /// How many facts have been worked out: each once for a reading, the first time it is asked for.
  static int debugWorkedOut = 0;

  /// How many readings are kept now.
  static int get debugKept => _kept.length;

  /// Forgets every reading and starts the counts again: for a test.
  static void debugForget() {
    _kept.clear();
    debugReadings = 0;
    debugWorkedOut = 0;
  }

  /// What [note]'s body says, read once for the body it has now.
  static NoteFacts of(Note note) {
    final body = note.body;
    final had = _kept[note.id];
    if (had != null) {
      if (identical(had._body, body)) {
        had._asked = _tick += 1;
        return had;
      }
      if (had._body == body) {
        // The same words in another string (the library read again): hold the newer, so the older can go.
        had._body = body;
        had._asked = _tick += 1;
        return had;
      }
    } else if (_kept.length >= most) {
      _trim();
    }
    final facts = NoteFacts._(body).._asked = _tick += 1;
    _kept[note.id] = facts;
    return facts;
  }

  /// Past [most]: the quarter asked for longest ago goes.
  static void _trim() {
    final byAsked = _kept.entries.toList()..sort((a, b) => a.value._asked.compareTo(b.value._asked));
    final go = byAsked.length ~/ 4 > 0 ? byAsked.length ~/ 4 : 1;
    for (var i = 0; i < go; i += 1) {
      _kept.remove(byAsked[i].key);
    }
  }

  int _asked = 0;
  String _body;

  /// The words this is a reading of.
  String get body => _body;

  static T _worked<T>(T value) {
    debugWorkedOut += 1;
    return value;
  }

  // ---- the front matter --------------------------------------------------------------------------------------------

  /// Where the front matter is (`frontMatterSpan`).
  late final FrontMatterSpan front = _worked(frontMatterSpan(_body));

  /// One key's value from the front matter (`frontMatterValue`).
  String? value(String key) => frontMatterValueIn(_body, front, key);

  // ---- the name ----------------------------------------------------------------------------------------------------

  /// The note's title (`noteTitle`).
  late final String title = _worked(noteTitleIn(_body, front));

  /// The title as it is matched (`titleKey(noteTitle(body))`).
  late final String key = _worked(titleKey(title));

  /// The title as a list writes it, a long address in it cut short (`shortenUrls(noteTitle(body))`).
  late final String shownTitle = _worked(shortenUrls(title));

  // ---- its kind ----------------------------------------------------------------------------------------------------

  /// Whether it is a notebook (`isBookBody`).
  late final bool isBook = _worked(saysYes(value('book')));

  /// Whether it is a notebook kept as a journal (`isJournalBody`).
  late final bool isJournal = isBook && _worked(saysYes(value('journal')));

  /// Whether it is a Templates notebook (`isTemplatesBook`).
  late final bool isTemplatesBook = isBook && _worked(saysYes(value('templates')));

  /// Whether it is a template's page (`isTemplatePage`).
  late final bool isTemplatePage = !isBook && _worked(_page.hasMatch(value('templates') ?? ''));

  /// Whether it is a canvas rather than words (`isCanvasBody`).
  late final bool isCanvas = _worked(isCanvasBody(_body));

  /// How many cards the canvas holds, or null for a note that is words (`canvasCardCount`). The one fact that
  /// decodes the canvas: asked only of a canvas a row is drawn for.
  late final int? canvasCards = isCanvas ? _worked(canvasOf(_body)?.nodes.length) : null;

  /// Whether it is a ticket (`isTicket`).
  late final bool isTicket = _worked(value('type')?.trim().toLowerCase() == ticketType);

  // ---- a notebook's --------------------------------------------------------------------------------------------------

  /// The index's chapters, in its order (`chaptersOf`). Not to be changed: every asker is handed this list.
  late final List<Chapter> chapters = _worked(List<Chapter>.unmodifiable(chaptersOf(_body)));

  /// Each chapter's title as it is matched, beside [chapters].
  late final List<String> chapterKeys = _worked(List<String>.unmodifiable([for (final chapter in chapters) titleKey(chapter.title)]));

  /// The workflow a notebook gives its tickets (`statusesOf`). Not to be changed.
  late final List<String> statuses = _worked(List<String>.unmodifiable(statusesOf(_body)));

  // ---- a ticket's --------------------------------------------------------------------------------------------------

  /// The ticket the note is, placed in no workflow, or null for a note that is not one (`ticketOf(body)`).
  late final Ticket? ticket = isTicket ? _worked(ticketOf(_body)) : null;

  List<String>? _workflow;
  Ticket? _placed;

  /// The ticket placed in a notebook's workflow (`ticketOf(body, statuses)`): [ticket] itself where the workflow
  /// places its status as no workflow does, which is nearly always. The last workflow asked about is kept.
  Ticket? ticketIn(List<String>? statuses) {
    final bare = ticket;
    if (bare == null || statuses == null) return bare;
    if (identical(statuses, _workflow)) return _placed;
    final category = statusCategory(bare.status, statuses);
    _workflow = statuses;
    return _placed = category == bare.category ? bare : _recategorised(bare, category);
  }

  static Ticket _recategorised(Ticket ticket, StatusCategory category) => Ticket(
        id: ticket.id,
        status: ticket.status,
        category: category,
        assignee: ticket.assignee,
        priority: ticket.priority,
        due: ticket.due,
        start: ticket.start,
        estimate: ticket.estimate,
        blockedBy: ticket.blockedBy,
        parent: ticket.parent,
        labels: ticket.labels,
      );

  // ---- what a list draws of it --------------------------------------------------------------------------------------

  /// How it starts, on one line, after its name (`firstLine`).
  late final String firstLine = _worked(words.firstLine(_body));

  /// [firstLine] as a list writes it, a long address in it cut short (`shortenUrls(firstLine(body))`).
  late final String shownFirstLine = _worked(shortenUrls(firstLine));

  /// The note after its title as Markdown, for a card to draw small (`peekMarkdown`); empty for a canvas, whose
  /// body is not words, and for a note with nothing under its name.
  late final String peek = isCanvas ? '' : _worked(peekMarkdown(_body));

  // ---- a journal's entry ---------------------------------------------------------------------------------------------

  int? _stampedFor;
  int _stamp = 0;

  /// When the note was written, as its wall clock (lib/book/journal.dart `stampOf`): its `date:`, else when it was
  /// made, which is the note's and so is handed in. Kept for the moment it was last asked with.
  int stamp(int createdAt) {
    if (_stampedFor == createdAt) return _stamp;
    _stampedFor = createdAt;
    return _stamp = _worked(stampOf(_body, createdAt));
  }
}

/// Whether two notes are one as a list shows it: the same note, or the same id with the same words, pin, archive,
/// tape and moments. A library that reads its notes again hands back new notes that say what the old ones said.
bool sameNote(Note a, Note b) {
  if (identical(a, b)) return true;
  return a.id == b.id &&
      a.updatedAt == b.updatedAt &&
      a.createdAt == b.createdAt &&
      a.starred == b.starred &&
      a.archivedAt == b.archivedAt &&
      a.recordingMs == b.recordingMs &&
      a.revision == b.revision &&
      (identical(a.body, b.body) || a.body == b.body);
}

/// Whether two lists are the same notes in the same order ([sameNote]): the question a page asks before it works
/// anything out again, since whoever hands it its notes may make a new list of the same notes at every build.
bool sameNotes(List<Note> a, List<Note> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (!sameNote(a[i], b[i])) return false;
  }
  return true;
}

/// Whether two lists hold the very same notes, object for object.
bool _identicalNotes(List<Note> a, List<Note> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

/// The last few answers of something worked out from every note at once (every page's notebook, every journal's
/// card), kept by the notes they were worked out from: asked again with the very same notes, in a new list or
/// not, the answer is the one already made. [also] is whatever else the answer depends on; it is compared with
/// `==`.
///
/// The notes are compared by which objects they are, not by what they say, since such an answer hands the notes
/// themselves back (a page's notebook is a [Note]).
class NotesMemo<T> {
  NotesMemo([this.most = 4]);

  /// How many answers are kept: one for each list asked about at a time (a workspace's notes, and all of them).
  final int most;
  final List<({List<Note> notes, Object? also, T answer})> _kept = [];

  /// How many times an answer was worked out, for a test.
  int debugMade = 0;

  T of(List<Note> notes, T Function() make, {Object? also}) {
    for (var i = 0; i < _kept.length; i += 1) {
      final kept = _kept[i];
      if (kept.also == also && _identicalNotes(kept.notes, notes)) {
        // The one asked for last is looked at first.
        if (i > 0) {
          _kept.removeAt(i);
          _kept.insert(0, kept);
        }
        return kept.answer;
      }
    }
    debugMade += 1;
    final answer = make();
    // A list of its own: the caller's may be changed after.
    _kept.insert(0, (notes: List<Note>.of(notes, growable: false), also: also, answer: answer));
    if (_kept.length > most) _kept.removeLast();
    return answer;
  }

  void clear() => _kept.clear();
}
