// lib/carry/webkit_stores.dart: what a Mac's WebKit kept for the Tauri app's page, read from its files.
//
// Twice over. Against storage made here in WebKit's layout (webkit_make.dart), which needs nothing but this Mac's
// sqlite3 and so runs from a fresh checkout. And against a REAL WebKit's storage, wherever
// tool/webkit_fixture.swift has been run (it writes test/carry/fixtures/mac_webkit, which holds made-up keys and
// is not in git): a WKWebView at tauri://localhost keeping what the page keeps, with what a reader must find
// written beside it. That second half is what holds the first to the truth; it is skipped where the fixture is
// not, and says so.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/carry/webkit_stores.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

import '../team_sync/support.dart' show coreBuilt, coreSkip, openCore;
import 'webkit_make.dart';

// A P-256 pair and an account key that are nobody's (test/carry/tauri_carry_test.dart's own), and RFC 8032's
// first Ed25519 test vector.
final Uint8List accountRaw = fromBase64Url('SP2m_BK5LNfUsc1VaHwDmn2PK8ePhEQSx4WCLgp1YSI');
final Uint8List pairScalar = fromBase64Url('nM4ABBzGyktNpOrduGaEzc6FECJkceNaSFrtzhVJ5TU');
final Uint8List pairPoint = fromBase64Url('BE0Ma7LPWtGS7C8yZOljz8ErvwNrBR2ED3k9LZBqQx-QnMtn56Yw9Grn3OWmk531P_uDuK7rGY5tQBWuDt3rvI8');
final Uint8List edSeed = Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'.substring(i, i + 2), radix: 16)]);
final Uint8List edPublic = Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'.substring(i, i + 2), radix: 16)]);

const String realFixture = 'test/carry/fixtures/mac_webkit';
String? get realSkip => File('$realFixture/expected.json').existsSync() ? null : 'no real WebKit storage here: swiftc -O tool/webkit_fixture.swift -o build/ghost-webkit-fixture && build/ghost-webkit-fixture $realFixture';

