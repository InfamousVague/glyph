import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/p256.dart';
import 'package:ghost_relay/relay.dart';
import 'package:test/test.dart';

/// One identity on several devices at once (Matt, 2026-11-18: "I want desktop to be able to run standalone for internal
/// friends and circles ... even if the desktop is linked"): a phone and its computer both here, each handed what is
/// sent to them, neither putting the other off; a reconnect from the same device still takes its own place.

final _rnd = Random(7);
List<int> _bytes(int n) => [for (var i = 0; i < n; i++) _rnd.nextInt(256)];
List<int> _unhex(String s) => [for (var i = 0; i + 1 < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

/// An install: a key, and connections to the hub signed with it.
class _Install {
  _Install() : scalar = _bytes(32) {
    key = P256.publicOf(scalar);
    id = Hub.nameOf(key);
  }
  final List<int> scalar;
  late final List<int> key;
  late final String id;
  bool closed = false;
  late WebSocket ws;
  final said = StreamController<Map>.broadcast();
  final frames = <List<int>>[];

  /// Signs in (or only looks, with [peek]); what the hub answers the hello with.
  /// The same identity on another device ([device] names it in the hello).
  _Install.copyOf(_Install other)
      : scalar = other.scalar,
        key = other.key,
        id = other.id;

  Future<Map> connect(String url, {bool peek = false, String? device}) async {
    final socket = await WebSocket.connect(url);
    if (!peek) ws = socket;
    socket.done.then((_) => closed = true);
    final first = Completer<Map>(), hello = Completer<Map>();
    socket.listen((d) {
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
    final nonce = _unhex((await first.future)['hello'] as String);
    final sig = P256.sign(scalar, [...utf8.encode(Hub.greeting), ...nonce], _bytes(32));
    socket.add(jsonEncode({'id': id, 'key': base64Encode(key), 'sig': base64Encode(sig), if (peek) 'peek': true, 'device': ?device}));
    return hello.future.timeout(const Duration(seconds: 5));
  }

  /// A packet to [to], as the app's hub route sends one: [1][seq][to][the packet].
  void sendTo(_Install to, List<int> packet) {
    final seq = ByteData(4)..setUint32(0, _rnd.nextInt(1 << 30));
    ws.add(Uint8List.fromList([Hub.toPeer, ...seq.buffer.asUint8List(), ..._unhex(to.id), ...packet]));
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 200));

void main() {
  late Relay relay;
  late Hub hub;
  late String url;

  setUp(() async {
    hub = Hub();
    relay = Relay(hub: hub);
    url = 'ws://127.0.0.1:${await relay.start(port: 0)}/hub';
  });
  tearDown(() => relay.stop());

  test('a phone and its computer, one identity, are both here and both handed what is sent', () async {
    final phone = _Install(), desk = _Install.copyOf(phone), friend = _Install();
    expect((await phone.connect(url, device: 'phone'))['ok'], isTrue);
    expect((await desk.connect(url, device: 'desk'))['ok'], isTrue);
    await friend.connect(url);
    await _settle();
    expect(phone.closed, isFalse, reason: 'the computer does not put the phone off');
    expect(hub.connected, 3);
    friend.sendTo(phone, [7, 7]);
    await _settle();
    expect(phone.frames.length, 1);
    expect(desk.frames.length, 1, reason: 'the same identity on the computer has it too');
  });

  test('the same device again takes its own place; one from before devices still takes the place of another', () async {
    final a = _Install(), again = _Install.copyOf(a), other = _Install.copyOf(a);
    await a.connect(url, device: 'phone');
    await other.connect(url, device: 'desk');
    await again.connect(url, device: 'phone');
    await _settle();
    expect(a.closed, isTrue);
    expect(other.closed, isFalse);
    expect(hub.connected, 2);
    final old1 = _Install(), old2 = _Install.copyOf(old1);
    await old1.connect(url);
    await old2.connect(url);
    await _settle();
    expect(old1.closed, isTrue, reason: 'two apps from before devices are one device, as before');
  });

  test('away is every device away; gone is the last one going', () async {
    final watcher = _Install(), phone = _Install(), desk = _Install.copyOf(phone);
    await watcher.connect(url);
    final heard = <Map>[];
    watcher.said.stream.listen(heard.add);
    watcher.ws.add(jsonEncode({'watch': [phone.id]}));
    await phone.connect(url, device: 'phone');
    await desk.connect(url, device: 'desk');
    await _settle();
    expect(heard.where((m) => m['came'] == phone.id).length, 1, reason: 'came once, with the first device');
    phone.ws.add(jsonEncode({'away': true}));
    await _settle();
    expect(heard.where((m) => m['away'] == phone.id), isEmpty, reason: 'the computer is still in use');
    desk.ws.add(jsonEncode({'away': true}));
    await _settle();
    expect(heard.lastWhere((m) => m['away'] == phone.id)['is'], isTrue);
    await phone.ws.close();
    await _settle();
    expect(heard.where((m) => m['went'] == phone.id), isEmpty, reason: 'the computer is still here');
    await desk.ws.close();
    await _settle();
    expect(heard.where((m) => m['went'] == phone.id).length, 1);
  });
}
