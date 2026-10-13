/// The carry from the Tauri app on a Mac (docs/CUTOVER.md §7): the ground lib/carry/tauri_carry.dart's two halves
/// run over there, and the half that comes before them.
///
/// On a phone this app wakes in the Tauri app's own folder and reads most of it where it lies. On a Mac it does
/// not, on purpose. The build that replaces the Tauri Mac app has that app's bundle id, but **it keeps a folder of
/// its own**, `~/Library/Application Support/com.mattssoftware.glyph.v2` (macos/Runner/GhostChannels.swift
/// `cutoverFolder`), and **never writes, moves or removes anything of the Tauri app's**: its folder
/// `~/Library/Application Support/com.mattssoftware.glyph` and its web view's storage under
/// `~/Library/WebKit/com.mattssoftware.glyph` are the way back, and somebody who puts 1.15.0 back finds every
/// note, setting and key as that app left them. So everything is COPIED, once:
///
/// | The Tauri app kept | where | this app |
/// | --- | --- | --- |
/// | the notes, their `.versions` files, each note's sidecar | `Library/`, `Library/.glyph/` | copied ([MacCarryFiles]). Not `Library/.glyph/index.sqlite`: the core makes its index again from the notes, and a file SQLite may have had open is not one to copy. |
/// | pictures, recordings, films | `images/`, `recordings/`, `video/` | copied |
/// | a library folder the person chose | `library-root.json` | copied: the same folder is opened where it is, as on a phone. It is the person's folder, not the Tauri app's. |
/// | the notes before 1.3.0 | `glyph.sqlite` | copied, for the core to move in on its first open |
/// | models | `models/` | cloned where the disk can (APFS: a second name for the same blocks, nothing copied and neither file able to change the other), else left to be downloaded again: they are gigabytes, and a model is not a person's writing. Never a `.part`. |
/// | downloaded pages, a write-up's state, a chosen folder's index | `ota/`, `jobs/`, `index/` | left: nothing here reads the first two, and the third is made again |
/// | `localStorage`, the team documents, the three keys | WebKit's files | read from copies of them ([MacCarrySource], webkit_stores.dart) and carried by the same two halves as on a phone |
/// | Slack's webhooks, Notion's sign-in | `slack.json`, `notion.json` | read where they are, into the Keychain |
///
/// The files come first and whole: until every file is across, no setting and no session is carried, so a sync
/// never runs over half a library (tauri_carry.dart `settings`).
///
/// **The keys.** WebKit wraps them under a key in the login Keychain that only the app that made it reads without
/// a prompt ([MacCarryDevice.masterKey]). A pair is proven as on a phone: the private half raised in the core must
/// answer the public half kept beside it. The account key has no page to seal a proof, so it is proven on
/// something the page sealed before, a notification's words ([accountProbesIn]); with none of those it is carried
/// on the strength of GCM's tag, which says the bytes are exactly the ones WebKit wrapped. A key that cannot be
/// opened or proven is not carried, and the person is asked for their password once.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../account/device_keys.dart' show SecureStore;
import '../core/mac_app.dart';
import 'tauri_carry.dart';
import 'webkit_stores.dart';

/// Where the Tauri Mac app kept things, beside this app's own folder.
class MacPlaces {
  const MacPlaces({required this.tauriData, required this.websiteData});

  /// `~/Library/Application Support/com.mattssoftware.glyph`.
  final String tauriData;

  /// `~/Library/WebKit/com.mattssoftware.glyph/WebsiteData`.
  final String websiteData;

  /// Under [library], a `~/Library`.
  factory MacPlaces.inLibrary(String library) => MacPlaces(tauriData: '$library/Application Support/$realAppId', websiteData: '$library/WebKit/$realAppId/WebsiteData');

  /// For an app whose own folder is [ownDataDir] (`~/Library/Application Support/<its folder>`): the same
  /// `~/Library`. [standIn] is another folder to take for `~/Library`, for a run over a copy
  /// (`GHOST_CARRY_LIBRARY`; docs/CUTOVER.md §7, "Proven").
  factory MacPlaces.beside(String ownDataDir, {String? standIn}) {
    if (standIn != null && standIn.isNotEmpty) return MacPlaces.inLibrary(standIn);
    return MacPlaces.inLibrary(Directory(ownDataDir).parent.parent.path);
  }
}

