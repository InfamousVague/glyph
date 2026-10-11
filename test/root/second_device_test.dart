// A second device of an account that was made on the phone, reading what the phone wrote: the check that the app
// put together in lib/root really syncs with the service. Run by hand after signing up in a build given
// `--dart-define=GHOST_API=http://10.0.2.2:<port>/api` against tool/local-server.sh:
//
//   GHOST_E2E_API=http://127.0.0.1:<port>/api GHOST_E2E_HANDLE=… GHOST_E2E_PASSWORD=… GHOST_E2E_WORDS='words typed on the phone' \
//     flutter test --no-pub test/root/second_device_test.dart
//
// Skipped unless all three are set, so the ordinary suite needs no server; refused unless the base names 127.0.0.1
// (test/e2e/world.dart `LocalWorld`), so it cannot reach the real service whatever the variables say. The crypto is
// the real one at the real 600,000 rounds, which is what the phone derived the account's keys with.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/account.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/org_keys.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/feed.dart';

import '../e2e/world.dart' show LocalWorld;
import '../support/sync_device.dart';
import '../team_sync/support.dart' show coreLibrary, coreSkip;

void main() {
  final env = Platform.environment;
  final base = env['GHOST_E2E_API'] ?? '', handle = env['GHOST_E2E_HANDLE'] ?? '', password = env['GHOST_E2E_PASSWORD'] ?? '';
  final words = env['GHOST_E2E_WORDS'] ?? '';
  final skip = base.isEmpty || handle.isEmpty || password.isEmpty ? 'no account made on a phone: set GHOST_E2E_API, GHOST_E2E_HANDLE and GHOST_E2E_PASSWORD' : coreSkip;

  test('a second device signs in to the account the phone made, and reads its notes and its organizations', () async {
    final world = LocalWorld(base);
    final core = await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);
    addTearDown(core.close);
    final api = world.api();
    final crypto = CoreCrypto(core.invoke);
    final keys = DeviceKeyStore(crypto: crypto, store: MemorySecureStore());
    final prefs = PreferencesStore()..startWithoutStorage();
    final kept = MemoryStored();
    final notes = DeviceNotes();
    final account = Account(keys: keys, api: api, crypto: crypto, label: 'A second device');
    final feed = NotificationFeed(account: account, crypto: crypto, kept: kept);
    final orgs = Orgs(account: account, api: api, workspaces: WorkspaceStore(storage: KeptWorkspaceStorage(prefs: prefs, stored: kept)), kept: kept);
    final engine = SyncEngine(account: AccountDoor(account), api: api, crypto: crypto, keys: keys, prefs: prefs, notes: notes, files: DeviceFiles(), feed: feed, orgs: orgs, orgKeys: OrgKeys(crypto: crypto, api: api), kept: kept);
    addTearDown(engine.dispose);

    await account.signIn(handle, password);
    expect(account.session, isNotNull);
    await engine.syncNow();
    final status = engine.status.value;
    expect((status.phase, status.message), ('idle', null), reason: 'the pass on the second device did not end clean');

    final bodies = [for (final note in notes.held.values) note.body];
    // ignore: avoid_print
    print('the second device holds ${bodies.length} notes; organizations: ${[for (final row in orgs.orgsState().list) '${row.name} (${row.state}, ${row.role})']}');
    expect(bodies, isNotEmpty, reason: 'nothing the phone wrote reached the service');
    if (words.isNotEmpty) expect(bodies.where((body) => body.contains(words)), isNotEmpty, reason: 'no note on the service holds "$words"');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
