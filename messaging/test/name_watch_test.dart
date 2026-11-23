import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/name_watch.dart';
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_relay/handles.dart' show Handles;

import 'support/direct_world.dart';
import 'support/fake_p2p.dart';

/// The name watch (lib/net/name_watch.dart; docs/OPEN_NETWORK.md, section 3): the relay's "@name is this key" checked by
/// asking it again, each friend's username once a day and this person's own at each sign-in, needing no direct route.
/// A relay that gives a friend's username to another key is shown on that friend, who is told by every route; it
/// never changes who a friend is.

/// The relay's directory of usernames, as a test makes it answer: who holds each, and every question asked of it.
class _Directory {
  _Directory(this.clock);
  final FakeClock clock;
  final names = <String, NetKeys>{};
  final asked = <({String name, int at})>[];
  bool down = false;

  Future<({String id, String key})?> whois(String name) async {
    asked.add((name: name, at: clock.ms));
    if (down) throw StateError('The relay server can\'t be reached right now.');
    final k = names[name];
    return k == null ? null : (id: k.id, key: base64Encode(k.public));
  }
}

/// [i]'s name watch, as the app makes it (lib/people.dart): its username, its friends by username as added, the
/// directory's answers, and a friend told by every route of [i]'s switchboard; and the envelopes of its kind that come
/// to [i] heard by it.
NameWatch _watchOf(World w, Install i, String username, Map<String, Account> friends, _Directory dir, {Map<String, String>? kept}) {
  final store = kept ?? <String, String>{};
  final watch = NameWatch(
    me: () => i.account.id,
    username: () => username,
    friends: () => [for (final e in friends.entries) WatchedName(e.key, e.value.id, base64Encode(e.value.keys.public))],
    whois: dir.whois,
    tell: (id, e) async {
      final peer = i.byId(id);
      if (peer != null) await i.board.sendEveryWay(peer, e);
    },
    read: (name) => store[name] ?? '',
    write: (name, value) => store[name] = value,
    now: w.clock.now,
    timer: w.clock.timer,
  );
  i.board.received.listen((r) {
    if (r.envelope.kind == NameWatch.kind) watch.heard(r.peer.id, r.envelope, sealed: r.sealed);
  });
  return watch;
}

