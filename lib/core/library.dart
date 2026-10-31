/// The notes, and the one door the app uses to reach them. A port of the public half of `src/app/core/store.ts`
/// (`listNotes`, `getNote`, `createNote`, `updateNote`, `applyCommandMutation`, `undoCommandMutation`,
/// `setNoteStarred`, `setNoteArchived`, `deleteNote`, `applyNote`, `listOrder`, `archiveOrder`, `newNoteId`, and the
/// `useNotes` hook's `notes`, `loading` and `refresh`), with the saving of an open note from
/// `src/app/editor/useNoteSaving.ts` ([NoteSaving]) and the three readings of a transcript it leans on from
/// `src/app/capture/markdown.ts`.
///
/// The library is the Rust core's (docs/STAGE3.md): Markdown files are the truth, and this is a typed remote
/// control. [NoteLibrary] is the interface a screen is given; lib/core/core_library.dart is the real one over the
/// core, and lib/core/sample_library.dart the invented one in memory.
///
/// What differs:
/// - The page has module functions and a hook; here they are one object that is listened to. Its value is the hook's
///   `notes`, [NoteLibrary.loading] its `loading`, and a write reads the list again by itself, where the page's
///   callers each call `refresh` (or `announceNotesChanged`) after theirs.
/// - [NoteLibrary.create] answers at once, with the note as it will be, and the write follows; the page awaits
///   `createNote` before it shows the note. [NoteLibrary.createNote] is the awaited one.
/// - [NoteLibrary.save] is not on the page: it is `updateNote` from the revision the list holds, with the editor's
///   rebase when the phone's write-up got there first. An open note is saved by a [NoteSaving], as on the page.
/// - Deleting is two things with two names: the trash is a preference (lib/core/kept_trash.dart) and touches no
///   note; [NoteLibrary.destroy] is the page's `deleteNote`, for good. [NoteLibrary.delete] and
///   [NoteLibrary.restore] are what the shell did before there was a trash, kept so it still builds.
/// - A command's write and its undo ([NoteLibrary.applyCommandMutation], [NoteLibrary.undoCommandMutation]) are
///   asked and answered in the shapes of lib/core/command_mutations.dart, and so is the one still undoable after
///   the app was stopped ([NoteLibrary.latestCommandMutation], which the root asks once at launch, as
///   `shell/useHousekeeping.ts` does). `setNoteRecording` is the recorder's still (lib/capture/recorder.dart).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../book/follow_rename.dart' show followRename;
import 'command_mutations.dart';
import 'native/core.dart';
import 'note.dart';
import 'note_text.dart';

/// What the store says when a save meets a note that is gone or has moved on (`updateNote`, and `update_note` in
/// src-tauri/src/commands.rs).
const String noteChanged = 'the note was deleted or changed';

/// What the store says when a new note's id is taken (`createNote`, `create_note`).
const String noteIdTaken = 'the note id already exists';

/// The notes, and what the app does to them (`core/store.ts`). Listen to it: its value is every note the library
/// holds, the newest edit first, and it tells its listeners when the notes or [loading] change.
///
/// What a listener can lean on to do no more than it must: the value is the same list object for as long as no note
/// in it changed, and a note that did not change is the same [Note] object from one value to the next, so
/// `identical` is the question to ask of either. A screen that shows one note listens to that note alone
/// ([NoteWatch]).
abstract class NoteLibrary implements ValueListenable<List<Note>> {
  /// Whether the notes have yet to be read for the first time (`useNotes().loading`).
  bool get loading;

  /// The first read of the notes, tried again where it fails (`useNotes`'s effect). Asked twice, it reads once.
  Future<void> load();

  /// Reads the notes again: what a pull down the page asks for, and what follows every write (`refresh`).
  Future<void> refresh();

  /// The note by that id as the list holds it, or null. Without what only [get] answers (its recording's phrases,
  /// its formatted version).
  Note? noteOf(String id);

