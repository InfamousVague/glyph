/// A file that is not a picture, brought into the app by a share or an import: a PDF, a sound, a spreadsheet, a
/// GIF. Kept beside the pictures, in the app's data folder, and linked from a note in plain Markdown:
///
///     [Lease.pdf](file/0b3c…e1.pdf)
///
/// the way a picture is `![](image/<name>)` (lib/core/images.dart): a path relative to the note, so the link still
/// says what it is anywhere Markdown is read.
///
/// **One door, [storeSharedFile].** The app has no attachments of its own yet (they are being built on another
/// branch); until they arrive this keeps the file under `<data>/attachments/<a fresh UUID>.<its extension>` and
/// answers `file/<that name>`. Not `<data>/files/`: on Android that is the app's own `filesDir`, which Android's
/// libraries write into. Whoever brings attachments in points this one function at their store, and the share sheet
/// and both importers follow.
///
/// What it does not do yet: sync does not carry these files (only pictures, recordings and versions files), and
/// deleting the note does not remove its file. Both are the attachments' to do.
library;

import 'dart:io';
import 'dart:typed_data';

import 'ids.dart';

/// The folder under the app's data folder that holds them, beside `images/` and `video/`.
const String sharedFilesFolder = 'attachments';

/// What a note's link to one starts with: `file/`.
const String sharedFileRef = 'file/';

/// Where a file comes from.
sealed class SharedFileSource {
  const SharedFileSource();
}

/// Bytes already in hand.
class SharedBytes extends SharedFileSource {
  const SharedBytes(this.bytes);
  final Uint8List bytes;
}

/// A file on this device, copied (or moved, where it is the app's own copy in its cache).
class SharedPath extends SharedFileSource {
  const SharedPath(this.path, {this.move = false});
  final String path;
  final bool move;
}

/// A file only something else can read (a document Android's picker granted), copied by it to the path it is
/// given.
class SharedCopy extends SharedFileSource {
  const SharedCopy(this.copyTo);
  final Future<void> Function(String path) copyTo;
}

final RegExp _extension = RegExp(r'\.([A-Za-z0-9]{1,10})$');

/// The extension a kept file is named with: the one [name] ends in, lower case, or none.
String sharedExtension(String name) => _extension.firstMatch(name)?.group(1)?.toLowerCase() ?? '';

/// The words of a link to a kept file: its own name, with what a link's words may not hold taken out.
String sharedFileWords(String name) {
  final words = name.replaceAll(RegExp(r'[\[\]\n\r]'), ' ').trim();
  return words.isEmpty ? 'File' : words;
}

/// The Markdown that links a kept file: `[Lease.pdf](file/<name>)`.
String sharedFileMarkdown(String name, String ref) => '[${sharedFileWords(name)}]($ref)';

/// Keeps [source] under the app's data folder [dataDir] and answers what a note links it by, `file/<name>`.
/// [name] is the file's own name, for its extension. Throws with a sentence when it cannot be kept.
Future<String> storeSharedFile(SharedFileSource source, {required String name, required String dataDir}) async {
  final ext = sharedExtension(name);
  final kept = '${randomId('file')}${ext.isEmpty ? '' : '.$ext'}';
  final dir = Directory('$dataDir/$sharedFilesFolder');
  final to = '${dir.path}/$kept';
  try {
    await dir.create(recursive: true);
    switch (source) {
      case SharedBytes(:final bytes):
        await File(to).writeAsBytes(bytes, flush: true);
      case SharedPath(:final path, :final move):
        if (move) {
          try {
            await File(path).rename(to);
          } on FileSystemException {
            // Another disk: a copy, then the cache's copy goes.
            await File(path).copy(to);
            await File(path).delete().catchError((Object _) => File(path));
          }
        } else {
          await File(path).copy(to);
        }
      case SharedCopy(:final copyTo):
        await copyTo(to);
    }
  } catch (failure) {
    await File(to).delete().catchError((Object _) => File(to));
    throw StateError('$name could not be kept.');
  }
  return '$sharedFileRef$kept';
}

/// Keeps files for one data folder: what the share sheet and the importers are handed.
class SharedFiles {
  const SharedFiles(this.dataDir);

  final String dataDir;

  Future<String> keep(SharedFileSource source, {required String name}) => storeSharedFile(source, name: name, dataDir: dataDir);
}
