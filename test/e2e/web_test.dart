// A Dart device and a WEB device on one account, through the real service on 127.0.0.1: the web app's own client
// code (tauri/src/app/core, with its own WebCrypto and its own Yjs) run under Node by tool/web_client.mjs,
// signing in to the account the Dart device made, reading its note, its picture, its settings and its team note,
// writing its own back, and both editing one team note apart.
//
//   tool/local-server.sh test          # runs this with the rest of test/e2e
//
// Skipped unless GHOST_E2E_API is set (and names 127.0.0.1), the Mac's core is built, `node` is on the PATH and
// tauri/ has its node_modules (the web's `yjs`). The Node side refuses any host but 127.0.0.1 three times over
// (web_client.mjs says how): the web's own default base is the real service, and must never be reached.
//
// What this proves, and no more: the two clients agree on the account's wire (PBKDF2 login halves, the account
// key's wrap, sealed notes, files and settings), on the organizations' (the account's pair sealed for its other
// devices, an organization key's wrap, a team row, a sealed update) and on the CRDT's (yrs and Yjs converge
// through the service's log), in BOTH directions. The web side is its sync modules driven as its own e2e test
// drives them, with its notes and settings in maps: not the web's engine (`core/sync/engine.ts`, which wants a
// page), not its IndexedDB key store, and not a browser.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/workspaces.dart';

import '../team_sync/support.dart' show coreBuilt, coreLibrary, coreSkip;
import 'world.dart';

String? _whyNot(String base) {
  if (base.isEmpty) return 'no local server: run tool/local-server.sh test (GHOST_E2E_API is not set)';
  if (coreSkip != null) return coreSkip;
  if (!Directory('tauri/node_modules/yjs').existsSync()) return 'tauri/ has no node_modules/yjs for the web client to load';
  try {
    if (Process.runSync('node', ['--version']).exitCode != 0) return '`node` did not run';
  } on ProcessException {
    return '`node` is not on the PATH';
  }
  return null;
}

void main() {
  final base = Platform.environment['GHOST_E2E_API'] ?? '';
  final skip = _whyNot(base);
  late GhostCore core;
  late LocalWorld world;
  final devices = <Device>[];

  /// One run of the web device (tool/web_client.mjs): what it held at the end.
  Future<Map<String, Object?>> web(Map<String, Object?> job) async {
    final ran = await Process.run('node', ['--experimental-transform-types', '--no-warnings', 'tool/web_client.mjs', jsonEncode(job)], environment: {'GHOST_E2E_API': base});
    if (ran.exitCode != 0) fail('the web client failed (${ran.exitCode}):\n${ran.stderr}\n${ran.stdout}');
    final said = (jsonDecode((ran.stdout as String).trim().split('\n').last) as Map).cast<String, Object?>();
    expect(said['apiBase'], base, reason: 'the web client spoke to the local server and nothing else');
    return said;
  }

  setUpAll(() async {
    if (skip != null) return;
    world = LocalWorld(base);
    core = await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);
  });

  tearDownAll(() async {
    for (final each in devices) {
      await each.close();
    }
    if (skip == null && coreBuilt) await core.close();
  });

  test('a Dart device and a web device read each other\'s note, picture and settings, and merge one team note edited on both', () async {
    final handle = freshHandle('web');
    const password = 'correct horse battery';
    final picture = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 9, 8, 7]);
    final phone = Device(world, core, label: 'phone');
    devices.add(phone);
    await phone.account.signUp(handle, password);
    phone.write('n1', '# From the phone 😀\n\n![](image/list.png)', starred: true);
    phone.pictures['list.png'] = picture;
    phone.prefs.update((now) => now.copyWith(theme: 'ember'));
    final org = await phone.orgs.createOrg('Ghost');
    await phone.sync();
    phone.write('t1', 'one 😀\ntwo\nthree ![](image/team.png)');
    phone.pictures['team.png'] = picture;
    phone.disk.files.versions['t1'] = '# Ghost.md versions 1\n# note t1\n\nv1 2026-10-05T00:00:00.000Z $handle 00000000 full\n  +one\n';
    phone.disk.files.owing.add('t1');
    phone.workspaces.fileNote('t1', orgWorkspaceId(org.id));
    await phone.sync();

    // The web device: signs in with the password, and reads everything the phone sealed.
    final first = await web({
      'handle': handle,
      'password': password,
      'rounds': e2eRounds,
      'write': {
        'note': {'id': 'w1', 'body': '# From the web\n\nécrit sur le web 🌍'},
        'theme': 'dawn',
        'team': {'id': 't1', 'append': '\nfour, from the web'},
      },
    });
    final read = (first['read'] as Map).cast<String, Object?>();
    expect((read['notes'] as Map)['n1'], '# From the phone 😀\n\n![](image/list.png)');
    expect((read['notes'] as Map)['t1'], 'one 😀\ntwo\nthree ![](image/team.png)');
    expect(read['theme'], 'ember');
    final held = (first['notes'] as Map).cast<String, Object?>();
    expect((held['n1'] as Map)['starred'], isTrue);
    expect((held['t1'] as Map)['team'], org.id, reason: 'the web filed the team\'s note under its organization');
    final files = (first['files'] as Map).cast<String, Object?>();
    expect(files['image/list.png'], picture, reason: 'the account\'s picture, opened by the web');
    expect(files['image/team.png'], picture, reason: 'the organization\'s picture, opened by the web with the organization key');
    expect((first['versions'] as Map)['versions/t1'], contains('v1 2026-10-05'));
    final passes = first['outcomes'] as List;
    expect(((passes.last as Map)['teams'] as Map)[org.id], containsPair('unsent', 0));
    expect(((passes.last as Map)['teams'] as Map)[org.id], containsPair('generation', 1));

    // Meanwhile the phone changed the same team note at its top. Its pass posts that, and takes the web's line.
    phone.write('t1', 'ONE 😀\ntwo\nthree ![](image/team.png)', at: 5);
    await phone.sync();
    await phone.sync();
    const merged = 'ONE 😀\ntwo\nthree ![](image/team.png)\nfour, from the web';
    expect(phone.notes['t1']?.body, merged);
    expect(phone.notes['w1']?.body, '# From the web\n\nécrit sur le web 🌍');
    expect(phone.prefs.value.theme, 'dawn');
    expect(phone.engine.status.value.conflicts, 0);

    // A second web device, signing in afresh: the merged note, by the row and the log the phone and the first left.
    final second = await web({'handle': handle, 'password': password, 'rounds': e2eRounds});
    final again = (second['notes'] as Map).cast<String, Object?>();
    expect((again['t1'] as Map)['body'], merged);
    expect((again['w1'] as Map)['body'], '# From the web\n\nécrit sur le web 🌍');
    expect((again['n1'] as Map)['body'], '# From the phone 😀\n\n![](image/list.png)');
    expect(second['theme'], 'dawn');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
