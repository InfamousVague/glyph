import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/p256.dart';
import 'package:test/test.dart';

/// The hub with no WebSocket and no server at all ([Hub.attach], [HubSocket]): what carries a connection is not the
/// hub's business, so one made in this very program, another relay's or a peer-to-peer stream is taken as a WebSocket
/// is. Here two installs are two connections held in memory; the WebSocket's way in ([Hub.accept]) is every other test's.

final _rnd = Random(11);
List<int> _bytes(int n) => [for (var i = 0; i < n; i++) _rnd.nextInt(256)];
List<int> _unhex(String s) => [for (var i = 0; i + 1 < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

/// A connection as the hub holds it, carried by nothing: what the hub says comes out of [said], what the other end
/// says ([say]) the hub hears a moment later, in order, and either end may close it.
class _MemorySocket implements HubSocket {
  final _incoming = StreamController<Object?>();
  final _said = StreamController<Object>();
  bool _open = true;

  /// What the hub closed it with, where it was the hub that did.
  int? code;
  String? reason;

  /// What the hub says to the other end: a String or a `List<int>`. Done once it has closed.
  Stream<Object> get said => _said.stream;

  /// The other end says [data] to the hub.
  void say(Object data) {
    if (_open) _incoming.add(data);
  }

  /// The other end goes, as a network going does: nothing said, no number.
  void drop() => _end();

  void _end() {
    if (!_open) return;
    _open = false;
    _incoming.close();
    _said.close();
  }

  @override
  Stream<Object?> get incoming => _incoming.stream;
  @override
  void add(Object data) {
    if (_open) _said.add(data);
  }

  @override
  bool get isOpen => _open;
  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_open) return;
    this.code = code;
    this.reason = reason;
    _end();
  }
}

/// An install: a key, and a connection to the hub signed with it.
class _Install {
  _Install() : scalar = _bytes(32) {
    key = P256.publicOf(scalar);
    id = Hub.nameOf(key);
  }
  final List<int> scalar;
  late final List<int> key;
  late final String id;

  /// Its newest connection.
  late _MemorySocket socket;

  /// What the hub said once signed in, and the packets it handed over.
  final said = <Map>[];
  final frames = <List<int>>[];

  /// Attaches a new connection to [hub] and signs in, as the other tests do over a WebSocket: the hub's number, signed
  /// with this install's key. What the hub answers the hello with.
  Future<Map> attach(Hub hub, {String? device}) async {
    final s = socket = _MemorySocket();
    final first = Completer<Map>(), hello = Completer<Map>();
    s.said.listen((d) {
      if (d is List<int>) {
        frames.add(d);
        return;
      }
      final m = jsonDecode(d as String) as Map;
      if (!first.isCompleted) {
        first.complete(m);
      } else if (!hello.isCompleted) {
        hello.complete(m);
      } else {
        said.add(m);
      }
    });
    hub.attach(s);
    final nonce = _unhex((await first.future)['hello'] as String);
    final sig = P256.sign(scalar, [...utf8.encode(Hub.greeting), ...nonce], _bytes(32));
    s.say(jsonEncode({'id': id, 'key': base64Encode(key), 'sig': base64Encode(sig), 'device': ?device}));
    return hello.future.timeout(const Duration(seconds: 5));
  }

  /// A packet to [to], as the app's hub route sends one: [1][seq][to][the packet].
  void sendTo(_Install to, List<int> packet, {required int seq}) {
    final n = ByteData(4)..setUint32(0, seq);
    socket.say(Uint8List.fromList([Hub.toPeer, ...n.buffer.asUint8List(), ..._unhex(to.id), ...packet]));
  }
}

