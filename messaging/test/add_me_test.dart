import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/desktop/links.dart';
import 'package:ghost_messaging/friends/add_link.dart';
import 'package:ghost_messaging/friends/buddies.dart';
import 'package:ghost_messaging/me/me.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/packet.dart' show Envelope;
import 'package:ghost_messaging/ui/add_me.dart';
import 'package:ghost_messaging/ui/common.dart' show GhostPage;
import 'package:ghost_messaging/ui/profile.dart';

import 'support/space_call_harness.dart';

/// The add-me link (GMFB-34: "A gogho.st/add/<username> link and QR code that opens a friend request").
class _Friends implements BuddiesPort {
  final asked = <String>[];
  @override
  Future<({String id, String key})> me() async => (id: 'me', key: 'k');
  @override
  String? get username => 'matt';
  @override
  String get displayName => 'Matt';
  @override
  String get bio => '';
  @override
  Future<({String id, String key})?> whois(String username) async {
    asked.add(username);
    return (id: 'b' * 32, key: base64Encode(List.filled(65, 4)));
  }

  @override
  Future<void> keep(String json) async {}
  @override
  Future<String> kept() async => '[]';
  @override
  Future<bool> send(String id, Envelope envelope, {bool sealed = true}) async => true;
  @override
  Stream<({String from, Envelope envelope})> get received => const Stream.empty();
  @override
  Stream<({String from, Envelope envelope})> get greetings => const Stream.empty();
}

/// A directory that answers with a real key pair for each username it holds, and a friends list that writes down what
/// it keeps and sends.
class _Keyed implements BuddiesPort {
  final names = <String, NetKeys>{};
  final sent = <Envelope>[];
  String list = '[]';
  @override
  Future<({String id, String key})> me() async => (id: 'a' * 32, key: 'k');
  @override
  String? get username => 'matt';
  @override
  String get displayName => 'Matt';
  @override
  String get bio => '';
  @override
  Future<({String id, String key})?> whois(String username) async {
    final k = names[username];
    return k == null ? null : (id: k.id, key: base64Encode(k.public));
  }

  @override
  Future<void> keep(String json) async => list = json;
  @override
  Future<String> kept() async => list;
  @override
  Future<bool> send(String id, Envelope envelope, {bool sealed = true}) async {
    sent.add(envelope);
    return true;
  }

  @override
  Stream<({String from, Envelope envelope})> get received => const Stream.empty();
  @override
  Stream<({String from, Envelope envelope})> get greetings => const Stream.empty();
}