  /// The note whole, as its file now says, or null when nothing answers to that id (`getNote`).
  Future<Note?> get(String id);

  /// A new note with those words, first in the list at once; the write follows. Blank, it is a draft with no file
  /// until it has words (docs/STAGE3.md).
  Note create(String body, {NoteSource source = NoteSource.editor});

  /// A new note with those words, answered as the library stored it (`createNote`, with `newNoteId` for [id] unless
  /// one is given). An id already taken is an error.
  Future<Note> createNote(String body, {NoteSource source = NoteSource.editor, String? id});

  /// Writes [body] over exactly the revision the caller read (`updateNote`). A note that is gone, or has moved on, is
  /// an error and never a new note: a stale save must not bring a deleted note back.
  Future<Note> update(String id, String body, int expectedRevision);

  /// Applies exactly the words a command previewed, if the note is still the revision and the words the preview was
  /// made from (`applyCommandMutation`); a note that has moved on, or one that is there where a new one was to be
  /// made, is a conflict answered with the note as it now stands, and nothing is written. The change is kept for
  /// [undoCommandMutation].
  Future<CommandMutationResult> applyCommandMutation(CommandMutationRequest request);

  /// Takes a command's change back, only while the note is exactly what the command left (`undoCommandMutation`):
  /// a note it added to gets the words it had, and a note it made goes. A note changed since is a conflict and is
  /// left as it is; a change taken back already, or one nothing knows of, is said as that.
  Future<CommandUndoResult> undoCommandMutation(String mutationId);

  /// The command of the last ten minutes that can still be taken back, if any (`latestCommandMutation`): asked once
  /// at launch, so a command whose Undo went with the app when it was stopped is offered its Undo again.
  Future<PendingCommandUndo?> latestCommandMutation();

  /// Writes [body] over the note as the list holds it. Where the phone's write-up appended its transcript meanwhile,
  /// the save is made again over it (editor/useNoteSaving.ts), and the note answered carries the transcript; any
  /// other conflict is the store's error.
  Future<Note> save(String id, String body);

  /// Pins the note to the top, or takes its pin off (`setNoteStarred`). Not an edit: it keeps its place.
  Future<void> pin(String id, {required bool pinned});

  /// Puts the note in the archive, or brings it out again (`setNoteArchived`). Not an edit either.
  Future<void> archive(String id, {required bool archived});

  /// Moves the note's file into the trash folder, `.trash/<its path>`, versions and all (library/trash.rs
  /// `trash_note`; Matt, 2026-10-31: "a `.trash/` folder, as Obsidian does"). Not an edit: the note keeps its time
  /// and revision, and it stays in the list, with [Note.inTrash] saying where it is. One already there, or gone, is
  /// left as it is. The trash itself (which note went in when) is still the preference (lib/core/kept_trash.dart);
  /// lib/core/trash_files.dart keeps the two in step.
  Future<void> putInTrash(String id);

  /// Moves the note's file back out of the trash folder to the path it had, or into `Inbox/` when that folder is
  /// gone (`restore_note`). One not in the trash, or gone, is left as it is.
  Future<void> takeFromTrash(String id);

  /// Deletes the note for good (`deleteNote`): what emptying the trash does. One already gone is not an error.
  Future<void> destroy(String id);

  /// Writes a note exactly as it is given: its own times, pin, archive, folder and recording (`applyNote`). Only ever
  /// a note from [get], changed: one from the list has no phrases and no formatted version, and applying it would
  /// write that over what the library keeps beside the note (docs/STAGE3.md, the first trap).
  Future<Note> apply(Note note);

  /// Takes the note out of the list and answers it, for an Undo; null where there was none. What the shell did before
  /// the trash was a preference: use the trash (lib/core/trash.dart) and [destroy].
  Note? delete(String id);

  /// Puts back a note [delete] took, where it was.
  void restore(Note note);
}

