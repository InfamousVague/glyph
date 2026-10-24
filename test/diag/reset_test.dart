import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/account/keystore.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/core/reset.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';

/// `core/reset.test.ts`, case for case, on stores kept in memory: what a reset clears, and the guard that keeps it
/// true (every key the app keeps has to be one a reset can find, which is every key named `glyph-`), and the order:
/// nothing is wiped while the device could still sync. Then what is new here: no plugin secret outlives a reset.
///
/// What differs from the web's file: the page's account and Tauri were module mocks; here they are the fakes a
/// [ResetGround] is made of. The source scan reads `lib/` as Dart. Two parts are not carried over and are said where
/// they would stand: the real sync engine asked after a failed wipe, and the scan's resolving of constants and
/// functions, which was written for TypeScript.

// ---- the app's own source, read as text ------------------------------------------------------------------------

final List<({String name, String text})> _files = [
  for (final entry in Directory('lib').listSync(recursive: true))
    if (entry is File && entry.path.endsWith('.dart')) (name: entry.path.substring('lib/'.length), text: entry.readAsStringSync()),
];

/// The code without its comments, near enough: the prose talks about the keys all the time.
String _codeOf(String text) => text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'''(^|[^:'"])//.*$''', multiLine: true), r'$1');

/// Every `'glyph-…'` the source names, and the `'glyph-…$` a key is built from.
final Set<String> _named = {
  for (final file in _files)
    for (final m in RegExp(r'''['"](glyph-[a-z0-9-]+)['"]''').allMatches(file.text)) m.group(1)!,
};
final Set<String> _built = {
  for (final file in _files)
    for (final m in RegExp(r'''['"](glyph-[a-z0-9-]*)\$''').allMatches(file.text)) m.group(1)!,
};

/// The doors a key is kept through with its name written out (lib/core/stored.dart, lib/core/preferences.dart).
final RegExp _keptThrough = RegExp(r'''(?:\.readText|\.writeText|\.readShared(?:<[^(]*>)?|\.flag|\bDeviceFlag)\(\s*(['"])([^'"$]*)\1''');

// ---- a device ---------------------------------------------------------------------------------------------------

/// What was true of this device when the wipe began: the one moment the order is about.
typedef _AtWipe = ({int signOuts, bool signedIn, String? stored, List<String> bookkeeping});

class _Device {
  final MemoryStored kept = MemoryStored();
  final MemorySecureStore secrets = MemorySecureStore();
  late final MemoryKeyStore keys = MemoryKeyStore(kept: kept);
  bool signedIn = false;
  bool native = false;
  bool recording = false;
  int generation = 11;
  int signOuts = 0;
  int restarts = 0;
  _AtWipe? atWipe;
  final List<String> order = [];
  final List<bool> wipedModels = [];
  Future<void> Function() wipe = () async {};
  Future<void> Function()? signOutFails;
  Future<void> Function() settled = () async {};
  List<String> pluginKeys = const [];
  List<String> pluginSecrets = const [];
  Iterable<String> Function(String prefix)? secretsUnder;

  void noteWipe() {
    atWipe = (signOuts: signOuts, signedIn: signedIn, stored: kept.getItem('glyph-account-session'), bookkeeping: [for (final key in kept.keys()) if (key.startsWith('glyph-sync-')) key]);
  }

  /// Signing out as the engine does it, as far as a reset can see: the session gone from the app and from storage.
  Future<void> signOut() async {
    signOuts += 1;
    final fails = signOutFails;
    if (fails != null) {
      signOutFails = null;
      return fails();
    }
    signedIn = false;
    kept.removeItem('glyph-account-session');
  }

  ResetGround get ground => ResetGround(
        kept: () => kept,
        account: ResetAccount(signedIn: () => signedIn, signOutHere: signOut, syncSettled: () => settled()),
        keys: keys,
        native: native
            ? ResetNativeOf(
                hasGeneration: (wanted) async => generation >= wanted,
                recording: () => recording,
                cancelWriteUps: () => order.add('cancelWriteUps'),
                resetLocalData: ({required bool models}) {
                  noteWipe();
                  order.add('reset_local_data');
                  wipedModels.add(models);
                  return wipe();
                },
              )
            : null,
        wipeHere: () async {
          noteWipe();
          order.add('deleteImages');
          // The browser's notes are a `glyph-` key and go with the rest; its pictures are what is wiped here.
          await wipe();
        },
        pluginKeys: () => pluginKeys,
        pluginSecrets: () => pluginSecrets,
        secretsUnder: secretsUnder,
        secrets: () => secrets,
        restart: () => restarts += 1,
      );

