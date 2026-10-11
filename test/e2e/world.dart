// What the end-to-end scenarios stand on (scenarios.dart): a WORLD, which is a service every device talks to, and
// whole DEVICES in it.
//
// A world is one of two, and never anything else (docs/STAGE7.md: a development build never talks to
// ghostmarkdown.com):
//
// - `FakeWorld`: the service in memory (test/support/fake_service.dart), handed the REAL crypto and the core's own
//   Ed25519 check for a device's signature. One account, as that service holds one. Offline.
// - `LocalWorld`: the real service (server) run on 127.0.0.1 by tool/local-server.sh, over real sockets.
//   Any number of accounts. Its base is refused unless its host is 127.0.0.1.
//
// A device is everything the app would make for one phone, with nothing standing in for the cryptography or the
// CRDT: `CoreCrypto` and `Crdt` over the Mac's build of the Rust core, `DeviceKeyStore` over a secure store in
// memory (so every key a device keeps goes through `keep` and comes back through `restore`), the real `Account`,
// the real `SyncEngine` with every pass its own and the team channel as its step-5 hook, the feed, the
// organizations and their keys, and the shares. Only what a phone keeps on disk is in maps: its notes, its
// pictures, its versions files, its settings.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/account.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/live/live.dart';
import 'package:ghost_md/live/nudge.dart';
import 'package:ghost_md/orgs/org_keys.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/share/share.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/feed.dart';
import 'package:ghost_md/sync/record.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';
import 'package:ghost_md/team/sync.dart';

import '../support/fake_service.dart';
import '../support/sync_device.dart';

/// PBKDF2's rounds in these scenarios: the web's own tests' `FAST`. The real 600,000 are held to the web's by the
/// fixtures (native/tests/crypto_vectors.rs); here they would only be minutes of waiting in a debug build.
const int e2eRounds = 1000;

final Random _random = Random.secure();

/// A handle nobody has: the real service keeps every account a run makes until it stops.
String freshHandle(String stem) => '$stem-${List.generate(8, (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[_random.nextInt(31)]).join()}';

/// Where the devices meet.
abstract class World {
  /// For a test's name: which service this is.
  String get name;

  /// Whether more than one account can be made (the service in memory holds one).
  bool get manyAccounts;

  /// The service, as one device reaches it.
  Api api();

  /// A new service for a test, where a world has one a test (the one in memory); nothing for the real one.
  Future<void> fresh();
}

/// The service in memory, with the real crypto.
class FakeWorld implements World {
  FakeWorld(this.core);
  final GhostCore core;
  late FakeService service;

  @override
  String get name => 'the service in memory';

  @override
  bool get manyAccounts => false;

  @override
  Future<void> fresh() async {
    service = await FakeService.start(
      crypto: CoreCrypto(core.invoke),
      // The service's half of password-free sign-in: Ed25519, by the core (native/src/crypto.rs `device_key_verify`).
      verify: (publicKey, nonce, signature) async => await core.invoke('device_key_verify', {'public': publicKey, 'nonce': nonce, 'signature': signature}) as bool,
    );
  }

  @override
  Api api() => Api(base: 'http://service.test/api', fetcher: service.fetcher);
}

/// The real service on this Mac (tool/local-server.sh).
class LocalWorld implements World {
  LocalWorld(this.base) {
    final host = Uri.parse(base).host;
    if (host != '127.0.0.1') throw ArgumentError('The end-to-end tests run against 127.0.0.1 and nothing else; GHOST_E2E_API names $host.');
  }

  final String base;
  final Fetcher _io = ioFetcher();

  /// The service lets an address in twenty times a minute (server/src/accounts.rs `SIGN_IN_PER_ADDRESS`), and every
  /// device of every scenario is this Mac. A way in refused as too many is waited for and asked again, as a person
  /// would; anything else is answered as it came.
  Future<FetchResponse> _fetcher(FetchRequest request) async {
    for (var tries = 0;; tries += 1) {
      final answer = await _io(request);
      if (answer.status != 429 || tries >= 8) return answer;
      await Future<void>.delayed(const Duration(milliseconds: 3200));
    }
  }

  @override
  String get name => 'the real service on 127.0.0.1';

  @override
  bool get manyAccounts => true;

  @override
  Future<void> fresh() async {}

  @override
  Api api() => Api(base: base, fetcher: _fetcher);
}

/// This device's pictures, as a share asks for them: the same map sync writes.
class MapPictures implements SharePictures {
  MapPictures(this.held);
  final Map<String, Uint8List> held;

  @override
  Future<Uint8List?> read(String name) async => held[name];

  @override
  Future<Uint8List> smaller(Uint8List bytes) async => bytes;

