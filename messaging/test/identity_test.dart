import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/me/identity.dart';
import 'package:ghost_messaging/net/crypto.dart';

/// An account's did:key and the statements it signs (GMFB-33; lib/me/identity.dart, docs/proofs.md).
void main() {
  test('a did:key is the W3C method\'s for a P-256 key, and reads back to the key', () {
    // The did:key method's own P-256 example: x and y of the key, and the DID it writes.
    final x = base64Url.decode('fyNYMN0976ci7xqiSdag3buk-ZCwgXU4kz9XNkBlNUI=');
    final y = base64Url.decode('hW2ojTNfH7Jbi8--CJUo3OCbH3y5n91g-IMA9MLMbTU=');
    final key = [(y.last & 1) == 1 ? 3 : 2, ...x];
    expect(Did.ofKey(key), 'did:key:zDnaerDaTF5BXEavCrfRZEk316dpbLsfPDZ3WJ5hRTPFU2169');
    expect(Did.keyOf('did:key:zDnaerDaTF5BXEavCrfRZEk316dpbLsfPDZ3WJ5hRTPFU2169'), key);

    final mine = NetKeys.generate();
    final did = Did.ofKey(mine.public);
    expect(did, startsWith('did:key:zDn'));
    expect(Did.keyOf(did), mine.public);
    // Not a P-256 did:key: an Ed25519 one (multicodec 0xed), a letter base58 hasn't got, another method, cut short.
    expect(Did.keyOf('did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK'), isNull);
    expect(Did.keyOf('did:key:zDnaerDaTF5BXEavCrfRZEk316dpbLsfPDZ3WJ5hRTPFU216O'), isNull);
    expect(Did.keyOf('did:pkh:eip155:1:0xb9c5714089478a327f09197987f16f9e5d936e8a'), isNull);
    expect(Did.keyOf(did.substring(0, did.length - 3)), isNull);
    expect(() => Did.ofKey(List.filled(65, 4)), throwsArgumentError);
    // Leading zero bytes are base58's 1s.
    expect(Base58.encode([0, 0, 1]), '112');
    expect(Base58.decode('112'), [0, 0, 1]);
  });

  test('a statement is signed, and checks out as that account\'s; a changed word, time or account does not', () async {
    final mine = NetKeys.generate();
    final block = await Proof.make('  I am @matt on Ghost Messaging  \r\n', publicKey: mine.public, sign: (m) async => NetCrypto.sign(mine, m), now: DateTime.utc(2026, 11, 23, 10, 15, 7, 900));
    expect(block.split('\n').take(3), [Proof.begin, 'Account: ${Did.ofKey(mine.public)}', 'Signed: 2026-11-23T10:15:07Z']);
    expect(block.split('\n').skip(4), ['', 'I am @matt on Ghost Messaging', Proof.end]);
    final good = Proof.check('Here is my proof:\n\n$block\n\nthanks');
    expect(good.good, isTrue, reason: good.problem);
    expect([good.statement, good.did, good.signed], ['I am @matt on Ghost Messaging', Did.ofKey(mine.public), DateTime.utc(2026, 11, 23, 10, 15, 7)]);
    // As a site may show it: other line ends, lines indented.
    expect(Proof.check(block.replaceAll('\n', '\r\n    ')).good, isTrue);

    expect(Proof.check(block.replaceFirst('@matt', '@mallory')).good, isFalse, reason: 'a changed word');
    expect(Proof.check(block.replaceFirst('10:15:07', '10:15:08')).good, isFalse, reason: 'a changed time');
    final other = Did.ofKey(NetKeys.generate().public);
    final moved = Proof.check(block.replaceFirst(Did.ofKey(mine.public), other));
    expect([moved.good, moved.problem], [false, contains('signature doesn\'t match')], reason: 'another account named');
    expect(Proof.check('I am @matt').problem, contains('No proof found'));
    expect(Proof.check(block.replaceFirst(RegExp(r'Signature: .*'), 'Signature: abc')).problem, contains('missing or was changed'));

    expect(Proof.refuse(''), isNotNull);
    expect(Proof.refuse('x' * 281), contains('281'));
    expect(Proof.refuse('😀' * 280), isNull, reason: 'counted in characters, not in UTF-16 units');
    expect(Proof.refuse('a\n${Proof.end}'), isNotNull);
  });

  test('tool/check-proof.mjs checks a proof with nothing but Node, as docs/proofs.md says anyone can', () async {
    final mine = NetKeys.generate();
    final block = await Proof.make('I am @matt on Ghost Messaging.\nAnd this is a second line ✓', publicKey: mine.public, sign: (m) async => NetCrypto.sign(mine, m));
    final dir = Directory.systemTemp.createTempSync('proof');
    addTearDown(() => dir.deleteSync(recursive: true));
    final good = File('${dir.path}/good.txt')..writeAsStringSync('pasted from somewhere:\n$block\n');
    final bad = File('${dir.path}/bad.txt')..writeAsStringSync(block.replaceFirst('second', 'third'));
    final ok = await Process.run('node', ['tool/check-proof.mjs', good.path]);
    expect(ok.exitCode, 0, reason: '${ok.stdout}${ok.stderr}');
    expect('${ok.stdout}', contains('Checks out'));
    final no = await Process.run('node', ['tool/check-proof.mjs', bad.path]);
    expect(no.exitCode, 1, reason: '${no.stdout}${no.stderr}');
    expect('${no.stdout}', contains('Does not check out'));
  });
}