/// The Mac's own half (macos/Runner/GhostChannels.swift, `ghost_md/tauri_carry`).
abstract interface class MacCarryDevice {
  /// What the login Keychain holds as the Tauri app's "WebCrypto Master Key", or null: none, or a Keychain that
  /// will not hand it to this app without asking the person (it is never made to ask).
  Future<Uint8List?> masterKey();

  /// A clone of the file [from] at [to]: true when the disk made one. False changes nothing.
  Future<bool> clone(String from, String to);
}

class ChannelMacCarryDevice implements MacCarryDevice {
  const ChannelMacCarryDevice();

  static const MethodChannel channel = MethodChannel('ghost_md/tauri_carry');

  @override
  Future<Uint8List?> masterKey() async {
    final said = await channel.invokeMethod<String>('masterKey').timeout(const Duration(seconds: 10));
    return said == null ? null : base64.decode(said);
  }

  @override
  Future<bool> clone(String from, String to) async => await channel.invokeMethod<bool>('clone', {'from': from, 'to': to}) ?? false;
}

/// A Mac with neither: a test, or a run outside the app. Files are copied byte for byte and models are left.
class NoMacCarryDevice implements MacCarryDevice {
  const NoMacCarryDevice();

  @override
  Future<Uint8List?> masterKey() async => null;

  @override
  Future<bool> clone(String from, String to) async => false;
}

/// The whole carry for a Mac: [TauriCarry] over the Mac's ground. [ownDataDir] is this app's own folder, which
/// must not be the Tauri app's or inside it. [host] is what the log calls the device: an iPhone's carry is this
/// one over the same ground inside the app's container (lib/carry/iphone_carry.dart).
TauriCarry macCarry({required String ownDataDir, required CarryPrefs prefs, required SecureStore secure, MacCarryDevice device = const ChannelMacCarryDevice(), String? standIn, DateTime Function()? now, String host = 'a Mac'}) {
  if (isRealAppPath(ownDataDir)) throw StateError('The carry writes into this app’s own folder, never Ghost.md’s first one.');
  final places = MacPlaces.beside(ownDataDir, standIn: standIn);
  return TauriCarry(
    dataDir: ownDataDir,
    prefs: prefs,
    secure: secure,
    device: const NoCarryDevice(),
    source: MacCarrySource(places: places, device: device, host: host),
    files: MacCarryFiles(from: places.tauriData, to: ownDataDir, device: device),
    now: now,
  );
}

/// What the page sealed under its account key and left in `localStorage`: the notifications that carry words of
/// their own (`glyph-sync-<account>-notifications`, tauri/src/app/core/notifications/feed.ts; each `blob` sealed
/// with the context `notification:<id>`, record.ts). A key that opens one is the page's account key.
List<({String context, String blob})> accountProbesIn(Map<String, String> local) {
  final out = <({String context, String blob})>[];
  for (final entry in local.entries) {
    if (!entry.key.startsWith('glyph-sync-') || !entry.key.endsWith('-notifications')) continue;
    try {
      final read = jsonDecode(entry.value);
      final items = read is Map ? read['items'] : null;
      if (items is! Map) continue;
      for (final item in items.values) {
        if (item is Map && item['id'] is String && item['blob'] is String && (item['blob'] as String).isNotEmpty) {
          out.add((context: 'notification:${item['id']}', blob: item['blob'] as String));
        }
      }
    } catch (_) {
      // Not a feed this reads.
    }
  }
  return out;
}

class MacCarrySource implements CarrySource {
  MacCarrySource({required this.places, required this.device, this.host = 'a Mac'});

  final MacPlaces places;
  final MacCarryDevice device;

  /// What the log calls the device.
  final String host;

  @override
  String get filesDir => places.tauriData;

