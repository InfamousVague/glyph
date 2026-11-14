import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/friends/groups.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/packet.dart';

import 'support/fake_groups.dart';

// Groups of friends (lib/friends/groups.dart) among phones that are not there: each has a stand-in for the routes
// and the phone (test/support/fake_groups.dart). Ann is friends with Ben, Cat and Dan; none of those three is a
// friend of another, so what passes between them passes because they are in a group together.

const ann = '+15550001', ben = '+15550002', cat = '+15550003', dan = '+15550004', eve = '+15550005';

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late World world;
  late Map<String, FakeGroupsPort> port;
  late Map<String, Groups> phone;

  setUp(() async {
    world = World();
    port = {for (final n in [ann, ben, cat, dan, eve]) n: FakeGroupsPort(world, n)};
    for (final n in [ben, cat, dan]) {
      port[ann]!.friends.add(n);
      port[n]!.friends.add(ann);
    }
    phone = {for (final e in port.entries) e.key: Groups(e.value)};
    for (final g in phone.values) {
      await g.start();
    }
  });

  tearDown(() async {
    for (final g in phone.values) {
      await g.shutdown();
    }
  });

  /// Ann's group "Crew" with Ben and Cat, everyone told.
  Future<String> crew() async {
    final g = await phone[ann]!.create('Crew', [ben, cat]);
    await settle();
    return g.id;
  }

  test('a group is made out of friends, and each of them has it', () async {
    final id = await crew();
    for (final n in [ann, ben, cat]) {
      final g = phone[n]!.of(id)!;
      expect(g.name, 'Crew', reason: n);
      expect(g.members.map((m) => m.address).toSet(), {if (n == ann) '' else ann, ben, cat}, reason: 'Ann\'s number is known to the others by her having sent it');
      expect(g.members.where((m) => m.admin).map((m) => m.id), [port[ann]!.me]);
      expect(g.mine!.id, port[n]!.me);
    }
    expect(phone[ann]!.of(id)!.amAdmin, isTrue);
    expect(phone[ben]!.of(id)!.amAdmin, isFalse);
    expect(port[ann]!.lines[id], ['* You made the group "Crew"']);
    expect(port[ben]!.lines[id], ['* $ann added you to "Crew"']);
    // It is its own conversation on each phone.
    expect(phone[ben]!.ofThread(phone[ben]!.of(id)!.thread)!.id, id);
  });

  test('what one member writes reaches the others, friends of theirs or not', () async {
    final id = await crew();
    expect(await phone[ben]!.sendText(id, 'Hike on Saturday?'), isTrue);
    await settle();
    expect(port[ann]!.lines[id]!.last, '$ben: Hike on Saturday?');
    expect(port[cat]!.lines[id]!.last, '$ben: Hike on Saturday?', reason: 'Ben and Cat never exchanged keys: the group is how they reach each other');
    expect(port[ben]!.rows.values.single, (group: id, words: 'Hike on Saturday?', state: 'sent'));
    // One envelope to each of the other two, of kind group.
    final texts = port[ben]!.sent.where((s) => s.envelope.body['do'] == 'text').toList();
    expect(texts.map((s) => s.to).toSet(), {port[ann]!.me, port[cat]!.me});
    expect(texts.every((s) => s.envelope.kind == 'group'), isTrue);
  });

  test('an admin names it; a member cannot, and a state from one is not taken', () async {
    final id = await crew();
    await phone[ann]!.rename(id, 'Weekend crew');
    await settle();
    expect(phone[cat]!.of(id)!.name, 'Weekend crew');
    expect(port[cat]!.lines[id]!.last, '* $ann named the group "Weekend crew"');
    expect(() => phone[ben]!.rename(id, 'Mine now'), throwsStateError);
    // Ben's phone says it anyway, as if it were an admin: nobody takes it.
    final forged = phone[ben]!.of(id)!.state(name: 'Mine now', v: 99, admins: [port[ben]!.me])..remove('id');
    await port[ben]!.send(port[ben]!.peer(port[cat]!.me)!, Envelope(kind: 'group', body: {'g': id, 'do': 'state', 's': forged}));
    await settle();
    expect(phone[cat]!.of(id)!.name, 'Weekend crew');
    expect(phone[cat]!.of(id)!.members.where((m) => m.admin).single.id, port[ann]!.me);
  });

  test('a member is added and another taken out', () async {
    final id = await crew();
    await phone[ann]!.add(id, dan);
    await settle();
    expect(phone[dan]!.of(id)!.members.length, 4);
    expect(port[dan]!.lines[id], ['* $ann added you to "Crew"']);
    expect(port[ben]!.lines[id]!.last, '* $ann added $dan');
    // Dan, a friend of Ann alone, now reaches Ben through the group.
    expect(await phone[dan]!.sendText(id, 'Hello all'), isTrue);
    await settle();
    expect(port[ben]!.lines[id]!.last, '$dan: Hello all');
    // Ben is taken out: his phone keeps the conversation and can write in it no more; nothing of his is taken.
    await phone[ann]!.remove(id, port[ben]!.me);
    await settle();
    expect(phone[ben]!.of(id)!.gone, isTrue);
    expect(port[ben]!.lines[id]!.last, '* $ann removed you');
    expect(port[cat]!.lines[id]!.last, '* $ann removed $ben');
    expect(phone[cat]!.of(id)!.member(port[ben]!.me), isNull);
    expect(await phone[ben]!.sendText(id, 'Still here?'), isFalse);
    final before = port[cat]!.lines[id]!.length;
    await port[ben]!.send(peerOf(port[cat]!), Envelope(kind: 'group', body: {'g': id, 'do': 'text', 't': 'Let me in'}));
    await settle();
    expect(port[cat]!.lines[id]!.length, before);
    // And he can be added again, by the friend who is its admin.
    await phone[ann]!.add(id, ben);
    await settle();
    expect(phone[ben]!.of(id)!.gone, isFalse);
    expect(port[ben]!.lines[id]!.last, '* $ann added you to "Crew"');
  });

  test('an admin makes another, who can then change the group', () async {
    final id = await crew();
    await phone[ann]!.setAdmin(id, port[cat]!.me, true);
    await settle();
    expect(phone[cat]!.of(id)!.amAdmin, isTrue);
    expect(port[ben]!.lines[id]!.last, '* $ann made $cat an admin');
    await phone[cat]!.rename(id, 'Cat\'s crew');
    await settle();
    expect(phone[ann]!.of(id)!.name, 'Cat\'s crew');
    expect(phone[ben]!.of(id)!.name, 'Cat\'s crew');
  });

  test('a member leaves; where the only admin leaves, the same member is made one on every phone', () async {
    final id = await crew();
    await phone[ben]!.leave(id);
    await settle();
    expect(phone[ben]!.of(id)!.gone, isTrue);
    expect(phone[ann]!.of(id)!.member(port[ben]!.me), isNull);
    expect(port[cat]!.lines[id]!.last, '* $ben left');
    await phone[ann]!.add(id, dan);
    await settle();
    await phone[ann]!.leave(id);
    await settle();
    final first = ([port[cat]!.me, port[dan]!.me]..sort()).first;
    expect(phone[cat]!.of(id)!.members.where((m) => m.admin).single.id, first);
    expect(phone[dan]!.of(id)!.members.where((m) => m.admin).single.id, first);
  });

  test('a group is joined only at a friend\'s asking, and an older state is not taken', () async {
    // Eve, nobody's friend, makes a group with Ben in it by hand and tells him: his phone does not take it.
    port[eve]!.friends.add(ben);
    final hers = await phone[eve]!.create('Free prizes', [ben]);
    await settle();
    expect(phone[ben]!.of(hers.id), isNull);
    // An admin's older word does not undo a newer one.
    final id = await crew();
    final old = phone[ann]!.of(id)!.state()..remove('id');
    await phone[ann]!.rename(id, 'Newer');
    await settle();
    await port[ann]!.send(port[ann]!.peer(port[ben]!.me)!, Envelope(kind: 'group', body: {'g': id, 'do': 'state', 's': old}));
    await settle();
    expect(phone[ben]!.of(id)!.name, 'Newer');
  });

  test('with no route up nothing is sent or kept; a member who is away is kept for and woken', () async {
    final id = await crew();
    port[ben]!.up = false;
    expect(await phone[ben]!.sendText(id, 'hello?'), isFalse);
    expect(port[ben]!.rows, isEmpty);
    expect(phone[ben]!.online, isFalse);
    port[ben]!.up = true;
    port[cat]!.here = false;
    expect(await phone[ben]!.sendText(id, 'Cat is away'), isTrue);
    await settle();
    expect(port[ben]!.woken, [port[cat]!.me]);
    expect(port[cat]!.lines[id]!.where((l) => l.contains('Cat is away')), isEmpty);
    port[cat]!.back();
    await settle();
    expect(port[cat]!.lines[id]!.last, '$ben: Cat is away');
  });
}

/// A phone as the routes name it, for sending to one by hand in a test.
Peer peerOf(FakeGroupsPort p) => Peer(id: p.me, address: p.number);
