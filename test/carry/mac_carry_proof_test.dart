// The Mac carry over a COPY of a real Mac's Tauri data, counted (docs/CUTOVER.md, section 7, "Proven"). Not a
// test of the code so much as a measurement of somebody's data: it runs only when told where the copy is, and
// says NUMBERS ONLY. No note's words or name, no setting's value, no key, token or session is printed, and the
// Keychain is never asked (so the keys are counted where they lie, wrapped, and not opened).
//
//   mkdir -p build/mac-carry-proof/Library/"Application Support" build/mac-carry-proof/Library/WebKit
//   cp -Rc ~/Library/"Application Support"/com.mattssoftware.glyph build/mac-carry-proof/Library/"Application Support"/
//   cp -Rc ~/Library/WebKit/com.mattssoftware.glyph build/mac-carry-proof/Library/WebKit/
//   GHOST_CARRY_PROOF=$PWD/build/mac-carry-proof/Library flutter test --no-pub test/carry/mac_carry_proof_test.dart
//   rm -rf build/mac-carry-proof
//
// `cp -Rc` clones (nothing is copied on an APFS disk, and the originals cannot be changed through the clone).
// The carried folder is made beside the copy, `…/Library/Application Support/com.mattssoftware.glyph.v2`, where
// the built app can then be started on it (GHOST_CARRY_LIBRARY; the section says how).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/carry/mac_carry.dart';
import 'package:ghost_md/carry/webkit_stores.dart';
import 'package:ghost_md/core/mac_app.dart';

import '../team_sync/support.dart' show coreSkip, openCore;
import 'tauri_carry_test.dart' show MapPrefs;
import 'webkit_make.dart' show treeState;

final String proofLibrary = Platform.environment['GHOST_CARRY_PROOF'] ?? '';

int _files(String folder, bool Function(String path) wanted, {bool hidden = false}) {
  final at = Directory(folder);
  if (!at.existsSync()) return 0;
  return at.listSync(recursive: true, followLinks: false).whereType<File>().where((file) {
    final inside = file.path.substring(folder.length);
    if (inside.endsWith('/.DS_Store')) return false;
    if (!hidden && inside.split('/').any((part) => part.startsWith('.'))) return false;
    return wanted(inside);
  }).length;
}

void main() {
  test('the carry over a copy of a real Mac\'s Tauri data, in numbers', skip: proofLibrary.isEmpty ? 'not asked: GHOST_CARRY_PROOF=<a copy of ~/Library> runs it' : coreSkip, () async {
    final places = MacPlaces.inLibrary(proofLibrary);
    final own = '$proofLibrary/Application Support/com.mattssoftware.glyph.v2';
    expect(Directory(places.tauriData).existsSync(), isTrue, reason: 'no copy of the Tauri app\'s folder at ${places.tauriData}');
    expect(proofLibrary.startsWith('${Platform.environment['HOME']}/Library'), isFalse, reason: 'a COPY, never ~/Library itself');
    expect(isRealAppPath(own), isFalse);
    // A failure of the file system names a file, and a note's file is named by its title: nothing that is thrown
    // here is printed, only what kind of thing it was.
    try {
      await _measure(places, own);
    } on TestFailure {
      rethrow;
    } catch (failure) {
      fail('the measurement stopped on a ${failure.runtimeType}');
    }
  });
}