  @override
  Future<bool> wasHere() async => await Directory(places.tauriData).exists() || await WebKitStores.originFolder(Directory(places.websiteData)) != null;

  @override
  Future<CarryRead> read() async {
    final web = await WebKitStores.read(Directory(places.websiteData));
    final notes = <String>[];
    Uint8List? master;
    if (web.wrappedCount > 0) {
      try {
        final kept = await device.masterKey();
        master = kept == null ? null : webCryptoMasterKey(kept);
        if (kept == null) {
          notes.add('the Keychain did not give WebKit’s key for stored keys: ${web.wrappedCount} keys left wrapped');
        } else if (master == null) {
          notes.add('what the Keychain holds as WebKit’s key is not one (${kept.length} bytes): ${web.wrappedCount} keys left wrapped');
        }
      } catch (failure) {
        notes.add('the Keychain could not be asked for WebKit’s key (${failure.runtimeType}): ${web.wrappedCount} keys left wrapped');
      }
    }
    final keys = web.keys(master);
    if (master != null) {
      final opened = [if (keys.account != null) 'account', if (keys.device != null) 'device', if (keys.encryption != null) 'encryption'];
      notes.add('WebKit’s key opened ${opened.length} of ${web.wrapped.length} stored keys (${opened.join(', ')})');
    }
    final how = !web.found
        ? 'the Tauri app’s web view kept nothing at tauri://localhost: there are no settings to carry'
        : 'read copies of WebKit’s files: ${web.local.length} keys of localStorage, ${web.team.length} team documents, ${web.wrappedCount} wrapped keys${web.damaged > 0 ? ', ${web.damaged} that could not be read${web.failure == null ? '' : ' (${web.failure})'}' : ''}';
    return CarryRead(
      local: web.local,
      fromWebView: false,
      webFailure: '$host has none to ask',
      diskCount: web.local.length,
      keys: keys,
      idbDamaged: web.damaged,
      web: {'team': web.team},
      how: how,
      accountProbes: accountProbesIn(web.local),
      accountRead: 'the account key opened under WebKit’s own key with its tag, and the page left nothing sealed to try it on: carried as read',
      notes: notes,
    );
  }
}

/// The files' half: the Tauri app's folder [from], copied into this app's own [to]. The header's table is the
/// rule. A file already at its place in [to] is left as it is; nothing in [from] is ever opened but to read it.
class MacCarryFiles implements CarryFiles {
  MacCarryFiles({required this.from, required this.to, this.device = const NoMacCarryDevice()}) {
    if (isRealAppPath(to)) throw StateError('The carry writes into this app’s own folder, never Ghost.md’s first one.');
  }

  final String from;
  final String to;
  final MacCarryDevice device;

  /// The folders copied whole, and what a file in each is counted as.
  static const Map<String, String> _folders = {'Library': 'library files', 'images': 'pictures', 'recordings': 'recordings', 'video': 'films'};

  /// Files at the top that are carried as they are.
  static const List<String> _topFiles = ['library-root.json', 'glyph.sqlite', 'glyph.sqlite-wal', 'glyph.sqlite-shm'];

  /// The Rust's own leftovers of a write cut short (tauri/src-tauri/src/fsx.rs), and the Finder's.
  static final RegExp _scrap = RegExp(r'^(\.[0-9a-f]{32}\.tmp|\.DS_Store)$');

  /// What a copy in hand is called until it is whole.
  static const String _part = '.carry-part';

  final Map<String, int> _counts = {};
  int _failed = 0;

  void _count(String what) => _counts[what] = (_counts[what] ?? 0) + 1;

  @override
  Future<CarryFilesOutcome> copy() async {
    _counts.clear();
    _failed = 0;
    final notes = <String>[];
    if (!await Directory(from).exists()) return CarryFilesOutcome(notes: ['the Tauri app kept no folder: no files to copy']);
    await Directory(to).create(recursive: true);
    for (final entry in _folders.entries) {
      final folder = Directory('$from/${entry.key}');
      if (await folder.exists()) await _tree(folder, '$to/${entry.key}', entry.value, library: entry.key == 'Library', top: true);
    }
    for (final name in _topFiles) {
      final file = File('$from/$name');
      if (await file.exists()) await _file(file, '$to/$name', 'other files');
    }
    final chosen = await _chosenFolder();
    if (chosen) notes.add('the library is a folder the person chose: it is opened where it is');
    await _models();
    return CarryFilesOutcome(counts: Map.of(_counts), failed: _failed, notes: notes);
  }

