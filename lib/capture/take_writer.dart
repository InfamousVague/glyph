/// The note a recording is written into, and every write the recorder makes to any note while it runs. A port of
/// `src/app/capture/takeWriter.ts`.
///
/// The note is chosen as the recorder opens - a new id, or the note whose Speak was pressed - because the phone can
/// kill the app mid-sentence, and the sound is kept under that id from the first second. What is written follows
/// three rules, each learned from a bug:
///
/// - Every write goes through one chain (`queue`), in turn. Two close together used to read the same body and the
///   second lost the first.
/// - A continued note's own text is read from the store once, when first needed, into a future (`baseBody`), so two
///   drafts racing both compose onto the text from BEFORE either of them wrote, and the take's words are always
///   `placeTake(base, words, placing)` (place.dart): never the stored note, which may already hold a draft of them.
/// - A command that changes the note being recorded onto changes that base, and the words are composed onto the end
///   of it again (`updateNote`). Applied to the stored note, which already held the words a draft had saved, they
///   were composed on a second time at the next save.
///
/// Discard undoes what drafts wrote (`undoDraft`): a continued note gets its text back, a new note goes. Aiming the
/// take at another note (`aim`) starts it afresh there: that note's base is read again when first needed, and no
/// draft of it is written yet, so the first note's text is never composed under the words in the second. The screen
/// owns what is said and shown; this owns the ids, the base and the chain, and tells the screen through its host
/// when the note being recorded onto changed, so the page can show the change land.
///
/// Where the words go in the note is its `placing` (place.dart): the end, for a new note and for a note's own Speak
/// as it always was, or the lists of a note whose title says it holds them. A note the live reader switched the take
/// to (live_route.dart) is written once, at Done, by `writeInto`: read fresh, the words placed into it, and stored
/// through `apply_command`, which checks the body and the revision, so nothing typed or synced meanwhile is
/// overwritten.
///
/// Nothing writes a draft mid-take since the take's phrase reader went: `flushDraft`, `keepDraft` and `updateNote`
/// are kept, unused, until it is decided whether a take kept safe from a kill wants them. With no draft ever
/// written, `savedDraft` is always false and `undoDraft`, which the recorder still calls, does nothing; the host's
/// `markdown` and `hasWords` serve only the drafts and `updateNote`.
///
/// What differs:
/// - The web imports the note store (`core/store.ts`); here it is given, as a [TakeStore] with the six functions
///   the web imports under the web's names. A command's request and its answer ([CommandMutationRequest],
///   [CommandMutationResult]) are the library's (lib/core/command_mutations.dart), handed on from here for the
///   files that found them here.
/// - [NamedNote] is a class that extends `Candidate` with the note, where the web intersects two types; its `note`
///   can be written, since every write here replaces the command list's copy.
/// - [TakeWriterHost] is a class of four functions, as the web's host is an object of four.
/// - `writeInto` takes the note's id, where the web takes any object with one, and answers a [WrittenInto].
library;

import 'dart:async';

import '../core/command_mutations.dart';
import '../core/note.dart';
import 'place.dart';
import 'route.dart' show Candidate;

export '../core/command_mutations.dart' show CommandMutationRequest, CommandMutationResult, CommandMutationResultApplied, CommandMutationResultConflict;

/// The note store, as the writer asks it (`core/store.ts`).
abstract class TakeStore {
  /// A genuinely new note; an id already taken is an error.
  Future<Note> createNote(String id, String body, [NoteSource source = NoteSource.editor]);

  /// Deletes the note for good. One already gone is not an error.
  Future<void> deleteNote(String id);

  /// The note whole, or null when nothing answers to that id.
  Future<Note?> getNote(String id);

  /// A fresh id for a note or a mutation.
  String newNoteId();

  /// Writes [body] over exactly the revision the caller read; a note that is gone, or has moved on, is an error.
  Future<Note> updateNote(String id, String body, int expectedRevision);

  /// Applies exactly the body that was previewed, if the previewed revision still exists.
  Future<CommandMutationResult> applyCommandMutation(CommandMutationRequest request);
}

/// A note a command can name, with the note itself, kept current by every write here.
class NamedNote extends Candidate {
  NamedNote({required super.id, required super.title, required this.note});

  Note note;

  @override
  String? get noteBody => note.body;
}

/// What the writer asks of the screen that owns the take.
class TakeWriterHost {
  const TakeWriterHost({required this.markdown, required this.hasWords, required this.candidates, required this.targetChanged});

  /// The take's markdown as it is saved: titled for a new note, not for words on the end of one.
  final String Function(bool titled) markdown;

  /// Whether the take holds anything a draft would write: a phrase.
  final bool Function() hasWords;

  /// The notes a command can name; each written note's copy there is replaced by what was stored.
  final List<NamedNote> Function() candidates;

  /// The note being recorded onto changed, or became another, or none: for the page to show it.
  final void Function(Note? note) targetChanged;
}

