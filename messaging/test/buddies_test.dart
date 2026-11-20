import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';
import 'package:ghost_messaging/friends/buddies.dart';
import 'package:ghost_messaging/games/game_activity.dart';
import 'package:ghost_messaging/me/me.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_messaging/ui/add_friend_drawer.dart';
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

  /// Lost on the way, as the hub loses what it was holding when the relay restarts: the next ones sent go nowhere.
  int drop = 0;

  @override
  Future<bool> send(String id, Envelope envelope, {bool sealed = true}) async {
    if (drop > 0) {
      drop--;
      return true;
    }
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

  // Matt, 2026-11-20: "what about game presence sensing like discord has?" (lib/games/game_activity.dart).
  test('a friend is told what you are playing, and that you stopped; someone who is not a friend is told nothing', () async {
    final world = _World();
    final maya = _Port(world, 'maya'), sam = _Port(world, 'sam'), theo = _Port(world, 'theo');
    final a = Buddies(maya), b = Buddies(sam), c = Buddies(theo);
    await a.start();
    await b.start();
    await c.start();
    await a.add('@sam');
    await _settle();
    await b.accept(b.requests.single);
    await _settle();
    // Theo asked Maya and she has not answered: not a friend.
    await c.add('@maya');
    await _settle();
    final heard = GameActivities.instance = GameActivities();
    addTearDown(() => GameActivities.instance = GameActivities());
    final since = DateTime.now().subtract(const Duration(minutes: 25));
    await a.sayActivity(GameActivity('Hades', since));
    await _settle();
    expect(heard.of(maya.keys.id)?.name, 'Hades', reason: 'Sam, her friend, was told');
    expect(heard.of(maya.keys.id)!.words(), 'Playing Hades · 25 min');
    expect(b.friends.single.status, '', reason: 'nothing of it is kept with the list');
    await a.sayActivity(null);
    await _settle();
    expect(heard.of(maya.keys.id), isNull, reason: 'and told she stopped');
    // What someone who is not a friend says is not taken.
    await sam.send(theo.keys.id, Envelope(kind: 'buddy', body: {'s': 'ga', 'ga': {'n': 'Doom', 's': 1}}), sealed: false);
    await _settle();
    expect(heard.of(sam.keys.id), isNull);
  });

  test('a request lost on its way, and then the yes, are asked again until both are friends', () async {
    // Matt, 2026-11-19: "my friend request to morgan never went through i also sent one from her phone and it didn't go
    // out". The hub drops what it holds when the relay restarts; nothing asked again.
    final world = _World();
    final maya = _Port(world, 'maya'), sam = _Port(world, 'sam');
    final a = Buddies(maya), b = Buddies(sam);
    await a.start();
    await b.start();
    maya.drop = 1;
    await a.add('sam');
    await _settle();
    expect(b.requests, isEmpty);
    // Asked again: Sam has it now, once.
    expect(await a.askAgain(), 1);
    await _settle();
    expect(b.requests.single.username, 'maya');
    await a.askAgain();
    await _settle();
    expect(b.requests, hasLength(1));
    // Sam's yes is lost too: Maya is still waiting, and asks again; Sam, a friend already, says yes again.
    sam.drop = 1;
    await b.accept(b.requests.single);
    await _settle();
    expect(a.friends, isEmpty);
    await a.askAgain();
    await _settle();
    expect(a.friends.single.username, 'sam');
    expect(b.friends.single.username, 'maya');
    // Answered: nothing left to ask.
    expect(await a.askAgain(), 0);
    a.dispose();
    b.dispose();
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
      // A friend now: listed On Ghost Messaging in Contacts with the friends by number, not here (2026-11-19).
      expect(find.text('Friends by username'), findsNothing);
      expect(find.text('Maya Chen'), findsNothing);
      expect(b.friends.single.username, 'maya');
      expect(a.friends.single.username, 'sam', reason: 'Maya hears the yes');
    });

    Future<void> drawer(WidgetTester tester, Buddies b, Me m) async {
      final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
      await tester.pumpWidget(WidgetsApp(
        color: const Color(0xFF4F5BD5),
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder w) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => w(c)),
        builder: (context, child) => GlacierTheme(sheet: sheet, attrs: const {'platform': 'mobile'}, child: GlacierToastProvider(child: child!)),
        home: AddFriendDrawer(buddies: b, me: m),
      ));
      await tester.pump();
    }

    /// Types [words] into the drawer and lets the look-up (a short wait, then the server) answer.
    Future<void> type(WidgetTester tester, String words) async {
      await tester.enterText(find.byType(EditableText), words);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    // Matt, 2026-11-16: "move the Add button to the side of search and have it open a drawer to search and add users
    // as well as setup username if hasn't been done already".
    testWidgets('the drawer looks a username up as it is typed, and Add asks them', (tester) async {
      final world = _World();
      final a = Buddies(_Port(world, 'maya')), b = Buddies(_Port(world, 'sam'));
      await tester.runAsync(() async {
        await a.start();
        await b.start();
      });
      await drawer(tester, a, await tester.runAsync(() => me('maya')) as Me);
      expect(find.text('Add a friend'), findsOneWidget);
      await type(tester, '@nobody');
      expect(find.text('Nobody has this username'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-found')), findsNothing);
      await type(tester, '@maya');
      expect(find.text('That\'s you'), findsOneWidget);
      await type(tester, '@sam');
      expect(find.text('On Ghost Messaging'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-found')));
      await settle(tester);
      expect(find.text('Friend request sent'), findsOneWidget);
      expect(b.requests.single.username, 'maya', reason: 'Sam sees the request');
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('without a username of your own the drawer has one chosen first', (tester) async {
      final b = Buddies(_Port(_World(), 'maya'));
      await tester.runAsync(b.start);
      await drawer(tester, b, await tester.runAsync(() => me(null)) as Me);
      expect(find.text('Choose your username'), findsOneWidget);
      expect(find.byKey(const ValueKey('username-field')), findsOneWidget);
      expect(find.text('Add a friend'), findsNothing);
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.tap(find.byKey(const ValueKey('claim-username')));
      await tester.pump();
      expect(find.textContaining('3 to 20 letters'), findsOneWidget);
    });

    testWidgets('the list keeps the requests and friends, and no field of its own', (tester) async {
      final b = Buddies(_Port(_World(), 'maya'));
      await tester.runAsync(b.start);
      await show(tester, b, await tester.runAsync(() => me(null)) as Me);
      expect(find.byType(EditableText), findsNothing);
    });
  });
}
