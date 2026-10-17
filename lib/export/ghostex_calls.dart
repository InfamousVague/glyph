/// The .ghostex export and its read-back as Settings reaches them (`SettingsFeatures.ghostex`): Account › Export
/// everything and Import › A .ghostex file. One value the root makes over the library, the workspaces, the core and
/// the phone ([Ghostex.overCore]), and a test makes from its own parts.
///
/// - **Out**: the file is written in the app's cache (`<cache>/ghostex/`, the one before it cleared away), then
///   handed to the person by the device's own share sheet (`ghost_md/documents` `share`: Android's chooser, which
///   offers Files, Drive and every app that takes a file; the Mac's share menu). Nothing is asked of any service.
/// - **In**: a file chosen with the importers' own picker (lib/importer/import_sources.dart), or one opened from
///   the phone's Files or the Mac's Finder ([ghostexWaiting]); opened with its password where it was protected, its
///   notes counted, then read back with the person's choice for the ones already here.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../account/crypto.dart';
import '../core/library.dart';
import '../core/mac_app.dart' show runsAsMacApp;
import '../core/native/core.dart';
import '../core/native/device_paths.dart';
import '../core/native/files.dart';
import '../core/workspaces.dart';
import '../files/attachment_store.dart' show keptAttachments;
import '../files/phone_documents.dart';
import '../importer/ghostex.dart';
import '../importer/import_report.dart' show ImportProgress;
import '../importer/import_sources.dart';
import '../share/share_in.dart' show SharedIn;
import 'ghostex.dart';
import 'ghostex_seal.dart';

/// A .ghostex on this device to be read back: where it is, and its own name.
@immutable
class GhostexChosen {
  const GhostexChosen({required this.path, required this.name, this.done});

  final String path;
  final String name;

  /// What lets go of [path] once it is read (a copy in the app's cache); null for a file that is the person's own.
  final Future<void> Function()? done;
}

/// A .ghostex opened from the phone's Files or the Mac's Finder, waiting for Settings › Import to take it.
final ValueNotifier<GhostexChosen?> ghostexWaiting = ValueNotifier<GhostexChosen?>(null);

/// Whether [name] is a .ghostex's.
bool isGhostexName(String name) => name.toLowerCase().endsWith('.$ghostexExtension');

/// The .ghostex a share is (a file opened from Files, or shared to the app): one file, of that name; else null.
GhostexChosen? ghostexShared(SharedIn share) {
  if (share.items.length != 1 || (share.text ?? '').trim().isNotEmpty) return null;
  final item = share.items.single;
  if (item.picture || !isGhostexName(item.name)) return null;
  return GhostexChosen(path: item.path, name: item.name, done: () => _quietlyDelete(item.path));
}

/// The .ghostex the Mac's Finder opened, as GhostChannels.swift keeps it for the links (`ghostmd://ghostex?path=…`);
/// null for any other link.
GhostexChosen? ghostexLinked(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null || uri.scheme != 'ghostmd' || uri.host != 'ghostex') return null;
  final path = uri.queryParameters['path'];
  if (path == null || !path.startsWith('/') || !isGhostexName(path)) return null;
  return GhostexChosen(path: path, name: path.substring(path.lastIndexOf('/') + 1));
}

Future<void> _quietlyDelete(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Left for the cache's own clearing.
  }
}

/// An export made and waiting to be handed over.
@immutable
class GhostexMade {
  const GhostexMade({required this.name, required this.written});
  final String name;
  final GhostexWritten written;
}

/// A .ghostex opened and counted: the ZIP to read, how many notes it holds and how many are here already.
@immutable
class GhostexOpened {
  const GhostexOpened({required this.chosen, required this.zip, required this.notes, required this.here, this.temporary = false});
  final GhostexChosen chosen;
  final String zip;
  final int notes;
  final int here;

  /// Whether [zip] is the export opened from its password into the cache, and goes once it is read.
  final bool temporary;
}

/// The export wants its password.
class GhostexNeedsPassword implements Exception {
  const GhostexNeedsPassword();
}

/// See the header.
class Ghostex {
  Ghostex({
    required this.source,
    required this.target,
    required this.temp,
    this.seal,
    this.hand,
    this.picker,
    this.handle,
    this.app = 'Ghost.md',
    this.exportOffered = true,
  });