Future<void> _measure(MacPlaces places, String own) async {
  {
    final before = {...treeState(Directory(places.tauriData)), ...treeState(Directory('$proofLibrary/WebKit'))};

    // What the Tauri app kept.
    final web = await WebKitStores.read(Directory(places.websiteData));
    final theirs = {
      'notes': _files('${places.tauriData}/Library', (path) => path.endsWith('.md')),
      'versions files': _files('${places.tauriData}/Library', (path) => path.endsWith('.versions')),
      'sidecars': _files('${places.tauriData}/Library/.glyph/notes', (path) => path.endsWith('.json')),
      'pictures': _files('${places.tauriData}/images', (path) => true),
      'recordings': _files('${places.tauriData}/recordings', (path) => true),
      'films': _files('${places.tauriData}/video', (path) => true),
    };
    final glyphKeys = web.local.keys.where((key) => key.startsWith('glyph-')).toList();
    int? workspaces;
    try {
      final preferences = jsonDecode(web.local['glyph-preferences'] ?? '');
      final kept = preferences is Map ? preferences['workspaces'] : null;
      final list = kept is Map ? kept['list'] : kept;
      workspaces = list is List ? list.length : null;
    } catch (_) {
      workspaces = null;
    }
    Object? session;
    try {
      session = jsonDecode(web.local['glyph-account-session'] ?? 'null');
    } catch (_) {
      session = null;
    }
    final signedIn = session is Map && session['token'] is String && session['handle'] is String && session['accountId'] is num;

    // The carry, into a folder beside the copy.
    final prefs = MapPrefs(), secure = MemorySecureStore();
    final carry = macCarry(ownDataDir: own, prefs: prefs, secure: secure, device: const NoMacCarryDevice(), standIn: proofLibrary);
    final files = await carry.copied();
    final settings = await carry.settings();
    final core = await openCore();
    final secrets = await carry.secrets(core.invoke);
    await core.init(dataDir: own, cacheDir: '$proofLibrary/Caches/com.mattssoftware.glyph.v2');
    final listed = await core.invoke('list_notes');
    await core.close();
    final marker = jsonDecode(File('$own/carry/tauri-carry.json').readAsStringSync()) as Map;

    final ours = {
      'notes': _files('$own/Library', (path) => path.endsWith('.md')),
      'versions files': _files('$own/Library', (path) => path.endsWith('.versions')),
      'sidecars': _files('$own/Library/.glyph/notes', (path) => path.endsWith('.json')),
      'pictures': _files('$own/images', (path) => true),
      'recordings': _files('$own/recordings', (path) => true),
      'films': _files('$own/video', (path) => true),
    };
    // Byte for byte: every file the Tauri app's folders hold of these kinds is the same file here.
    var same = 0, different = 0;
    for (final folder in const ['Library', 'images', 'recordings', 'video']) {
      final from = Directory('${places.tauriData}/$folder');
      if (!from.existsSync()) continue;
      for (final file in from.listSync(recursive: true, followLinks: false).whereType<File>()) {
        final inside = file.path.substring(places.tauriData.length);
        if (inside.endsWith('/.DS_Store') || RegExp(r'/\.glyph/index\.sqlite(-wal|-shm)?$').hasMatch(inside) || RegExp(r'/\.[0-9a-f]{32}\.tmp$').hasMatch(inside)) continue;
        final copy = File('$own$inside');
        if (copy.existsSync() && copy.lengthSync() == file.lengthSync() && copy.lastModifiedSync() == file.lastModifiedSync() && _same(copy.readAsBytesSync(), file.readAsBytesSync())) {
          same += 1;
        } else {
          different += 1;
        }
      }
    }
    final after = {...treeState(Directory(places.tauriData)), ...treeState(Directory('$proofLibrary/WebKit'))};

    final lines = [
      'WHAT THE TAURI APP KEPT (the copy)',
      for (final entry in theirs.entries) '  ${entry.key}: ${entry.value}',
      '  web view storage found: ${web.found}; could not be read: ${web.damaged}',
      '  localStorage keys: ${web.local.length} (${glyphKeys.length} glyph-)',
      '  workspaces in the preferences: ${workspaces ?? 'not read'}',
      '  versions kept in localStorage for want of a file: ${glyphKeys.where((key) => key.startsWith('glyph-versions-') && key != 'glyph-versions-unsent').length}',
      '  a session (signed in): $signedIn',
      '  key database found: ${web.keysFound}; records: ${web.wrapped.length}; wrapped keys: ${web.wrappedCount} (${(web.wrapped.keys.toList()..sort()).join(', ')})',
      '  things the page sealed under the account key (to prove it on): ${accountProbesIn(web.local).length}',
      '  team documents: ${web.team.length}',
      'WHAT THE CARRY DID',
      '  files: done ${files.done}; counts ${(marker['files'] as Map?)?['counts']}',
      '  settings: done ${settings.done}; carried ${settings.carried.length}, left ${settings.left.length}, failed ${settings.failed.length}; team documents written: ${_files('$own/team', (path) => path.endsWith('.json'))}',
      '  secrets: done ${secrets.done}; carried ${secrets.carried.length} (${secrets.carried.map((name) => name.startsWith('glyph-slack-webhook:') ? 'a Slack webhook' : name).join(', ')}), failed ${secrets.failed.length}',
      '  keys opened: none: this run never asks the Keychain for WebKit\'s master key',
      'WHAT THIS APP NOW HAS',
      for (final entry in ours.entries) '  ${entry.key}: ${entry.value}',
      '  notes the core lists on the carried library: ${listed is List ? listed.length : 'not a list'}',
      '  preferences carried: ${prefs.kept.length}',
      '  files the same byte for byte and time for time: $same; not the same or missing: $different',
      'THE COPY OF THE TAURI APP\'S DATA: ${_equal(before, after) ? 'unchanged (${before.length} files and folders, every length, time and hash)' : 'CHANGED'}',
    ];
    // ignore: avoid_print
    print(lines.join('\n'));

    expect(_equal(before, after), isTrue, reason: 'the Tauri app\'s files were changed');
    expect(files.done && settings.done && secrets.done, isTrue);
    expect(ours, theirs);
    expect(different, 0);
    expect(listed is List ? listed.length : -1, theirs['notes']);
    expect(prefs.kept.length, glyphKeys.where((key) => key != 'glyph-account-session' && key != 'glyph-github-token').length);
    expect(secure.held.containsKey('glyph-account-session'), signedIn);
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _equal(Map<String, String> a, Map<String, String> b) => a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);