/// One note of a library, for whatever shows one: told when that note is another object than it was (its words, its
/// pin, where its file is) or has gone, and not when any other note changed. It listens to the library only while
/// something listens to it, so one nobody follows costs nothing and needs no disposing.
class NoteWatch extends ChangeNotifier implements ValueListenable<Note?> {
  NoteWatch(this.library, this.id);

  final NoteLibrary library;
  final String id;
  Note? _note;

  /// The note as the library holds it now, or null where it holds none by that id.
  @override
  Note? get value => hasListeners ? _note : library.noteOf(id);

  void _heard() {
    final now = library.noteOf(id);
    if (identical(now, _note)) return;
    _note = now;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _note = library.noteOf(id);
      library.addListener(_heard);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) library.removeListener(_heard);
  }

  @override
  void dispose() {
    library.removeListener(_heard);
    super.dispose();
  }
}

/// The list as the list screen shows it: pinned notes first, each group newest edit first, archived notes left out
/// (`listOrder`).
List<Note> listOrder(Iterable<Note> notes) {
  final shown = [
    for (final note in notes)
      if (note.archivedAt == null || note.archivedAt == 0) note,
  ];
  mergeSort<Note>(shown, compare: (a, b) {
    final byPin = (b.starred ? 1 : 0) - (a.starred ? 1 : 0);
    return byPin != 0 ? byPin : b.updatedAt.compareTo(a.updatedAt);
  });
  return shown;
}

/// The archive: the reverse selection, most recently archived first (`archiveOrder`).
List<Note> archiveOrder(Iterable<Note> notes) {
  final shown = [
    for (final note in notes)
      if (note.archivedAt != null && note.archivedAt != 0) note,
  ];
  mergeSort<Note>(shown, compare: (a, b) => (b.archivedAt ?? 0).compareTo(a.archivedAt ?? 0));
  return shown;
}

/// Newest-updated first, the only order the list is ever held in (`byRecency`). Stable, as the page's sort is.
List<Note> byRecency(Iterable<Note> notes) {
  final sorted = [...notes];
  mergeSort<Note>(sorted, compare: (a, b) => b.updatedAt.compareTo(a.updatedAt));
  return sorted;
}

