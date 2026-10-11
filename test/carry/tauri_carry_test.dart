// The carry from the Tauri app (lib/carry/tauri_carry.dart), over the Tauri app's own storage as an emulator's
// copy of version 1.15.0 left it (test/carry/fixtures, web_stores_test.dart says how they were made), with the
// Rust core's real crypto raising the keys. The web view is a stand-in that answers what the page answered.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/account/keystore.dart' show readSession;
import 'package:ghost_md/carry/tauri_carry.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/team/docs.dart';

import '../team_sync/support.dart' show coreBuilt, coreSkip, openCore;

class MapPrefs implements CarryPrefs {
  final Map<String, String> kept = {};
  int reloads = 0;

  /// Keys whose write is refused.
  final Set<String> refuses = {};

  @override
  String? read(String key) => kept[key];

  @override
  Future<bool> write(String key, String value) async {
    if (refuses.contains(key)) return false;
    kept[key] = value;
    return true;
  }

  @override
  Future<void> reload() async => reloads += 1;
}

class FakeDevice implements CarryDevice {
  FakeDevice(this.answer);

  /// What the web view answers, or null for a phone with none.
  String? Function(String probeContext)? answer;
  int reads = 0;
  List<String>? forgot;

  @override
  Future<String> readWeb(String probeContext) async {
    reads += 1;
    final said = answer?.call(probeContext);
    if (said == null) throw StateError('No web view.');
    return said;
  }

  @override
  Future<void> forgetWork(List<String> names) async => forgot = names;
}

const String accountRaw = 'SP2m_BK5LNfUsc1VaHwDmn2PK8ePhEQSx4WCLgp1YSI';
const String pairRaw = 'nM4ABBzGyktNpOrduGaEzc6FECJkceNaSFrtzhVJ5TU';
const String pairPublic = 'BE0Ma7LPWtGS7C8yZOljz8ErvwNrBR2ED3k9LZBqQx-QnMtn56Yw9Grn3OWmk531P_uDuK7rGY5tQBWuDt3rvI8';

