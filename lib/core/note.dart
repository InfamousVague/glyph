import 'package:flutter/foundation.dart';

/// How a note came to exist: typed in the app, or spoken into a capture (`NoteSource`, src/app/core/store.ts).
enum NoteSource { editor, capture }

/// One phrase of a recording, with its times (`Segment`, core/store.ts).
@immutable
class Segment {
  const Segment({required this.startMs, required this.endMs, required this.text});
  final int startMs;
  final int endMs;
  final String text;
}

/// A note, as the web app's store holds it (`Note`, src/app/core/store.ts): its Markdown body and what the library
/// knows about it. Everything a screen shows of a note - its title, its workspace, whether it is a ticket or a
/// notebook - is read from the body, as there.
@immutable
class Note {
  const Note({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.source = NoteSource.editor,
    this.starred = false,
    this.archivedAt,
    this.recordingMs,
    this.segments,
    this.formatted,
    this.formattedFor,
    this.formattedModel,
    this.path,
    this.revision = 1,
  });

  final String id;
  final String body;

  /// Milliseconds since the epoch.
  final int createdAt;
  final int updatedAt;
  final NoteSource source;

  /// Pinned to the top of the list.
  final bool starred;

  /// When it was put in the archive; null for a note in the list.
  final int? archivedAt;

  /// The kept recording's length, for a spoken note whose tape was kept.
  final int? recordingMs;
  final List<Segment>? segments;

  /// The on-device model's version of the body, the hash of the body it was written from, and the model's id.
  final String? formatted;
  final int? formattedFor;
  final String? formattedModel;

  /// Where the note's file is in the library, relative to it (`Inbox/AttackFM.md`).
  final String? path;

  /// The body's version, counted up at each write.
  final int revision;

  Note copyWith({String? body, int? updatedAt, bool? starred, int? Function()? archivedAt, String? Function()? path, int? revision}) => Note(
        id: id,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        source: source,
        starred: starred ?? this.starred,
        archivedAt: archivedAt == null ? this.archivedAt : archivedAt(),
        recordingMs: recordingMs,
        segments: segments,
        formatted: formatted,
        formattedFor: formattedFor,
        formattedModel: formattedModel,
        path: path == null ? this.path : path(),
        revision: revision ?? this.revision,
      );
}
