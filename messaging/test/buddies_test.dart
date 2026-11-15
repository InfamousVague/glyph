import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/friends/buddies.dart';
import 'package:ghost_messaging/me/me.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/packet.dart';

/// Friends by username (lib/friends/buddies.dart). Matt, 2026-11-14: "create a profile and username under "me" to
/// register a username and add friends on the platform".
///
/// Two installs, each with its own key pair, a directory that maps usernames to them, and routes that pass what one
/// sends to the other: sealed only once the sender holds a key for them (it has them in its list), in the clear only
/// as a greeting, as the switchboard does.
class _World {
  final Map<String, _Port> byName = {};
  final Map<String, _Port> byId = {};
}

class _Port implements BuddiesPort {
  _Port(this.world, this.name, {this.display = '', this.line = ''}) : keys = NetKeys.generate() {
    world.byName[name] = this;
    world.byId[keys.id] = this;
  }

  final _World world;
  final String name;
  final NetKeys keys;
  String display, line;
  String list = '[]';
  final _in = StreamController<({String from, Envelope envelope})>.broadcast();
  final _hellos = StreamController<({String from, Envelope envelope})>.broadcast();

  bool _holds(String id) => (jsonDecode(list) as List).any((b) => (b as Map)['i'] == id);

  @override
  Future<({String id, String key})> me() async => (id: keys.id, key: base64Encode(keys.public));
  @override
  String? get username => name;
  @override
  String get displayName => display;
  @override
  String get bio => line;
  @override
  Future<({String id, String key})?> whois(String username) async {
    final p = world.byName[username];
    return p == null ? null : (id: p.keys.id, key: base64Encode(p.keys.public));
  }

  @override
  Future<void> keep(String json) async => list = json;
  @override
  Future<String> kept() async => list;

  @override
  Future<bool> send(String id, Envelope envelope, {bool sealed = true}) async {
    final to = world.byId[id];
    if (to == null) return false;
    // Sealed needs a key on both sides: each must have the other in its list.
    if (sealed && (!_holds(id) || !to._holds(keys.id))) return false;
    scheduleMicrotask(() => (sealed ? to._in : to._hellos).add((from: keys.id, envelope: envelope)));
    return true;
  }

  @override
  Stream<({String from, Envelope envelope})> get received => _in.stream;
  @override
  Stream<({String from, Envelope envelope})> get greetings => _hellos.stream;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('ask by username, the other says yes, and both are friends with each other\'s name', () async {
    final world = _World();
    final maya = _Port(world, 'maya', display: 'Maya Chen', line: 'climbing most days');
    final sam = _Port(world, 'sam', display: 'Sam');
    final a = Buddies(maya), b = Buddies(sam);
    await a.start();
    await b.start();

    final asked = await a.add('@Sam');
    expect(asked.state, 'asked');
    await _settle();
    // Sam sees who asked, with what Maya says about herself.
    expect(b.requests.single.username, 'maya');
    expect(b.requests.single.name, 'Maya Chen');
    expect(b.requests.single.bio, 'climbing most days');

    await b.accept(b.requests.single);
    await _settle();
    expect(a.friends.single.username, 'sam');
    expect(a.friends.single.name, 'Sam');
    expect(b.friends.single.username, 'maya');
    // Kept for the phone to make the sealing keys from.
    expect(jsonDecode(maya.list), [containsPair('s', 'yes')]);

    // A new name reaches friends.
    maya.display = 'Maya C.';
    await a.shareProfile();
    await _settle();
    expect(b.friends.single.name, 'Maya C.');

    // Removed: gone on both.
    await b.remove(b.friends.single);
    await _settle();
    expect(a.all, isEmpty);
    expect(b.all, isEmpty);
  });

  test('two who ask each other are friends at once; nobody, yourself, or no username of your own is refused', () async {
    final world = _World();
    final maya = _Port(world, 'maya'), sam = _Port(world, 'sam');
    final a = Buddies(maya), b = Buddies(sam);
    await a.start();
    await b.start();
    await a.add('sam');
    await _settle();
    await b.add('maya');
    await _settle();
    expect(a.friends.map((f) => f.username), ['sam']);
    expect(b.friends.map((f) => f.username), ['maya']);
    await expectLater(a.add('nobody'), throwsA(isA<MeError>()));
    await expectLater(a.add('maya'), throwsA(isA<MeError>()));
  });

  test('a request in someone else\'s name is not taken: its key must be the sender\'s', () async {
    final world = _World();
    final maya = _Port(world, 'maya'), sam = _Port(world, 'sam');
    final b = Buddies(sam);
    await b.start();
    final other = NetKeys.generate();
    sam._hellos.add((from: maya.keys.id, envelope: Envelope(kind: 'hello', body: {'buddy': 'ask', 'u': 'maya', 'k': base64Encode(other.public)})));
    await _settle();
    expect(b.requests, isEmpty);
    expect(Me.goodUsername('ab'), isFalse);
    expect(Me.goodUsername('Maya_C'), isTrue);
  });
}