  /// A device signed in to account 7, with the bookkeeping of its last sync, and some left from account 3.
  void signedInWithBookkeeping() {
    signedIn = true;
    kept.setItem('glyph-account-session', '{"token":"t","handle":"sam","accountId":7}');
    kept.setItem('glyph-sync-7-notes', '{"cursor":9,"notes":{"n1":{"rev":3,"mark":"x"}},"files":{}}');
    kept.setItem('glyph-sync-7-prefs', '{"rev":2,"seen":null}');
    kept.setItem('glyph-sync-7-notifications', '{"cursor":3,"items":{},"marks":[],"unsent":[]}');
    kept.setItem('glyph-sync-7-orgs', '{"list":[],"at":1}');
    kept.setItem('glyph-sync-3-notes', '{"cursor":4,"notes":{"n2":{"rev":1,"mark":"y"}},"files":{}}');
  }

  Future<void> reset({bool models = false}) => resetLocalData(ground, models: models);
}

/// Signed out once, no session in the app or in storage, and no bookkeeping: what a wipe must begin with.
void _expectClean(_AtWipe? at) {
  expect(at, isNotNull);
  expect((at!.signOuts, at.signedIn, at.stored), (1, false, null));
  expect(at.bookkeeping, isEmpty);
}

Matcher _throwsSaying(String words) => throwsA(predicate((Object e) => e.toString().contains(words), 'says "$words"'));

PluginManifest _manifest(String id, {List<String> storage = const [], List<String> secrets = const []}) =>
    PluginManifest(id: id, name: id, description: '', version: '1.0.0', author: 'test', standard: true, permissions: const [], storage: storage, secrets: secrets);

