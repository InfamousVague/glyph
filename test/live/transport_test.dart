// The relay's transport (lib/live/transport.dart) over a socket the test plays the relay through: the cases of
// the web's own core/live/transport.test.ts, and what a phone adds (rest and wake in place of the page's window).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/live/transport.dart';

/// A socket that records what a device sends and lets the test play the relay.
class FakeSocket extends LiveSocket {
  FakeSocket(this.url) {
    made.add(this);
  }

  static List<FakeSocket> made = [];
  final String url;
  final List<Object?> sent = [];
  bool closed = false;

  @override
  void send(String text) => sent.add(jsonDecode(text));

  @override
  void close() => closed = true;

  // The relay's side.
  void opens() => onOpen?.call();
  void says(Map<String, Object?> frame) => onMessage?.call(jsonEncode(frame));
  void drops([int code = 1006]) => onClose?.call(code);
}

({List<String> heard, LiveEvents events}) recorder() {
  final heard = <String>[];
  return (
    heard: heard,
    events: LiveEvents(
      ready: (id) => heard.add('ready $id'),
      joined: (room, first, peers, org) => heard.add('joined $room first=$first peers=$peers${org != null ? ' org=$org' : ''}'),
      peers: (room, peers, org, left) => heard.add('peers $room $peers${org != null ? ' org=$org' : ''}${left == null ? '' : ' left=$left'}'),
      message: (room, from, data, org) => heard.add('msg $room from=$from $data${org != null ? ' org=$org' : ''}'),
      down: (why) => heard.add('down $why'),
    ),
  );
}