  Future<bool> _chosenFolder() async {
    try {
      final file = File('$from/library-root.json');
      if (!await file.exists()) return false;
      final read = jsonDecode(await file.readAsString());
      return read is Map && read['kind'] == 'folder';
    } catch (_) {
      return false;
    }
  }

  Future<void> _tree(Directory folder, String into, String what, {required bool library, bool top = false, bool hidden = false}) async {
    try {
      await Directory(into).create(recursive: true);
      final entries = await folder.list(followLinks: false).toList();
      for (final entry in entries) {
        final name = entry.uri.pathSegments.lastWhere((part) => part.isNotEmpty);
        if (_scrap.hasMatch(name) || name.endsWith(_part)) continue;
        if (entry is Link) {
          // A link is not followed out of the folder, and not made again here.
          _count('links left');
        } else if (entry is Directory) {
          await _tree(entry, '$into/$name', what, library: library, hidden: hidden || (library && top && name == '.glyph'));
        } else if (entry is File) {
          // The core's index of the app's own folder: made again from the notes.
          if (library && hidden && RegExp(r'^index\.sqlite(-wal|-shm)?$').hasMatch(name) && folder.path.endsWith('/.glyph')) {
            _count('index files left');
            continue;
          }
          await _file(entry, '$into/$name', !library ? what : (hidden ? 'sidecars' : (name.endsWith('.md') ? 'notes' : (name.endsWith('.versions') ? 'versions files' : what))));
        }
      }
    } catch (_) {
      _failed += 1;
    }
  }

  Future<void> _models() async {
    final folder = Directory('$from/models');
    if (!await folder.exists()) return;
    try {
      await for (final entry in folder.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (name.endsWith('.part') || _scrap.hasMatch(name) || name.endsWith(_part)) continue;
        final target = File('$to/models/$name');
        if (await target.exists()) {
          _count('models already here');
          continue;
        }
        await Directory('$to/models').create(recursive: true);
        final part = '${target.path}$_part';
        await _clear(part);
        if (await _cloned(entry.path, part) && await File(part).length() == await entry.length()) {
          await File(part).rename(target.path);
          _count('models');
        } else {
          await _clear(part);
          _count('models left to download');
        }
      }
    } catch (_) {
      // A model that did not come across is downloaded again: never a reason to hold the carry back.
      _count('models left to download');
    }
  }

  Future<bool> _cloned(String source, String target) async {
    _guard(target);
    try {
      return await device.clone(source, target);
    } catch (_) {
      return false;
    }
  }

  Future<void> _clear(String path) async {
    _guard(path);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Every path this half writes or removes is asked this first: inside this app's folder, never the Tauri app's.
  void _guard(String path) {
    if (isRealAppPath(path) || !(path == to || path.startsWith('$to/'))) throw StateError('The carry writes into this app’s own folder and nowhere else.');
  }

  /// One file: left when its place is taken, else copied beside its place, checked, and moved into it.
  Future<void> _file(File source, String target, String what) async {
    try {
      _guard(target);
      if (await FileSystemEntity.type(target, followLinks: false) != FileSystemEntityType.notFound) {
        _count('$what already here');
        return;
      }
      final part = '$target$_part';
      await _clear(part);
      if (!await _cloned(source.path, part)) await source.copy(part);
      final copy = File(part);
      final length = await source.length();
      if (await copy.length() != length) {
        await _clear(part);
        _failed += 1;
        return;
      }
      // A note's time is when it was last written, not when it was carried.
      await copy.setLastModified(await source.lastModified());
      await copy.rename(target);
      _count(what);
    } catch (_) {
      _failed += 1;
    }
  }
}
