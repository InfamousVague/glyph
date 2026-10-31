/// The files notes link to (lib/core/attachment_refs.dart): kept on this device, under the library, by Dart.
///
/// **Where.** The core says ([AttachmentPlaces], lib/files/attachment_places.dart; the rule is
/// tauri/src-tauri/src/library/attachments.rs): `Library/file/<name>` since 2026-10-31, the path the notes link
/// (`[Name](file/<name>)`), so a copy of the library folder has every file a note names; and still read from
/// `<data>/images/files/<name>`, where every build before kept them, until the core's gather at open has brought
/// them in. Until the core has answered ([follow]), the old folder alone. The core carries the folder with the rest
/// of the library's attachments: the export names it `Library/file/`, the backup `Attachments/Files/`, and Erase
/// everything removes it with the app's own library (kept/reset.rs).
///
/// **Names** are the pictures' rule: a version 4 UUID and the extension the file came with, in lower case, given
/// when it arrives and never reused ([attachmentName]). A name that is not one is never made into a path.
///
/// **The door for everything that brings a file in** is [AttachmentStore.keep] (and [storeAttachment] over the
/// app's own store): the + menu's A file and Scan a document, and the share sheet and the importers (branch
/// `feat/share-import`, whose `storeSharedFile` is to call it). It answers a [KeptAttachment], whose
/// [KeptAttachment.markdown] is the note's line.
///
/// **Written whole or not at all**: through a hidden `.<uuid>.part` beside the file and a rename, as the core
/// writes its own (fsx.rs `write_atomically`); the export and the backup both leave a `.part` out.
///
/// A file goes when a note that linked it is deleted for good and no other note links it ([forgetUnlinked]): the
/// pictures' own rule (the core's `remove_unreferenced` on `delete_note`). Taking the line out of a note does not
/// remove the file, so Undo, an older version of the note, or the same line in another note still finds it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/attachment_refs.dart';
import '../core/ids.dart';
import 'attachment_places.dart';

/// The folder under the pictures' folder every build before 2.3.94 kept the files in (`<data>/images/files`).
const String attachmentsFolder = 'files';

/// Where a file to keep comes from.
sealed class AttachmentSource {
  const AttachmentSource();
}

/// Bytes already in hand.
class AttachmentBytes extends AttachmentSource {
  const AttachmentBytes(this.bytes);
  final Uint8List bytes;
}

/// A file on this device: copied, or moved where it is the app's own copy in its cache (`picked/`).
class AttachmentPath extends AttachmentSource {
  const AttachmentPath(this.path, {this.move = false});
  final String path;
  final bool move;
}

/// A file only something else can read (a document a picker granted), which it copies to the path it is given.
class AttachmentCopy extends AttachmentSource {
  const AttachmentCopy(this.copyTo);
  final Future<void> Function(String path) copyTo;
}

/// A file kept: its name in the app's keeping, the name it came with, and its size.
@immutable
class KeptAttachment {
  const KeptAttachment({required this.name, required this.original, required this.bytes});

  final String name;
  final String original;
  final int bytes;

  /// What a note links it by: `file/<name>`.
  String get ref => 'file/$name';

  /// The note's line for it (lib/core/attachment_refs.dart).
  String get markdown => attachmentMarkdown(name, original, bytes: bytes);

  @override
  String toString() => 'KeptAttachment($name, $original, $bytes)';
}

/// What a person reads when a file is too large to keep at all.
const String tooLargeToKeep = 'That file is too large to add.';

/// The files of one data folder.
class AttachmentStore extends ChangeNotifier {
  /// Over the folders [places] names for the files, or the old folder alone until the core has answered ([follow]).
  AttachmentStore({required String dataDir, String Function()? newName, AttachmentPlaces? places})
      : _dirs = (places ?? AttachmentPlaces.legacy(dataDir)).file,
        _newName = newName;

  /// The folders the files are read from, the first the one written to (`AttachmentPlaces.file`).
  List<String> _dirs;
  final String Function()? _newName;