void main() {
  final transports = <WebSocketTransport>[];
  tearDown(() {
    for (final made in transports) {
      made.close();
    }
    transports.clear();
  });

  ({WebSocketTransport t, List<({void Function() run, int ms})> waits, FakeSocket Function() socket}) transport(LiveEvents events, {String? Function()? token, double random = 1}) {
    FakeSocket.made = [];
    final waits = <({void Function() run, int ms})>[];
    final t = WebSocketTransport(
      url: 'wss://example/live',
      token: token ?? () => 'tok',
      events: events,
      socket: FakeSocket.new,
      schedule: (run, ms) {
        waits.add((run: run, ms: ms));
        return null;
      },
      random: () => random,
    );
    transports.add(t);
    return (t: t, waits: waits, socket: () => FakeSocket.made.last);
  }

  group('the relay transport', () {
    test('finds the relay beside the service', () {
      expect(liveUrl('https://attack.fm/api'), 'wss://attack.fm/api/v1/live');
      expect(liveUrl('http://127.0.0.1:8796/api'), 'ws://127.0.0.1:8796/api/v1/live');
    });

    test('signs in with its first frame, and says nothing else until the relay is ready', () {
      final (:heard, :events) = recorder();
      final (:t, waits: _, :socket) = transport(events);
      t.join('note');
      socket().opens();
      // The join asked for before the relay was ready is not sent early: only the sign-in is.
      expect(socket().sent, [
        {'t': 'auth', 'token': 'tok'},
      ]);
      socket().says({'t': 'ready', 'id': 7});
      expect(socket().sent[1], {'t': 'join', 'room': 'note'});
      socket().says({'t': 'joined', 'room': 'note', 'first': true, 'peers': 0});
      socket().says({'t': 'msg', 'room': 'note', 'from': 9, 'data': 'abc'});
      expect(heard, ['ready 7', 'joined note first=true peers=0', 'msg note from=9 abc']);
    });

    test('comes back after a drop and rejoins every room it was in', () {
      final (:heard, :events) = recorder();
      final (:t, :waits, :socket) = transport(events);
      t.join('a');
      t.join('b');
      socket().opens();
      socket().says({'t': 'ready', 'id': 1});
      socket().drops();
      expect(heard, contains('down network'));
      expect(waits, hasLength(1));
      waits[0].run();
      final again = socket();
      again.opens();
      again.says({'t': 'ready', 'id': 2});
      expect(again.sent, [
        {'t': 'auth', 'token': 'tok'},
        {'t': 'join', 'room': 'a'},
        {'t': 'join', 'room': 'b'},
      ]);
    });

    test('does not keep knocking once the relay has refused the token', () {
      final (:heard, :events) = recorder();
      final (t: _, :waits, :socket) = transport(events);
      socket().opens();
      socket().drops(4401);
      expect(heard, ['down signIn']);
      expect(waits, isEmpty);
    });

    test('does not connect at all while signed out', () {
      final (:heard, :events) = recorder();
      transport(events, token: () => null);
      expect(FakeSocket.made, isEmpty);
      expect(heard, ['down signIn']);
    });

    test('sends only into rooms it is in, and nothing while down', () {
      final (heard: _, :events) = recorder();
      final (:t, waits: _, :socket) = transport(events);
      socket().opens();
      socket().says({'t': 'ready', 'id': 1});
      t.send('not-joined', 'x');
      t.join('n');
      t.send('n', 'y', to: 4);
      t.leave('n');
      t.send('n', 'z');
      expect(socket().sent.sublist(1), [
        {'t': 'join', 'room': 'n'},
        {'t': 'msg', 'room': 'n', 'data': 'y', 'to': 4},
        {'t': 'leave', 'room': 'n'},
      ]);
    });
  });

  group('an organization\'s rooms', () {
    test('joins, leaves and sends with the organization named, hears its events apart from the account\'s own, and rejoins them after a drop', () {
      final (:heard, :events) = recorder();
      final (:t, :waits, :socket) = transport(events);
      socket().opens();
      socket().says({'t': 'ready', 'id': 1});
      t.join('n', 'org-1');
      t.join('n');
      t.send('n', 'x', org: 'org-1');
      t.send('n', 'y', to: 4);
      socket().says({'t': 'joined', 'room': 'n', 'org': 'org-1', 'first': false, 'peers': 2});
      socket().says({'t': 'peers', 'room': 'n', 'org': 'org-1', 'peers': 1, 'left': 7});
      socket().says({'t': 'msg', 'room': 'n', 'org': 'org-1', 'from': 7, 'data': 'z'});
      socket().says({'t': 'joined', 'room': 'n', 'first': true, 'peers': 0});
      expect(socket().sent.sublist(1), [
        {'t': 'join', 'room': 'n', 'org': 'org-1'},
        {'t': 'join', 'room': 'n'},
        {'t': 'msg', 'room': 'n', 'org': 'org-1', 'data': 'x'},
        {'t': 'msg', 'room': 'n', 'data': 'y', 'to': 4},
      ]);
      expect(heard, ['ready 1', 'joined n first=false peers=2 org=org-1', 'peers n 1 org=org-1 left=7', 'msg n from=7 z org=org-1', 'joined n first=true peers=0']);
      t.leave('n', 'org-1');
      expect(socket().sent.last, {'t': 'leave', 'room': 'n', 'org': 'org-1'});
      // Dropped and back: the account's room is rejoined, and the organization's room, left, is not.
      t.join('p', 'org-1');
      socket().drops();
      waits.removeAt(0).run();
      socket().opens();
      socket().says({'t': 'ready', 'id': 2});
      expect(socket().sent.sublist(1), [
        {'t': 'join', 'room': 'n'},
        {'t': 'join', 'room': 'p', 'org': 'org-1'},
      ]);
    });
  });

  group('coming back after a drop', () {
    test('waits twice as long each time from half a second, never past thirty, and from the start again once signed in', () {
      final (heard: _, :events) = recorder();
      final (t: _, :waits, :socket) = transport(events);
      for (var i = 0; i < 8; i += 1) {
        socket().drops();
        waits.last.run();
      }
      expect([for (final wait in waits) wait.ms], [500, 1000, 2000, 4000, 8000, 16000, 30000, 30000]);
      socket().opens();
      socket().says({'t': 'ready', 'id': 3});
      socket().drops();
      expect(waits.last.ms, 500);
    });

    test('spreads each wait over its second half, so a relay restart is not met by every device at once', () {
      final (heard: _, :events) = recorder();
      final (t: _, :waits, :socket) = transport(events, random: 0);
      socket().drops();
      waits.last.run();
      socket().drops();
      expect([for (final wait in waits) wait.ms], [250, 500]);
    });

    test('tries at once when the app comes back, and not while it rests', () {
      final (:heard, :events) = recorder();
      final (:t, :waits, :socket) = transport(events);
      socket().drops();
      expect(FakeSocket.made, hasLength(1));
      // Behind another app: nothing knocks, whatever was waiting.
      t.rest();
      waits.last.run();
      expect(FakeSocket.made, hasLength(1));
      t.wake();
      expect(FakeSocket.made, hasLength(2));
      // Connected again: another wake while connected does nothing.
      t.wake();
      expect(FakeSocket.made, hasLength(2));
      expect(waits, hasLength(1));
      // Resting lets the socket go and says so, once; the rooms are joined again on waking.
      t.join('n');
      socket().opens();
      socket().says({'t': 'ready', 'id': 5});
      heard.clear();
      t.rest();
      expect(socket().closed, isTrue);
      expect(heard, ['down network']);
      t.wake();
      expect(FakeSocket.made, hasLength(3));
      socket().opens();
      socket().says({'t': 'ready', 'id': 6});
      expect(socket().sent.last, {'t': 'join', 'room': 'n'});
    });

    test('stays down once closed, whatever wakes it', () {
      final (heard: _, :events) = recorder();
      final (:t, waits: _, :socket) = transport(events);
      socket().opens();
      t.close();
      socket().drops();
      t.wake();
      expect(FakeSocket.made, hasLength(1));
    });

    test('ignores a frame it cannot read and a refusal, and keeps the socket', () {
      final (:heard, :events) = recorder();
      final (t: _, waits: _, :socket) = transport(events);
      socket().opens();
      socket().onMessage?.call('{not json');
      socket().says({'t': 'error', 'message': 'too fast'});
      socket().says({'t': 'ready', 'id': 4});
      expect(heard, ['ready 4']);
    });
  });
}