/// What `writeInto` did with the words.
class WrittenInto {
  const WrittenInto({required this.saved, required this.before, required this.blocks, required this.spot, required this.mutationId, required this.own});

  /// The note as stored: the one named, or the words' own.
  final Note saved;

  /// The named note's text before the words, or null where they became a note of their own.
  final String? before;

  /// The pieces of text put in it, each exactly as written.
  final List<String> blocks;

  /// Where they went, as place.dart says it.
  final String? spot;

  /// The write's mutation id, for Undo, or null where nothing was written into the note.
  final String? mutationId;

  /// The words became a note of their own.
  final bool own;
}

class TakeWriter {
  TakeWriter(this._host, {required TakeStore store})
      : _store = store,
        noteId = store.newNoteId();

  final TakeWriterHost _host;
  final TakeStore _store;

  /// The note being written: a new id, or the note this capture continues.
  String noteId;

  /// The note this capture is being added to, if it continues one.
  Note? target;

  /// The continued note's text before this capture, read from the store once, when first needed - after the editor
  /// that may have been open has flushed its last keystrokes. A future, so two drafts racing both get the text from
  /// BEFORE either of them wrote.
  Future<String>? _base;

  /// A draft has been written since the take last began, which Discard (`undoDraft`) takes back.
  bool _drafted = false;

  /// The stored row of a new capture's draft, once one is made: later drafts are revision-checked edits of it.
  Note? _draft;

  /// Every write to a note, in turn: a command's change, the draft, the take carrying on elsewhere.
  Future<Object?> _chain = Future<Object?>.value();

  /// Where the words go in the note being written: the end, or its lists (place.dart).
  Placing placing = end;

  /// The note was switched to by a command, not opened from its own Speak: it is written by `writeInto` at Done.
  bool routed = false;

  /// A switched-to note read fresh, for its tape and phrases, which the candidate it was found as lacks.
  Future<Object?> _refreshing = Future<Object?>.value();

  /// The continued note's text before this capture, once a draft or a command has read it; null until then.
  Future<String>? get baseBody => _base;

  /// Whether a draft has been written since the take last began (on this note), which Discard takes back.
  bool get savedDraft => _drafted;

  /// The take is written into [note] from here, or into a new note with a fresh id when it is null. It begins afresh
  /// there: the base is [note]'s, read when first needed, and nothing written to the note before is this take's
  /// draft to take back.
  void aim(Note? note, [Placing placing = end, bool routed = false]) {
    target = note;
    _draft = null;
    _base = null;
    _drafted = false;
    this.placing = placing;
    this.routed = routed && note != null;
    noteId = note?.id ?? _store.newNoteId();
    _host.targetChanged(note);
  }

  /// The note aimed at, read again from the store in the background: a candidate carries no tape or phrases, which
  /// the sound kept at Done lines up with. It replaces `target` only while the take is still aimed there.
  /// Synchronous to call, so a phrase committed straight after a switch lands in the new note; Done waits for it
  /// (`refreshed`).
  void refresh(String id) {
    _refreshing = _refreshing.then((_) async {
      Note? full;
      try {
        full = await _store.getNote(id);
      } catch (_) {
        full = null;
      }
      if (full != null && target?.id == id) {
        target = full;
        _host.targetChanged(full);
      }
      return null;
    });
  }

  /// Every `refresh` asked for so far, done.
  Future<Object?> refreshed() => _refreshing;

  /// What the drafts wrote stays where it is: Discard no longer takes it back, and the base is read afresh when next
  /// needed. The take carrying on elsewhere ("New note"), at once, before the note it goes on to is known.
  void keepDraft() {
    _drafted = false;
    _base = null;
  }

  /// How the words go into the note being written changed: a heading said for them, or a to-do.
  void setPlacing(Placing placing) {
    this.placing = placing;
  }

  /// A command changed the note being recorded onto, outside `updateNote`: its new body is the base the words go
  /// under.
  void rebase(Note note) {
    if (target?.id != note.id) return;
    target = note;
    _base = Future<String>.value(note.body);
    _host.targetChanged(note);
  }

  /// Every write asked for so far, done: what Done waits on before it writes the note itself.
  Future<Object?> settled() => _chain;

  /// A write to a note, after every write before it, whether that one worked or not.
  Future<T> queue<T>(Future<T> Function() run) {
    final done = _chain.then<T>((_) => run(), onError: (Object _) => run());
    _chain = done.then<Object?>((value) => value, onError: (Object _) => null);
    return done;
  }

  Future<String> _readBase(Note continued) async {
    Note? stored;
    try {
      stored = await _store.getNote(continued.id);
    } catch (_) {
      stored = null;
    }
    return stored?.body ?? continued.body;
  }

  /// The body to store: this capture's markdown in the continued note's text, where its placing says, if there is
  /// one.
  Future<String> compose(String markdown) async {
    final continued = target;
    if (continued == null) return markdown;
    final base = _base ??= _readBase(continued);
    return placeTake(await base, markdown, placing).body;
  }