/// A fresh id for a note: a UUID v4 in its hyphenated form (`newNoteId`, core/ids.ts `randomId`), which is what the
/// library names a note's sidecar by and checks before it names a file (`fsx::plain_id`). The page's fallback for a
/// context with no `crypto.randomUUID` has no counterpart: there is always a random source here.
String newNoteId([Random? random]) {
  final from = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => from.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

// ---- the transcript (capture/markdown.ts) -------------------------------------------------------------------------

/// The heading a transcript sits under (`TRANSCRIPT_HEADING`).
const String transcriptHeading = '## Transcript';

final RegExp _transcriptLine = RegExp(r'^## Transcript[ \t]*$', multiLine: true);

/// The transcript section of a body, from its heading to the end, or null where there is none (`transcriptOf`).
String? transcriptOf(String body) {
  final at = _transcriptLine.firstMatch(body)?.start;
  return at == null ? null : body.substring(at).trimRight();
}

/// The body with [transcript] (a whole section, heading and all) in place of the one it has, or on its end
/// (`withTranscript`).
String withTranscript(String body, String transcript) {
  final section = transcript.trimRight();
  final at = _transcriptLine.firstMatch(body)?.start;
  if (at != null) return '${body.substring(0, at)}$section';
  final before = body.trimRight();
  return before.isEmpty ? section : '$before\n\n$section';
}

/// The body with its transcript section taken off, for telling a transcript that arrived from an edit
/// (`withoutTranscript`).
String withoutTranscript(String body) {
  final at = _transcriptLine.firstMatch(body)?.start;
  return (at == null ? body : body.substring(0, at)).trimRight();
}

/// The transcript a refused save may be made again over, or null where it may not: [stored] is the note as the
/// library has it now, and [written] the words it last took from this writer. The one writer allowed in is the
/// phone's write-up, which appends the transcript; when that is the whole difference between the two, the save is
/// rebased, and any other difference is somebody's words, which a rebase would drop (editor/useNoteSaving.ts).
String? transcriptToRebaseOver(Note? stored, String written) {
  if (stored == null) return null;
  final transcript = transcriptOf(stored.body);
  if (transcript == null || transcript == transcriptOf(written)) return null;
  return withoutTranscript(stored.body) == withoutTranscript(written) ? transcript : null;
}

// ---- saving the open note (editor/useNoteSaving.ts) ---------------------------------------------------------------

/// How long after the last keystroke the open note is saved (`SAVE_DEBOUNCE_MS`).
const Duration saveDebounce = Duration(milliseconds: 400);

/// The saves each note's last screen made, by the note's id: what the next screen on that note waits for before it
/// reads (`lastWrites`).
final Map<String, Future<void>> _lastWrites = {};

/// Saving the open note (`useNoteSaving`, src/app/editor/useNoteSaving.ts).
///
/// Two paths, as there: a debounce after the last keystroke, and a [flush] for every way the app or the screen can
/// go away (the app hidden or paused, the screen disposed of, and whatever way off the note the screen offers). The
/// live document is [body], and only [onChange] writes it. A save the library refuses is read again: where the
/// stored note differs from what was last written here by the phone's transcript alone the save is rebased over it
/// and the editor handed the result ([onExternalChange]); any other conflict stops the saving. And a note opened
/// again is read again, once the last screen on it has finished saving, and taken while nothing is typed here yet
/// ([adopt]).
///
/// A save that changes the note's title is followed into the notebooks and journals that list it
/// (lib/book/follow_rename.dart), from the last title the library held for it: an emptied heading is a rename still
/// being typed, followed once it has a title again.
///
/// What differs: the hook is a class, listened to for [title] and [blank] (the hook's state). The rename asked for
/// from the note's tab is the note's screen's (lib/note/note_screen.dart `renameHere`). A screen that saved anything
/// reads the list again as it goes ([dispose]), which is the page's `announceNotesChanged`.
class NoteSaving extends ChangeNotifier {
  NoteSaving(this.library, Note note, {this.onExternalChange, Duration debounce = saveDebounce, bool lifecycle = true, void Function(String message)? log})
      : id = note.id,
        _debounce = debounce,
        _log = log ?? debugPrint,
        _body = note.body,
        _saved = note.body,
        _written = note.body,
        _revision = note.revision,
        _title = noteTitle(note.body),
        _titled = noteTitle(note.body),
        _blank = note.body.trim().isEmpty {
    if (lifecycle) _hides = AppLifecycleListener(onHide: flush, onPause: flush, onDetach: flush);
    // The note as the library has it, once the last screen on it has finished saving: taken only while this screen has
    // saved nothing, and only when the library's is another revision than the copy this screen was opened with.
    // Another, not a higher one: a note a sync wrote carries the other device's count.
    unawaited(() async {
      try {
        await (_lastWrites[id] ?? Future<void>.value());
        final stored = await library.get(id);
        if (!_gone && stored != null && !_wrote && stored.revision != _revision) adopt(stored);
      } catch (_) {
        // The note stays as it was opened; the next save says what is wrong, if anything is.
      }
    }());
  }

  final NoteLibrary library;

  /// The note's id.
  final String id;

  /// The words changed under the editor - a transcript arrived - and the editor is to show them.
  final ValueChanged<String>? onExternalChange;

  final Duration _debounce;
  final void Function(String message) _log;
  AppLifecycleListener? _hides;

  String _body;
  String _saved;

  /// The body the library last took from here: what a conflict is measured against.
  String _written;
  int _revision;
  Future<void> _writes = Future<void>.value();

  /// Whether this screen has saved anything: said as it goes, so the list reads the note again.
  bool _wrote = false;
  bool _writable = true;
  Timer? _timer;
  bool _gone = false;
  String _title;
  bool _blank;

  /// The title the library last held for this note, not empty: a save that changes it is followed into its notebooks.
  String _titled;

  /// What the editor holds now: written by [onChange] and nothing else.
  String get body => _body;

  /// The note's first line, which is the only title it has.
  String get title => _title;

  /// No words at all yet.
  bool get blank => _blank;

  /// False once a save has been refused for good: nothing more is written from here.
  bool get writable => _writable;

  void _show(String next) {
    final title = noteTitle(next), blank = next.trim().isEmpty;
    if (title == _title && blank == _blank) return;
    _title = title;
    _blank = blank;
    if (!_gone) notifyListeners();
  }

  /// The editor shown words that came from outside it, and the header title with them.
  void _handOver(String next) {
    _show(next);
    onExternalChange?.call(next);
  }

  /// The editor's words changed: kept, and saved on the debounce.
  void onChange(String next) {
    _body = next;
    _show(next);
    _timer?.cancel();
    _timer = Timer(_debounce, flush);
  }

  /// Saves what is waiting now, if anything is. Safe to call as often as a way off the note is taken.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_body == _saved) return;
    final pending = _body;
    _saved = pending;
    _wrote = true;
    _writes = _writes.then((_) async {
      if (!_writable) return;
      try {
        final stored = await library.update(id, pending, _revision);
        _revision = stored.revision;
        _written = pending;
        // A page renamed keeps its place in its notebooks and journals (lib/book/follow_rename.dart).
        final now = noteTitle(pending);
        if (now.isNotEmpty && titleKey(now) != titleKey(_titled)) {
          final from = _titled;
          _titled = now;
          if (from.isNotEmpty) unawaited(followRename(library, id, from, now).then<void>((_) {}, onError: (Object _) {}));
        }
      } catch (failure) {
        // Another writer won, or the note was deleted. The one writer allowed is the phone's write-up, which appends
        // the transcript: when that is the whole difference, the save is made again over it.
        Note? stored;
        try {
          stored = await library.get(id);
        } catch (_) {
          stored = null;
        }
        final transcript = transcriptToRebaseOver(stored, _written);
        if (stored != null && transcript != null) {
          final rebased = withTranscript(pending, transcript);
          _revision = stored.revision;
          _saved = rebased;
          // Typed on since: the words in hand keep the transcript's place for the next save; else they are these.
          if (_body == pending) {
            _body = rebased;
            _handOver(rebased);
          } else {
            _body = withTranscript(_body, transcript);
          }
          try {
            final again = await library.update(id, rebased, _revision);
            _revision = again.revision;
            _written = rebased;
          } catch (second) {
            _writable = false;
            _log('[glyph] editor save stopped: $second');
          }
          return;
        }
        // Most importantly, this editor cannot bring a deleted note back.
        _writable = false;
        _log('[glyph] editor save stopped: $failure');
      }
    });
    _lastWrites[id] = _writes;
  }

  /// Saves what is waiting and completes once every save from here has been answered: a pull to refresh waits on it.
  Future<void> settled() {
    flush();
    return _writes;
  }

  /// The note as the library has it now, taken as the editor's words and revision, when nothing here is unsaved:
  /// true when it was taken, and the editor was handed the words. False with an edit still to save, or a save
  /// flushed and not yet answered, which the next save's rebase looks after.
  bool adopt(Note stored) {
    if (!_writable || _body != _saved || _written != _saved) return false;
    _revision = stored.revision;
    _written = stored.body;
    if (stored.body == _body) return true;
    _body = stored.body;
    _saved = stored.body;
    _handOver(stored.body);
    return true;
  }

  /// The screen is going: what is waiting is saved, and the list reads the note again once it has landed.
  @override
  void dispose() {
    flush();
    _gone = true;
    _hides?.dispose();
    if (_wrote) {
      unawaited(_writes.then((_) => library.refresh()).catchError((Object error) => _log('[glyph] the notes could not be read again: $error')));
    }
    super.dispose();
  }
}

/// A save refused because the note is gone or has moved on, as the store words it.
CoreError noteChangedError() => const CoreError(noteChanged);