void main() {
  test('two connections held in memory both sign in, and a packet from one reaches the other', () async {
    final hub = Hub();
    final a = _Install(), b = _Install();
    expect(await a.attach(hub), {'ok': true, 'held': 0});
    expect(await b.attach(hub), {'ok': true, 'held': 0});
    expect(hub.connected, 2);
    a.sendTo(b, [7, 7, 7], seq: 5);
    await pumpEventQueue();
    expect(b.frames.single, [Hub.toPeer, ..._unhex(a.id), 7, 7, 7], reason: 'handed over with who sent it, as the hub vouches');
    expect(a.said.single, {'ack': 5, 'here': true});
    expect(a.frames, isEmpty);
  });

  test('a packet for someone away is held, and handed over when their connection is attached', () async {
    final hub = Hub();
    final a = _Install(), b = _Install();
    await a.attach(hub);
    a.sendTo(b, [1, 2, 3], seq: 9);
    await pumpEventQueue();
    expect(a.said.single, {'ack': 9, 'here': false});
    expect(hub.heldFor(b.id), 1);
    expect(await b.attach(hub), {'ok': true, 'held': 1});
    await pumpEventQueue();
    expect(b.frames.single, [Hub.toPeer, ..._unhex(a.id), 1, 2, 3]);
    expect(hub.heldFor(b.id), 0);
    expect(hub.holding, 0);
  });

  test('a connection going tells whoever watches its name that they went', () async {
    final hub = Hub();
    final watcher = _Install(), b = _Install();
    await watcher.attach(hub);
    watcher.socket.say(jsonEncode({'watch': [b.id]}));
    await pumpEventQueue();
    expect(watcher.said.single['here'], isEmpty);
    await b.attach(hub);
    await pumpEventQueue();
    expect(watcher.said.last, {'came': b.id});
    expect(hub.connected, 2);
    b.socket.drop();
    await pumpEventQueue();
    expect(watcher.said.last['went'], b.id);
    expect(watcher.said.where((m) => m.containsKey('went')), hasLength(1));
    expect(hub.connected, 1);
    expect(hub.seenOf(b.id), isNotNull, reason: 'and when they were last here is kept');
  });

  test('what the hub closes, it closes with the numbers a WebSocket is given', () async {
    final hub = Hub();
    // A hello nobody signed: answered, then closed.
    final stranger = _MemorySocket();
    final heard = <Object>[];
    stranger.said.listen(heard.add);
    hub.attach(stranger);
    await pumpEventQueue();
    stranger.say(jsonEncode({'id': '00' * 16, 'key': base64Encode(_bytes(33)), 'sig': base64Encode(_bytes(64))}));
    await pumpEventQueue();
    expect(jsonDecode(heard.last as String), {'ok': false, 'err': 'bad hello'});
    expect([stranger.isOpen, stranger.code, stranger.reason], [false, 4400, 'bad hello']);
    // The same device again takes its own place.
    final a = _Install();
    await a.attach(hub, device: 'phone');
    final older = a.socket;
    await a.attach(hub, device: 'phone');
    await pumpEventQueue();
    expect([older.isOpen, older.code, older.reason], [false, 4409, 'replaced']);
    expect(a.socket.isOpen, isTrue);
    expect(hub.connected, 1);
    // A packet too big to be one.
    a.socket.say(Uint8List(Hub.maxPacket + 33));
    await pumpEventQueue();
    expect([a.socket.isOpen, a.socket.code, a.socket.reason], [false, 1009, 'too big']);
    expect(hub.connected, 0);
  });

  test('no more than maxConnections at once, attached ones too: one too many is closed, and there is room when one goes', () async {
    final hub = Hub(maxConnections: 1);
    final a = _Install();
    await a.attach(hub);
    final over = _MemorySocket();
    final heard = <Object>[];
    over.said.listen(heard.add);
    hub.attach(over);
    await pumpEventQueue();
    expect([over.isOpen, over.code, over.reason], [false, 4503, 'full']);
    expect(heard, isEmpty, reason: 'not so much as a hello');
    expect(hub.connected, 1);
    a.socket.drop();
    await pumpEventQueue();
    expect(await _Install().attach(hub), {'ok': true, 'held': 0});
  });
}
