import 'package:ghost_md/core/note.dart';

/// A note for a test: an id, the words, and whatever else the test is about - everything else a note typed in the
/// editor at the start of time, so a fixture says only what matters to it. A port of the web's `src/test/notes.ts`,
/// whose `over: Partial<Note>` is the named parameters here.
Note makeNote(String id, {String? body, int createdAt = 0, int updatedAt = 0, NoteSource source = NoteSource.editor, int? archivedAt, int revision = 1}) =>
    Note(id: id, body: body ?? '# $id', createdAt: createdAt, updatedAt: updatedAt, source: source, archivedAt: archivedAt, revision: revision);
