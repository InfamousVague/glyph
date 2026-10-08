/// The real notes: [NoteLibrary] over the Rust core (lib/core/native/core.dart). A port of `src/app/core/store.ts`,
/// the Tauri half of each function and the `useNotes` hook, which is where the first read's retries and the read
/// again on coming back to the front are.
///
/// Every command is the web's own by name and arguments (docs/STAGE3.md): `list_notes`, `get_note {id}`,
/// `create_note {id, body, source}`, `update_note {id, body, expectedRevision}`, `delete_note {id}`,
/// `set_note_starred {id, starred}`, `set_note_archived {id, archived}`, `store_apply {note}`.
///
/// What differs:
/// - **A write reads the list again by itself**, and a write's future completes once it has, where on the page each
///   caller refreshes after its own (`announceNotesChanged`, or the hook's `refresh`). The note a command answers is
///   put in the list at once, before that read, so a pin is seen on the next frame.
/// - **A new note is in the list before the core has answered** ([create]), and a blank one stays in it: the core
///   holds a note with no words as a draft with no file and leaves it out of `list_notes`, and the page shows such a
///   note by handing it straight to the note screen. The shell here opens only what the list holds, so the drafts
///   made in this run are kept at the head of the list until they have a file or are deleted ([isDraft] says which
///   they are, for a screen that would rather not draw them).
/// - **A first read that fails every time** leaves [loading] true, as the page does, and is also said as
///   [firstReadError], so a screen can say something where the page stays blank.
/// - `NOTE_SAVED`, the event the sync engine sends a note on, is [touched]; `NOTES_CHANGED` is calling [refresh].
/// - [delete] and [restore] change nothing in the library: they hide a note for this run and show it again. They are
///   the shell's from before the trash was a preference, and deleting for good is [destroy] alone.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'library.dart';
import 'native/core.dart';
import 'note.dart';
import 'note_json.dart';

/// Retries for the first read of the list: a store still opening, or an index busy after an install
/// (`FIRST_READ_RETRIES_MS`).
const List<Duration> firstReadRetries = [Duration(milliseconds: 250), Duration(milliseconds: 900), Duration(milliseconds: 2400)];

/// How long after an empty first answer the list is asked once more: a library that was there a launch ago is more
/// likely still there than gone.
const Duration emptyFirstReadWait = Duration(milliseconds: 1200);

/// [NoteLibrary] over the Rust core.
class CoreLibrary extends ChangeNotifier implements NoteLibrary {
  /// [invoke] is the core (the FFI's, or a test's fake). [resume] reads the notes again whenever the app comes back
  /// to the front, from [load] on; a test with no binding turns it off. [wait] is how a retry waits, and [clock] the
  /// time a new note is given until the core answers with its own.
  CoreLibrary(
    this._invoke, {
    bool resume = true,
    int Function()? clock,
    Random? random,
    Future<void> Function(Duration time)? wait,
    void Function(String message)? log,
  })  : _resume = resume,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _random = random,
        _wait = wait ?? ((time) => Future<void>.delayed(time)),
        _log = log ?? debugPrint;

  final CoreInvoke _invoke;
  final bool _resume;
  final int Function() _clock;
  final Random? _random;
  final Future<void> Function(Duration time) _wait;
  final void Function(String message) _log;

  /// The notes as `list_notes` last answered, newest edit first.
  List<Note> _listed = const [];

  /// Notes made here that the list has not answered yet: a draft with no file, or a note whose write is on its way.
  /// The newest made first.
  final Map<String, Note> _made = {};

  /// Notes hidden for this run by [delete].
  final Set<String> _taken = {};

  List<Note> _value = const [];
  bool _loading = true;
  Object? _firstReadError;
  Future<void>? _loaded;
  AppLifecycleListener? _resumes;
  bool _gone = false;

  /// One read of the list at a time: a second asked for meanwhile runs after it, once, however many asked.
  Future<void>? _reading;
  bool _readAgain = false;

