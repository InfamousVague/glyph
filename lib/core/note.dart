import 'package:flutter/foundation.dart';

/// How a note came to exist: typed in the app, or spoken into a capture (`NoteSource`, src/app/core/store.ts).
enum NoteSource { editor, capture }

/// The folder at the library's root that holds trashed notes' files (library/trash.rs `TRASH`; Matt, 2026-10-31:
/// "Trash: a `.trash/` folder, as Obsidian does"). A trashed note's file is at `.trash/<its path>`.
const String trashFolder = '.trash';

/// Whether a note's path is in the trash: under `.trash/` at the root (library/trash.rs `is_trashed_path`). A
/// `.trash` deeper down is another app's and no trash of ours; null is a draft with no file, which is not trashed.
bool isTrashedPath(String? path) => path != null && path.startsWith('$trashFolder/');

/// `.trash/<path>`: where a live note's file goes when it is trashed (`trashed_path_of`); a path already in the trash
/// is answered as it is.
String trashedPathOf(String path) => isTrashedPath(path) ? path : '$trashFolder/$path';

/// `<path>` for `.trash/<path>`, where a trashed note's file came from (`live_path_of`); a path not in the trash is
/// answered as it is, and null stays null.
String? livePathOf(String? path) => isTrashedPath(path) ? path!.substring(trashFolder.length + 1) : path;

/// One phrase of a recording, with its times (`Segment`, core/store.ts).
@immutable
class Segment {
  const Segment({required this.startMs, required this.endMs, required this.text});
  final int startMs;
  final int endMs;
  final String text;

  @override
  bool operator ==(Object other) => other is Segment && other.startMs == startMs && other.endMs == endMs && other.text == text;

  @override
  int get hashCode => Object.hash(startMs, endMs, text);
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
    this.sourceName,
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

  /// The source as the library said it, where it is neither of the two: the core keeps a free string (`source`,
  /// src-tauri/src/note.rs), and a note handed back whole (`store_apply`) must say the word it came with. Such a note
  /// reads as typed ([source] is [NoteSource.editor]), as the page's `source === 'capture'` reads it.
  final String? sourceName;

  /// The source's word as the library keeps it: `editor`, `capture`, or whatever else it was born with.
  String get sourceWord => sourceName ?? source.name;

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

  /// Where the note's file is in the library, relative to it (`Inbox/AttackFM.md`); under `.trash/` for a note in
  /// the trash ([inTrash]).
  final String? path;

  /// Whether the note's file is in the trash folder (library/trash.rs): the files' word on the trash, which the
  /// synced trash map (lib/core/kept_trash.dart) is kept in step with.
  bool get inTrash => isTrashedPath(path);

  /// The body's version, counted up at each write.
  final int revision;

  Note copyWith({String? body, int? updatedAt, bool? starred, int? Function()? archivedAt, String? Function()? path, int? revision, List<Segment>? segments}) => Note(
        id: id,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        source: source,
        sourceName: sourceName,
        starred: starred ?? this.starred,
        archivedAt: archivedAt == null ? this.archivedAt : archivedAt(),
        recordingMs: recordingMs,
        segments: segments ?? this.segments,
        formatted: formatted,
        formattedFor: formattedFor,
        formattedModel: formattedModel,
        path: path == null ? this.path : path(),
        revision: revision ?? this.revision,
      );

  /// The same note, field for field: what the library asks of a note it has read again, to hand its listeners the
  /// object they already hold where nothing in it moved (lib/core/core_library.dart). The cheap fields are asked
  /// first and the words last, and two bodies of different lengths are told apart without being read.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          other.id == id &&
          other.revision == revision &&
          other.updatedAt == updatedAt &&
          other.createdAt == createdAt &&
          other.starred == starred &&
          other.archivedAt == archivedAt &&
          other.source == source &&
          other.sourceName == sourceName &&
          other.recordingMs == recordingMs &&
          other.formattedFor == formattedFor &&
          other.formattedModel == formattedModel &&
          other.path == path &&
          other.formatted == formatted &&
          listEquals(other.segments, segments) &&
          other.body == body;

  /// Not the words: a hash is asked of a note far more often than two notes with one id are told apart.
  @override
  int get hashCode => Object.hash(id, revision, updatedAt, starred, archivedAt, path);
}
