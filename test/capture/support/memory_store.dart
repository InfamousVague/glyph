import 'package:ghost_md/core/note.dart';

/// The note store the web's capture tests run over (`core/store.ts` in the browser, on `localStorage`), as much of
/// it as they ask: notes made and read, a revision-checked write, and a command's change applied only to the body
/// and revision it was previewed on. Not a port of a test helper: the web tests use the store itself, which is not
/// in this port's reach, so a test here makes one of these where the web's clears `localStorage`.
class MemoryStore {
  final List<Note> _notes = [];
  int _clock = 0;
  int _ids = 0;

  int _now() => _clock += 1;

  /// `newNoteId`.
  String newNoteId() => 'n-test-${_ids += 1}';

  /// `listNotes`: every note, newest first.
  Future<List<Note>> listNotes() async {
    final sorted = <Note>[];
    for (final note in _notes) {
      var at = sorted.length;
      while (at > 0 && sorted[at - 1].updatedAt < note.updatedAt) {
        at -= 1;
      }
      sorted.insert(at, note);
    }
    return sorted;
  }

  /// `getNote`.
  Future<Note?> getNote(String id) async {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  /// `createNote`: a genuinely new note.
  Future<Note> createNote(String id, String body, [NoteSource source = NoteSource.editor]) async {
    if (_notes.any((note) => note.id == id)) throw StateError('the note id already exists');
    final now = _now();
    final note = Note(id: id, body: body, createdAt: now, updatedAt: now, source: source);
    _notes.insert(0, note);
    return note;
  }

  /// `updateNote`: exactly the revision the caller read.
  Future<Note> updateNote(String id, String body, int expectedRevision) async {
    final at = _notes.indexWhere((note) => note.id == id);
    if (at < 0 || _notes[at].revision != expectedRevision) throw StateError('the note was deleted or changed');
    final note = _notes[at].copyWith(body: body, updatedAt: _now(), revision: expectedRevision + 1);
    _notes[at] = note;
    return note;
  }

  /// `applyCommandMutation`: exactly the body that was previewed, if the previewed revision still exists.
  Future<({String status, Note? note, Note? current})> applyCommandMutation({
    required String mutationId,
    required String noteId,
    required String kind,
    required int? beforeRevision,
    required String? beforeBody,
    required String afterBody,
    required NoteSource source,
  }) async {
    final at = _notes.indexWhere((note) => note.id == noteId);
    final current = at < 0 ? null : _notes[at];
    final matches = beforeRevision == null ? current == null && beforeBody == null : current != null && current.revision == beforeRevision && current.body == beforeBody;
    if (!matches) return (status: 'conflict', note: null, current: current);
    final now = _now();
    final note = current != null
        ? current.copyWith(body: afterBody, updatedAt: now, revision: current.revision + 1)
        : Note(id: noteId, body: afterBody, createdAt: now, updatedAt: now, source: source);
    if (at >= 0) _notes.removeAt(at);
    _notes.insert(0, note);
    return (status: 'applied', note: note, current: null);
  }
}