  final ValueNotifier<int> _touched = ValueNotifier<int>(0);

  @override
  List<Note> get value => _value;

  @override
  bool get loading => _loading;

  /// Why the notes could not be read, when every try of the first read failed; null otherwise, and again once a
  /// later read has answered.
  Object? get firstReadError => _firstReadError;

  /// Told after this device changes a note, so sync sends it soon (`NOTE_SAVED`). Its value only counts.
  ValueListenable<int> get touched => _touched;

  /// Whether the note is one made here that has no file yet.
  bool isDraft(String id) => _made[id]?.path == null && _made.containsKey(id);

  void _touch() {
    if (!_gone) _touched.value += 1;
  }

  void _publish() {
    if (_gone) return;
    final listed = {for (final note in _listed) note.id};
    _made.removeWhere((id, _) => listed.contains(id));
    _value = List.unmodifiable([
      for (final note in _made.values.toList().reversed)
        if (!_taken.contains(note.id)) note,
      for (final note in _listed)
        if (!_taken.contains(note.id)) note,
    ]);
    notifyListeners();
  }

  /// The note the core just answered, put where it belongs in the list before the list is read again.
  void _put(Note note) {
    if (note.path == null) {
      // A draft: no file, so no list will answer it. One that had words and lost them all goes back to being one.
      _made[note.id] = note;
      _listed = [
        for (final each in _listed)
          if (each.id != note.id) each,
      ];
    } else if (_made.containsKey(note.id)) {
      _made[note.id] = note;
    } else if (_listed.any((each) => each.id == note.id)) {
      // What only `get_note` fills is left off, as the list leaves it.
      final light = Note(
        id: note.id,
        body: note.body,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        source: note.source,
        sourceName: note.sourceName,
        starred: note.starred,
        archivedAt: note.archivedAt,
        recordingMs: note.recordingMs,
        formattedFor: note.formattedFor,
        formattedModel: note.formattedModel,
        path: note.path,
        revision: note.revision,
      );
      _listed = byRecency([for (final each in _listed) each.id == note.id ? light : each]);
    } else {
      return;
    }
    _publish();
  }

  /// `listNotes`: every note, newest edit first.
  Future<List<Note>> _list() async => byRecency(notesFromJson(await _invoke('list_notes')));

  void _take(List<Note> next) {
    _listed = next;
    _loading = false;
    _firstReadError = null;
    _publish();
  }