  /// The folder new files are written to: `Library/file`, or `<data>/images/files` until the core has answered.
  Directory get dir => Directory(_dirs.first);

  /// Every folder a file may be in, the one written to first.
  List<String> get dirs => List<String>.unmodifiable(_dirs);

  /// Where the core says the files are, once it has answered (lib/files/files_kit.dart): read from every folder it
  /// names, written to the first. An answer with no folder for the files is no answer.
  void follow(AttachmentPlaces places) {
    if (places.file.isEmpty || listEquals(places.file, _dirs)) return;
    _dirs = places.file;
    notifyListeners();
  }

  /// How many times each file has landed this run, by name: a card drawing one draws it again (a sync that arrived
  /// after it asked).
  final Map<String, int> _landed = <String, int>{};

  /// Bumped each time a file lands, for whatever draws one to look again.
  int landedTimes(String name) => _landed[name] ?? 0;

  /// The file's path where a new one is written, whether or not it is there; null for a name that may not name a
  /// file. For what writes: what reads asks [fileOf], which looks in every folder.
  String? pathOf(String name) => attachmentName.hasMatch(name) ? '${_dirs.first}/$name' : null;

  /// The file, where this device has it: the first of the folders that has it (under the library, or beside it
  /// from an older build).
  Future<File?> fileOf(String name) async {
    if (!attachmentName.hasMatch(name)) return null;
    for (final folder in _dirs) {
      final file = File('$folder/$name');
      if (await file.exists()) return file;
    }
    return null;
  }

  /// Its size in bytes, where this device has it.
  Future<int?> sizeOf(String name) async {
    final file = await fileOf(name);
    if (file == null) return null;
    try {
      return await file.length();
    } on FileSystemException {
      return null;
    }
  }

