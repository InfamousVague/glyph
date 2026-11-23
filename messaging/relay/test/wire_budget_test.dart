import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/relay.dart';
import 'package:ghost_relay/ws_door.dart';
import 'package:test/test.dart';

import 'ws_door_test.dart' show frame;

/// What every connection together may hold in memory (lib/ws_door.dart, WireBudget; asked for in the second look at
/// the relay's doors, 2026-11-23, as v2 is to be switched on for gogho.st). One door's ceiling bounds one connection,
/// but many connections each holding their share would add up past the 300 MB the relay has: the part of a message
/// that has come in and isn't finished, and what waits to go out to a peer that doesn't read, the answers to its pings
/// included (Dart answers each ping by itself). Here the doors are real ones on this machine, spoken to over plain
/// sockets.

Future<void> until(bool Function() ok, String what) async {
  for (var i = 0; i < 1000 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ok(), isTrue, reason: what);
}

/// A connection to [port]'s door at [path], upgraded by hand. Where [reads] is false, nothing is read after the
/// answer to the upgrade: everything the door sends it waits, first in the machine's own buffers, then at the door.
class Client {
  Client._(this.socket);
  final Socket socket;
  final closed = Completer<void>();

  static Future<Client> open(int port, String path, {bool reads = true}) async {
    final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final c = Client._(s);
    final got = BytesBuilder();
    final head = Completer<void>();
    late final StreamSubscription<Uint8List> sub;
    sub = s.listen(
      (d) {
        if (head.isCompleted) return;
        got.add(d);
        if (latin1.decode(got.toBytes()).contains('\r\n\r\n')) {
          head.complete();
          if (!reads) sub.pause();
        }
      },
      onDone: () {
        if (!c.closed.isCompleted) c.closed.complete();
      },
      onError: (_) {
        if (!c.closed.isCompleted) c.closed.complete();
      },
    );
    unawaited(s.done.then((_) {}, onError: (_) {}));
    s.write('GET $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n');
    await s.flush();
    await head.future.timeout(const Duration(seconds: 10));
    return c;
  }

  /// Sends [batch] up to [times] times; how many went before writing failed (the door had ended the connection).
  Future<int> sendUntilRefused(List<int> batch, int times) async {
    for (var i = 0; i < times; i++) {
      try {
        socket.add(batch);
        await socket.flush();
      } catch (_) {
        return i;
      }
    }
    return times;
  }
}

void main() {
  test('a peer that pings and never reads what comes back is ended once the answers waiting for it pass what one may hold', () async {
    final wire = WireBudget(eachOut: 512 << 10);
    final relay = Relay(hub: Hub(wire: wire));
    final port = await relay.start(port: 0);
    addTearDown(relay.stop);
    final deaf = await Client.open(port, '/hub', reads: false);
    // Pings of 125 bytes, a thousand at a time: up to 21 MB of them, and as many answers, which it never reads. The
    // machine's own buffers take a few hundred kilobytes of the answers; past them they wait at the door.
    final ping = frame(9, List.filled(125, 7));
    final batch = [for (var i = 0; i < 1000; i++) ...ping];
    final went = await deaf.sendUntilRefused(batch, 160);
    expect(went, lessThan(160), reason: 'the door ended it, its answers waiting past half a megabyte');
    expect(wire.ended, 1);
    await until(() => wire.used == 0, 'what it held is let go');
    // An app is as welcome as ever: said hello to, and kept.
    final app = await WebSocket.connect('ws://127.0.0.1:$port/hub');
    final said = StreamIterator(app);
    expect(await said.moveNext(), isTrue);
    expect((jsonDecode(said.current as String) as Map)['hello'], isA<String>());
    expect(wire.ended, 1);
    await app.close();
  });

  test('many connections each half way through a long message: past what all may hold together, the one holding the most is ended', () async {
    final wire = WireBudget(most: 1 << 20);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    // A door that takes messages of a megabyte, from the first.
    server.listen((request) async {
      final ws = await upgradeGuarded(request, most: 1 << 20, first: 1 << 20, budget: wire);
      ws?.listen((_) {}, onError: (_) {});
    });
    final clients = <Client>[];
    for (var i = 0; i < 3; i++) {
      final c = await Client.open(server.port, '/');
      clients.add(c);
      // A message that says it is a million bytes long, and 400,000 of them: the door holds them until the rest comes.
      c.socket.add(frame(2, List.filled(400000, 1), say: 1000000));
      await c.socket.flush();
      await until(() => wire.used >= (i + 1) * 400000 || wire.ended > 0, 'the door never had what client $i sent');
    }
    expect(wire.ended, 1, reason: 'three of 400,000 bytes are more than a megabyte together: one is ended, and two fit');
    expect(wire.used, lessThanOrEqualTo(wire.most));
    await until(() => clients.where((c) => c.closed.isCompleted).length == 1, 'the one ended was never closed');
    expect(clients.last.closed.isCompleted, isFalse, reason: 'it was one of the two holding the most when the third came');
    for (final c in clients) {
      c.socket.destroy();
    }
    await until(() => wire.used == 0, 'what they held is let go as they go');
  });

  test('the budget by itself: past one connection\'s share of what waits it is ended; past everyone\'s, the one holding the most', () {
    final wire = WireBudget(most: 1000, eachOut: 600);
    final ended = <String>[];
    WireHold hold(String name) => wire.open(() => ended.add(name));
    final a = hold('a'), b = hold('b'), c = hold('c');
    expect(a.queued(500), isTrue);
    expect(a.queued(200), isFalse, reason: '700 waiting to go out to one, past its 600');
    expect([ended, wire.used], [['a'], 0]);
    expect(b.incoming(700), isTrue);
    expect(c.incoming(400), isTrue, reason: '1,100 together: the one holding the most goes, which is b, not c');
    expect([ended, wire.used], [['a', 'b'], 400]);
    expect(c.incoming(1001), isFalse, reason: 'more than everyone\'s alone: it goes itself');
    expect([ended, wire.used, wire.holders], [['a', 'b', 'c'], 0, 0]);
    final d = hold('d');
    expect([d.queued(100), d.held, wire.used], [true, 100, 100]);
    d.sent(100);
    expect([d.held, wire.used, wire.holders], [0, 0, 0]);
    d.close();
    expect(wire.ended, 3);
  });
}