  @override
  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    if (_resume) _resumes = AppLifecycleListener(onResume: () => unawaited(_quietly()));
    // The first read is the one that can go wrong: on a phone the store may still be opening, or its index busy right
    // after an install. So a failed first read is tried again a few times, and an empty first answer is asked once
    // more a moment later.
    for (var attempt = 0;; attempt += 1) {
      try {
        final next = await _list();
        if (_gone) return;
        _take(next);
        if (next.isEmpty && attempt == 0) {
          _log('[glyph] first read of the notes was empty; asking again');
          await _wait(emptyFirstReadWait);
          if (!_gone) await _quietly();
        }
        return;
      } catch (error) {
        if (attempt >= firstReadRetries.length) {
          _log('[glyph] the notes could not be read: $error');
          if (_gone) return;
          _firstReadError = error;
          notifyListeners();
          return;
        }
        await _wait(firstReadRetries[attempt]);
        if (_gone) return;
      }
    }
  }

  /// Reads the notes again; an error is the caller's, as the page's `refresh` rejects.
  @override
  Future<void> refresh() {
    final reading = _reading;
    if (reading != null) {
      _readAgain = true;
      return reading;
    }
    return _reading = _read().whenComplete(() => _reading = null);
  }

  Future<void> _read() async {
    do {
      _readAgain = false;
      final next = await _list();
      if (_gone) return;
      _take(next);
    } while (_readAgain);
  }

  /// A read nobody is waiting on: after a write, on coming back to the front. What goes wrong is said and no more,
  /// since the list as it stands is still the best there is.
  Future<void> _quietly() async {
    try {
      await refresh();
    } catch (error) {
      _log('[glyph] the notes could not be read again: $error');
    }
  }

  @override
  Note? noteOf(String id) {
    for (final note in _value) {
      if (note.id == id) return note;
    }
    return null;
  }

  @override
  Future<Note?> get(String id) async => noteFromJson(await _invoke('get_note', {'id': id}));

  @override
  Note create(String body, {NoteSource source = NoteSource.editor}) {
    final id = newNoteId(_random);
    unawaited(createNote(body, source: source, id: id).then<void>((_) {}, onError: (Object error) => _log('[glyph] the note could not be made: $error')));
    return _made[id]!;
  }

  @override
  Future<Note> createNote(String body, {NoteSource source = NoteSource.editor, String? id}) async {
    final made = id ?? newNoteId(_random);
    final at = _clock();
    final fresh = !_made.containsKey(made) && noteOf(made) == null;
    if (fresh) {
      _made[made] = Note(id: made, body: body, createdAt: at, updatedAt: at, source: source);
      _publish();
    }
    final Note stored;
    try {
      final answer = noteFromJson(await _invoke('create_note', {'id': made, 'body': body, 'source': source.name}));
      if (answer == null) throw const CoreError('the note was made, and the library did not say how');
      stored = answer;
    } catch (_) {
      if (fresh) {
        _made.remove(made);
        _publish();
      }
      rethrow;
    }
    _touch();
    _made[made] = stored;
    _publish();
    await _quietly();
    return stored;
  }

  @override
  Future<Note> update(String id, String body, int expectedRevision) async {
    final stored = noteFromJson(await _invoke('update_note', {'id': id, 'body': body, 'expectedRevision': expectedRevision}));
    if (stored == null) throw noteChangedError();
    _touch();
    _put(stored);
    await _quietly();
    return stored;
  }

  @override
  Future<Note> save(String id, String body) async {
    final known = noteOf(id);
    if (known == null) throw noteChangedError();
    try {
      return await update(id, body, known.revision);
    } catch (_) {
      Note? stored;
      try {
        stored = await get(id);
      } catch (_) {
        stored = null;
      }
      final transcript = transcriptToRebaseOver(stored, known.body);
      if (stored == null || transcript == null) rethrow;
      return update(id, withTranscript(body, transcript), stored.revision);
    }
  }

  Future<void> _flag(String command, Map<String, Object?> args) async {
    final stored = noteFromJson(await _invoke(command, args));
    _touch();
    if (stored != null) _put(stored);
    await _quietly();
  }

  @override
  Future<void> pin(String id, {required bool pinned}) => _flag('set_note_starred', {'id': id, 'starred': pinned});

  @override
  Future<void> archive(String id, {required bool archived}) => _flag('set_note_archived', {'id': id, 'archived': archived});

  @override
  Future<void> destroy(String id) async {
    await _invoke('delete_note', {'id': id});
    _touch();
    _made.remove(id);
    _taken.remove(id);
    _listed = [
      for (final note in _listed)
        if (note.id != id) note,
    ];
    _publish();
    await _quietly();
  }

  /// `applyNote`. Not [touched]: a note written as another device has it is not one changed here.
  @override
  Future<Note> apply(Note note) async {
    final stored = noteFromJson(await _invoke('store_apply', {'note': noteToJson(note)}));
    if (stored == null) throw const CoreError('the note was written, and the library did not say how');
    _put(stored);
    await _quietly();
    return stored;
  }

  @override
  Note? delete(String id) {
    final note = noteOf(id);
    if (note == null) return null;
    _taken.add(id);
    _publish();
    return note;
  }

  @override
  void restore(Note note) {
    if (!_taken.remove(note.id)) return;
    _publish();
  }

  @override
  void dispose() {
    _gone = true;
    _resumes?.dispose();
    _touched.dispose();
    super.dispose();
  }
}
