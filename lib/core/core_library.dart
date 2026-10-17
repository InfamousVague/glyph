/// The real notes: [NoteLibrary] over the Rust core (lib/core/native/core.dart). A port of `src/app/core/store.ts`,
/// the Tauri half of each function and the `useNotes` hook, which is where the first read's retries and the read
/// again on coming back to the front are.
///
/// Every command is the web's own by name and arguments (docs/STAGE3.md): `list_notes`, `get_note {id}`,
/// `create_note {id, body, source}`, `update_note {id, body, expectedRevision}`, `delete_note {id}`,
/// `set_note_starred {id, starred}`, `set_note_archived {id, archived}`, `store_apply {note}`,
/// `apply_command_mutation {request}`, `undo_command_mutation {mutationId}`.
///
/// What differs:
/// - **A write is put in the list from the core's own answer**, and a write's future completes once it has been:
///   the note `update_note`, `create_note`, a pin, an archive or `store_apply` answers is the note as the library
///   now has it, so it takes its place among the others (newest edit first, the core's own order between two of one
///   moment: by id) and the list is not read again for it. On the page each caller refreshes after its own write
///   (`announceNotesChanged`, or the hook's `refresh`), and an open note's saves read nothing until it is left;
///   here the whole library was read again after every one, every 400 ms of typing, and its listeners told twice.
///   A command's write and its undo still read again: an undo can take a note out of the library and says only that
///   it did.
/// - **A listener is told once, and only of a change.** A note that is the same, field for field, after a read
///   again is the object it was ([Note.==]), and the list itself is the list it was while no note in it is another:
///   `identical` answers "did the notes change" and "did this note", and [revision] counts the times they did.
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