  @override
  Future<void> keep(String name, Uint8List bytes) async => held[name] = bytes;
}

/// What a device has on disk, which a relaunch finds again: the secure store, what it remembers, its notes, its
/// files, its documents.
class Disk {
  final MemorySecureStore secure = MemorySecureStore();
  final MemoryStored kept = MemoryStored();
  final DeviceNotes notes = DeviceNotes();
  final DeviceFiles files = DeviceFiles();
  final MemoryDocs docs = MemoryDocs();
}

/// One whole device. See the header.
class Device {
  /// [live]: with live sync too (lib/live/live.dart), over a real socket to the relay beside the service; only in
  /// a [LocalWorld], which has one.
  Device(this.world, this.core, {String label = 'a device', Disk? disk, bool live = false})
      : disk = disk ?? Disk(),
        api = world.api() {
    crypto = CoreCrypto(core.invoke);
    keys = DeviceKeyStore(crypto: crypto, store: this.disk.secure);
    prefs = PreferencesStore()..startWithoutStorage();
    account = Account(keys: keys, api: api, crypto: crypto, iterations: e2eRounds, label: label);
    feed = NotificationFeed(account: account, crypto: crypto, kept: kept);
    workspaces = WorkspaceStore(storage: KeptWorkspaceStorage(prefs: prefs, stored: kept));
    orgs = Orgs(account: account, api: api, workspaces: workspaces, kept: kept);
    orgKeys = OrgKeys(crypto: crypto, api: api);
    record = SelfNotifications(feed: feed, api: api);
    docs = TeamDocs(crdt: Crdt(core.invoke), store: this.disk.docs);
    final world = this.world;
    this.live = live && world is LocalWorld ? LiveServices(base: world.base, account: account, crypto: crypto, crdt: Crdt(core.invoke), orgs: orgs, orgKeys: orgKeys, prefs: prefs, kept: kept) : null;
    shares = Shares(account: account, api: api, crypto: crypto, prefs: prefs, pictures: MapPictures(this.disk.files.pictures), listNotes: this.disk.notes.list);
    engine = SyncEngine(
      account: AccountDoor(account),
      api: api,
      crypto: crypto,
      keys: keys,
      prefs: prefs,
      notes: this.disk.notes,
      files: this.disk.files,
      feed: feed,
      orgs: orgs,
      orgKeys: orgKeys,
      record: record,
      kept: kept,
      onNotesChanged: () => told += 1,
      teamNotes: teamNotesPass(docs),
      forgetTeams: docs.forget,
      sharedLive: this.live?.shared.isShared,
      tellChanged: this.live?.nudges.tellChanged,
    );
    this.live?.start(NudgeHooks(keys: engine.syncNotificationsNow, notes: engine.syncTeamsNow));
  }

  final World world;
  final GhostCore core;
  final Disk disk;
  final Api api;
  late final CoreCrypto crypto;
  late final DeviceKeyStore keys;
  late final PreferencesStore prefs;
  late final Account account;
  late final NotificationFeed feed;
  late final WorkspaceStore workspaces;
  late final Orgs orgs;
  late final OrgKeys orgKeys;
  late final SelfNotifications record;
  late final TeamDocs docs;
  late final Shares shares;
  late final SyncEngine engine;

  /// Live sync, for a device made with it.
  late final LiveServices? live;

  /// How many times the list was told to read again.
  int told = 0;
  bool _closed = false;

  MemoryStored get kept => disk.kept;
  Map<String, Note> get notes => disk.notes.held;
  Map<String, Uint8List> get pictures => disk.files.pictures;
  Map<String, String> get versions => disk.files.versions;

  /// A note written on this device.
  void write(String id, String body, {int at = 1, bool starred = false}) {
    final had = notes[id];
    notes[id] = had == null ? Note(id: id, body: body, createdAt: at, updatedAt: at, starred: starred) : had.copyWith(body: body, updatedAt: at);
  }

  /// One whole pass, which must end clean: anything else fails the test with what the pass said.
  Future<void> sync() async {
    await engine.syncNow();
    final status = engine.status.value;
    expect((status.phase, status.message, status.unsent, status.unsentReason), ('idle', null, 0, null), reason: 'a pass on this device did not end clean');
  }

  /// The app closed and opened again on the same phone: everything in memory gone, everything on disk found.
  /// Nothing is asked of the service until [Account.resume] or a pass.
  Future<Device> relaunched({String label = 'a device'}) async {
    await close();
    final next = Device(world, core, label: label, disk: disk);
    final settings = prefs.value;
    next.prefs.update((_) => settings);
    await next.account.restore();
    return next;
  }

  /// The device put down: its documents let go from the core.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    live?.dispose();
    engine.dispose();
    await docs.forget();
  }
}