void main() {
  late Directory temp;
  late Directory websiteData;
  final master = randomBytes(16);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('webkit');
    websiteData = Directory('${temp.path}/WebKit/com.mattssoftware.glyph/WebsiteData')..createSync(recursive: true);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  group('storage made in WebKit\'s layout', skip: webKitSkip, () {
    const local = {
      'glyph-preferences': '{"theme":"dawn","words":"héllo ✓ 𝄞"}',
      'glyph-account-session': '{"token":"t","handle":"made","accountId":7}',
      'glyph-empty': '',
      "glyph-it's": 'quoted',
      'someone-elses': 'kept by the page all the same',
    };
    final documents = {
      'note-one': (state: List.generate(300, (i) => (i * 7 + 1) & 0xff), seq: 12, snapshotSeq: 9, pending: [List.generate(5, (i) => i + 3), List.generate(70000, (i) => i & 0xff)]),
      'note-none': (state: <int>[], seq: 0, snapshotSeq: 1, pending: <List<int>>[]),
      'note-far': (state: [200, 201], seq: 70000, snapshotSeq: 1, pending: [<int>[255]]),
    };

    Directory make({Uint8List? key}) => makeWebKit(websiteData, local: local, databases: [
          accountDatabase(key ?? master, account: accountRaw, encryption: (scalar: pairScalar, point: pairPoint), device: (seed: edSeed, public: edPublic)),
          teamDatabase(documents),
        ]);

    test('localStorage, as the page wrote it: every key, any character, an empty value', () async {
      make();
      final read = await WebKitStores.read(websiteData);
      expect(read.found, isTrue);
      expect(read.failure, isNull);
      expect(read.damaged, 0);
      expect(read.local, local);
    });

    test('the three keys, opened under WebKit\'s master key', () async {
      make();
      final read = await WebKitStores.read(websiteData);
      expect(read.keysFound, isTrue);
      expect(read.wrappedCount, 5);
      final keys = read.keys(master);
      expect(keys.found, isTrue);
      expect(keys.account!.secret, accountRaw);
      expect(keys.account!.extractable, isFalse);
      expect(keys.encryption!.secret, pairScalar);
      expect(keys.encryption!.public, pairPoint);
      expect(keys.device!.secret, edSeed);
      expect(keys.device!.public, edPublic);
    });

    test('with no master key, or another one, the keys are found and none is read', () async {
      make();
      final read = await WebKitStores.read(websiteData);
      for (final keys in [read.keys(null), read.keys(randomBytes(16))]) {
        expect(keys.found, isTrue);
        expect(keys.account, isNull);
        expect(keys.device, isNull);
        expect(keys.encryption, isNull);
      }
    });

    test('the master key is what the Keychain holds: sixteen bytes, written as base64', () {
      expect(webCryptoMasterKey(Uint8List.fromList(ascii.encode(base64.encode(master)))), master);
      expect(webCryptoMasterKey(master), master);
      expect(webCryptoMasterKey(Uint8List.fromList(ascii.encode('not a key'))), isNull);
      expect(webCryptoMasterKey(Uint8List.fromList(ascii.encode(base64.encode(randomBytes(32))))), isNull);
      expect(webCryptoMasterKeyAccount('com.mattssoftware.glyph'), 'com.apple.WebKit.WebCrypto.master+com.mattssoftware.glyph');
    });

    test('a key that is not the kind its name says, a half in the other half\'s place, and a wrap of another version are no key', () async {
      makeWebKit(websiteData, databases: [
        (
          name: 'glyph-account',
          store: 'keys',
          records: {
            // An Ed25519 key where the account key should be.
            'account': Ssv.whole(Ssv.cryptoKey(webKitWrap(master, KeyBytes.okp(edSeed, private: true)))),
            // The public half under the private half's name.
            'device': Ssv.whole(Ssv.object({'privateKey': Ssv.cryptoKey(webKitWrap(master, KeyBytes.okp(edPublic, private: false))), 'publicKey': Ssv.cryptoKey(webKitWrap(master, KeyBytes.okp(edPublic, private: false)))})),
            'encryption': Ssv.whole(Ssv.object({'privateKey': Ssv.cryptoKey(webKitWrap(master, KeyBytes.ecPrivate(pairScalar, pairPoint), version: 2))})),
          },
        ),
      ]);
      final keys = (await WebKitStores.read(websiteData)).keys(master);
      expect(keys.found, isTrue);
      expect(keys.account, isNull);
      expect(keys.device, isNull);
      expect(keys.encryption, isNull);
    });

    test('the team notes\' documents, as the carry takes them', () async {
      make();
      final read = await WebKitStores.read(websiteData);
      final byId = {for (final each in read.team) each['id'] as String: each};
      expect(byId.keys.toSet(), documents.keys.toSet());
      for (final entry in documents.entries) {
        final got = byId[entry.key]!;
        expect(fromBase64Url(got['state'] as String), entry.value.state);
        expect(got['seq'], entry.value.seq);
        expect(got['snapshotSeq'], entry.value.snapshotSeq);
        expect([for (final each in got['pending'] as List) fromBase64Url(each as String)], entry.value.pending);
      }
    });

    test('a record that will not parse is counted and left, and the rest is read', () async {
      makeWebKit(websiteData, local: local, databases: [
        (
          name: 'glyph-team',
          store: 'docs',
          records: {
            ...teamDatabase({'good': (state: [1, 2, 3], seq: 1, snapshotSeq: 1, pending: <List<int>>[])}).records,
            'a date': Ssv.whole([11, 0, 0, 0, 0, 0, 0, 0, 0]),
            'cut short': Uint8List.fromList(Ssv.whole(Ssv.object({'state': Ssv.bytes([1, 2, 3])})).sublist(0, 20)),
            'not a document': Ssv.whole(Ssv.object({'state': Ssv.number(4)})),
          },
        ),
      ]);
      final read = await WebKitStores.read(websiteData);
      expect(read.team.map((each) => each['id']), ['good']);
      expect(read.damaged, 3);
      expect(read.local, local);
    });

    test('only the Tauri app\'s origin is read', () async {
      makeWebKit(websiteData, scheme: 'https', host: 'example.com', local: {'glyph-preferences': 'another page\'s'});
      expect((await WebKitStores.read(websiteData)).found, isFalse);
      make();
      expect((await WebKitStores.read(websiteData)).local, local);
    });

    test('nothing WebKit kept is written, moved or added to by reading it', () async {
      make();
      final before = treeState(temp);
      final read = await WebKitStores.read(websiteData);
      read.keys(master);
      expect(read.local, isNotEmpty);
      expect(treeState(temp), before);
    });

    test('a store made by identifier keeps its origins under Origins, and is read the same', () async {
      final folder = make();
      Directory('${websiteData.path}/Default').renameSync('${websiteData.path}/Origins');
      expect(folder.existsSync(), isFalse);
      expect((await WebKitStores.read(websiteData)).local, local);
    });
  });

  test('a Mac the Tauri app\'s web view never kept anything on', () async {
    final read = await WebKitStores.read(websiteData);
    expect(read.found, isFalse);
    expect(read.local, isEmpty);
    expect(read.keys(master).found, isFalse);
    expect((await WebKitStores.read(Directory('${temp.path}/nowhere'))).found, isFalse);
  });

  group('a real WebKit\'s storage (tool/webkit_fixture.swift)', skip: realSkip, () {
    late Map<String, Object?> expected;
    late Uint8List realMaster;
    late WebKitRead read;
    GhostCore? core;

    setUpAll(() async {
      expected = (jsonDecode(File('$realFixture/expected.json').readAsStringSync()) as Map).cast<String, Object?>();
      realMaster = base64.decode(expected['masterKey'] as String);
      final before = treeState(Directory(realFixture));
      read = await WebKitStores.read(Directory(realFixture));
      expect(treeState(Directory(realFixture)), before, reason: 'the fixture itself is only read');
      if (coreBuilt) core = await openCore();
    });
    tearDownAll(() async => core?.close());

    test('the page was at the Tauri app\'s origin and WebKit asked for the master key it was given', () {
      expect(expected['origin'], 'tauri://localhost');
      expect(expected['masterKeyAsked'], isTrue);
      expect(read.found, isTrue);
      expect(read.damaged, 0);
    });

    test('localStorage is what the page itself read back', () {
      expect(read.local, (expected['local'] as Map).cast<String, String>());
      expect(read.local['glyph-long']!.length, 70000);
    });

    test('the account key and the pair are the bytes the page made them from', () {
      final keys = read.keys(realMaster);
      final said = expected['keys'] as Map;
      expect(toBase64Url(keys.account!.secret), (said['account'] as Map)['raw']);
      expect(keys.account!.extractable, isFalse);
      expect(toBase64Url(keys.encryption!.secret), (said['encryption'] as Map)['d']);
      expect(toBase64Url(keys.encryption!.public!), (said['encryption'] as Map)['public']);
      expect(keys.encryption!.extractable, isFalse);
    });

    test('the device\'s Ed25519 key: a known seed read back, and the page\'s own with the public key it exported', () {
      final said = expected['keys'] as Map;
      expect(said['deviceFailure'], isNull, reason: 'this WebKit has Ed25519');
      final known = read.keys(realMaster, deviceRecord: 'device-known').device!;
      expect(toBase64Url(known.secret), (said['deviceKnown'] as Map)['d']);
      expect(toBase64Url(known.public!), (said['deviceKnown'] as Map)['public']);
      final device = read.keys(realMaster).device!;
      expect(device.secret.length, 32);
      expect(toBase64Url(device.public!), (said['device'] as Map)['public']);
      expect(device.extractable, isFalse);
    });

    test('each private key, raised in the core, answers the public key WebKit kept beside it', skip: coreSkip, () async {
      final keys = read.keys(realMaster);
      for (final (kind, key) in [('device', keys.device!), ('pair', keys.encryption!)]) {
        final raised = (await core!.invoke('key_restore', {'kind': kind, 'raw': toBase64Url(key.secret)})) as Map;
        expect(raised['public'], toBase64Url(key.public!));
        await core!.invoke('key_forget', {'key': raised['key']});
      }
    });

    test('another master key opens nothing', () {
      final keys = read.keys(randomBytes(16));
      expect(keys.found, isTrue);
      expect([keys.account, keys.device, keys.encryption], everyElement(isNull));
    });

    test('the team documents are the bytes the page put', () {
      final want = {for (final each in (expected['team'] as List).cast<Map>()) each['id'] as String: each};
      final got = {for (final each in read.team) each['id'] as String: each};
      expect(got.keys.toSet(), want.keys.toSet());
      for (final id in want.keys) {
        expect(got[id]!['state'], want[id]!['state']);
        expect(got[id]!['seq'], want[id]!['seq']);
        expect(got[id]!['snapshotSeq'], want[id]!['snapshotSeq']);
        expect(got[id]!['pending'], want[id]!['pending']);
      }
    });
  });
}
