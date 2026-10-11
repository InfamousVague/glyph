// Every scenario of scenarios.dart against the REAL account and sync service (server), run on this Mac by
// tool/local-server.sh, with the real crypto and the real CRDT, over real sockets:
//
//   tool/local-server.sh test                      # builds it once, starts it, runs this, stops it
//   GHOST_E2E_API=http://127.0.0.1:<port>/api flutter test --no-pub test/e2e/local_server_test.dart
//
// Skipped unless GHOST_E2E_API is set, so the ordinary suite needs no server; and refused unless it names
// 127.0.0.1 (world.dart `LocalWorld`), so nothing here can reach ghostmarkdown.com whatever the variable says
// (docs/STAGE7.md, the first rule). Every run makes its own accounts, under handles nobody has; the server's data
// folder is thrown away when it stops.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

import '../team_sync/support.dart' show coreBuilt, coreLibrary, coreSkip;
import 'scenarios.dart';
import 'world.dart';

void main() {
  final base = Platform.environment['GHOST_E2E_API'] ?? '';
  final skip = base.isEmpty ? 'no local server: run tool/local-server.sh test (GHOST_E2E_API is not set)' : coreSkip;
  late GhostCore core;
  late LocalWorld world;

  setUpAll(() async {
    if (skip != null) return;
    // Refuses anything but 127.0.0.1 before a single request is made.
    world = LocalWorld(base);
    core = await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);
    final health = await world.api().fetcher(FetchRequest(method: 'GET', url: Uri.parse('$base/health')));
    expect(health.status, 200, reason: 'the local server at $base did not answer its health route');
  });

  tearDownAll(() async {
    if (skip == null && coreBuilt) await core.close();
  });

  group('with the real crypto, against the real service on 127.0.0.1:', () {
    scenarios(() => world, () => core, manyAccounts: true, skip: skip);
  });
}
