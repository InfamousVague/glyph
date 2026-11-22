import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/friends/add_link.dart';
import 'package:ghost_messaging/friends/buddies.dart';
import 'package:ghost_messaging/me/me.dart';
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

void main() {
  test('the link and the names it can carry', () {
    expect(addMeLink('maya'), 'https://gogho.st/add/maya');
    expect(addLinkUsername('https://gogho.st/add/maya'), 'maya');
    expect(addLinkUsername('https://gogho.st/add/@Maya.Chen/'), 'maya.chen');
    expect(addLinkUsername('ghostmsg://add/maya_c'), 'maya_c', reason: 'the page\'s Open in Ghost Messaging');
    expect(addLinkUsername('https://gogho.st/add/ab'), isNull, reason: 'too short to be a username');
    expect(addLinkUsername('https://evil.example/add/maya'), isNull);
    expect(addLinkUsername('https://gogho.st/c/maya'), isNull, reason: 'a circle\'s invite word');
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
      await h.shoot(tester, const ProfileScreen(), 'add-me-profile', size: const Size(412, 2600));
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