  /// The take's words into the note [id], an existing note, once: read fresh, placed where [placing] says, and
  /// stored through `apply_command` (a compare-and-swap on the body and the revision). A conflict - the note changed
  /// between the read and the write - reads and places once more; a second, or a note deleted meanwhile, makes the
  /// words a note of their own ([fallback], titled), so they are never lost and never overwrite anyone's edit.
  Future<WrittenInto> writeInto(String id, String markdown, Placing placing, String Function() fallback) {
    return queue(() async {
      for (var attempt = 0; attempt < 2; attempt += 1) {
        Note? fresh;
        try {
          fresh = await _store.getNote(id);
        } catch (_) {
          fresh = null;
        }
        if (fresh == null) break;
        final placed = placeTake(fresh.body, markdown, placing);
        if (placed.body == fresh.body) {
          return WrittenInto(saved: fresh, before: fresh.body, blocks: const [], spot: placed.spot, mutationId: null, own: false);
        }
        final mutationId = _store.newNoteId();
        CommandMutationResult? result;
        try {
          result = await _store.applyCommandMutation(CommandMutationRequest(
            mutationId: mutationId,
            noteId: fresh.id,
            kind: 'append',
            beforeRevision: fresh.revision,
            beforeBody: fresh.body,
            afterBody: placed.body,
            source: fresh.source,
          ));
        } catch (_) {
          result = null;
        }
        if (result is CommandMutationResultApplied) {
          remember(result.note);
          if (target?.id == result.note.id) target = result.note;
          return WrittenInto(saved: result.note, before: fresh.body, blocks: placed.blocks, spot: placed.spot, mutationId: mutationId, own: false);
        }
      }
      final made = await _store.createNote(_store.newNoteId(), fallback(), NoteSource.capture);
      return WrittenInto(saved: made, before: null, blocks: const [], spot: null, mutationId: null, own: true);
    });
  }

  /// Stores [body] as note [id]: a birth, or a revision-checked edit of a note this capture knows; never an upsert
  /// of a missing id.
  Future<Note> persist(String id, String body, [NoteSource source = NoteSource.capture]) async {
    final known = target?.id == id
        ? target
        : _draft?.id == id
            ? _draft
            : null;
    final saved = known != null ? await _store.updateNote(id, body, known.revision) : await _store.createNote(id, body, source);
    if (target?.id == id) {
      target = saved;
      _host.targetChanged(saved);
    } else if (noteId == id) {
      _draft = saved;
    }
    remember(saved);
    return saved;
  }

  /// The words so far, written to the note they were said for now rather than waiting for Done.
  Future<void> flushDraft() async {
    if (!_host.hasWords()) return;
    await queue(() async {
      _drafted = true;
      final body = await compose(_host.markdown(target == null));
      await persist(noteId, body, NoteSource.capture);
    });
  }

  /// Undoes whatever drafts wrote: the continued note gets its text back, a new note goes.
  Future<void> undoDraft() async {
    if (!_drafted) return;
    _drafted = false;
    await _chain;
    final continued = target;
    if (continued != null) {
      final base = _base;
      await persist(continued.id, base != null ? await base : continued.body, continued.source);
    } else {
      await _store.deleteNote(noteId);
    }
  }

  /// A note's body rewritten by [change], in turn with every other write: the new body, or null when there is no
  /// such note or the change changed nothing.
  ///
  /// The note being recorded onto is the special case: the change goes into the note as it was before this take's
  /// words, and the words are composed onto the end of that again. Applied to the stored note, which already holds
  /// the words a draft saved, they were composed on a second time at the next save.
  Future<String?> updateNote(String id, String? Function(String body) change) {
    return queue(() async {
      final fresh = await _store.getNote(id);
      if (fresh == null) return null;
      final continued = target;
      if (continued?.id == id) {
        // No draft composed yet means the store holds the note as it was; otherwise the base is what drafts build on.
        final base = await (_base ??= Future<String>.value(fresh.body));
        final next = change(base);
        if (next == null || next == base) return null;
        _base = Future<String>.value(next);
        final updated = fresh.copyWith(body: next);
        target = updated;
        // The page shows the change land, in its place above the words being said.
        _host.targetChanged(updated);
        final known = _named(id);
        if (known != null) known.note = updated;
        final saved = await _store.updateNote(id, placeTake(next, _host.markdown(false), placing).body, fresh.revision);
        target = saved;
        if (known != null) known.note = saved;
        return next;
      }
      final body = change(fresh.body);
      if (body == null || body == fresh.body) return null;
      final saved = await _store.updateNote(id, body, fresh.revision);
      remember(saved);
      return body;
    });
  }

  /// The command list's copy of note [id], if it has one.
  NamedNote? _named(String id) {
    for (final candidate in _host.candidates()) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  /// [saved] in place of the command list's copy of it, so the next command reads what is stored.
  void remember(Note saved) {
    final known = _named(saved.id);
    if (known != null) known.note = saved;
  }
}
