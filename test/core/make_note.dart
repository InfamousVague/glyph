import 'package:ghost_md/core/note.dart';

/// A note for a test: an id, the words, and whatever else the test is about (the web's `test/notes.ts` `makeNote`).
Note makeNote(String id, {String? body, int createdAt = 0, int updatedAt = 0, NoteSource source = NoteSource.editor, bool starred = false, int? archivedAt, int? recordingMs}) =>
    Note(id: id, body: body ?? '# $id', createdAt: createdAt, updatedAt: updatedAt, source: source, starred: starred, archivedAt: archivedAt, recordingMs: recordingMs);

List<String> ids(Iterable<Note> notes) => [for (final n in notes) n.id];
