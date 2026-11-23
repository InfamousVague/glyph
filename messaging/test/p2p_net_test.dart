import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/account/account.dart';
import 'package:ghost_messaging/account/account_crypto.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/friends/friends.dart';
import 'package:ghost_messaging/me/me.dart' show AppMeStore, Me;
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/net/net.dart';
import 'package:ghost_messaging/net/p2p/card.dart';
import 'package:ghost_messaging/net/p2p/node.dart';
import 'package:ghost_messaging/net/p2p/p2p.dart';
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/relay.dart';

import 'support/direct_world.dart' show HandEnd, LinkWords, PlainCarrier;
import 'support/fake_p2p.dart';

/// The direct route as the app holds it (lib/net/net.dart): there only where the build has the core
/// ([Net.p2pNode]), after the relay's hub in the order, linking with friends and nobody else the routes reach, kept in
/// step with the people, the person's mode, the app being put away and coming back and the relay in use, and deleted
/// from the device at sign-out. The phone under it is a stand-in channel, as test/net_want_test.dart's.

/// Waits for [ok], however long the machine takes (five seconds at most), not for a length of time.
Future<void> _until(bool Function() ok, String what) async {
  for (var i = 0; i < 1000 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ok(), isTrue, reason: what);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final me = NetKeys.generate();
  // A friend by username, a friend by number, someone who has asked, and a member of a group this phone is in.
  final sam = NetKeys.generate(), nell = NetKeys.generate(), asker = NetKeys.generate(), member = NetKeys.generate();
  Uint8List keyWith(NetKeys them) => NetCrypto.netKey(NetCrypto.conversationKey(me, them.public)!);
  late Map<String, String> secrets;
  late List<Map<String, Object?>> peers;
  late List<Map<String, Object?>> e2e;
  late List<Map<String, Object?>> buddies;
  late bool e2eFails;
  late FakeP2pMesh mesh;
  late FakeP2pNode node;

  /// A friend by username as the phone keeps them (lib/friends/buddies.dart), where they stand with this phone.
  Map<String, Object?> buddy(String username, NetKeys keys, String state) => {'u': username, 'i': keys.id, 'k': base64Encode(keys.public), 's': state};

  setUp(() {
    HttpOverrides.global = null;
    secrets = {};
    // As Android's netPeers has them: those encryption is on with (Net.peers), the members of this phone's groups
    // (Groups.peers), and friends by username, asked or asking (Buddies.peers).
    peers = [
      {'id': sam.id, 'address': '@sam', 'key': keyWith(sam)},
      {'id': nell.id, 'address': '+1 (555) 000-0001', 'key': keyWith(nell)},
      {'id': asker.id, 'address': '', 'key': keyWith(asker)},
      {'id': member.id, 'address': '+15550000002', 'key': keyWith(member)},
    ];
    // The phone's own records of who is a friend: each by the id their key makes.
    e2e = [
      {'address': '+15550000001', 'state': 'on', 'friend': 'yes', 'id': nell.id},
      {'address': '+15550000002', 'state': 'on', 'friend': '', 'id': member.id},
    ];
    buddies = [buddy('sam', sam, 'yes'), buddy('asker', asker, 'asked')];
    e2eFails = false;
    mesh = FakeP2pMesh();
    node = mesh.node();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async {
      final a = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'netIdentity':
          return {'id': me.id, 'key': base64Encode(me.public)};
        case 'netSign':
          return NetCrypto.sign(me, (a['message'] as List).cast<int>());
        case 'netPeers':
          return peers;
        case 'e2eList':
          if (e2eFails) throw PlatformException(code: 'locked');
          return e2e;
        case 'buddiesKept':
          return jsonEncode(buddies);
        case 'netSmsDrain':
          return const <Object>[];
        case 'secretKeep':
          final value = '${a['value'] ?? ''}';
          value.isEmpty ? secrets.remove('${a['name']}') : secrets['${a['name']}'] = value;
          return null;
        case 'secretRead':
          return secrets['${a['name']}'];
      }
      return null;
    });
  });
  tearDown(() async {
    await Net.instance.shutdown();
    Net.p2pNode = null;
  });

  /// A card from Sam's device, sealed as his app seals it, as it comes by a route.
  Future<(DeviceCard, Uint8List)> samsCard() async {
    final card = await DeviceCard.make(KeysSigner(sam), device: NetCrypto.hex(NetCrypto.randomBytes(16)), nodeId: NetCrypto.hex(NetCrypto.randomBytes(32)), now: DateTime.now());
    final envelope = Envelope(kind: P2p.kind, body: {'t': 'card', 'c': card.toJson(), 'h': [?Net.instance.p2p?.card?.tag]}, ack: false);
    return (card, Packet.wrap(from: sam.id, sealed: true, payload: NetCrypto.seal(keyWith(sam), envelope.encode())));
  }

  test('a build with no core has no direct route, and one whose core gives no node has none either', () async {
    expect(Net.p2pNode, isNull, reason: 'null in this branch: the core\'s factory is wired in with the core');
    final hub = PlainCarrier('hub'), sms = PlainCarrier('sms');
    await Net.instance.start(AppState(), carriers: [hub, sms]);
    expect(Net.instance.p2p, isNull);
    expect(Net.instance.board!.carriers.map((c) => c.id), ['hub', 'sms']);
    expect(secrets.keys, isNot(contains(P2p.keyName)));
    await Net.instance.shutdown();
    Net.p2pNode = () => null;
    await Net.instance.start(AppState(), carriers: [PlainCarrier('hub')]);
    expect(Net.instance.p2p, isNull);
    expect(Net.instance.board!.carrier('p2p'), isNull);
  });

  // The second review, M3 (R2-K): the node and the direct network were made inside the one try that sets every route
  // up, so a core that failed to load took the relay's route down with it.
  test('a core that fails to load leaves the other routes as they are, and Settings is told why there is no Direct', () async {
    for (final broken in [
      FakeP2pMesh.broken(StateError('the direct network\'s library could not be loaded')),
      // One that loads and then breaks node.dart's word at once: its getters throw.
      () => node..throws.addAll({'state', 'paths', 'opened'}),
    ]) {
      Net.p2pNode = broken;
      final hub = PlainCarrier('hub'), sms = PlainCarrier('sms');
      await Net.instance.start(AppState(), carriers: [hub, sms]);
      expect([Net.instance.board, Net.instance.error], [isNotNull, isNull], reason: 'the routes were set up');
      expect(Net.instance.board!.carriers.map((c) => c.id), ['hub', 'sms']);
      expect(Net.instance.p2p, isNull);
      expect(Net.instance.directProblem, contains('could not be started'));
      // The relay's route carries as ever.
      await _until(() => hub.state.value == CarrierState.up, 'the relay\'s route started');
      final d = await Net.instance.send(Peer(id: sam.id, key: keyWith(sam)), Envelope(kind: 'ping', ack: false));
      expect(d.via, 'hub');
      await Net.instance.shutdown();
      expect(Net.instance.directProblem, isNull, reason: 'said of the routes as they were set up, and gone with them');
    }
  });

  test('with a core: the route comes after the relay\'s, its key is with the secrets, and only friends are told the card', () async {
    Net.p2pNode = () => node;
    final hub = PlainCarrier('hub'), sms = PlainCarrier('sms', traits: const CarrierTraits(maxPacket: 133, maxParts: 6, metered: true, live: false, wakes: true));
    final app = AppState();
    await Net.instance.start(app, carriers: [hub, sms]);
    final p2p = Net.instance.p2p!;
    expect(Net.instance.board!.order, ['hub', 'p2p', 'lan', 'sms']);
    expect(Net.instance.board!.carriers.map((c) => c.id), ['hub', 'p2p', 'sms']);
    expect(Net.instance.board!.carrier('p2p'), same(p2p.carrier));
    await _until(() => p2p.loaded && p2p.card != null, 'what the direct network keeps was read');
    // The node key where the install keeps its keys; the node id and the card with the app's choices.
    expect(secrets[P2p.keyName], hasLength(64));
    expect(p2p.nodeId, FakeP2pNode.idFor(NetCrypto.unhex(secrets[P2p.keyName]!)));
    expect(app.choice(P2p.idName, ''), contains(p2p.nodeId!));
    expect(app.withPrefix('p2p_').values.join(), isNot(contains(secrets[P2p.keyName]!)));
    final card = DeviceCard.fromJson(jsonDecode(app.choice(P2p.cardName, '')), now: DateTime.now().millisecondsSinceEpoch)!;
    expect([card.account, card.device, card.nodeId], [me.id, app.choice('hub_device', ''), p2p.nodeId]);
    expect(card, p2p.card, reason: 'signed through the phone, whose key it is');
    // A phone's policy: the node is not started for any of this.
    expect([p2p.policy.stayUp, node.starts], [false, 0]);

    // The people the routes reach are four; the friends are two. Only they were told anything, and by the relay's
    // route alone.
    expect(Net.instance.people.map((p) => p.id), unorderedEquals([sam.id, nell.id, asker.id, member.id]));
    expect(Net.instance.friends.map((p) => p.id), unorderedEquals([sam.id, nell.id]));
    await _until(() => hub.to.length >= 2, 'both friends were told');
    await pumpEventQueue();
    expect(hub.to, unorderedEquals([sam.id, nell.id]));
    expect(sms.carried, isEmpty);
    expect([p2p.mayLink(sam.id), p2p.mayLink(nell.id), p2p.mayLink(asker.id), p2p.mayLink(member.id)], [true, true, false, false]);

    // A card from a friend's device is taken; the same from the one who has only asked is not.
    final (theirs, packet) = await samsCard();
    hub.take(packet, from: sam.id);
    await _until(() => p2p.devicesOf(sam.id).isNotEmpty, 'Sam\'s card was taken');
    expect(p2p.devicesOf(sam.id).single.card, theirs);
    expect(node.allowed.keys, [theirs.nodeId]);
    final asking = await DeviceCard.make(KeysSigner(asker), device: 'ab' * 16, nodeId: 'cd' * 32, now: DateTime.now());
    hub.take(Packet.wrap(from: asker.id, sealed: true, payload: NetCrypto.seal(keyWith(asker), Envelope(kind: P2p.kind, body: {'t': 'card', 'c': asking.toJson()}, ack: false).encode())), from: asker.id);
    await pumpEventQueue();
    expect(p2p.devicesOf(asker.id), isEmpty);
    expect(hub.to.where((id) => id == asker.id), isEmpty, reason: 'nor answered');
    expect(Net.instance.direct.value, greaterThan(0), reason: 'Settings is told to draw again');
  });

  // The second review, M1: who counted as a friend came from the address the routes have for someone, and on Android
  // that includes the members of a group, whose addresses are whatever the group's admin wrote.
  test('friends are those the records say are, by the id their key makes: never a group member, whatever address an admin gave them, nor a pending request', () async {
    final atMember = NetKeys.generate(), numberMember = NetKeys.generate(), inviter = NetKeys.generate(), stranger = NetKeys.generate();
    peers.addAll([
      // Members of a group a friend admins, as Groups.peers has them: one the admin wrote as "@anything", one written
      // with the number of this phone's real friend, Nell.
      {'id': atMember.id, 'address': '@anything', 'key': keyWith(atMember)},
      {'id': numberMember.id, 'address': '+15550000001', 'key': keyWith(numberMember)},
      // Someone who asked to be a friend by username (Buddies.peers gives them no address).
      {'id': inviter.id, 'address': '', 'key': keyWith(inviter)},
    ]);
    buddies.add(buddy('inviter', inviter, 'invited'));
    // A record that says yes for someone the routes don't reach: no one to link with.
    e2e.add({'address': '+15550009999', 'state': 'on', 'friend': 'yes', 'id': stranger.id});
    Net.p2pNode = () => node;
    final hub = PlainCarrier('hub');
    await Net.instance.start(AppState(), carriers: [hub]);
    final p2p = Net.instance.p2p!;
    await _until(() => p2p.loaded && p2p.card != null && hub.to.length >= 2, 'read, and the friends told');
    await pumpEventQueue();
    expect(Net.instance.people, hasLength(7));
    expect(Net.instance.friends.map((p) => p.id), unorderedEquals([sam.id, nell.id]));
    expect(hub.to, unorderedEquals([sam.id, nell.id]), reason: 'only friends are told the card, and where this device is');
    for (final who in [atMember, numberMember, asker, inviter, member]) {
      expect(p2p.mayLink(who.id), isFalse);
    }
    // What they say of themselves is not looked at: a card, or a meet that would bring the node up.
    for (final (i, who) in [atMember, numberMember].indexed) {
      final card = await DeviceCard.make(KeysSigner(who), device: '${i}d' * 16, nodeId: '${i}e' * 32, now: DateTime.now());
      for (final what in ['card', 'meet']) {
        hub.take(Packet.wrap(from: who.id, sealed: true, payload: NetCrypto.seal(keyWith(who), Envelope(kind: P2p.kind, body: {'t': what, 'c': card.toJson()}, ack: false).encode())), from: who.id);
      }
    }
    await pumpEventQueue(times: 50);
    expect([p2p.devicesOf(atMember.id), p2p.devicesOf(numberMember.id), node.allowed, node.starts], [isEmpty, isEmpty, isEmpty, 0]);
    expect(hub.to, hasLength(2), reason: 'nor answered');
    // The records change: Nell is a friend no longer, the inviter is one now. Read again, by id.
    e2e[0]['friend'] = '';
    buddies[2]['s'] = 'yes';
    await Net.instance.refresh();
    expect(Net.instance.friends.map((p) => p.id), unorderedEquals([sam.id, inviter.id]));
    // A record that can't be read now: whoever was a friend stays one.
    e2eFails = true;
    await Net.instance.refresh();
    expect(Net.instance.friends.map((p) => p.id), unorderedEquals([sam.id, inviter.id]));
  });

  test('kept in step: the people, how the person chose to be shown, the app put away and back, and shutting down', () async {
    Net.p2pNode = () => node;
    final hub = PlainCarrier('hub');
    await Net.instance.start(AppState(), carriers: [hub]);
    final p2p = Net.instance.p2p!;
    await _until(() => p2p.loaded && p2p.card != null, 'what the direct network keeps was read');
    final (theirs, packet) = await samsCard();
    hub.take(packet, from: sam.id);
    await _until(() => p2p.devicesOf(sam.id).isNotEmpty, 'Sam\'s card was taken');

    // Invisible: no friend's device is let in. Seen again: let in again.
    Net.instance.setMode('invisible');
    expect([p2p.mayLink(sam.id), node.allowed], [false, isEmpty]);
    Net.instance.setMode('online');
    expect([p2p.mayLink(sam.id), node.allowed.keys], [true, [theirs.nodeId]]);

    // Put away, and back on the screen: the direct network knows which, and the node, where it is up, looks at its
    // paths again.
    expect(p2p.inUse, isTrue);
    Net.instance.setAway(true);
    expect(p2p.inUse, isFalse);
    Net.instance.setAway(false);
    expect(p2p.inUse, isTrue);
    await p2p.up();
    Net.instance.resume(const Duration(minutes: 2));
    expect(node.networkChanges, 1);

    // The friend by number is one no longer (the phone's own record says so): not a friend to the direct route.
    e2e[0]['friend'] = '';
    await Net.instance.refresh();
    expect(Net.instance.friends.map((p) => p.id), [sam.id]);
    // Sam is removed, or blocked: no longer among the people. His card goes, and his device is let in no longer.
    peers.removeWhere((p) => p['id'] == sam.id);
    await Net.instance.refresh();
    await _until(() => p2p.devicesOf(sam.id).isEmpty, 'Sam\'s card went with him');
    expect(node.allowed, isEmpty);

    // Shut down: the node stops, and the app holds no direct network.
    expect([node.state.value, p2p.loaded], [P2pState.up, true]);
    await Net.instance.shutdown();
    expect([node.state.value, Net.instance.p2p, p2p.loaded], [P2pState.off, null, false]);
    // And it hears nothing more: a card that comes now is nobody's to take.
    final before = Net.instance.direct.value;
    p2p.setHelpers(const ['https://late.example']);
    expect(Net.instance.direct.value, before, reason: 'no longer listened to');
  });

  test('a direct network made while the person is Invisible and the app put away starts so', () async {
    // As the app opens in the background with Invisible chosen before (Me tells Net as it starts).
    Net.instance.setMode('invisible');
    Net.instance.setAway(true);
    addTearDown(() {
      Net.instance.setMode('online');
      Net.instance.setAway(false);
    });
    Net.p2pNode = () => node;
    final hub = PlainCarrier('hub');
    await Net.instance.start(AppState(), carriers: [hub]);
    final p2p = Net.instance.p2p!;
    await _until(() => p2p.loaded && p2p.card != null, 'what the direct network keeps was read');
    await pumpEventQueue();
    expect([p2p.inUse, p2p.mayLink(sam.id)], [false, false]);
    expect(hub.to, isEmpty, reason: 'Invisible, no friend is told anything');
    final (_, packet) = await samsCard();
    hub.take(packet, from: sam.id);
    await _until(() => p2p.devicesOf(sam.id).isNotEmpty, 'Sam\'s card was taken');
    expect(node.allowed, isEmpty, reason: 'and his device is not let in');
    // Seen again: let in, and told.
    Net.instance.setMode('online');
    expect(node.allowed, hasLength(1));
    await _until(() => hub.to.contains(sam.id), 'Sam was told once the person was seen again');
  });

  test('the relay in use names the link helpers as the app signs in to it, and another relay\'s take their place', () async {
    final one = Relay(hub: Hub(helpers: ['https://link.one.example'])), two = Relay(hub: Hub(helpers: ['https://link.two.example', 'https://link.three.example']));
    final first = 'ws://127.0.0.1:${await one.start(port: 0)}/hub', second = 'ws://127.0.0.1:${await two.start(port: 0)}/hub';
    addTearDown(one.stop);
    addTearDown(two.stop);
    Net.p2pNode = () => node;
    final app = AppState()..set('net_hub', first);
    await Net.instance.start(app);
    final p2p = Net.instance.p2p!;
    await _until(() => Net.instance.hub!.state.value == CarrierState.up && p2p.loaded, 'signed in to the first relay');
    expect(Net.instance.hub!.helpers.value, ['https://link.one.example']);
    expect(p2p.helpers, ['https://link.one.example']);
    expect(jsonDecode(app.choice(P2p.helpersName, '')), ['https://link.one.example']);
    // Its next start is with them.
    await p2p.up();
    expect(node.config!.helpers, ['https://link.one.example']);

    // Moved to another relay: the first one's are used no longer, at once, and the second's once it has said.
    final starts = node.starts;
    await Net.instance.setHub(second);
    expect(p2p.helpers, isEmpty);
    await _until(() => p2p.helpers.isNotEmpty, 'signed in to the second relay');
    expect(p2p.helpers, ['https://link.two.example', 'https://link.three.example']);
    await _until(() => node.state.value == P2pState.up && node.config!.helpers.length == 2, 'the running node was started again with them');
    expect(node.starts, greaterThan(starts));
    expect(Net.instance.board!.carriers.map((c) => c.id), ['hub', 'p2p', 'sms']);
  });

  // GMFB-21's copies (lib/friends/friends.dart, copyKind) went by the relay alone. With the relay away they now go
  // straight to the account's other device.
  test('a copy of a friend\'s words reaches the account\'s own other device directly when the relay can\'t be reached', () async {
    // An account on this install: its words where the install keeps its keys, which make the key its devices share.
    final words = AccountCrypto.newWords();
    secrets['account_words'] = words.join(' ');
    final mineKey = Me.mineKeyOf(words);
    e2e.add({'address': '@sam', 'state': 'on', 'friend': 'yes'});
    Net.p2pNode = () => node;
    final hub = PlainCarrier('hub');
    final app = AppState();
    await Net.instance.start(app, carriers: [hub]);
    final p2p = Net.instance.p2p!;
    await _until(() => p2p.loaded && p2p.card != null, 'what the direct network keeps was read');
    await Friends.instance.start(app);
    addTearDown(() async {
      await Friends.instance.shutdown();
      Friends.instance = null;
    });

    // The account's other device: a node of its own, whose card it tells through the account's own name.
    final other = mesh.node();
    await other.start(P2pConfig(secret: NetCrypto.randomBytes(32)));
    final card = await DeviceCard.make(KeysSigner(me), device: 'cd' * 16, nodeId: other.nodeId!, now: DateTime.now());
    final told = Envelope(kind: P2p.kind, body: {'t': 'card', 'c': card.toJson(), 'w': other.whereabouts.value!.toJson(), 'h': [p2p.card!.tag]}, ack: false);
    hub.take(Packet.wrap(from: me.id, sealed: true, payload: NetCrypto.seal(mineKey, told.encode())), from: me.id);
    await _until(() => p2p.ownDevices == 1, 'the account\'s other device is known');
    expect(p2p.friendsDevices, 0);
    // It answers a dial as the app's route does: its nonce, its proof once this device's has checked out, and then it
    // takes what comes.
    other.allow(p2p.nodeId!, {P2pChannel.packets});
    final ends = <HandEnd>[];
    other.opened.listen((s) => ends.add(HandEnd(s, linkKey: LinkWords.linkKey(mineKey), account: me.id, node: other.nodeId!, them: me.id)));
    List<Uint8List> taken() => [for (final e in ends) ...e.frames];

    // The relay can't be reached. A friend's words come all the same (by whatever way), and are copied on.
    hub.state.value = CarrierState.down;
    final byRelay = hub.to.length;
    final words_ = Envelope(kind: 'text', body: {'t': 'see you at 7'}, ack: false);
    hub.take(Packet.wrap(from: sam.id, sealed: true, payload: NetCrypto.seal(keyWith(sam), words_.encode())), from: sam.id);
    await _until(() => taken().isNotEmpty, 'the copy came straight to the other device');
    expect(ends.single.proved, isTrue, reason: 'this device proved it is the account\'s');
    final packet = Packet.parse(taken().single)!;
    expect([packet.from, packet.sealed], [me.id, true]);
    final copy = Envelope.decode(NetCrypto.open(mineKey, packet.payload)!)!;
    expect(copy.kind, Friends.copyKind);
    expect([copy.body['a'], copy.body['t'], copy.body['i'], copy.body['o']], ['@sam', 'see you at 7', words_.id, false]);
    expect(hub.to, hasLength(byRelay), reason: 'nothing went by the relay, which was away');
    expect(node.pathTo(other.nodeId!)!.kind, P2pPathKind.direct);
  });

  test('a device the account is gone from forgets its place on the direct network: the key, the cards and what was told', () async {
    Net.p2pNode = () => node;
    final hub = PlainCarrier('hub');
    final app = AppState();
    await Net.instance.start(app, carriers: [hub]);
    final p2p = Net.instance.p2p!;
    await _until(() => p2p.loaded && p2p.card != null && hub.to.length >= 2, 'read, and the friends told');
    final (_, packet) = await samsCard();
    hub.take(packet, from: sam.id);
    await _until(() => p2p.devicesOf(sam.id).isNotEmpty, 'Sam\'s card was taken');
    await p2p.up();
    await pumpEventQueue();
    for (final name in [P2p.idName, P2p.cardName, P2p.cardsName, P2p.toldName]) {
      expect(app.choice(name, ''), isNotEmpty, reason: name);
    }
    expect(secrets[P2p.keyName], isNotNull);

    // The relay says this device is no longer the account's (removed from another device): what signing out does too.
    final account = Account(relay: _Gone(), port: SmsAccountPort(), store: AppMeStore(app), profiles: AppAccountProfiles());
    app.set('acct_address', '0x52908400098527886E0F7030069857D2E4169EE7');
    await account.check();
    expect(account.signedIn, isFalse);
    expect(secrets.keys, isNot(contains(P2p.keyName)));
    for (final name in P2p.keptNames) {
      expect(app.choice(name, 'unset'), isEmpty, reason: name);
    }
    expect([p2p.loaded, p2p.card, p2p.nodeId, p2p.devicesOf(sam.id)], [false, null, null, isEmpty]);
    expect([node.state.value, node.allowed], [P2pState.off, isEmpty]);
    expect(p2p.carrier.reaches(Peer(id: sam.id, key: keyWith(sam))), isFalse);
  });

  test('where no routes were ever set up, signing out still deletes what the direct network kept', () async {
    final app = AppState()
      ..set(P2p.cardsName, '{"x":[]}')
      ..set(P2p.toldName, '{"x":{}}')
      ..set(P2p.idName, '{"n":"x"}')
      ..set(P2p.cardName, '{}')
      ..set('acct_address', '0x52908400098527886E0F7030069857D2E4169EE7');
    secrets[P2p.keyName] = 'ab' * 32;
    expect(Net.instance.p2p, isNull);
    final account = Account(relay: _Gone(), port: SmsAccountPort(), store: AppMeStore(app), profiles: AppAccountProfiles());
    await account.check();
    expect(secrets.keys, isNot(contains(P2p.keyName)));
    for (final name in P2p.keptNames) {
      expect(app.choice(name, 'unset'), isEmpty, reason: name);
    }
    expect(AccountCrypto.goodAddress('0x52908400098527886E0F7030069857D2E4169EE7'), isTrue);
  });
}

/// A relay that says this device is not the account's any more.
class _Gone implements AccountRelay {
  @override
  String get hubId => '';
  @override
  Future<Map<String, dynamic>> ask(Map<String, Object?> what) async => {'known': false};
}
