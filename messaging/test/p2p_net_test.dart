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

import 'support/direct_world.dart' show PlainCarrier;
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
  late FakeP2pMesh mesh;
  late FakeP2pNode node;

  setUp(() {
    HttpOverrides.global = null;
    secrets = {};
    peers = [
      {'id': sam.id, 'address': '@sam', 'key': keyWith(sam)},
      {'id': nell.id, 'address': '+1 (555) 000-0001', 'key': keyWith(nell)},
      {'id': asker.id, 'address': '', 'key': keyWith(asker)},
      {'id': member.id, 'address': '+15550000002', 'key': keyWith(member)},
    ];
    e2e = [
      {'address': '+15550000001', 'state': 'on', 'friend': 'yes'},
      {'address': '+15550000002', 'state': 'on', 'friend': ''},
    ];
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
          return e2e;
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

    // Back on the screen: the node, where it is up, looks at its paths again.
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
    // It answers a dial as the app's route does: its proof for this device's, then it takes what comes.
    other.allow(p2p.nodeId!, {P2pChannel.packets});
    final linkKey = NetCrypto.derive(mineKey, 'p2p link');
    Uint8List proof(String from, String to) => Uint8List.fromList([0, 1, ...NetCrypto.hmac(linkKey, [...utf8.encode('ghost-p2p link v1\n'), ...NetCrypto.unhex(from), ...NetCrypto.unhex(to)])]);
    final taken = <Uint8List>[];
    other.opened.listen((s) {
      var proved = false;
      s.frames.listen((f) {
        if (proved) return taken.add(f);
        proved = true;
        expect(f, proof(p2p.nodeId!, other.nodeId!), reason: 'this device proves it is the account\'s');
        s.add(proof(other.nodeId!, p2p.nodeId!));
      });
    });

    // The relay can't be reached. A friend's words come all the same (by whatever way), and are copied on.
    hub.state.value = CarrierState.down;
    final byRelay = hub.to.length;
    final words_ = Envelope(kind: 'text', body: {'t': 'see you at 7'}, ack: false);
    hub.take(Packet.wrap(from: sam.id, sealed: true, payload: NetCrypto.seal(keyWith(sam), words_.encode())), from: sam.id);
    await _until(() => taken.isNotEmpty, 'the copy came straight to the other device');
    final packet = Packet.parse(taken.single)!;
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