  /// Over the app's own library, its core and its account's crypto: pictures and recordings where the core keeps
  /// them, the files where the attachments' store does, the share sheet and the importers' picker.
  factory Ghostex.overCore({required NoteLibrary library, required WorkspaceStore workspaces, required CoreInvoke invoke, CoreCrypto? crypto, String? Function()? handle, TargetPlatform? platform}) {
    final files = CoreFiles(invoke);
    Future<DevicePaths>? paths;
    Future<DevicePaths> where() => paths ??= DevicePaths.find();
    final on = platform ?? defaultTargetPlatform;
    final documents = PhoneDocuments(platform: on);
    return Ghostex(
      source: GhostexSource(
        library: library,
        workspaces: workspaces,
        picturePath: (name) async => (await files.where(CoreFileKind.image, name))?.path,
        filePath: (name) async => (await keptAttachments?.fileOf(name))?.path,
        recordingPath: (id) async => (await files.where(CoreFileKind.recording, id))?.path,
      ),
      target: () async => GhostexTarget(
        library: library,
        workspaces: workspaces,
        hasPicture: (name) => files.exists(CoreFileKind.image, name),
        keepPicture: (name, path) => files.adopt(CoreFileKind.image, name, path),
        hasFile: (name) async => await keptAttachments?.fileOf(name) != null,
        keepFile: (name, path) async {
          final store = keptAttachments;
          if (store == null) throw StateError('This build cannot keep files yet.');
          await store.write(name, await File(path).readAsBytes());
        },
        keepRecording: (id, path) => files.adopt(CoreFileKind.recording, id, path),
        temp: '${(await where()).cacheDir}/ghostex-in',
      ),
      temp: () async => (await where()).cacheDir,
      seal: crypto == null ? null : CoreGhostexSeal(crypto),
      hand: (path, name) => documents.share(path, name: name),
      picker: ImportPicker(cacheDir: () async => (await where()).cacheDir),
      handle: handle,
      exportOffered: on == TargetPlatform.android || (on == TargetPlatform.macOS && runsAsMacApp),
    );
  }

  final GhostexSource source;
  final Future<GhostexTarget> Function() target;

  /// The app's cache folder.
  final Future<String> Function() temp;

  /// Seals and opens a protected export; null is a build that cannot, where the option is not offered.
  final GhostexSeal? seal;

  /// Hands the finished file to the person as its name: the share sheet.
  final Future<void> Function(String path, String name)? hand;

  /// Chooses a .ghostex to read back.
  final ImportPicker? picker;

  /// The account's handle, for the file's name; null with none.
  final String? Function()? handle;

  /// What the manifest says made it.
  final String app;

  /// Whether this device can hand a file over (Android, the Mac app).
  final bool exportOffered;

  /// Whether this device can choose a .ghostex to read back.
  bool get importOffered => picker?.offered ?? false;

  /// Whether an export can be protected with a password here.
  bool get seals => seal != null;

  /// Writes everything under [options] as `<handle>-<date>.ghostex` in the cache, the last one cleared away first.
  Future<GhostexMade> export(GhostexOptions options, {void Function(GhostexProgress progress)? progress, DateTime? at}) async {
    final now = at ?? DateTime.now();
    final name = ghostexName(handle?.call(), now);
    final dir = Directory('${await temp()}/ghostex');
    if (await dir.exists()) await dir.delete(recursive: true).then<void>((_) {}, onError: (Object _) {});
    await dir.create(recursive: true);
    final written = await writeGhostex(source, options, '${dir.path}/$name', seal: seal, temp: dir.path, at: now, app: app, progress: progress);
    return GhostexMade(name: name, written: written);
  }

  /// The file handed to the person: the share sheet, where they save or send it.
  Future<void> handOver(GhostexMade made) async {
    final hand = this.hand;
    if (hand == null) throw StateError('This device cannot hand a file over.');
    await hand(made.written.path, made.name);
  }

  /// A .ghostex chosen with the picker; null when it was closed.
  Future<GhostexChosen?> choose() async {
    final files = await picker?.chooseFiles();
    if (files == null || files.isEmpty) return null;
    final file = files.first;
    for (final other in files.skip(1)) {
      await other.done();
    }
    return GhostexChosen(path: await file.localPath(), name: file.name, done: file.done);
  }

  /// [chosen] opened: with [password] where it is protected, and counted. Throws [GhostexNeedsPassword] where it is
  /// protected and none was given, [GhostexWrongPassword] where that is not its password, and a [StateError] in the
  /// app's words where it is not a .ghostex.
  Future<GhostexOpened> open(GhostexChosen chosen, {String? password}) async {
    final kind = await ghostexKindOfFile(chosen.path);
    switch (kind) {
      case GhostexKind.neither:
        throw StateError('That is not a .ghostex file.');
      case GhostexKind.zip:
        final counts = await ghostexCounts(chosen.path, source.library);
        return GhostexOpened(chosen: chosen, zip: chosen.path, notes: counts.notes, here: counts.here);
      case GhostexKind.sealed:
        if (password == null || password.isEmpty) throw const GhostexNeedsPassword();
        final seal = this.seal;
        if (seal == null) throw StateError('This build cannot open a protected export.');
        final dir = Directory('${await temp()}/ghostex-in');
        await dir.create(recursive: true);
        final zip = '${dir.path}/.${DateTime.now().microsecondsSinceEpoch}.zip';
        await seal.open(chosen.path, zip, password);
        try {
          final counts = await ghostexCounts(zip, source.library);
          return GhostexOpened(chosen: chosen, zip: zip, notes: counts.notes, here: counts.here, temporary: true);
        } catch (_) {
          await _quietlyDelete(zip);
          rethrow;
        }
    }
  }

  /// Reads [opened] back, then lets go of every copy made of it.
  Future<GhostexReport> read(GhostexOpened opened, {required GhostexCollision collision, void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
    try {
      return await importGhostex(opened.zip, await target(), collision: collision, progress: progress, stopped: stopped);
    } finally {
      await close(opened);
    }
  }

  /// Lets go of [opened] without reading it.
  Future<void> close(GhostexOpened opened) async {
    if (opened.temporary) await _quietlyDelete(opened.zip);
    await opened.chosen.done?.call();
  }
}