  /// Its bytes, where this device has it (what sync seals and sends).
  Future<Uint8List?> read(String name) async {
    final file = await fileOf(name);
    if (file == null) return null;
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  String _fresh(String original) => '${_newName?.call() ?? randomId('file')}.${keptExtension(original)}';

  /// A hidden file beside the kept ones, for a write that has not finished.
  File _part() => File('${dir.path}/.${randomId('part')}.part');

  /// Keeps a file that came from elsewhere under its own name, whole or not at all (by sync, lib/sync/notes.dart).
  /// Written where files are written now; a copy an older build left in another folder goes, so the one read is the
  /// one that arrived (as the core's `sync_put_file` has it).
  Future<void> write(String name, Uint8List bytes) async {
    final path = pathOf(name);
    if (path == null) throw StateError('That is not a file name.');
    if (bytes.length > attachmentKeepLimit) throw StateError(tooLargeToKeep);
    await dir.create(recursive: true);
    final part = _part();
    try {
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(path);
    } catch (failure) {
      await _quietlyDelete(part);
      rethrow;
    }
    for (final folder in _dirs.skip(1)) {
      await _quietlyDelete(File('$folder/$name'));
    }
    _arrived(name);
  }

  void _arrived(String name) {
    _landed[name] = (_landed[name] ?? 0) + 1;
    notifyListeners();
  }

  /// Keeps [source] under a fresh name and answers it. [original] is the name it came with: its words in the note
  /// and its extension here. Throws a [StateError] with a sentence for the note when it cannot be kept.
  Future<KeptAttachment> keep(AttachmentSource source, {required String original}) async {
    final name = _fresh(original);
    final to = File(pathOf(name)!);
    final part = _part();
    try {
      await dir.create(recursive: true);
      switch (source) {
        case AttachmentBytes(:final bytes):
          if (bytes.length > attachmentKeepLimit) throw StateError(tooLargeToKeep);
          await part.writeAsBytes(bytes, flush: true);
        case AttachmentPath(:final path, :final move):
          final from = File(path);
          if (await from.length() > attachmentKeepLimit) throw StateError(tooLargeToKeep);
          if (move) {
            try {
              await from.rename(part.path);
            } on FileSystemException {
              // Another disk (a Mac's temporary folder, a removable drive): a copy, then the cache's copy goes.
              await from.copy(part.path);
              await _quietlyDelete(from);
            }
          } else {
            await from.copy(part.path);
          }
        case AttachmentCopy(:final copyTo):
          await copyTo(part.path);
      }
      final bytes = await part.length();
      if (bytes > attachmentKeepLimit) throw StateError(tooLargeToKeep);
      await part.rename(to.path);
      _arrived(name);
      return KeptAttachment(name: name, original: original, bytes: bytes);
    } on StateError {
      await _quietlyDelete(part);
      rethrow;
    } catch (failure) {
      await _quietlyDelete(part);
      debugPrint('[files] $original was not kept: $failure');
      throw StateError('That file could not be added.');
    }
  }

  /// Removes a file and the words read in it ([readTextSuffix] beside it), from every folder it may be in. One
  /// already gone is nothing.
  Future<void> remove(String name) async {
    if (!attachmentName.hasMatch(name)) return;
    for (final folder in _dirs) {
      await _quietlyDelete(File('$folder/$name'));
      await _quietlyDelete(File('$folder/$name$readTextSuffix'));
    }
  }

  /// The files a deleted note linked, removed where no other note links them: the pictures' rule. [stillLinked]
  /// is every other note's words, asked once and only when the note linked a file. Best effort: a file whose use
  /// cannot be checked is left.
  Future<List<String>> forgetUnlinked(String deletedBody, Future<Iterable<String>> Function() stillLinked) async {
    final names = attachmentNames(deletedBody);
    if (names.isEmpty) return const <String>[];
    final Iterable<String> others;
    try {
      others = await stillLinked();
    } catch (_) {
      return const <String>[];
    }
    final linked = <String>{for (final body in others) ...attachmentNames(body)};
    final gone = <String>[];
    for (final name in names) {
      if (linked.contains(name)) continue;
      await remove(name);
      gone.add(name);
    }
    return gone;
  }

  /// Every file kept here, by name, with its size, each from the first folder that has it: for Settings' count, and
  /// for the low-priority reading pass.
  Future<Map<String, int>> all() async {
    final found = <String, int>{};
    for (final folder in _dirs) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      try {
        await for (final entry in dir.list(followLinks: false)) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.last;
          if (!attachmentName.hasMatch(name) || found.containsKey(name)) continue;
          try {
            found[name] = await entry.length();
          } on FileSystemException {
            // Gone between the listing and the asking.
          }
        }
      } on FileSystemException {
        // A folder that will not be listed is nothing kept.
      }
    }
    return found;
  }

  /// What every file kept here takes, in bytes.
  Future<int> bytesUsed() async => (await all()).values.fold<int>(0, (sum, each) => sum + each);
}

/// What follows a file's name for the words read in it (lib/files/read_text.dart).
const String readTextSuffix = '.ocr.txt';

Future<void> _quietlyDelete(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Already gone, or not ours to remove: left.
  }
}

/// The app's own store, once the device has said where its files are (lib/files/files_kit.dart); null before, and
/// in a run with no data folder.
AttachmentStore? keptAttachments;

/// Keeps a file brought into the app, by anything (the + menu, a share, an import), in the app's own store, and
/// answers it: the one door ([AttachmentStore.keep]). Throws a [StateError] with a sentence where there is no store
/// yet or the file cannot be kept.
Future<KeptAttachment> storeAttachment(AttachmentSource source, {required String name}) async {
  final store = keptAttachments;
  if (store == null) throw StateError('This build cannot add files yet.');
  final kept = await store.keep(source, original: name);
  attachmentKept?.call(kept);
  return kept;
}

/// Told of each file [storeAttachment] keeps: the words in it are read soon after (lib/files/files_kit.dart).
void Function(KeptAttachment kept)? attachmentKept;
