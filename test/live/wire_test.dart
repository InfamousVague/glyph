// What live sync says inside a sealed message (lib/live/wire.dart), sealed by the Rust core's real crypto: the
// cases of the web's core/live/wire.test.ts.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/live/wire.dart';

import 'support.dart';

void main() {
  late GhostCore core;
  late CoreCrypto crypto;

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await openCore();
    crypto = CoreCrypto(core.invoke);
  });
  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  /// An account key as a device holds one: made, then settled.
  Future<CoreKey> accountKey() async => await crypto.settle(await crypto.newAccountKey()) as CoreKey;

  group('a live message', () {
    test('comes back as it went, through the seal', () async {
      final key = await accountKey();
      final payload = Uint8List.fromList([1, 2, 3, 250]);
      final data = await sealEnvelope(crypto, key, 'note-a', Envelope(Kind.update, payload));
      // What the relay carries: base64url and nothing it could read.
      expect(data, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      final back = await openEnvelope(crypto, key, 'note-a', data);
      expect(back.kind, Kind.update);
      expect(back.bytes, payload);
    }, skip: coreSkip);

    test('will not open in another note, so it cannot be replayed into one', () async {
      final key = await accountKey();
      final data = await sealEnvelope(crypto, key, 'note-a', Envelope(Kind.update, Uint8List.fromList([7])));
      await expectLater(openEnvelope(crypto, key, 'note-b', data), throwsA(anything));
    }, skip: coreSkip);

    test('will not open under another account key', () async {
      final data = await sealEnvelope(crypto, await accountKey(), 'note-a', const Envelope(Kind.query));
      await expectLater(openEnvelope(crypto, await accountKey(), 'note-a', data), throwsA(anything));
    }, skip: coreSkip);

    test('sealed for a team\'s room, opens in that organization\'s room alone', () async {
      final key = await accountKey();
      final data = await sealTeamEnvelope(crypto, key, 'org-1', 'note-a', Envelope(Kind.presence, Uint8List.fromList([3])));
      expect((await openTeamEnvelope(crypto, key, 'org-1', 'note-a', data)).bytes, [3]);
      await expectLater(openTeamEnvelope(crypto, key, 'org-2', 'note-a', data), throwsA(anything));
      await expectLater(openTeamEnvelope(crypto, key, 'org-1', 'note-b', data), throwsA(anything));
      // Nor as an account's own message about that note.
      await expectLater(openEnvelope(crypto, key, 'note-a', data), throwsA(anything));
    }, skip: coreSkip);

    test('refuses a kind it does not know rather than guessing', () {
      expect(() => decodeEnvelope(Uint8List.fromList([99, 1])), throwsFormatException);
      expect(() => decodeEnvelope(Uint8List(0)), throwsFormatException);
      expect(decodeEnvelope(encodeEnvelope(Envelope(Kind.presence, Uint8List.fromList([5])))).kind, Kind.presence);
    });

    test('carries a document with its seed id in front', () {
      final seed = newSeed();
      final unpacked = unpackState(packState(seed, Uint8List.fromList([9, 8, 7])));
      expect(unpacked.seed, seed);
      expect(unpacked.state, [9, 8, 7]);
      expect(newSeed(), isNot(seed));
      expect(() => unpackState(Uint8List(3)), throwsFormatException);
    });
  });
}
