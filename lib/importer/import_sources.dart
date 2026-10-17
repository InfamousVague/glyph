/// What an import reads from: a folder the person chose (an Obsidian vault) or files they chose (Evernote's
/// `.enex` exports, Todoist's `.csv` ones), on this device, through the device's own picker.
///
/// - **On Android** the picker is the storage access framework's, over `ghost_md/files` (FilesBridge.kt, whose
///   import half is files/ImportTree.kt): `chooseImportFolder` grants a folder for this run, `importList` walks it,
///   `importRead` reads one file's bytes and `importCopy` copies one to a path of the app's, so a large file never
///   crosses the channel. Nothing is granted past the run.
/// - **On a Mac** the picker is the Mac's open panel, over the same channel (macos/Runner/FilesChannel.swift), which
///   answers a plain path; the folder is then read with `dart:io` ([DirectoryFolder]), as a test reads its fixtures.
/// - **On an iPhone**, and anywhere with no picker, nothing is offered ([ImportPicker.offered]).
///
/// A folder's walk leaves out every folder whose name starts with a dot (`.obsidian`, `.trash`, `.git`) and says
/// which it left, for the report.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/iphone_app.dart' show runsAsIPhoneApp;
import '../core/library_folder.dart' show filesChannel;
import '../core/mac_app.dart' show runsAsMacApp;
import '../core/shared_files.dart';

/// One file in a folder being imported.
@immutable
class ImportEntry {
  const ImportEntry({required this.path, required this.size, required this.modified, required this.handle});

  /// Where it is in the folder, with forward slashes and no leading one: `Projects/Alpha.md`.
  final String path;
  final int size;

  /// When it was last changed, in milliseconds; 0 where the device does not say.
  final int modified;

  /// How the device reaches it: a path on a Mac and in a test, a document's address on Android.
  final String handle;

  /// Its name, without its folders.
  String get name => path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;

  /// Its folders, outermost first.
  List<String> get folders => path.contains('/') ? path.substring(0, path.lastIndexOf('/')).split('/') : const [];
}

/// What a walk found: every file, and the dot folders it did not go into.
@immutable
class ImportListing {
  const ImportListing({required this.entries, this.skipped = const []});
  final List<ImportEntry> entries;

  /// The folders left out, by their path in the folder: `.obsidian`, `Projects/.trash`.
  final List<String> skipped;
}

/// A folder being imported.
abstract class ImportFolder {
  /// Its own name, the vault's: `Notes`.
  String get name;
  Future<ImportListing> list();
  Future<Uint8List> read(ImportEntry entry);

  /// The entry as a file to keep (lib/core/shared_files.dart), copied by whoever can read it.
  SharedFileSource source(ImportEntry entry);
}

/// One of the files chosen for an import.
abstract class ImportFile {
  String get name;
  int get size;

  /// A path on this device the file can be read from as it streams. On Android a copy in the app's cache, made the
  /// first time this is asked and removed by [done].
  Future<String> localPath();
  Future<void> done();
}

/// A folder on this device, read with `dart:io`: the Mac's, and a test's.
class DirectoryFolder implements ImportFolder {
  DirectoryFolder(this.path);

  final String path;

  @override
  String get name {
    final parts = path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  @override
  Future<ImportListing> list() async {
    final entries = <ImportEntry>[];
    final skipped = <String>[];
    Future<void> walk(Directory dir, String prefix) async {
      final children = await dir.list(followLinks: false).toList();
      children.sort((a, b) => a.path.compareTo(b.path));
      for (final child in children) {
        final name = child.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final rel = prefix.isEmpty ? name : '$prefix/$name';
        if (child is Directory) {
          if (name.startsWith('.')) {
            skipped.add(rel);
          } else {
            await walk(child, rel);
          }
        } else if (child is File && !name.startsWith('.')) {
          final stat = await child.stat();
          entries.add(ImportEntry(path: rel, size: stat.size, modified: stat.modified.millisecondsSinceEpoch, handle: child.path));
        }
      }
    }

    await walk(Directory(path), '');
    return ImportListing(entries: entries, skipped: skipped);
  }

  @override
  Future<Uint8List> read(ImportEntry entry) => File(entry.handle).readAsBytes();

  @override
  SharedFileSource source(ImportEntry entry) => SharedPath(entry.handle);
}

/// A file on this device: the Mac's, and a test's.
class DirectoryFile implements ImportFile {
  DirectoryFile(this.path) : size = File(path).existsSync() ? File(path).lengthSync() : 0;

  final String path;

  @override
  final int size;

  @override
  String get name => path.split(Platform.pathSeparator).last;

  @override
  Future<String> localPath() async => path;

  @override
  Future<void> done() async {}
}

/// A folder granted through Android's picker, read through the activity.
class PhoneFolder implements ImportFolder {
  PhoneFolder({required this.tree, required this.name, MethodChannel channel = filesChannel}) : _channel = channel;

