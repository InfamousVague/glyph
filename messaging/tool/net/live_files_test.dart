import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/files/files_api.dart';
import 'package:ghost_messaging/files/files_store.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/voice/voice.dart';

/// A Files space on the relay that is really there (relay/lib/files.dart, behind gogho.st/files):
///
///     flutter test tool/net/live_files_test.dart --dart-define=FILES=https://gogho.st/files
///
/// The check run after tool/deploy-relay.mjs and tool/deploy-site.mjs --caddy for Files spaces (Matt, 2026-11-17:
/// "Deploy and release it all"). Two members made up here: one makes a new space and adds a file, sealed; the other
/// lists it, brings it down and finds it whole; the uploader deletes it. It leaves an empty space of its own behind,
/// which the relay removes when it has been idle long enough.
const files = String.fromEnvironment('FILES');

class _Hub {
  final List<_Route> routes = [];
}

class _Route implements VoiceRoute {
  _Route(this.hub, this.me) {
    hub.routes.add(this);
  }
  final _Hub hub;
  @override
  final String me;
  final _packets = StreamController<({String room, String from, Uint8List bytes})>.broadcast();
  @override
  Future<List<String>> join(String room, String token) async => const [];
  @override
  void leave(String room) {}
  @override
  void send(String room, Uint8List bytes) {
    for (final r in hub.routes) {
      if (r != this) r._packets.add((room: room, from: me, bytes: bytes));
    }
  }

  @override
  void look(String room, String token) {}
  @override
  void unlook(String room) {}
  @override
  Stream<RoomEvent> get events => const Stream.empty();
  @override
  Stream<({String room, String from, Uint8List bytes})> get packets => _packets.stream;
  @override
  Stream<({String room, List<String> members})> get looks => const Stream.empty();
}

Future<void> _until(bool Function() ok, String what) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('waited too long: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  test('a Files space on $files: added sealed, listed and brought down whole by another, deleted', () async {
    expect(files, isNotEmpty, reason: 'say where: --dart-define=FILES=https://…/files');
    final dir = await Directory.systemTemp.createTemp('ghost-live-files');
    final hub = _Hub();
    final maya = KeysSigner(NetKeys.generate()), sam = KeysSigner(NetKeys.generate());
    final space = VoiceChannel(seed: NetCrypto.hex(NetCrypto.randomBytes(32)), name: 'Live check', kind: SpaceKind.files, owner: NetCrypto.hex(maya.publicKey));
    final base = Uri.parse(files);
    final a = FilesStore.forTest(base: base, signer: maya, data: Directory('${dir.path}/Maya'), route: _Route(hub, maya.id), name: 'Maya');
    final b = FilesStore.forTest(base: base, signer: sam, data: Directory('${dir.path}/Sam'), route: _Route(hub, sam.id), name: 'Sam');
    try {
      await a.open(space);
      await b.open(space);
      final r = Random(17);
      final data = Uint8List.fromList(List.generate(700 * 1000, (_) => r.nextInt(256)));
      final input = File('${dir.path}/in/live check.bin')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(data);
      a.upload(space, [input.path]);
      await _until(() => a.of(space).files.isNotEmpty, 'the upload (${a.transfers.firstOrNull?.error})');
      await _until(() => b.of(space).files.isNotEmpty, 'the other member to see it');
      final f = b.of(space).files.values.single;
      expect(f.size, data.length);
      final path = await b.fetch(space, f);
      expect(await File(path).readAsBytes(), data, reason: 'it came down whole');
      expect(await a.delete(space, a.of(space).files.values.single), isTrue);
      await b.of(space).refresh();
      await _until(() => b.of(space).files.isEmpty, 'the delete to reach the other member');
    } finally {
      await a.clear();
      await b.clear();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