import '../perf/frame_log.dart';
import 'attachment_refs.dart' show noteGoneForGood, tellNoteGone;
import 'command_mutations.dart';
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

  /// The notes as `list_notes` last answered, newest edit first, and where two were written in one millisecond in
  /// the core's order for them, by id (`ORDER BY modified_at DESC, id`, src-tauri/src/library/index.rs).
  List<Note> _listed = const [];

  /// Notes made here that the list has not answered yet: a draft with no file, or a note whose write is on its way.
  /// The newest made first.
  final Map<String, Note> _made = {};

  /// Notes hidden for this run by [delete].
  final Set<String> _taken = {};

  List<Note> _value = const [];

  /// [_value] by id, made the first time a note is asked for after the list changed.
  Map<String, Note>? _index;
  int _revision = 0;
  bool _loading = true;
  Object? _firstReadError;
  Future<void>? _loaded;
  AppLifecycleListener? _resumes;
  bool _gone = false;

  /// One read of the list at a time: a second asked for meanwhile runs after it, once, however many asked.
  Future<void>? _reading;
  bool _readAgain = false;

  final ValueNotifier<int> _touched = ValueNotifier<int>(0);

  /// Every note, drafts first. The same list object for as long as no note in it is another object, so
  /// `identical(library.value, last)` is "nothing changed".
  @override
  List<Note> get value => _value;

  /// How many times the notes have changed: one more whenever [value] is another list, and never for a read that
  /// found the library as it was.
  int get revision => _revision;

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

  final StreamController<SavedHere> _savedHere = StreamController<SavedHere>.broadcast();

  /// Each note whose words this device changed, made, saved or changed by a command, with its words before: what
  /// an outgoing webhook hears (lib/integrations/webhooks). Never a note written as another device has it ([apply]),
  /// nor a pin or an archive.
  Stream<SavedHere> get savedHere => _savedHere.stream;

  void _saved(Note? before, Note after) {
    if (_gone || (before != null && before.body == after.body)) return;
    _savedHere.add(SavedHere(before: before, after: after));
  }

  /// The list put together again from what is held, and the listeners told: once, and only where a note in it is
  /// another object than it was, or [told] says something else they read (whether the first read is over, why it
  /// failed) is.
  void _publish({bool told = false}) {
    if (_gone) return;
    if (_made.isNotEmpty) {
      final listed = {for (final note in _listed) note.id};
      _made.removeWhere((id, _) => listed.contains(id));
    }
    final next = <Note>[
      for (final note in _made.values.toList().reversed)
        if (!_taken.contains(note.id)) note,
      for (final note in _listed)
        if (!_taken.contains(note.id)) note,
    ];
    var moved = next.length != _value.length;
    for (var i = 0; !moved && i < next.length; i += 1) {
      moved = !identical(next[i], _value[i]);
    }
    if (moved) {
      _value = List.unmodifiable(next);
      _index = null;
      _revision += 1;
    }
    if (!moved && !told) return;
    if (ghostPerf) Perf.count('library.notify');
    notifyListeners();
  }

  /// Where [note] belongs among [notes]: before the first that is older, or as old with an id after its own.
  static int _placeOf(List<Note> notes, Note note) {
    for (var i = 0; i < notes.length; i += 1) {
      final each = notes[i];
      if (each.updatedAt < note.updatedAt || (each.updatedAt == note.updatedAt && each.id.compareTo(note.id) > 0)) return i;
    }
    return notes.length;
  }

  /// The note the core just answered, put where it belongs in the list, which is not read again for it.
  void _put(Note note) {
    final at = _listed.indexWhere((each) => each.id == note.id);
    if (note.path == null) {
      // A draft: no file, so no list will answer it. One that had words and lost them all goes back to being one.
      _made[note.id] = note;
      if (at >= 0) _listed = [..._listed]..removeAt(at);
    } else {
      _made.remove(note.id);
      // What only `get_note` fills is left off, as the list leaves it.
      final light = note.segments == null && note.formatted == null
          ? note
          : Note(
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
      if (at >= 0 && _listed[at] == light) {
        // As it was: the object the listeners hold stays.
      } else if (at >= 0 && _listed[at].updatedAt == light.updatedAt) {
        // A pin, an archive: not an edit, and it keeps its place.
        _listed = [..._listed]..[at] = light;
      } else {
        final next = [..._listed];
        if (at >= 0) next.removeAt(at);
        _listed = next..insert(_placeOf(next, light), light);
      }
    }
    _publish();
  }

  /// `listNotes`: every note, newest edit first.
  Future<List<Note>> _list() async {
    final began = ghostPerf ? Perf.now() : 0;
    final listed = byRecency(notesFromJson(await _invoke('list_notes')));
    if (ghostPerf) Perf.add('library.list', began);
    return listed;
  }

  /// The list as it was just read. A note that reads the same as the one held is the one held, and the list held is
  /// kept where every note is.
  void _take(List<Note> next) {
    final had = <String, Note>{for (final note in _listed) note.id: note};
    var same = next.length == _listed.length;
    final kept = <Note>[];
    for (var i = 0; i < next.length; i += 1) {
      final read = next[i];
      final held = had[read.id];
      final keep = held != null && held == read ? held : read;
      if (same && !identical(keep, _listed[i])) same = false;
      kept.add(keep);
    }
    if (!same) _listed = kept;
    final told = _loading || _firstReadError != null;
    _loading = false;
    _firstReadError = null;
    _publish(told: told);
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
    if (ghostPerf) Perf.count('library.refresh by ${_asker()}');
    final reading = _reading;
    if (reading != null) {
      _readAgain = true;
      return reading;
    }
    return _reading = _read().whenComplete(() => _reading = null);
  }

  /// Who asked for the list to be read again, for a measured build's counts: the first function on the stack that
  /// is not the library's own.
  static String _asker() {
    for (final line in StackTrace.current.toString().split('\n').skip(1)) {
      if (line.contains('core_library.dart') || line.contains('<asynchronous suspension>') || line.trim().isEmpty) continue;
      final frame = RegExp(r'^#\d+\s+(.+?) \(').firstMatch(line);
      return frame?.group(1) ?? line.trim();
    }
    return 'nobody on the stack';
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
  Note? noteOf(String id) => (_index ??= {for (final note in _value) note.id: note})[id];

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
    final before = fresh ? null : noteOf(made);
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
    _put(stored);
    _saved(before, stored);
    return stored;
  }

  @override
  Future<Note> update(String id, String body, int expectedRevision) async {
    final before = noteOf(id);
    final stored = noteFromJson(await _invoke('update_note', {'id': id, 'body': body, 'expectedRevision': expectedRevision}));
    if (stored == null) throw noteChangedError();
    _touch();
    _put(stored);
    _saved(before, stored);
    return stored;
  }

  /// `applyCommandMutation`: the core's `apply_command`, which holds the note against what was previewed under the
  /// library's own lock and keeps the change in its index for [undoCommandMutation]. [touched] whatever it answers,
  /// as the page's is.
  @override
  Future<CommandMutationResult> applyCommandMutation(CommandMutationRequest request) async {
    final before = noteOf(request.noteId);
    final result = commandMutationResultFromJson(await _invoke('apply_command_mutation', {'request': commandMutationRequestToJson(request)}));
    _touch();
    if (result is! CommandMutationResultApplied) return result;
    _put(result.note);
    _saved(before, result.note);
    await _quietly();
    return result;
  }

  /// `undoCommandMutation`: the core's `undo_command`. A note that got its words back is put in the list at once;
  /// one the command had made is out of the list once it is read again, which this waits for.
  @override
  Future<CommandUndoResult> undoCommandMutation(String mutationId) async {
    final result = commandUndoResultFromJson(await _invoke('undo_command_mutation', {'mutationId': mutationId}));
    _touch();
    if (result is! CommandUndoResultUndone) return result;
    final restored = result.note;
    if (restored != null) _put(restored);
    await _quietly();
    return result;
  }

  /// `latestCommandMutation`: the core's `latest_command_mutation`, which reads the library's own index of commands.
  @override
  Future<PendingCommandUndo?> latestCommandMutation() async => pendingCommandUndoFromJson(await _invoke('latest_command_mutation'));

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
    // A note that has gone answers nothing: the list is read again, which is where it stops being in it.
    if (stored == null) return _quietly();
    _put(stored);
  }

  @override
  Future<void> pin(String id, {required bool pinned}) => _flag('set_note_starred', {'id': id, 'starred': pinned});

  @override
  Future<void> archive(String id, {required bool archived}) => _flag('set_note_archived', {'id': id, 'archived': archived});

  @override
  Future<void> destroy(String id) async {
    var body = _listed.where((note) => note.id == id).firstOrNull?.body;
    if (body == null && noteGoneForGood != null) {
      try {
        body = (await get(id))?.body;
      } catch (_) {
        // A note that will not be read leaves its files: the delete still happens.
      }
    }
    await _invoke('delete_note', {'id': id});
    // The files it linked, where no other note does: the core has just done the same for its pictures.
    tellNoteGone(id, body);
    _touch();
    _made.remove(id);
    _taken.remove(id);
    if (_listed.any((note) => note.id == id)) {
      _listed = [
        for (final note in _listed)
          if (note.id != id) note,
      ];
    }
    _publish();
  }

  /// `applyNote`. Not [touched]: a note written as another device has it is not one changed here.
  @override
  Future<Note> apply(Note note) async {
    final stored = noteFromJson(await _invoke('store_apply', {'note': noteToJson(note)}));
    if (stored == null) throw const CoreError('the note was written, and the library did not say how');
    _put(stored);
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
    unawaited(_savedHere.close());
    super.dispose();
  }
}

/// A note's words changed on this device by this device's own hand ([CoreLibrary.savedHere]): the note as it was
/// before, null for one made just now, and as it is after.
@immutable
class SavedHere {
  const SavedHere({this.before, required this.after});
  final Note? before;
  final Note after;
}