void main() {
  test('the link carries the account\'s whole name after #, never sent to a server; the app refuses the relay\'s answer where its key doesn\'t make that name, and keeps and sends nothing', () async {
    final maya = NetKeys.generate(), mallory = NetKeys.generate();
    final link = addMeLink('maya', id: maya.id);
    // All 32 hex digits (the review, S3): eight were 32 bits, which a relay could search out a key to match.
    expect(link, 'https://gogho.st/add/maya#${maya.id}');
    expect(keyDigits, 32);
    expect([addLinkUsername(link), addLinkKey(link)], ['maya', maya.id]);
    expect(addLinkKey('ghostmsg://add/maya#${maya.id.toUpperCase()}'), maya.id, reason: 'the page passes it on as it is');
    // A link from before, with eight, is still taken as it says.
    expect(addLinkKey('https://gogho.st/add/maya#${maya.id.substring(0, 8)}'), maya.id.substring(0, 8));
    expect([addLinkKey('https://gogho.st/add/maya'), addLinkKey('https://gogho.st/add/maya#1234'), addLinkKey('https://gogho.st/add/maya#not-a-key'), addLinkKey('https://evil.example/add/maya#${maya.id.substring(0, 8)}')], [isNull, isNull, isNull, isNull]);
    expect(addMeLink('maya'), 'https://gogho.st/add/maya', reason: 'with no account name, a link from before');

    final port = _Keyed()..names['maya'] = mallory;
    final b = Buddies(port);
    await b.start();
    // The relay gives @maya to someone else: refused, nothing kept, nothing sent.
    await expectLater(b.add('maya', keyPrefix: addLinkKey(link)), throwsA(isA<MeError>().having((e) => e.message, 'message', contains('different key'))));
    expect([b.all, port.sent, port.list], [isEmpty, isEmpty, '[]']);
    // The key the link names: asked.
    port.names['maya'] = maya;
    final got = await b.add('maya', keyPrefix: addLinkKey(link));
    expect([got.id, got.state, port.sent.single.kind], [maya.id, 'asked', 'hello']);
    // A link from before, with no key: as ever.
    port.names['sam'] = mallory;
    expect((await b.add('sam')).id, mallory.id);
    expect(Buddies.keyMatches((id: maya.id, key: base64Encode(mallory.public)), maya.id.substring(0, 8)), isFalse, reason: 'a name that is not its key\'s');
    b.dispose();
  });

  test('on a computer an add-me link is known for one, not taken for a circle\'s (GMFB-34)', () {
    expect(DeskLinks.isAddLink('ghostmsg://add/maya#0123456789abcdef0123456789abcdef'), isTrue);
    expect(DeskLinks.isAddLink(' https://gogho.st/add/maya '), isTrue);
    expect(DeskLinks.isAddLink('ghostmsg://join/#c.abc'), isFalse);
    expect(DeskLinks.isAddLink('ghostmsg://relay?a=x'), isFalse);
    expect(DeskLinks.isAddLink('ghostmsg://add/'), isFalse);
  });

  test('the link and the names it can carry', () {
    expect(addMeLink('maya'), 'https://gogho.st/add/maya');
    expect(addLinkUsername('https://gogho.st/add/maya'), 'maya');
    expect(addLinkUsername('https://gogho.st/add/@Maya.Chen/'), 'maya.chen');
    expect(addLinkUsername('ghostmsg://add/maya_c'), 'maya_c', reason: 'the page\'s Open in Ghost Messaging');
    expect(addLinkUsername('https://gogho.st/add/ab'), isNull, reason: 'too short to be a username');
    expect(addLinkUsername('https://evil.example/add/maya'), isNull);
    expect(addLinkUsername('https://gogho.st/c/maya'), isNull, reason: 'a circle\'s invite word');
  });

  testWidgets('an opened link whose key the relay\'s answer doesn\'t match is refused on screen, and nothing is sent', (tester) async {
    final maya = NetKeys.generate(), mallory = NetKeys.generate();
    final port = _Keyed()..names['maya'] = mallory;
    Buddies.instance = Buddies(port);
    addTearDown(() => Buddies.instance = null);
    await tester.runAsync(() => Buddies.instance.start());
    final h = await SpaceHarness.load(tester);
    await tester.runAsync(() => Me.instance.start(MemoryMeStore()..set('me_username', 'matt'), ValueNotifier(0), () => null));
    addTearDown(() => tester.runAsync(() => Me.instance.start(MemoryMeStore(), ValueNotifier(0), () => null)));
    await h.shoot(tester, const GhostPage(title: 'Messages', body: SizedBox()), 'add-me-wrong-key');
    askToAdd(tester.element(find.text('Messages')), addMeLink('maya', id: maya.id));
    await tester.pump(const Duration(milliseconds: 400));
    await h.again(tester, 'add-me-wrong-key-open');
    await tester.tap(find.text('Send a friend request'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('The relay gave @maya to a different key than the link names'), findsOneWidget);
    expect([port.sent, Buddies.instance.all], [isEmpty, isEmpty]);
    await tester.pump(const Duration(seconds: 5));
  });

  group('on screen', () {
    late _Friends friends;
    setUp(() async {
      friends = _Friends();
      Buddies.instance = Buddies(friends);
      await Buddies.instance.start();
    });
    tearDown(() => Buddies.instance = null);

    testWidgets('an opened link asks first, then sends the request', (tester) async {
      final h = await SpaceHarness.load(tester);
      await tester.runAsync(() => Me.instance.start(MemoryMeStore()..set('me_username', 'matt'), ValueNotifier(0), () => null));
      addTearDown(() => tester.runAsync(() => Me.instance.start(MemoryMeStore(), ValueNotifier(0), () => null)));
      await h.shoot(tester, const GhostPage(title: 'Messages', body: SizedBox()), 'add-me-ask');
      askToAdd(tester.element(find.text('Messages')), 'https://gogho.st/add/maya');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Send @maya a friend request?'), findsOneWidget);
      expect(friends.asked, isEmpty, reason: 'nothing sent before the yes');
      await h.again(tester, 'add-me-ask-open');
      await tester.tap(find.text('Send a friend request'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(friends.asked, ['maya']);
      expect(Buddies.instance.all.single.username, 'maya');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Profile has the add-me link and its QR code', (tester) async {
      final h = await SpaceHarness.load(tester);
      await tester.runAsync(() => Me.instance.start(MemoryMeStore()..set('me_username', 'matt'), ValueNotifier(0), () => null));
      addTearDown(() => tester.runAsync(() => Me.instance.start(MemoryMeStore(), ValueNotifier(0), () => null)));
      await h.shoot(tester, const ProfileScreen(), 'add-me-profile', size: const Size(412, 3400));
      expect(find.text('gogho.st/add/matt'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('add-me-qr')));
      await tester.tap(find.byKey(const ValueKey('add-me-qr')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('add-me-code')), findsOneWidget);
      await h.again(tester, 'add-me-code');
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
