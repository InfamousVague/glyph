// The real-crypto proof, OFFLINE: every scenario of scenarios.dart against the service in memory, with `CoreCrypto`
// (the Rust core's PBKDF2, AES-256-GCM, Ed25519, P-256 and HKDF, through the Mac's library) where every other test
// of the stage uses the fake, and the service checking a device's signature with the core's own Ed25519 verify.
// The CRDT is the real one too. Nothing here opens a socket.
//
// What this proves is that the flows hold under real cryptography: every key made, wrapped, kept, restored and
// used by its handle; every blob sealed on one device opened on another. What it does not prove is that the
// SERVICE is the real one's shape (local_server_test.dart does), nor that the bytes are the web's
// (native/tests/crypto_vectors.rs and tool/web_client.mjs do).
//
// Skipped, out loud, where the Mac's core is not built: tool/build-native.sh host.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

import '../team_sync/support.dart' show coreBuilt, coreLibrary, coreSkip;
import 'scenarios.dart';
import 'world.dart';

void main() {
  late GhostCore core;
  late FakeWorld world;

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);
    world = FakeWorld(core);
  });

  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  group('with the real crypto, against the service in memory:', () {
    scenarios(() => world, () => core, manyAccounts: false, skip: coreSkip);
  });
}
