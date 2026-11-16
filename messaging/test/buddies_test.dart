import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';
import 'package:ghost_messaging/friends/buddies.dart';
import 'package:ghost_messaging/me/me.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_messaging/ui/username_friends.dart';

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

  group('on Contacts (UsernameFriends)', () {
    // Matt, 2026-11-16: "We need a way to add friends on the network by username on the contacts page and see friend
    // requests".
    Future<Me> me(String? username) async {
      final store = MemoryMeStore();
      if (username != null) store.set('me_username', username);
      final m = Me.forTest();
      await m.start(store, ValueNotifier(0), () => null);
      return m;
    }

    Future<void> show(WidgetTester tester, Buddies b, Me m) async {
      final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
      await tester.pumpWidget(WidgetsApp(
        color: const Color(0xFF4F5BD5),
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder w) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => w(c)),
        builder: (context, child) => GlacierTheme(sheet: sheet, attrs: const {'platform': 'mobile'}, child: GlacierToastProvider(child: child!)),
        home: ListView(children: [UsernameFriends(buddies: b, me: m)]),
      ));
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(_settle);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('a request shows with Accept and Decline, and Accept makes friends of both', (tester) async {
      final world = _World();
      final a = Buddies(_Port(world, 'maya', display: 'Maya Chen')), b = Buddies(_Port(world, 'sam'));
      await tester.runAsync(() async {
        await a.start();
        await b.start();
        await a.add('sam');
        await _settle();
      });
      await show(tester, b, await tester.runAsync(() => me('sam')) as Me);
      expect(find.text('Friend request'), findsOneWidget);
      expect(find.text('Maya Chen'), findsOneWidget);
      expect(find.byKey(const ValueKey('decline-maya')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accept-maya')));
      await settle(tester);
      expect(find.text('Friend request'), findsNothing);
      expect(find.text('Friends by username'), findsOneWidget);
      expect(b.friends.single.username, 'maya');
      expect(a.friends.single.username, 'sam', reason: 'Maya hears the yes');
    });

    testWidgets('asking by @username from the field; nobody by that name is said so', (tester) async {
      final world = _World();
      final a = Buddies(_Port(world, 'maya')), b = Buddies(_Port(world, 'sam'));
      await tester.runAsync(() async {
        await a.start();
        await b.start();
      });
      await show(tester, a, await tester.runAsync(() => me('maya')) as Me);
      await tester.enterText(find.byType(EditableText), '@nobody');
      await tester.tap(find.byKey(const ValueKey('add-friend')));
      await settle(tester);
      expect(find.textContaining('Nobody has the username @nobody'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '@sam');
      await tester.tap(find.byKey(const ValueKey('add-friend')));
      await settle(tester);
      expect(find.text('Waiting for them'), findsOneWidget);
      expect(find.text('@sam'), findsOneWidget);
      expect(b.requests.single.username, 'maya', reason: 'Sam sees the request');
    });

    testWidgets('without a username of your own it says to choose one first', (tester) async {
      final b = Buddies(_Port(_World(), 'maya'));
      await tester.runAsync(b.start);
      await show(tester, b, await tester.runAsync(() => me(null)) as Me);
      expect(find.text('Add friends by username'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-friend-field')), findsNothing);
    });
  });
}