void main() {
  group('a reset', () {
    test('clears every key the app names, and leaves developer mode, the smoke overrides and other apps’ keys', () {
      final device = _Device()..pluginKeys = ['glyph-plugins', 'glyph-notion-links', 'a-plugin-key-not-named-glyph'];
      final seeded = [..._named, for (final start in _built) '${start}7-notes', ...device.pluginKeys];
      for (final key in seeded) {
        device.kept.setItem(key, 'kept');
      }
      device.kept.setItem('glyph-added-later', 'kept');
      device.kept.setItem('someone-else', 'kept');
      clearPageData(device.ground);
      expect(device.kept.keys()..sort(), [...spared, 'someone-else']..sort());
    });

    test('signs out and forgets every account’s sync bookkeeping before the phone’s notes are wiped', () async {
      final device = _Device()
        ..native = true
        ..signedInWithBookkeeping();
      await device.reset();
      _expectClean(device.atWipe);
      expect(device.restarts, 1);
    });

    test('does the same before the browser’s pictures and notes go', () async {
      final device = _Device()..signedInWithBookkeeping();
      device.kept.setItem('glyph-notes', '[{"id":"n1"}]');
      await device.reset();
      expect(device.order, ['deleteImages']);
      _expectClean(device.atWipe);
      expect(device.kept.getItem('glyph-notes'), isNull);
    });

    test('refuses while a meeting is being recorded, and otherwise cancels the phone’s write-ups before the wipe', () async {
      final device = _Device()
        ..native = true
        ..recording = true
        ..signedInWithBookkeeping();
      await expectLater(device.reset(), _throwsSaying('Stop the meeting first.'));
      expect(device.order, isEmpty);
      // Nothing was touched: still signed in, the bookkeeping still there.
      expect(device.signOuts, 0);
      expect(device.kept.getItem('glyph-sync-7-notes'), isNotNull);
      device.recording = false;
      await device.reset();
      expect(device.order, ['cancelWriteUps', 'reset_local_data']);
    });

    test('leaves nothing that could sync the wiped notes as deletions when the native wipe fails partway', () async {
      final device = _Device()
        ..native = true
        ..signedInWithBookkeeping();
      device.wipe = () async => throw StateError('could not remove the recordings');
      await expectLater(device.reset(models: true), _throwsSaying('could not remove the recordings'));
      expect(device.wipedModels, [true]);
      expect(device.signOuts, 1);
      expect(device.signedIn, isFalse);
      expect(device.kept.getItem('glyph-account-session'), isNull);
      expect(device.kept.keys().where((key) => key.startsWith('glyph-sync-')), isEmpty);
      // The app stays up after a failure, and is not started again on a half-wiped store.
      expect(device.restarts, 0);
      // Not carried over: the page then ran its real `syncNow` and saw no request. The engine here is not this
      // file's to build; signed out with no bookkeeping is what it would be asked with (test/sync has the engine's).
    });

    test('waits for a sync already running to finish before anything is wiped', () async {
      final device = _Device()
        ..native = true
        ..signedInWithBookkeeping();
      final running = Completer<void>();
      device.settled = () => running.future;
      final resetting = device.reset();
      // Every step up to the wait is a future already settled; a timer queued now runs after all of them.
      await Future<void>.delayed(Duration.zero);
      expect(device.signOuts, 1);
      expect(device.atWipe, isNull);
      running.complete();
      await resetting;
      _expectClean(device.atWipe);
    });

    test('wipes nothing when the device cannot sign out, so the notes and the bookkeeping still agree', () async {
      final device = _Device()
        ..native = true
        ..signedInWithBookkeeping();
      device.signOutFails = () async => throw StateError('IndexedDB failed');
      await expectLater(device.reset(), _throwsSaying('Could not sign out, so nothing was reset: IndexedDB failed'));
      expect(device.atWipe, isNull);
      expect(device.kept.getItem('glyph-sync-7-notes'), isNotNull);
      expect(device.kept.getItem('glyph-account-session'), isNotNull);
    });

    test('wipes nothing when a sync signed the device back in while it was waited for', () async {
      // The page's own comment, as a case: account.ts `resume` renews the session inside a running sync.
      final device = _Device()
        ..native = true
        ..signedInWithBookkeeping();
      device.settled = () async => device.signedIn = true;
      await expectLater(device.reset(), _throwsSaying('Could not sign out, so nothing was reset.'));
      expect(device.atWipe, isNull);
      expect(device.kept.getItem('glyph-sync-7-notes'), isNotNull);
    });

    test('asks nothing of an account a device never signed in to', () async {
      final device = _Device();
      await forgetAccount(device.ground);
      expect(device.signOuts, 0);
    });

    test('refuses a binary that cannot wipe, with nothing touched', () async {
      final device = _Device()
        ..native = true
        ..generation = 10
        ..signedInWithBookkeeping();
      await expectLater(device.reset(), _throwsSaying('Resetting needs the newest Ghost.md.'));
      expect(device.signOuts, 0);
      expect(device.order, isEmpty);
    });

    test('spares only keys the app really keeps, so the list cannot drift the way the old one did', () {
      final elsewhere = {
        for (final file in _files)
          if (file.name != 'core/reset.dart')
            for (final m in RegExp(r'''['"](glyph-[a-z0-9-]+)['"]''').allMatches(file.text)) m.group(1)!,
      };
      for (final key in spared) {
        expect(elsewhere, contains(key));
      }
    });
  });

  group('the account’s keys', () {
    test('are emptied with the session, so a key left by a sign-in that never finished does not outlive a reset', () async {
      final device = _Device();
      await device.keys.setSession(const Session(token: 't', handle: 'sam', accountId: 7));
      expect(await device.keys.session(), isNotNull);
      // Never signed in as far as the account says, but the store holds a session all the same.
      await device.reset();
      expect(await device.keys.session(), isNull);
      expect(await device.keys.accountKey(), isNull);
      expect(await device.keys.deviceKey(), isNull);
      expect(await device.keys.encryptionKey(), isNull);
    });
  });

  group('a plugin’s secrets', () {
    test('are forgotten by name, and under a prefix by the names whoever holds them gives', () async {
      final device = _Device()
        ..pluginKeys = ['glyph-slack-channels']
        ..pluginSecrets = ['glyph-notion-account', 'glyph-slack-webhook:'];
      device.kept.setItem('glyph-slack-channels', '[{"id":"c1"},{"id":"c2"}]');
      // A store that cannot list itself: only what is named can be forgotten.
      final store = _BlindStore({'glyph-notion-account': 'secret', 'glyph-slack-webhook:c1': 'hook 1', 'glyph-slack-webhook:c2': 'hook 2', 'account-keys': 'not a plugin’s'});
      var askedWith = '';
      final ground = ResetGround(
        kept: () => device.kept,
        pluginKeys: () => device.pluginKeys,
        pluginSecrets: () => device.pluginSecrets,
        // Asked while the channels are still listed: after the storage is cleared there would be nothing to read.
        secretsUnder: (prefix) {
          askedWith = device.kept.getItem('glyph-slack-channels') ?? 'already cleared';
          return ['${prefix}c1', '${prefix}c2', 'someone-elses-name'];
        },
        secrets: () => store,
      );
      await resetLocalData(ground, models: false);
      expect(askedWith, contains('c1'));
      expect(store.held.keys, ['account-keys']);
      expect(device.kept.getItem('glyph-slack-channels'), isNull);
    });

    test('a reset leaves no plugin secret readable', () async {
      final kept = MemoryStored();
      final secrets = MemorySecureStore();
      final was = pluginGround;
      final wasPlugins = plugins;
      addTearDown(() {
        usePluginGround(was);
        usePlugins(wasPlugins);
      });
      usePluginGround(PluginGround(stored: () => kept, secrets: secrets));
      final notion = _manifest('notion', storage: ['glyph-notion-links'], secrets: ['glyph-notion-account']);
      final slack = _manifest('slack', storage: ['glyph-slack-channels'], secrets: ['glyph-slack-webhook:']);
      usePlugins(createRegistry([GlyphPlugin(manifest: notion, icon: 'puzzle'), GlyphPlugin(manifest: slack, icon: 'puzzle')], store: MemorySwitches()));
      final notionHost = createHost(notion), slackHost = createHost(slack);
      await notionHost.secrets.write('glyph-notion-account', 'a token');
      await slackHost.secrets.write('glyph-slack-webhook:c1', 'https://hooks.example/1');
      await slackHost.secrets.write('glyph-slack-webhook:c2', 'https://hooks.example/2');
      slackHost.storage.set('glyph-slack-channels', [
        {'id': 'c1', 'name': '#launch'},
      ]);
      expect(notionHost.secrets.held('glyph-notion-account'), 'a token');

      // The app's own registry, ground and secure store, as the root would leave them: nothing given but the memory.
      await resetLocalData(ResetGround(kept: () => kept), models: false);

      expect(secrets.held, isEmpty);
      expect(await notionHost.secrets.read('glyph-notion-account'), isNull);
      expect(await slackHost.secrets.read('glyph-slack-webhook:c1'), isNull);
      expect(await slackHost.secrets.read('glyph-slack-webhook:c2'), isNull);
      // And not from the hosts' own memory of what they had read, which their synchronous door answers from.
      final fresh = createHost(notion);
      expect(fresh.secrets.held('glyph-notion-account'), isNull);
      expect(kept.keys(), isEmpty);
    });

    test('one that cannot be forgotten is said after everything else has gone', () async {
      final device = _Device()..pluginSecrets = ['glyph-notion-account', 'glyph-github-token'];
      device.kept.setItem('glyph-notes', '[]');
      final store = _BlindStore({'glyph-notion-account': 'secret', 'glyph-github-token': 'token'}, refuses: {'glyph-notion-account'});
      var restarts = 0;
      final ground = ResetGround(kept: () => device.kept, pluginKeys: () => const [], pluginSecrets: () => device.pluginSecrets, secrets: () => store, restart: () => restarts += 1);
      await expectLater(resetLocalData(ground, models: false), throwsA(isA<SecretsLeft>().having((e) => e.names, 'names', ['glyph-notion-account'])));
      expect(store.held.keys, ['glyph-notion-account']);
      expect(device.kept.getItem('glyph-notes'), isNull);
      expect(restarts, 1);
    });
  });

  group('every key the app keeps is one a reset can find', () {
    test('is kept through lib/core/stored.dart: nothing else touches the device’s storage', () {
      // The page's rule was "nothing but core/stored.ts touches localStorage". Here the device's storage is
      // SharedPreferences, opened by the memory itself and by the preferences, which keep `glyph-` keys in the same
      // store (lib/core/stored_device.dart's header).
      final touching = [
        for (final file in _files)
          if (RegExp(r'\bSharedPreferences\b').hasMatch(_codeOf(file.text))) file.name,
      ]..sort();
      expect(touching, ['core/preferences.dart', 'core/stored_device.dart']);
    });

    test('is named glyph-, wherever a door is handed one by name', () {
      final wrong = <String>[];
      for (final file in _files) {
        for (final m in _keptThrough.allMatches(_codeOf(file.text))) {
          final key = m.group(2)!;
          if (!key.startsWith('glyph-')) wrong.add('${file.name}: $key');
        }
      }
      expect(wrong, isEmpty);
      // Not carried over: the page's scan also resolved a key passed as a constant or made by a function, and listed
      // the seven it could not. Here a key passed by a name is not followed; sync's are `glyph-sync-<account>-<part>`
      // (lib/sync/engine.dart `_stateKey`), which the built keys below hold to.
      expect(_built, contains('glyph-sync-'));
    });

    test('finds the keys it checks: a scan that sees nothing passes for the wrong reason', () {
      final passed = [
        for (final file in _files) ..._keptThrough.allMatches(_codeOf(file.text)).map((m) => m.group(2)!),
      ];
      expect(passed.length, greaterThan(3));
      expect(_named.length, greaterThan(20));
      expect(_named, contains('glyph-developer'));
      expect(_named, contains('glyph-link-previews'));
    });
  });
}

/// A secure store as the phone's is: read and write by name, and no way to ask what it holds. [refuses] are names
/// whose write fails.
class _BlindStore implements SecureStore {
  _BlindStore(Map<String, String> held, {this.refuses = const {}}) : held = {...held};
  final Map<String, String> held;
  final Set<String> refuses;

  @override
  Future<String?> read(String name) async => held[name];

  @override
  Future<void> write(String name, String? value) async {
    if (refuses.contains(name)) throw StateError('the keystore is locked');
    if (value == null) {
      held.remove(name);
    } else {
      held[name] = value;
    }
  }
}