void main() {
  late World w;
  setUp(() => w = World());
  tearDown(() => w.stop());

  test('a friend\'s username the relay now gives to another key: shown on that friend, the friend told by every route, their app saying so, and the friend still the key that was added', () async {
    final maya = w.account('maya'), sam = w.account('sam'), mallory = w.account('mallory');
    final a = w.install(maya, computer: true), b = w.install(sam, computer: true);
    w.friends(a, b);
    await a.start();
    await b.start();
    final dir = _Directory(w.clock)
      ..names['maya'] = maya.keys
      ..names['sam'] = sam.keys;
    final wa = _watchOf(w, a, 'maya', {'sam': sam}, dir), wb = _watchOf(w, b, 'sam', {'maya': maya}, dir);
    final toldAt = <int>[];
    b.board.received.listen((r) {
      if (r.envelope.kind == NameWatch.kind) toldAt.add(w.clock.ms);
    });
    wa.start();
    wb.start();
    // Each friend's username is asked within the day, and the relay gives the keys that were added.
    await w.clock.pass(const Duration(days: 1));
    expect(dir.asked.map((x) => x.name).toSet(), {'sam', 'maya'});
    expect([wa.changeFor(sam.id), wb.changeFor(maya.id), wb.toldMe], [isNull, isNull, isEmpty]);

    // The relay now gives @sam to another key, and drops what Maya's computer sends Sam's through it: she is told by
    // the direct route too, so it reaches him all the same.
    dir.names['sam'] = mallory.keys;
    b.pair!.dropToApp = (said) => said is List<int> && said.isNotEmpty && said[0] == 1;
    await w.clock.pass(const Duration(days: 1));
    final change = wa.changeFor(sam.id)!;
    expect([change.username, change.other], ['sam', mallory.id]);
    expect(wa.changes.single.friend, sam.id);
    await w.until(() => wb.toldMe.isNotEmpty, 'Sam\'s app told');
    expect(b.pair!.dropped, greaterThan(0), reason: 'the relay dropped its copy');
    final told = [for (final r in b.got) if (r.envelope.kind == NameWatch.kind) r];
    expect([for (final r in told) [r.via, r.sealed, r.peer.id]], [['p2p', true, maya.id]]);
    expect([wb.toldMe.single.by, wb.toldMe.single.other, wb.toldMe.single.username], [maya.id, mallory.id, 'sam']);
    expect(wb.notice.value?.by, maya.id, reason: 'said at once');
    b.pair!.dropToApp = null;

    // Nothing changes who Sam is to Maya: what she sends is sealed for his key and reaches his computer.
    expect((await a.text(sam, 'still you')).acked, isTrue);
    expect(b.texts, contains('still you'));
    // Told again while it lasts, once a day at most.
    await w.clock.pass(const Duration(days: 3));
    expect(toldAt.length, inInclusiveRange(3, 4));
    for (var i = 1; i < toldAt.length; i++) {
      // (The first came by the direct route after the relay's copy was waited on four seconds.)
      expect(toldAt[i] - toldAt[i - 1], greaterThanOrEqualTo(NameWatch.tellEvery.inMilliseconds - 5000));
    }
    // The relay gives @sam to his key again: the word on him goes.
    dir.names['sam'] = sam.keys;
    await w.clock.pass(const Duration(days: 1));
    expect(wa.changeFor(sam.id), isNull);
  });

  test('its own username asked at each sign-in, at most every ten minutes: given to another key, shown at once; a friend\'s word taken only for this username and another key, from a friend, sealed, once an hour', () async {
    final clock = FakeClock();
    final maya = NetKeys.generate(), sam = NetKeys.generate(), mallory = NetKeys.generate(), stranger = NetKeys.generate();
    final dir = _Directory(clock)..names['maya'] = mallory;
    final kept = <String, String>{};
    final watch = NameWatch(
      me: () => maya.id,
      username: () => 'maya',
      friends: () => [WatchedName('sam', sam.id, base64Encode(sam.public))],
      whois: dir.whois,
      tell: (_, _) async {},
      read: (name) => kept[name] ?? '',
      write: (name, value) => kept[name] = value,
      now: clock.now,
      timer: clock.timer,
    )..start();
    final shown = <NameChange?>[];
    watch.notice.addListener(() => shown.add(watch.notice.value));
    await watch.signedIn();
    expect([watch.own?.username, watch.own?.other, shown.single?.other], ['maya', mallory.id, mallory.id]);
    final asked = dir.asked.length;
    await clock.pass(const Duration(minutes: 9));
    await watch.signedIn();
    expect(dir.asked.length, asked, reason: 'not again inside ten minutes');
    await clock.pass(_minute);
    dir.names['maya'] = maya;
    await watch.signedIn();
    expect([dir.asked.length, watch.own], [asked + 1, isNull], reason: 'its own key again: the warning goes');

    Envelope said(String u, String i) => Envelope(kind: NameWatch.kind, body: {'u': u, 'i': i, 'at': clock.ms});
    watch.heard(stranger.id, said('maya', mallory.id));
    watch.heard(sam.id, said('someone', mallory.id));
    watch.heard(sam.id, said('maya', maya.id));
    watch.heard(sam.id, said('maya', mallory.id), sealed: false);
    watch.heard(sam.id, said('maya', 'not a name'));
    expect(watch.toldMe, isEmpty);
    watch.heard(sam.id, said('@Maya', mallory.id));
    expect([watch.toldMe.single.by, watch.toldMe.single.other, shown.last?.by], [sam.id, mallory.id, sam.id]);
    watch.heard(sam.id, said('maya', stranger.id));
    expect(watch.toldMe.single.other, mallory.id, reason: 'once an hour from one friend');
    // Kept with the choices; a week on, it is shown no more.
    final again = NameWatch(me: () => maya.id, username: () => 'maya', friends: () => [WatchedName('sam', sam.id, base64Encode(sam.public))], whois: dir.whois, tell: (_, _) async {}, read: (name) => kept[name] ?? '', write: (name, value) => kept[name] = value, now: clock.now, timer: clock.timer)..start();
    expect(again.toldMe.single.by, sam.id);
    await clock.pass(const Duration(days: 7));
    expect(again.toldMe, isEmpty);
    watch.dispose();
    again.dispose();
  });

  test('the lookups are spread through the day, each friend once, never more than so many an hour or closer than a minute, well inside the relay\'s limit; and a relay that can\'t be reached is asked again ten minutes on, not at once', () async {
    expect(NameWatch.mostAnHour, lessThanOrEqualTo(Handles.lookupsAnHour ~/ 4), reason: 'most of the relay\'s lookups are left to the person');
    final clock = FakeClock();
    final dir = _Directory(clock);
    final friends = [for (var i = 0; i < 300; i++) WatchedName('friend$i', NetCrypto.hex(NetCrypto.randomBytes(16)), 'k')];
    final kept = <String, String>{};
    NameWatch make() => NameWatch(me: () => 'a' * 32, username: () => null, friends: () => friends, whois: dir.whois, tell: (_, _) async {}, read: (name) => kept[name] ?? '', write: (name, value) => kept[name] = value, now: clock.now, timer: clock.timer);
    final watch = make()..start();
    final start = clock.ms;
    await clock.pass(const Duration(hours: 26));
    final times = [for (final x in dir.asked) x.at];
    // Each friend asked, and none twice in the first day, nor within a day of the last time.
    expect(dir.asked.map((x) => x.name).toSet(), hasLength(300));
    final firstDay = [for (final x in dir.asked) if (x.at - start < const Duration(days: 1).inMilliseconds) x.name];
    expect(firstDay.toSet().length, firstDay.length);
    final last = <String, int>{};
    for (final x in dir.asked) {
      if (last[x.name] != null) expect(x.at - last[x.name]!, greaterThanOrEqualTo(const Duration(days: 1).inMilliseconds));
      last[x.name] = x.at;
    }
    // Never closer than a minute, never more than so many in any hour.
    for (var i = 1; i < times.length; i++) {
      expect(times[i] - times[i - 1], greaterThanOrEqualTo(NameWatch.gap.inMilliseconds));
    }
    for (final t in times) {
      expect(times.where((u) => u >= t && u - t < const Duration(hours: 1).inMilliseconds).length, lessThanOrEqualTo(NameWatch.mostAnHour));
    }
    // Spread through the day, not all at once: some in each of its hours.
    for (var h = 0; h < 24; h++) {
      expect(times.any((t) => t - start >= h * 3600000 && t - start < (h + 1) * 3600000), isTrue, reason: 'hour $h');
    }
    expect(watch.askedInDay, greaterThan(250));
    // Started again on the same choices, nobody is asked at once: each is due a day after it was last asked.
    watch.dispose();
    final again = make()..start();
    final before = dir.asked.length;
    await clock.pass(const Duration(minutes: 30));
    expect(dir.asked.length - before, lessThanOrEqualTo(30 ~/ NameWatch.gap.inMinutes + 1));
    // The relay can't be reached: asked again ten minutes on each time, not at once.
    dir.down = true;
    final downAt = dir.asked.length;
    await clock.pass(const Duration(hours: 2));
    expect(dir.asked.length - downAt, lessThanOrEqualTo(13));
    again.dispose();
  });
}

const _minute = Duration(minutes: 1);
