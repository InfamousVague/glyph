/// A share written into the library (lib/share/share_in.dart says what it becomes): a new note, filed in a
/// workspace where one was chosen, or added to the end of a note that is there. And the notes added to last, which
/// the sheet offers first.
library;

import 'dart:io';

import '../core/images.dart' show PictureAdopter, imageMarkdown;
import '../core/library.dart';
import '../core/note.dart';
import '../core/shared_files.dart';
import '../core/stored.dart';
import '../core/workspaces.dart';
import 'share_in.dart';

/// The key the notes last added to are kept under, on this device.
const String shareRecentKey = 'glyph-share-recent';

/// How many of them are kept.
const int shareRecentMost = 5;

/// Writes shares into the library.
class ShareKeeper {
  ShareKeeper({required this.library, required this.workspaces, required this.keepFile, this.adoptPicture, Stored? kept}) : _kept = kept;

  final NoteLibrary library;
  final WorkspaceStore workspaces;

  /// Moves a picture the phone shrank into the library's pictures and answers its name (the editor's own:
  /// lib/core/phone_pictures.dart `corePictureAdopter`); null where there is none, and a picture is kept as a file.
  final PictureAdopter? adoptPicture;

  /// Keeps any other file and answers its link (lib/core/shared_files.dart `storeSharedFile`).
  final Future<String> Function(SharedFileSource source, String name) keepFile;
  final Stored? _kept;

  Stored get _store => _kept ?? stored;

  /// The ids of the notes a share was last added to, the latest first.
  List<String> recent() => _store.read<List<String>>(shareRecentKey, const [], (raw) => raw is List ? [for (final id in raw) if (id is String) id] : null);

  void _remember(String id) => _store.write(shareRecentKey, [id, ...recent().where((each) => each != id)].take(shareRecentMost).toList());

  /// Each of the share's files kept, as the Markdown that shows or links it, in order. One that cannot be kept is
  /// left out and counted in [failed].
  Future<({List<String> markdown, int failed})> keepItems(SharedIn share) async {
    final markdown = <String>[];
    var failed = 0;
    for (final item in share.items) {
      try {
        final adopt = adoptPicture;
        if (item.picture && adopt != null) {
          markdown.add(imageMarkdown(await adopt(item.path)));
          continue;
        }
        final ref = await keepFile(SharedPath(item.path, move: true), item.name);
        markdown.add(sharedFileMarkdown(item.name, ref));
      } catch (_) {
        failed += 1;
      }
    }
    return (markdown: markdown, failed: failed);
  }

  /// A new note of [share], named [title], filed in [workspaceId] where one is given. Answers the note and how many
  /// of its files could not be kept.
  Future<({Note note, int failed})> keepNew(SharedIn share, {required String title, String? workspaceId}) async {
    final kept = await keepItems(share);
    final name = title.trim().isEmpty ? sharedTitle(share) : title.trim();
    final note = await library.createNote(sharedNoteBody(name, sharedMarkdown(share, kept.markdown)));
    if (workspaceId != null) workspaces.fileNote(note.id, workspaceId);
    return (note: note, failed: kept.failed + share.unread);
  }

  /// [share] added to the end of the note [noteId]. Answers the note and how many of its files could not be kept.
  Future<({Note note, int failed})> keepOnto(SharedIn share, String noteId) async {
    final kept = await keepItems(share);
    final now = await library.get(noteId) ?? library.noteOf(noteId);
    if (now == null) throw StateError('That note is not there any more.');
    final note = await library.save(noteId, sharedAppended(now.body, sharedMarkdown(share, kept.markdown)));
    _remember(noteId);
    return (note: note, failed: kept.failed + share.unread);
  }

  /// A share closed without being kept: what the phone copied for it goes.
  Future<void> discard(SharedIn share) async {
    for (final item in share.items) {
      try {
        await File(item.path).delete();
      } catch (_) {
        // Already gone, or the cache's to clear.
      }
    }
  }
}
