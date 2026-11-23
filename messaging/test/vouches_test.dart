import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/friends/vouches.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/packet.dart';

import 'support/vouch_world.dart';

/// Vouches (GMFB-33; lib/friends/vouches.dart, docs/proofs.md): a friend's signed word that an account is who they say,
/// sent sealed to them, carried with their profile to their friends, and counted by a viewer only for the viewer's own
/// friends, checked against the keys the viewer holds. The installs are test/support/vouch_world.dart's.
void main() {
  test('a vouch reaches the friend, travels with their profile, and counts for a viewer whose friend gave it; taking it back is newest and stands against the old one sent again', () async {
    final w = VouchWorld();
    final maya = VouchPort(w, 'maya'), sam = VouchPort(w, 'sam'), theo = VouchPort(w, 'theo');
    final b = await makeFriends([(maya, sam), (maya, theo), (sam, theo)]);
    final mayaAtSam = b[sam]!.byId(maya.keys.id)!, mayaAtTheo = b[theo]!.byId(maya.keys.id)!;
    expect(b[theo]!.vouchersOf(mayaAtTheo), isEmpty);

    await b[sam]!.vouch(mayaAtSam);
    await pumpEventQueue();
    expect(b[sam]!.vouchedFor(mayaAtSam), isTrue);
    expect([for (final v in b[maya]!.vouchersOf(null)) v.username], ['sam'], reason: 'Maya holds Sam\'s vouch for her');
    expect([for (final v in b[theo]!.vouchersOf(mayaAtTheo)) v.username], ['sam'], reason: 'carried to Theo, whose friend Sam is');
    final sent = sam.sent.where((s) => s.envelope.kind == 'vouch').single;
    expect([sent.to, sent.sealed], [maya.keys.id, true]);
    // What Maya carried went sealed, and never in a request in the clear.
    expect(maya.sent.where((s) => s.envelope.body.containsKey('vo')).every((s) => s.sealed), isTrue);
    final oldVouch = sent.envelope;
    final oldCarried = maya.sent.lastWhere((s) => s.to == theo.keys.id && s.envelope.body['s'] == 'vo').envelope;

    await b[sam]!.vouch(mayaAtSam, on: false);
    await pumpEventQueue();
    expect([b[maya]!.vouchersOf(null), b[theo]!.vouchersOf(mayaAtTheo)], [isEmpty, isEmpty]);
    expect(b[sam]!.vouchedFor(mayaAtSam), isFalse);

    // Replays of the vouch from before it was taken back: Sam's own envelope to Maya, and Maya's old profile to Theo.
    sam.deliver(maya, oldVouch);
    maya.deliver(theo, oldCarried);
    await pumpEventQueue();
    expect(b[maya]!.vouchersOf(null), isEmpty, reason: 'the old vouch is older than its withdrawal');
    expect(b[theo]!.vouchersOf(mayaAtTheo), isEmpty, reason: 'Theo saw the withdrawal, and keeps it');
    for (final x in b.values) {
      x.dispose();
    }
  });

  test('a non-friend\'s vouch, and one forged in a friend\'s name, count for nobody', () async {
    final w = VouchWorld();
    final maya = VouchPort(w, 'maya'), sam = VouchPort(w, 'sam'), theo = VouchPort(w, 'theo'), mallory = VouchPort(w, 'mallory');
    final b = await makeFriends([(maya, sam), (maya, theo), (maya, mallory), (sam, theo)]);
    final mayaAtTheo = b[theo]!.byId(maya.keys.id)!;
    // Mallory is Maya's friend, not Theo's: Maya holds her vouch, Theo doesn't count it.
    await b[mallory]!.vouch(b[mallory]!.byId(maya.keys.id)!);
    await pumpEventQueue();
    expect([for (final v in b[maya]!.vouchersOf(null)) v.username], ['mallory']);
    expect(b[theo]!.vouchersOf(mayaAtTheo), isEmpty);

    // Mallory signs a vouch in Sam's name (Sam is Theo's friend) and gets it to Theo in Maya's profile.
    final t = DateTime.now().millisecondsSinceEpoch;
    final forged = Vouch(by: sam.keys.id, forId: maya.keys.id, on: true, t: t, sig: NetCrypto.sign(mallory.keys, Vouch.signedBytes(by: sam.keys.id, forId: maya.keys.id, forKey: maya.key, on: true, t: t)));
    maya.deliver(theo, Envelope(kind: 'buddy', body: {'s': 'vo', 'vo': [forged.carried()]}));
    await pumpEventQueue();
    expect(b[theo]!.vouchersOf(mayaAtTheo), isEmpty, reason: 'it isn\'t Sam\'s signature');
    // Nor does Maya take it from Mallory as Sam's.
    mallory.deliver(maya, Envelope(kind: 'vouch', body: forged.toJson()));
    await pumpEventQueue();
    expect([for (final v in b[maya]!.vouchersOf(null)) v.username], ['mallory']);
    for (final x in b.values) {
      x.dispose();
    }
  });

  test('a vouch is for a key: someone under the same name with a new key carries none of it', () async {
    final w = VouchWorld();
    // Maya, and Maya's new install: the same username, another key, friends with Theo too.
    final maya = VouchPort(w, 'maya'), maya2 = VouchPort(w, 'maya'), sam = VouchPort(w, 'sam'), theo = VouchPort(w, 'theo');
    final b = await makeFriends([(maya, sam), (maya, theo), (sam, theo), (maya2, theo)]);
    await b[sam]!.vouch(b[sam]!.byId(maya.keys.id)!);
    await pumpEventQueue();
    final carried = maya.sent.lastWhere((s) => s.to == theo.keys.id && s.envelope.body['s'] == 'vo').envelope;
    // The new install says it holds the old key's vouches.
    maya2.deliver(theo, carried);
    await pumpEventQueue();
    expect(b[theo]!.vouchersOf(b[theo]!.byId(maya2.keys.id)), isEmpty);
    expect(b[theo]!.vouchersOf(b[theo]!.byId(maya.keys.id)).length, 1, reason: 'the old key still has it');
    for (final x in b.values) {
      x.dispose();
    }
  });

  test('hidden, the vouches go from friends\' view; removing a friend drops their vouch', () async {
    final w = VouchWorld();
    final maya = VouchPort(w, 'maya'), sam = VouchPort(w, 'sam'), theo = VouchPort(w, 'theo');
    final b = await makeFriends([(maya, sam), (maya, theo), (sam, theo)]);
    final mayaAtTheo = b[theo]!.byId(maya.keys.id)!;
    await b[sam]!.vouch(b[sam]!.byId(maya.keys.id)!);
    await pumpEventQueue();
    expect(b[theo]!.vouchersOf(mayaAtTheo).length, 1);
    await b[maya]!.hideVouches(true);
    await pumpEventQueue();
    expect(b[theo]!.vouchersOf(mayaAtTheo), isEmpty);
    expect(b[maya]!.vouchersOf(null).length, 1, reason: 'still hers to see');
    await b[maya]!.hideVouches(false);
    await pumpEventQueue();
    expect(b[theo]!.vouchersOf(mayaAtTheo).length, 1);

    await b[maya]!.remove(b[maya]!.byId(sam.keys.id)!);
    await pumpEventQueue();
    expect(b[maya]!.vouchersOf(null), isEmpty);
    expect(b[maya]!.vouches.held, isEmpty);
    expect(b[theo]!.vouchersOf(mayaAtTheo), isEmpty, reason: 'her friends are told she holds it no more');
    expect(b[sam]!.vouchedFor(mayaAtTheo), isFalse, reason: 'she ended it with Sam, who forgets his vouch');
    for (final x in b.values) {
      x.dispose();
    }
  });

  test('what a profile carries is bounded, kept apart from the list the phone reads keys from, and survives a restart', () async {
    final store = <String, String>{};
    Vouches make() => Vouches(read: (k) => store[k] ?? '', write: (k, v) => store[k] = v);
    final me = NetKeys.generate(), friend = NetKeys.generate();
    final v = make()..load(me.id);
    // 500 vouches for a friend from 500 others: no more than 2 × 64 are read, and 64 kept.
    final many = [
      for (var i = 0; i < 500; i++) {'b': NetCrypto.hex(NetCrypto.sha256([i]).sublist(0, 16)), 't': 1000 + i, 's': base64Encode(List.filled(64, 1))},
    ];
    v.tookCarried(friend.id, many);
    expect(v.carried[friend.id]!.length, Vouches.most);
    // A malformed one, or one with a huge signature, is passed over.
    v.tookCarried('b' * 32, [{'b': 'x', 't': 1, 's': ''}, {'b': 'c' * 32, 't': 1, 's': 'A' * 400}]);
    expect(v.carried['b' * 32] ?? const {}, isEmpty);

    // Kept: read back after a restart.
    final again = make()..load(me.id);
    expect(again.carried[friend.id]!.length, Vouches.most);

    // A word made with a clock that went back is still later than the one before it.
    var clock = 5000;
    final mine = Vouches.inMemory(now: () => clock);
    final first = await mine.make(me: me.id, forId: friend.id, forKey: base64Encode(friend.public), on: true, sign: (m) async => NetCrypto.sign(me, m));
    clock = 10;
    final back = await mine.make(me: me.id, forId: friend.id, forKey: base64Encode(friend.public), on: false, sign: (m) async => NetCrypto.sign(me, m));
    expect(back.t, greaterThan(first.t));
    expect(back.checks(byKey: base64Encode(me.public), forKey: base64Encode(friend.public)), isTrue);
  });

  test('the friends list the phone keeps is unchanged by vouches, and an envelope of a kind or step it doesn\'t know changes nothing', () async {
    final w = VouchWorld();
    final maya = VouchPort(w, 'maya'), sam = VouchPort(w, 'sam');
    final b = await makeFriends([(maya, sam)]);
    await pumpEventQueue();
    final before = maya.list;
    await b[sam]!.vouch(b[sam]!.byId(maya.keys.id)!);
    await pumpEventQueue();
    expect(maya.list, before, reason: 'held apart, so the phone\'s list (and every build that reads it) is the same');
    // A build from before carried no `vo`: what is held of them stays as it was.
    sam.deliver(maya, Envelope(kind: 'buddy', body: {'s': 'me', 'n': 'Sam'}));
    sam.deliver(maya, Envelope(kind: 'buddy', body: {'s': 'whatever'}));
    await pumpEventQueue();
    expect(b[maya]!.vouchersOf(null).length, 1);
    expect(b[maya]!.friends.single.name, 'Sam');
    for (final x in b.values) {
      x.dispose();
    }
  });
}