void main() {
  late GhostCore core;
  late Directory data;
  late Map<String, String> truth;

  setUpAll(() async {
    if (coreBuilt) core = await openCore();
  });
  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  /// A phone's data folder as the Tauri app left it.
  setUp(() async {
    data = await Directory.systemTemp.createTemp('carry');
    final web = '${data.path}/app_webview/Default';
    await Directory('$web/Local Storage/leveldb').create(recursive: true);
    await Directory('$web/IndexedDB/http_tauri.localhost_0.indexeddb.leveldb').create(recursive: true);
    File('test/carry/fixtures/phone_local/000003.log').copySync('$web/Local Storage/leveldb/000003.log');
    File('test/carry/fixtures/phone_idb/000003.log').copySync('$web/IndexedDB/http_tauri.localhost_0.indexeddb.leveldb/000003.log');
    File('${data.path}/slack.json').writeAsStringSync('{"channels":{"c0ffee-1":"https://hooks.slack.com/services/T000/B000/x","bad id":"https://hooks.slack.com/services/T/B/y","elsewhere":"https://example.com/hook"}}');
    File('${data.path}/notion.json').writeAsStringSync('{"accessToken":"secret_x","refreshToken":null,"botId":"bot1","workspaceId":"ws1","workspaceName":"Space","workspaceIcon":null}');
    truth = (jsonDecode(File('test/carry/fixtures/phone_local_truth.json').readAsStringSync()) as Map).cast<String, String>();
  });
  tearDown(() => data.delete(recursive: true));

  /// What the page would seal under its account key: the core's own seal under the same bytes.
  Future<String> probe(String context, {String raw = accountRaw}) async {
    final key = ((await core.invoke('key_restore', {'kind': 'account', 'raw': raw})) as Map)['key'];
    return await core.invoke('seal', {'key': key, 'context': context, 'text': jsonEncode('ghost-carry')}) as String;
  }

  /// The page's answer (TauriCarry.kt's PAGE), with [sealed] as the account key's probe.
  String page(String? sealed, {String public = pairPublic}) => jsonEncode({
        'v': 1,
        'origin': 'http://tauri.localhost',
        'local': truth,
        'databases': ['glyph-account', 'glyph-team'],
        'keys': {
          'account': {'algorithm': 'AES-GCM', 'extractable': false, 'probe': ?sealed},
          'encryption': {'algorithm': 'ECDH', 'public': public},
        },
        'team': [
          {'id': 'note_cutover_team_1', 'state': 'AQID-vv8', 'seq': 7, 'snapshotSeq': 5, 'pending': ['CQgH', 'Bg']},
          {'id': '../escape', 'state': 'AQID', 'seq': 1, 'snapshotSeq': 1, 'pending': []},
        ],
      });

  ({TauriCarry carry, MapPrefs prefs, MemorySecureStore secure, FakeDevice device}) make(String? Function(String)? answer, {MapPrefs? prefs, MemorySecureStore? secure}) {
    final kept = prefs ?? MapPrefs(), secrets = secure ?? MemorySecureStore(), device = FakeDevice(answer);
    return (carry: TauriCarry(dataDir: data.path, prefs: kept, secure: secrets, device: device, now: () => DateTime.utc(2026, 10, 11, 12)), prefs: kept, secure: secrets, device: device);
  }

  String log() => File('${data.path}/carry/tauri-carry.log').readAsStringSync();
  Map marker() => jsonDecode(File('${data.path}/carry/tauri-carry.json').readAsStringSync()) as Map;

  test('everything the page kept is this app\'s, and a signed-in person is signed in with their keys', () async {
    final sealed = await probe(carryProbeContext);
    final made = make((context) => page(sealed));
    final first = await made.carry.settings();
    expect(first.done, isTrue);
    expect(first.failed, isEmpty);

    // Every key but the two secrets, text for text.
    final expected = Map.of(truth)
      ..remove('glyph-account-session')
      ..remove('glyph-github-token');
    expect(made.prefs.kept, expected);
    expect(made.prefs.reloads, 1, reason: 'read back from where it is kept');
    // And read as the app reads them: the theme chosen and the workspace made in the Tauri app.
    final preferences = jsonDecode(made.prefs.kept['glyph-preferences']!) as Map;
    expect(preferences['theme'], 'dawn');
    expect(((preferences['workspaces'] as Map)['list'] as List).single['name'], 'Harbour');

    // The team note's document, where lib/team/docs.dart reads it, with what was not yet sent.
    final doc = await FileDocs.forAccount(data.path, 4242).read('note_cutover_team_1');
    expect(doc!.state, [1, 2, 3, 250, 251, 252]);
    expect(doc.seq, 7);
    expect(doc.snapshotSeq, 5);
    expect(doc.pending, [
      [9, 8, 7],
      [6],
    ]);
    expect(Directory('${data.path}/team/4242').listSync().length, 1, reason: 'a name that is no note id is no file');

    final second = await made.carry.secrets(core.invoke);
    expect(second.done, isTrue);
    expect(second.failed, isEmpty);
    expect(made.secure.held.keys.toSet(), {'glyph-account-session', 'glyph-github-token', 'glyph-slack-webhook:c0ffee-1', 'glyph-notion-account', 'account', 'encryption'});
    expect(made.secure.held['glyph-github-token'], 'ghp_cutover_test_not_real');
    expect(made.secure.held['glyph-slack-webhook:c0ffee-1'], 'https://hooks.slack.com/services/T000/B000/x');
    expect(jsonDecode(made.secure.held['glyph-notion-account']!), {'accessToken': 'secret_x', 'refreshToken': null, 'botId': 'bot1', 'workspaceId': 'ws1', 'workspaceName': 'Space', 'workspaceIcon': null});
    expect(made.device.forgot, carryStaleWork);

    // The app's own key store reads a signed-in device out of it: the session, and keys the core raises.
    final crypto = CoreCrypto(core.invoke);
    final keys = DeviceKeyStore(crypto: crypto, store: made.secure);
    final session = await keys.session();
    expect(session!.handle, 'cutover');
    expect(session.accountId, 4242);
    final account = await keys.accountKey();
    expect(await crypto.open(account!, sealed, carryProbeContext), 'ghost-carry');
    final pair = await keys.encryptionKey();
    expect(await crypto.encryptionPublicKeyOf(pair!), pairPublic);
    expect(await keys.deviceKey(), isNull, reason: 'that web view had no Ed25519, so the page kept none');

    // Marked, logged, and nothing of the Tauri app's removed.
    expect(marker()['settings'], containsPair('source', 'webview'));
    expect((marker()['secrets'] as Map)['carried'], containsAll(['account', 'encryption', 'glyph-account-session']));
    expect(log(), contains('the account key opened what the page sealed'));
    expect(log(), contains('the encryption key answers its public key, the page\'s too'));
    for (final secret in ['cutover-test-token-not-real', 'ghp_cutover_test_not_real', accountRaw, pairRaw, 'secret_x', 'hooks.slack.com']) {
      expect(log(), isNot(contains(secret)));
      expect(File('${data.path}/carry/tauri-carry.json').readAsStringSync(), isNot(contains(secret)));
    }
    expect(File('${data.path}/app_webview/Default/Local Storage/leveldb/000003.log').existsSync(), isTrue);
    expect(File('${data.path}/app_webview/Default/IndexedDB/http_tauri.localhost_0.indexeddb.leveldb/000003.log').existsSync(), isTrue);
    expect(File('${data.path}/slack.json').existsSync(), isTrue);
    expect(File('${data.path}/notion.json').existsSync(), isTrue);
  }, skip: coreSkip);

  test('it runs once: the next launch asks no web view and changes nothing', () async {
    final sealed = await probe(carryProbeContext);
    final first = make((context) => page(sealed));
    await first.carry.settings();
    await first.carry.secrets(core.invoke);
    expect(first.device.reads, 1, reason: 'one web view for both halves');
    // The person changes a setting in this app; the Tauri app's old value must never come back over it.
    first.prefs.kept['glyph-all-notes-sort'] = 'oldest';
    final again = make((context) => fail('asked again'), prefs: first.prefs, secure: first.secure);
    expect((await again.carry.settings()).ran, isFalse);
    expect((await again.carry.secrets(core.invoke)).ran, isFalse);
    expect(again.device.reads, 0);
    expect(first.prefs.kept['glyph-all-notes-sort'], 'oldest');
  }, skip: coreSkip);

  test('cut short, it runs again and comes to the same place, over nothing this app already holds', () async {
    final sealed = await probe(carryProbeContext);
    final prefs = MapPrefs()..refuses.add('glyph-tape-ids');
    final first = make((context) => page(sealed), prefs: prefs);
    final cut = await first.carry.settings();
    expect(cut.done, isFalse);
    expect(cut.failed, ['glyph-tape-ids']);
    expect(File('${data.path}/carry/tauri-carry.json').existsSync(), isFalse);
    // Not marked, so the second half does not go on alone.
    expect((await first.carry.secrets(core.invoke)).done, isFalse);
    expect(first.secure.held, isEmpty);

    // Meanwhile this app wrote one of the keys itself.
    prefs.refuses.clear();
    prefs.kept['glyph-sidebar-shown'] = '1';
    final secure = MemorySecureStore()..held['glyph-github-token'] = 'this-apps-own';
    final again = make((context) => page(sealed), prefs: prefs, secure: secure);
    final whole = await again.carry.settings();
    expect(whole.done, isTrue);
    expect(whole.carried, contains('glyph-tape-ids'));
    expect(whole.left, contains('glyph-sidebar-shown'));
    expect(prefs.kept['glyph-sidebar-shown'], '1');
    expect(prefs.kept['glyph-tape-ids'], truth['glyph-tape-ids']);
    final secrets = await again.carry.secrets(core.invoke);
    expect(secrets.done, isTrue);
    expect(secrets.left, ['glyph-github-token']);
    expect(secure.held['glyph-github-token'], 'this-apps-own');
  }, skip: coreSkip);

  test('with no web view, localStorage and the keys are read from the files', () async {
    final made = make(null);
    expect((await made.carry.settings()).done, isTrue);
    final expected = Map.of(truth)
      ..remove('glyph-account-session')
      ..remove('glyph-github-token');
    expect(made.prefs.kept, expected);
    expect((await made.carry.secrets(core.invoke)).done, isTrue);
    expect(made.secure.held['account'], accountRaw);
    expect(made.secure.held['encryption'], pairRaw);
    expect(readSession(MemoryStoredOf(made.secure.held))?.handle, 'cutover');
    expect(marker()['settings'], containsPair('source', 'files'));
    expect(log(), contains('no web view could seal a proof'));
  }, skip: coreSkip);

  test('a key that does not prove itself is not carried: signed in, and asked for the password once', () async {
    // The page's key is another key than the files gave, and its pair answers another public key.
    final other = await probe(carryProbeContext, raw: 'KT5Ybr-WVWEyVYV-XkgGX4wkDq46Aj2oSEnVDaDHQME');
    final made = make((context) => page(other, public: 'BKO9UMI6W1H0zX-KAjH9CVtQcaA1LIO2SRwMzjuZ3_GsJ9h4PTXbttsD4_5UNlGkpWjG2RULFzZORoQRU2EadCY'));
    await made.carry.settings();
    final secrets = await made.carry.secrets(core.invoke);
    expect(secrets.done, isTrue);
    expect(made.secure.held.containsKey('account'), isFalse);
    expect(made.secure.held.containsKey('encryption'), isFalse);
    expect(made.secure.held.containsKey('glyph-account-session'), isTrue);
    expect(log(), contains('did not open what the page sealed: not carried'));
    expect(log(), contains('the password is asked once'));
  }, skip: coreSkip);

  test('a phone the Tauri app was never on carries nothing and asks no web view, ever', () async {
    await Directory('${data.path}/app_webview').delete(recursive: true);
    final made = make((context) => fail('asked'));
    final settings = await made.carry.settings();
    expect(settings.ran, isFalse);
    expect(settings.done, isTrue);
    expect((await made.carry.secrets(core.invoke)).ran, isFalse);
    expect(made.prefs.kept, isEmpty);
    expect(made.secure.held, isEmpty, reason: 'slack.json and notion.json alone are not a Tauri app\'s web view');
    expect(marker()['settings'], {'at': '2026-10-11T12:00:00.000Z', 'found': false});
  }, skip: coreSkip);

  test('the phone\'s half answers on the channel and with the names this file asks', () {
    final kotlin = File('android/app/src/main/kotlin/com/mattssoftware/ghost_md/TauriCarry.kt').readAsStringSync();
    expect(kotlin, contains('"${ChannelCarryDevice.channel.name}"'));
    expect(kotlin, allOf(contains('"read" ->'), contains('"forgetWork" ->'), contains('"probeContext"'), contains('"names"')));
    expect(kotlin, contains('http://tauri.localhost/'));
    final activity = File('android/app/src/main/kotlin/com/mattssoftware/ghost_md/MainActivity.kt').readAsStringSync();
    expect(activity, contains('TauriCarry(this).also { it.register(messenger) }'));
  });
}

/// A [Stored] over a map, to read a session as the page's shape.
class MemoryStoredOf extends Stored {
  MemoryStoredOf(this.map);

  final Map<String, String> map;

  @override
  String? getItem(String key) => map[key];

  @override
  void setItem(String key, String text) => map[key] = text;

  @override
  void removeItem(String key) => map.remove(key);

  @override
  Iterable<String> get allKeys => map.keys;
}
