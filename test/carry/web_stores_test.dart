// What a Chromium web view leaves on disk, read without one (lib/carry/leveldb.dart, web_stores.dart).
//
// The fixtures are real: `phone_*` is the Tauri app's own storage, version 1.15.0 on an Android emulator (WebView
// 133), after a made-up sign-in was put into its page the way src/app/core/account/keystore.ts keeps one, with
// what the page itself answered for `localStorage` beside it (`phone_local_truth.json`); `chrome_*` is a desktop
// Chrome 154's, for the two things that web view could not show: Ed25519, and records that have been compacted
// out of the log into a Snappy-packed table. Every key in them was made for the fixture and opens nothing.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/carry/leveldb.dart';
import 'package:ghost_md/carry/web_stores.dart';

String b64(Uint8List? bytes) => bytes == null ? 'none' : base64Url.encode(bytes).replaceAll('=', '');

void main() {
  final fixtures = Directory('test/carry/fixtures');

  test('the phone\'s localStorage reads as the page itself answered it', () async {
    final db = await LevelDb.read(Directory('${fixtures.path}/phone_local'));
    expect(db.damaged, 0);
    final truth = (jsonDecode(File('${fixtures.path}/phone_local_truth.json').readAsStringSync()) as Map).cast<String, String>();
    expect(truth.length, 19);
    expect(localStorageOf(db), truth);
    expect(localStorageOf(db, origin: 'http://elsewhere.localhost'), isEmpty);
  });

  test('both of Chromium\'s forms of a string are read', () async {
    final db = await LevelDb.read(Directory('${fixtures.path}/chrome_local'));
    expect(localStorageOf(db, origin: 'http://tauri.localhost:18473'), {'glyph-plain': 'one byte a character', 'glyph-wide': 'two bytes: — \u{1F47B} café'});
  });

  test('the phone\'s keys are the ones that stand, not the account\'s before', () async {
    final db = await LevelDb.read(Directory('${fixtures.path}/phone_idb'));
    expect(db.damaged, 0);
    final keys = DiskKeys.of(db);
    expect(keys.found, isTrue);
    expect(b64(keys.account?.secret), 'SP2m_BK5LNfUsc1VaHwDmn2PK8ePhEQSx4WCLgp1YSI');
    expect(keys.account?.extractable, isFalse);
    expect(b64(keys.encryption?.secret), 'nM4ABBzGyktNpOrduGaEzc6FECJkceNaSFrtzhVJ5TU');
    expect(b64(keys.encryption?.public), 'BE0Ma7LPWtGS7C8yZOljz8ErvwNrBR2ED3k9LZBqQx-QnMtn56Yw9Grn3OWmk531P_uDuK7rGY5tQBWuDt3rvI8');
    expect(keys.encryption?.extractable, isFalse);
    // That web view has no Ed25519, so the page kept no device key.
    expect(keys.device, isNull);
  });

  test('keys compacted into a packed table, and an Ed25519 pair', () async {
    final db = await LevelDb.read(Directory('${fixtures.path}/chrome_idb'));
    expect(db.damaged, 0);
    expect(db.files, 1);
    final keys = DiskKeys.of(db);
    expect(b64(keys.account?.secret), 'KT5Ybr-WVWEyVYV-XkgGX4wkDq46Aj2oSEnVDaDHQME');
    expect(b64(keys.device?.secret), 'RDC8t6hkWWuvg65ENyS9Pjpj-5EklMHcg0Sspcuj5FY');
    expect(b64(keys.device?.public), 'zppcpNyRbyJ6fQsOeCZniPkzncsIupONCj47VHacjIs');
    expect(b64(keys.encryption?.secret), 'kWf6mYLLcCDpnKYOf9l-IJyaPW3GFu6jGSIl-CoRHGM');
    expect(b64(keys.encryption?.public), 'BKO9UMI6W1H0zX-KAjH9CVtQcaA1LIO2SRwMzjuZ3_GsJ9h4PTXbttsD4_5UNlGkpWjG2RULFzZORoQRU2EadCY');
  });

  test('a folder that is not there, and one of rubbish, hold nothing and throw nothing', () async {
    final none = await LevelDb.read(Directory('${fixtures.path}/no_such_folder'));
    expect(none.entries, isEmpty);
    expect(DiskKeys.of(none).found, isFalse);
    final dir = await Directory.systemTemp.createTemp('carry');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/000001.log').writeAsBytesSync(List.filled(500, 0xab));
    File('${dir.path}/000002.ldb').writeAsBytesSync(List.filled(500, 0xcd));
    final rubbish = await LevelDb.read(dir);
    expect(rubbish.entries, isEmpty);
    expect(rubbish.damaged, greaterThan(0));
  });

  test('Snappy: a literal and a copy that runs into itself', () {
    // 10 bytes: the literal "ab", then eight more copied from two back.
    expect(snappyUnpack(Uint8List.fromList([10, 0x04, 0x61, 0x62, 0x11, 0x02])), 'ababababab'.codeUnits);
    expect(snappyUnpack(Uint8List.fromList([10, 0x04, 0x61, 0x62])), isNull);
  });
}
