/// A [Note] to and from the JSON the Rust core speaks: the `Note` of `src-tauri/src/note.rs`, camelCase, which is
/// also the page's `Note` (`src/app/core/store.ts`).
///
/// Read forgivingly, as the page reads it by a cast: a field the core leaves out, or says as null, is the note
/// without it. `segments` and `formatted` are null on a note from `list_notes` and filled only by `get_note`;
/// `path` is left out for a draft with no file; `revision` reads as 1 where it is not said. `source` is a free
/// string there: `editor` and `capture` are [NoteSource], and any other word is kept beside it ([Note.sourceName])
/// so the note goes back as it came.
///
/// What differs: the page hands a note to `store_apply` as the object it holds, whatever its fields; here it is
/// written out whole ([noteToJson]), every field said, `starred` always (core/store.ts `applyNote` fills it for the
/// binaries up to generation 25 that refuse a note without one) and `path` only when there is one, as note.rs
/// itself writes it.
library;

import 'note.dart';

int? _int(Object? raw) => raw is num && raw.isFinite ? raw.toInt() : null;

/// One phrase of a recording, or null for anything that is not one.
Segment? segmentFromJson(Object? raw) {
  if (raw is! Map) return null;
  final text = raw['text'], start = _int(raw['startMs']), end = _int(raw['endMs']);
  if (text is! String || start == null || end == null) return null;
  return Segment(text: text, startMs: start, endMs: end);
}

Map<String, Object?> segmentToJson(Segment segment) => {'text': segment.text, 'startMs': segment.startMs, 'endMs': segment.endMs};

/// The note the core answered, or null for an answer that is not a note: `null` itself (`get_note` for an id
/// nothing answers to, a pin of a note that has gone), or a shape with no id or no words.
Note? noteFromJson(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'], body = raw['body'];
  if (id is! String || body is! String) return null;
  final source = raw['source'];
  final known = source == 'capture' ? NoteSource.capture : NoteSource.editor;
  final segments = raw['segments'];
  final createdAt = _int(raw['createdAt']) ?? 0;
  return Note(
    id: id,
    body: body,
    createdAt: createdAt,
    updatedAt: _int(raw['updatedAt']) ?? createdAt,
    source: known,
    sourceName: source is String && source != known.name ? source : null,
    starred: raw['starred'] == true,
    archivedAt: _int(raw['archivedAt']),
    recordingMs: _int(raw['recordingMs']),
    segments: segments is List ? List.unmodifiable([for (final each in segments) ?segmentFromJson(each)]) : null,
    formatted: raw['formatted'] is String ? raw['formatted'] as String : null,
    formattedFor: _int(raw['formattedFor']),
    formattedModel: raw['formattedModel'] is String ? raw['formattedModel'] as String : null,
    path: raw['path'] is String ? raw['path'] as String : null,
    revision: _int(raw['revision']) ?? 1,
  );
}

/// Every note of a `list_notes` answer, in the order it came; what is not a note is left out, and an answer that is
/// not a list is no notes.
List<Note> notesFromJson(Object? raw) => [
      if (raw is List)
        for (final each in raw) ?noteFromJson(each),
    ];

/// The note as the core reads one (`store_apply`'s `note`).
Map<String, Object?> noteToJson(Note note) => {
      'id': note.id,
      'body': note.body,
      'createdAt': note.createdAt,
      'updatedAt': note.updatedAt,
      'source': note.sourceWord,
      'starred': note.starred,
      'archivedAt': note.archivedAt,
      'recordingMs': note.recordingMs,
      'segments': note.segments == null ? null : [for (final segment in note.segments!) segmentToJson(segment)],
      'formatted': note.formatted,
      'formattedFor': note.formattedFor,
      'formattedModel': note.formattedModel,
      if (note.path != null) 'path': note.path,
      'revision': note.revision,
    };
