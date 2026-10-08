/// The account, made for this device: what `App.tsx` gets by importing `core/account`, `core/sync`, `core/orgs`,
/// `core/notifications` and `share/`, put together once by whoever starts the app.
///
/// **Off unless the build is told where its service is.** There is no default base (docs/STAGE7.md: a development
/// build never talks to ghostmarkdown.com). A build is given one with `--dart-define=GHOST_API=http://…`
/// ([ghostApiDefine]); with none, [accountBase] answers null, nothing here is made, and the app has no account
/// object at all: the signed-out screens, whose way in says so ([noServiceWayIn]). A base that names the real
/// service is refused in a debug build here, before an [Api] is made, and by the [Api]'s own assert after.
///
/// What is made ([WiredAccount.make]), each the real one: the crypto in the Rust core on a lane of its own for the
/// long calls ([CoreCrypto.withLane], made by `main`), the keys under the phone's Keystore ([DeviceKeyStore]), the
/// [Account], the notifications' feed, the organizations and their keys, the team notes' documents as files beside
/// the library (one folder to an account), the shares, and the [SyncEngine] over this device's own library and
/// files, with team notes as its fifth step.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/account.dart';
import '../account/api.dart';
import '../account/crypto.dart';
import '../account/crypto_api.dart' show rounds;
import '../account/device_keys.dart';
import '../account/ui_state.dart';
import '../core/native/core.dart';
import '../core/native/files.dart';
import '../core/note.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../core/versions_store.dart';
import '../core/workspaces.dart';
import '../orgs/org_keys.dart';
import '../orgs/orgs.dart';
import '../share/share.dart';
import '../sync/device.dart';
import '../sync/engine.dart';
import '../sync/feed.dart';
import '../sync/local.dart';
import '../sync/record.dart';
import '../team/crdt.dart';
import '../team/doc.dart';
import '../team/docs.dart';
import '../team/sync.dart';

/// The base this build was given: `--dart-define=GHOST_API=http://10.0.2.2:<port>/api`. Empty in every build
/// that was not.
const String ghostApiDefine = String.fromEnvironment('GHOST_API');

/// The service's base for this build, or null for a build with no account: none given, one that is not an
/// address, or, in a build that is not a release ([debug]), one that names the real service.
String? accountBase(String given, {bool debug = !kReleaseMode}) {
  final base = given.trim();
  if (base.isEmpty) return null;
  final uri = Uri.tryParse(base);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
  if (debug && isProductionHost(uri.host)) return null;
  return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
}

/// What a way in says in a build with no service to sign in to.
const String noServiceWords = 'This build has no account service. Notes stay on this device.';

/// The way in of a build with no account: it says so, whatever was typed.
Future<List<String>?> noServiceWayIn({required String mode, required String handle, required String password, String? code}) async => throw const SaidFailure(noServiceWords);

/// What `main` hands the app for an account: where the service is, the crypto, and the app's data folder.
@immutable
class AccountMaking {
  const AccountMaking({required this.base, required this.crypto, required this.dataDir, this.fetcher, this.secure, this.iterations = rounds});

  final String base;
  final CoreCrypto crypto;
  final String dataDir;

  /// A test's; `dart:io`'s unless given.
  final Fetcher? fetcher;
  final SecureStore? secure;

  /// PBKDF2's rounds; the real 600,000 unless a test says otherwise.
  final int iterations;
}

/// The team notes' documents, in the folder of whoever is signed in: signed out, there are none to read and
/// nowhere to write.
class _AccountDocs implements TeamDocStore {
  _AccountDocs(this._dataDir, this._account);

  final String _dataDir;
  final Account _account;
  FileDocs? _docs;
  int? _for;

  FileDocs? get _now {
    final id = _account.session?.accountId;
    if (id == null) return null;
    if (_for != id) {
      _for = id;
      _docs = FileDocs.forAccount(_dataDir, id);
    }
    return _docs;
  }

  @override
  Future<TeamDocRecord?> read(String noteId) async => _now?.read(noteId);

  @override
  Future<void> write(String noteId, TeamDocRecord record) async => _now?.write(noteId, record);

  @override
  Future<void> remove(String noteId) async => _now?.remove(noteId);
}

/// The account's objects for this device, and their bundle for the screens.
class WiredAccount {
  WiredAccount._(this.services, this.engine, this._docs);

  /// Makes everything over this device's own stores. [core] is the library's core; [touched] is told after this
  /// device changes a note and [refresh] reads the list again after a pass changed notes (`CoreLibrary`'s two);
  /// [versions] is the versions' own store, shared with the note's history; [onPicture] is told a picture's name
  /// once sync has kept it.
  factory WiredAccount.make({
    required AccountMaking making,
    required CoreInvoke core,
    required WorkspaceStore workspaces,
    required VersionsStore versions,
    required Listenable? touched,
    required FutureOr<void> Function() refresh,
    required List<Note> Function() shownNotes,
    PreferencesStore? prefs,
    Stored? kept,
    void Function(String name)? onPicture,
  }) {
    final settings = prefs ?? preferences;
    final device = kept ?? stored;
    final crypto = making.crypto;
    final api = Api(base: making.base, fetcher: making.fetcher ?? ioFetcher());
    final keys = DeviceKeyStore(crypto: crypto, store: making.secure ?? deviceSecureStore());
    final account = Account(keys: keys, api: api, crypto: crypto, iterations: making.iterations, label: 'Ghost Flutter');
    final feed = NotificationFeed(account: account, crypto: crypto, kept: device);
    final orgs = Orgs(account: account, api: api, workspaces: workspaces, kept: device);
    final orgKeys = OrgKeys(crypto: crypto, api: api);
    final files = CoreFiles(core);
    final notes = LibraryNotes(core);
    final docs = TeamDocs(crdt: Crdt(core), store: _AccountDocs(making.dataDir, account));
    final shares = Shares(account: account, api: api, crypto: crypto, prefs: settings, pictures: CorePictures(files, onPicture: onPicture), listNotes: notes.list);
    final engine = SyncEngine(
      account: AccountDoor(account),
      api: api,
      crypto: crypto,
      keys: keys,
      prefs: settings,
      notes: notes,
      files: KeptFiles(versions: versions, bytes: CoreDeviceBytes(files, onPicture: onPicture)),
      feed: feed,
      orgs: orgs,
      orgKeys: orgKeys,
      record: SelfNotifications(feed: feed, api: api, localOnly: () => settings.value.localOnly),
      kept: device,
      touched: touched,
      onNotesChanged: refresh,
      teamNotes: teamNotesPass(docs),
      forgetTeams: docs.forget,
    );
    final services = AccountServices(
      account: account,
      engine: engine,
      orgs: orgs,
      orgKeys: orgKeys,
      feed: feed,
      shares: shares,
      listNotes: () async => shownNotes(),
      prefs: settings,
      workspaces: workspaces,
      kept: device,
    );
    return WiredAccount._(services, engine, docs);
  }

  final AccountServices services;
  final SyncEngine engine;
  final TeamDocs _docs;
  bool _started = false;

  /// What this device kept of an account, read without asking the service anything; then the sync for the life of
  /// the app. Once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await services.account.restore();
    } catch (failure) {
      debugPrint('[ghost] the account kept on this device would not read: $failure');
    }
    engine.start();
  }

  /// The app came back to the front.
  void resumed() => engine.resumed();

  void dispose() {
    engine.dispose();
    unawaited(Future<void>.sync(_docs.forget).catchError((Object _) {}));
  }
}