  final String tree;
  @override
  final String name;
  final MethodChannel _channel;

  @override
  Future<ImportListing> list() async {
    final said = await _channel.invokeMethod<String>('importList', {'tree': tree});
    final json = jsonDecode(said ?? '{}') as Map<String, Object?>;
    if (json['error'] is String) throw StateError(json['error'] as String);
    return ImportListing(
      entries: [
        for (final raw in (json['entries'] as List? ?? const []).cast<Map<String, Object?>>())
          ImportEntry(path: raw['path'] as String, size: (raw['size'] as num?)?.toInt() ?? 0, modified: (raw['modified'] as num?)?.toInt() ?? 0, handle: raw['uri'] as String),
      ],
      skipped: [for (final each in (json['skipped'] as List? ?? const [])) '$each'],
    );
  }

  @override
  Future<Uint8List> read(ImportEntry entry) async {
    final bytes = await _channel.invokeMethod<Uint8List>('importRead', {'uri': entry.handle});
    if (bytes == null) throw StateError('${entry.name} could not be read.');
    return bytes;
  }

  @override
  SharedFileSource source(ImportEntry entry) => SharedCopy((to) => _channel.invokeMethod<void>('importCopy', {'uri': entry.handle, 'to': to}));
}

/// A file granted through Android's picker, copied into the app's cache to be read.
class PhoneFile implements ImportFile {
  PhoneFile({required this.uri, required this.name, required this.size, required this.cacheDir, MethodChannel channel = filesChannel}) : _channel = channel;

  final String uri;
  @override
  final String name;
  @override
  final int size;

  /// The app's cache folder, asked when the copy is made.
  final Future<String> Function() cacheDir;
  final MethodChannel _channel;
  String? _copy;

  @override
  Future<String> localPath() async {
    final made = _copy;
    if (made != null) return made;
    final dir = Directory('${await cacheDir()}/import');
    await dir.create(recursive: true);
    final to = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.enex';
    await _channel.invokeMethod<void>('importCopy', {'uri': uri, 'to': to});
    return _copy = to;
  }

  @override
  Future<void> done() async {
    final made = _copy;
    _copy = null;
    if (made != null) await File(made).delete().then<void>((_) {}, onError: (Object _) {});
  }
}

/// The device's pickers for an import: a folder, or some files.
class ImportPicker {
  ImportPicker({MethodChannel channel = filesChannel, TargetPlatform? platform, Future<String> Function()? cacheDir})
      : _channel = channel,
        _platform = platform,
        _cacheDir = cacheDir ?? (() async => Directory.systemTemp.path);

  final MethodChannel _channel;
  final TargetPlatform? _platform;
  final Future<String> Function() _cacheDir;

  TargetPlatform get _on => _platform ?? defaultTargetPlatform;

  /// Whether this device can choose what to import: Android, and the Mac app. Never an iPhone.
  bool get offered => !runsAsIPhoneApp && (_on == TargetPlatform.android || (_on == TargetPlatform.macOS && (runsAsMacApp || _platform != null)));

  /// A folder, or null when the picker was closed. Throws what went wrong in the app's words.
  Future<ImportFolder?> chooseFolder() async {
    final json = await _ask('chooseImportFolder', const {});
    if (json == null) return null;
    final name = json['name'] as String? ?? 'Vault';
    if (json['path'] is String) return DirectoryFolder(json['path'] as String);
    if (json['tree'] is String) return PhoneFolder(tree: json['tree'] as String, name: name, channel: _channel);
    return null;
  }

  /// One or more files, or null when the picker was closed. [kind] is what the Mac's panel lets be chosen: `enex`,
  /// Evernote's exports, or `csv`, Todoist's (Android's picker takes any file, and the import says what it could
  /// not read).
  Future<List<ImportFile>?> chooseFiles({String kind = 'enex'}) async {
    final json = await _ask('chooseImportFiles', {'kind': kind});
    if (json == null) return null;
    final files = (json['files'] as List? ?? const []).cast<Map<String, Object?>>();
    return [
      for (final raw in files)
        if (raw['path'] is String)
          DirectoryFile(raw['path'] as String)
        else
          PhoneFile(uri: raw['uri'] as String, name: raw['name'] as String? ?? 'Export.enex', size: (raw['size'] as num?)?.toInt() ?? 0, cacheDir: _cacheDir, channel: _channel),
    ];
  }

  Future<Map<String, Object?>?> _ask(String method, Map<String, Object?> args) async {
    final String? said;
    try {
      said = await _channel.invokeMethod<String>(method, args);
    } on MissingPluginException {
      throw StateError('This build cannot open a picker.');
    } on PlatformException catch (failure) {
      throw StateError(failure.message ?? 'The picker did not open.');
    }
    final json = jsonDecode(said ?? '{}') as Map<String, Object?>;
    if (json['cancelled'] == true) return null;
    if (json['error'] is String) throw StateError(json['error'] as String);
    return json;
  }
}
