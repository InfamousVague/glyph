import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/friends/buddies.dart';
import 'package:ghost_messaging/me/me.dart' show Me, MeError;
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/name_watch.dart';
import 'package:ghost_messaging/net/p2p/p2p.dart' show P2pPolicy;
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_messaging/people.dart' show quietly;
import 'package:ghost_relay/handles.dart' show Handles;

import 'support/direct_world.dart';
import 'support/fake_p2p.dart';

/// The name watch (lib/net/name_watch.dart; docs/OPEN_NETWORK.md, section 3): the relay's "@name is this key" checked by
/// asking it again, each friend's username once a day and this person's own at each sign-in, needing no direct route.
/// After the review (2026-11-23): each relay is its own directory, and another account under a friend's username is
/// said only where that relay named their key under it before; a friend who changed their username is followed; this
/// person's own username is said calmly and once, with what usually causes it; the account's devices share the relay's
/// lookups. The reviewer's probes 1-4 and 8 are here, turned round: each holds the fixed behaviour.

const _day = Duration(days: 1);
const _relay = 'wss://memory.test/hub';

/// The relay's directory of usernames, as a test makes it answer: who holds each, which name a key holds (the relay's
/// `name` question), and every question asked of it.
class _Directory {
  _Directory(this.clock);
  final FakeClock clock;
  final names = <String, NetKeys>{};
  final asked = <({String name, int at})>[];
  bool down = false, refuses = false;

  /// Answers held until a test lets them go.
  Completer<void>? hold;

  Future<({String id, String key})?> whois(String name) async {
    asked.add((name: name, at: clock.ms));
    if (refuses) throw MeError('Too many lookups. Try again in a while.');
    if (down) throw StateError('The relay server can\'t be reached right now.');
    final h = hold;
    if (h != null) await h.future;
    final k = names[name];
    return k == null ? null : (id: k.id, key: base64Encode(k.public));
  }

  /// Which username [keys] holds here: the name's hash (Me.nameKeyOf), or null.
  String? heldBy(NetKeys keys) {
    for (final e in names.entries) {
      if (e.value.id == keys.id) return Me.nameKeyOf(e.key);
    }
    return null;
  }
}

/// [i]'s name watch, as the app makes it (lib/people.dart): its username, its friends by username as added, the
/// directory's answers, a friend told by the relay and by an open direct link (Switchboard.sendEveryWay); and the
/// envelopes of its kind that come to [i] heard by it.
NameWatch _watchOf(World w, Install i, String username, Map<String, Account> friends, _Directory dir, {Map<String, String>? kept}) {
  final store = kept ?? <String, String>{};
  final watch = NameWatch(
    me: () => i.account.id,
    username: () => username,
    friends: () => [for (final e in friends.entries) WatchedName(e.key, e.value.id, base64Encode(e.value.keys.public))],
    whois: dir.whois,
    held: () async => dir.heldBy(i.account.keys),
    relay: () => _relay,
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

/// A watch with no installs under it: its own clock, the directory, and what it keeps.
NameWatch _bare(FakeClock clock, _Directory dir, {required String me, String? Function()? username, List<WatchedName> Function()? friends, Map<String, String>? kept, String Function()? relay, Future<String?> Function()? held, ({int index, int of}) Function()? share, List<(String, Envelope)>? told}) {
  final store = kept ?? <String, String>{};
  return NameWatch(
    me: () => me,
    username: username ?? () => null,
    friends: friends ?? () => const [],
    whois: dir.whois,
    held: held,
    relay: relay ?? () => _relay,
    share: share,
    tell: (id, e) async => told?.add((id, e)),
    read: (name) => store[name] ?? '',
    write: (name, value) => store[name] = value,
    now: clock.now,
    timer: clock.timer,
  )..start();
}

WatchedName _friend(String username, NetKeys keys) => WatchedName(username, keys.id, base64Encode(keys.public));

/// Friends by username over the directory: what this phone asks of the relay, and what friends send it sealed.
class _Port implements BuddiesPort {
  _Port(this.dir, this.keys);
  final _Directory dir;
  final NetKeys keys;
  String list = '[]';
  final sealed = StreamController<({String from, Envelope envelope})>.broadcast();
  @override
  Future<({String id, String key})> me() async => (id: keys.id, key: base64Encode(keys.public));
  @override
  String? get username => 'sam';
  @override
  String get displayName => 'Sam';
  @override
  String get bio => '';
  @override
  Future<({String id, String key})?> whois(String username) => dir.whois(username);
  @override
  Future<void> keep(String json) async => list = json;
  @override
  Future<String> kept() async => list;
  @override
  Future<bool> send(String id, Envelope envelope, {bool sealed = true}) async => true;
  @override
  Stream<({String from, Envelope envelope})> get received => sealed.stream;
  @override
  Stream<({String from, Envelope envelope})> get greetings => const Stream.empty();
}

void main() {
  late World w;
  setUp(() => w = World());
  tearDown(() => w.stop());

  test('a friend\'s username the relay now gives to another account, once it named their key: shown on them, the friend told by the relay and by an open direct link and never by a dial, and cleared when nobody holds it', () async {
    final maya = w.account('maya'), sam = w.account('sam'), mallory = w.account('mallory');
    // Computers whose direct links stay open while nothing is said on them for days: a link open when the word goes.
    const open = P2pPolicy(stayUp: true, quiet: Duration(days: 4));
    final a = w.install(maya, policy: open), b = w.install(sam, policy: open);
    w.friends(a, b);
    await a.start();
    await b.start();
    final dir = _Directory(w.clock)
      ..names['maya'] = maya.keys
      ..names['sam'] = sam.keys;
    final wa = _watchOf(w, a, 'maya', {'sam': sam}, dir), wb = _watchOf(w, b, 'sam', {'maya': maya}, dir);
    wa.start();
    wb.start();
    // Within the day each is asked, and the relay names the keys that were added: confirmed there.
    await w.clock.pass(_day);
    expect(dir.asked.map((x) => x.name).toSet(), {'sam', 'maya'});
    expect([wa.changeFor(sam.id), wb.toldMe], [isNull, isEmpty]);

    // The relay now gives @sam to another account, and drops what reaches Sam's computer through it. No direct link is
    // open: the word goes by the relay alone, and nothing is dialled for it (D8).
    dir.names['sam'] = mallory.keys;
    b.pair!.dropToApp = (said) => said is List<int> && said.isNotEmpty && said[0] == 1;
    final dials = w.mesh.dials.length;
    await w.clock.pass(_day);
    final change = wa.changeFor(sam.id)!;
    expect([change.username, change.other, change.kind], ['sam', mallory.id, NameKind.friend]);
    expect(w.mesh.dials.length, dials, reason: 'nothing dialled for the name watch');
    expect(wb.toldMe, isEmpty, reason: 'the relay dropped it, and no link was open');
    // With a link open, the next day's word goes by it too, and reaches him.
    b.pair!.dropToApp = null;
    expect((await a.text(sam, 'a link', only: {'p2p'})).acked, isTrue);
    b.pair!.dropToApp = (said) => said is List<int> && said.isNotEmpty && said[0] == 1;
    await w.clock.pass(_day);
    expect(a.p2p.carrier.linked(a.to(sam)), isTrue);
    expect([wb.toldMe.single.by, wb.toldMe.single.other, wb.toldMe.single.kind], [maya.id, mallory.id, NameKind.told]);
    expect([for (final r in b.got) if (r.envelope.kind == NameWatch.kind) '${r.via} ${r.sealed}'], ['p2p true']);
    expect(wb.notice.value?.by, maya.id, reason: 'said at once, the first time');
    b.pair!.dropToApp = null;
    // Nothing changes who Sam is to Maya.
    expect((await a.text(sam, 'still you')).acked, isTrue);
    // Nobody holds @sam now: the word on him goes (M2).
    dir.names.remove('sam');
    await w.clock.pass(_day);
    expect(wa.changeFor(sam.id), isNull);
    wa.dispose();
    wb.dispose();
  });

  test('PROBE 1, fixed: a friend who changed their username is followed once the relay names their key for the new one, and a stranger taking the old one says nothing; unfollowed, what is said goes when nobody holds the name', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final me = NetKeys.generate(), maya = NetKeys.generate(), stranger = NetKeys.generate();
    dir.names['maya'] = maya;
    final told = <(String, Envelope)>[];
    final friends = [_friend('maya', maya)];
    final w1 = _bare(clock, dir, me: me.id, username: () => 'sam', friends: () => friends, told: told);
    await clock.pass(_day);
    expect(w1.changeFor(maya.id), isNull);
    // Maya changes to @maya.k (the relay lets @maya go) and says so in her sealed profile.
    dir.names
      ..remove('maya')
      ..['maya.k'] = maya;
    w1.saidName(maya.id, 'Maya.K');
    await clock.pass(const Duration(minutes: 2));
    expect(dir.asked.last.name, 'maya.k', reason: 'looked up before it is taken');
    final before = dir.asked.where((x) => x.name == 'maya').length;
    // A stranger takes @maya: nothing is said, and @maya is asked about no more.
    dir.names['maya'] = stranger;
    await clock.pass(const Duration(days: 3));
    expect([w1.changeFor(maya.id), told], [isNull, isEmpty]);
    expect(dir.asked.where((x) => x.name == 'maya').length, before);
    expect(dir.asked.where((x) => x.name == 'maya.k').length, greaterThanOrEqualTo(3));
    // A name a friend says that the relay gives to someone else is not taken.
    final followed = dir.asked.where((x) => x.name == 'maya.k').length;
    w1.saidName(maya.id, 'maya');
    await clock.pass(const Duration(hours: 2));
    expect(dir.asked.last.name, 'maya');
    await clock.pass(_day);
    expect(dir.asked.where((x) => x.name == 'maya.k').length, greaterThan(followed), reason: 'still asked about @maya.k');
    w1.dispose();

    // Not followed (she said nothing): the stranger's @maya is said, and goes once nobody holds it.
    dir.names['maya'] = maya;
    final w2 = _bare(clock, dir, me: me.id, username: () => 'sam', friends: () => friends, kept: {});
    await clock.pass(_day);
    dir.names['maya'] = stranger;
    await clock.pass(_day);
    expect(w2.changeFor(maya.id)?.other, stranger.id);
    dir.names.remove('maya');
    await clock.pass(_day);
    expect(w2.changeFor(maya.id), isNull, reason: 'nobody holds it: nothing is said');
    w2.dispose();
  });

  test('PROBE 3, fixed: another relay is another directory: nobody\'s username is said to be someone else\'s there until that relay has named their key under it, and its own is not asked where it was never held', () async {
    final clock = FakeClock();
    final home = _Directory(clock), other = _Directory(clock);
    final me = NetKeys.generate(), maya = NetKeys.generate(), someone = NetKeys.generate(), someone2 = NetKeys.generate();
    home.names['maya'] = maya;
    home.names['sam'] = me;
    other.names['maya'] = someone;
    other.names['sam'] = someone2;
    var dir = home, relay = 'wss://gogho.st/hub';
    final w1 = NameWatch(
      me: () => me.id,
      username: () => 'sam',
      friends: () => [_friend('maya', maya)],
      whois: (n) => dir.whois(n),
      held: () async => dir.heldBy(me),
      relay: () => relay,
      tell: (_, _) async {},
      read: (_) => '',
      write: (_, _) {},
      now: clock.now,
      timer: clock.timer,
    )..start();
    await w1.signedIn();
    await clock.pass(_day);
    expect([w1.changeFor(maya.id), w1.own], [isNull, isNull]);
    // A relay of one's own, chosen in Settings › Routes.
    dir = other;
    relay = 'wss://relay.example/hub';
    await clock.pass(const Duration(minutes: 11));
    await w1.signedIn();
    await clock.pass(_day);
    expect([w1.changeFor(maya.id), w1.own], [isNull, isNull]);
    expect(other.asked.where((x) => x.name == 'sam'), isEmpty, reason: 'never held there: not asked');
    expect(other.asked.where((x) => x.name == 'maya'), isNotEmpty, reason: 'asked, and nothing said');
    // Back on the relay it was found on, it is still watched there.
    dir = home;
    relay = 'wss://gogho.st/hub';
    home.names['maya'] = someone;
    await clock.pass(const Duration(days: 2));
    expect(w1.changeFor(maya.id)?.other, someone.id);
    w1.dispose();
  });

  test('PROBE 4, fixed: someone kept under a username they only claimed (the relay never named their key for it) is told nothing, and nothing is said of them', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final me = NetKeys.generate(), alice = NetKeys.generate(), mallory = NetKeys.generate();
    dir.names['alice'] = alice;
    final told = <(String, Envelope)>[];
    final w1 = _bare(clock, dir, me: me.id, username: () => 'sam', friends: () => [_friend('alice', mallory)], told: told);
    await clock.pass(const Duration(days: 2));
    expect([w1.changeFor(mallory.id), told], [isNull, isEmpty], reason: 'the real holder\'s id is told to no one');
    w1.dispose();
  });

  test('an add that found them under the name is what the relay is held to: the first daily answer naming another account is said', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final me = NetKeys.generate(), maya = NetKeys.generate(), mallory = NetKeys.generate();
    final w1 = _bare(clock, dir, me: me.id, username: () => 'sam', friends: () => [_friend('maya', maya)]);
    // Buddies.add looked her up and the relay named her key: the watch is told (no lookup of its own).
    w1.confirmed(maya.id, 'maya');
    dir.names['maya'] = mallory;
    await clock.pass(const Duration(hours: 25));
    expect(w1.changeFor(maya.id)?.other, mallory.id);
    expect(dir.asked.where((x) => x.name == 'maya'), hasLength(1), reason: 'first asked a day after the add');
    w1.dispose();
  });

  test('friends by username tell the watch: an add that found them is what the relay is held to, and a new username they say in their sealed profile is looked up', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final me = NetKeys.generate(), maya = NetKeys.generate(), mallory = NetKeys.generate();
    dir.names['maya'] = maya;
    final port = _Port(dir, me);
    final buddies = Buddies(port);
    await buddies.start();
    final watch = NameWatch.instance = _bare(clock, dir, me: me.id, username: () => 'sam', friends: () => [for (final b in buddies.friends) WatchedName(b.username, b.id, b.key)]);
    addTearDown(() => NameWatch.instance = null);
    // As the app has it (lib/people.dart): the friends changing, the watch plans again.
    buddies.addListener(watch.friendsChanged);
    await buddies.add('maya');
    // She says yes: a friend now, under the name the add found her by.
    port.sealed.add((from: maya.id, envelope: Envelope(kind: 'buddy', body: {'s': 'yes', 'u': 'maya', 'n': 'Maya'})));
    await clock.settle();
    expect(buddies.friends.single.username, 'maya');
    final asked = dir.asked.length;
    dir.names['maya'] = mallory;
    await clock.pass(const Duration(hours: 25));
    expect(watch.changeFor(maya.id)?.other, mallory.id, reason: 'held to what the add found');
    expect(dir.asked.length - asked, 1);
    // She says, sealed, that she goes by @maya.k now: looked up.
    dir.names['maya.k'] = maya;
    port.sealed.add((from: maya.id, envelope: Envelope(kind: 'buddy', body: {'s': 'me', 'u': 'maya.k', 'n': 'Maya'})));
    await clock.pass(const Duration(minutes: 2));
    expect(dir.asked.last.name, 'maya.k');
    expect(watch.changeFor(maya.id), isNull, reason: 'followed: the old name is nothing to say now');
    watch.dispose();
    buddies.dispose();
  });

  test('PROBE 2, fixed: its own username given up or changed on another device and taken since: said calmly and once, not at every sign-in; gone when this device\'s username changes or is given up, or nobody holds it', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final me = NetKeys.generate(), stranger = NetKeys.generate();
    String? username = 'matt';
    var holds = Me.nameKeyOf('matt');
    final w1 = _bare(clock, dir, me: me.id, username: () => username, held: () async => holds.isEmpty ? null : holds);
    NameWatch.instance = w1;
    addTearDown(() => NameWatch.instance = null);
    var notices = 0;
    final sub = NameWatch.notices.listen((_) => notices++);
    dir.names['matt'] = me;
    await w1.signedIn();
    expect([w1.own, notices], [isNull, 0], reason: 'held here, and by this key');
    // Given up on the Mac, and taken since; this phone still says @matt. The relay says this key holds no name.
    dir.names['matt'] = stranger;
    holds = '';
    for (var i = 0; i < 6; i++) {
      await clock.pass(const Duration(minutes: 11));
      await w1.signedIn();
    }
    await clock.settle();
    expect([w1.own?.kind, w1.own?.other, notices], [NameKind.none, stranger.id, 1], reason: 'said once, not six times');
    // Changed on another device to another name this key now holds.
    holds = Me.nameKeyOf('matt.k');
    await clock.pass(const Duration(minutes: 11));
    await w1.signedIn();
    expect(w1.own?.kind, NameKind.changed);
    // Given up here too: what was said of it goes.
    username = null;
    w1.usernameChanged();
    expect(w1.own, isNull);
    username = 'matt';
    await clock.pass(const Duration(minutes: 11));
    await w1.signedIn();
    expect(w1.own, isNotNull);
    // Nobody holds it now: gone too.
    dir.names.remove('matt');
    await clock.pass(const Duration(minutes: 11));
    await w1.signedIn();
    expect(w1.own, isNull);
    await sub.cancel();
    w1.dispose();
  });

  test('its own username still held by this device\'s old key (a new key made): said as that; and where the relay says this key holds it yet gives it to another account, said as the relay contradicting itself', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final old = NetKeys.generate(), now = NetKeys.generate(), stranger = NetKeys.generate();
    final kept = <String, String>{};
    // Before the new key: @matt claimed and held under the old one.
    dir.names['matt'] = old;
    final before = _bare(clock, dir, me: old.id, username: () => 'matt', held: () async => dir.heldBy(old), kept: kept);
    before.claimed('matt');
    await before.signedIn();
    expect(before.own, isNull);
    before.dispose();
    // "New key for this phone": another identity, the username still the phone's, the relay still giving it to the old.
    final after = _bare(clock, dir, me: now.id, username: () => 'matt', held: () async => dir.heldBy(now), kept: kept);
    await clock.pass(const Duration(minutes: 11));
    await after.signedIn();
    expect([after.own?.kind, after.own?.other], [NameKind.old, old.id]);
    after.dispose();
    // The relay says this key holds @matt, and gives @matt to someone else when asked.
    final mine = NetKeys.generate();
    final lying = _bare(clock, dir, me: mine.id, username: () => 'matt', held: () async => Me.nameKeyOf('matt'), kept: {});
    dir.names['matt'] = stranger;
    await clock.pass(const Duration(minutes: 11));
    await lying.signedIn();
    expect(lying.own?.kind, NameKind.contradicts);
    lying.dispose();
  });

  test('a friend\'s word about its own username: taken only from a friend, sealed, for this username and another account; said at once only when new that week', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final me = NetKeys.generate(), sam = NetKeys.generate(), cleo = NetKeys.generate(), mallory = NetKeys.generate(), stranger = NetKeys.generate();
    final w1 = _bare(clock, dir, me: me.id, username: () => 'maya', friends: () => [_friend('sam', sam), _friend('cleo', cleo)]);
    final shown = <NameChange?>[];
    w1.notice.addListener(() => shown.add(w1.notice.value));
    Envelope said(String u, String i) => Envelope(kind: NameWatch.kind, body: {'u': u, 'i': i, 'at': clock.ms});
    w1.heard(stranger.id, said('maya', mallory.id));
    w1.heard(sam.id, said('someone', mallory.id));
    w1.heard(sam.id, said('maya', me.id));
    w1.heard(sam.id, said('maya', mallory.id), sealed: false);
    w1.heard(sam.id, said('maya', 'not a name'));
    expect([w1.toldMe, shown], [isEmpty, isEmpty]);
    w1.heard(sam.id, said('@Maya', mallory.id));
    expect([w1.toldMe.single.by, shown.single?.by], [sam.id, sam.id]);
    // The same from another friend, and again from Sam's other device an hour on: kept, not said again this week.
    w1.heard(cleo.id, said('maya', mallory.id));
    await clock.pass(const Duration(hours: 1));
    w1.heard(sam.id, said('maya', mallory.id));
    expect([w1.toldMe.length, shown.length], [2, 1]);
    // A week on, it is said again where it is still so.
    await clock.pass(const Duration(days: 7));
    w1.heard(cleo.id, said('maya', mallory.id));
    expect(shown.length, 2);
    w1.dispose();
  });

  test('S9: what was kept for another identity (an account signed in to without signing out) is not shown', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final before = NetKeys.generate(), after = NetKeys.generate(), sam = NetKeys.generate(), stranger = NetKeys.generate();
    final kept = <String, String>{};
    dir.names['matt'] = before;
    final w1 = _bare(clock, dir, me: before.id, username: () => 'matt', friends: () => [_friend('sam', sam)], held: () async => dir.heldBy(before), kept: kept);
    await w1.signedIn();
    dir.names['matt'] = stranger;
    await clock.pass(const Duration(minutes: 11));
    await w1.signedIn();
    w1.heard(sam.id, Envelope(kind: NameWatch.kind, body: {'u': 'matt', 'i': stranger.id}));
    expect([w1.own, w1.toldMe], [isNotNull, isNotEmpty]);
    w1.dispose();
    final w2 = _bare(clock, dir, me: after.id, username: () => 'matt', friends: () => [_friend('sam', sam)], kept: kept);
    expect([w2.own, w2.toldMe, w2.changes], [isNull, isEmpty, isEmpty]);
    w2.dispose();
  });

  test('S6: a sign-in while a friend\'s lookup is under way: its own username is asked as soon as that one ends, not skipped', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final me = NetKeys.generate(), sam = NetKeys.generate();
    dir.names
      ..['matt'] = me
      ..['sam'] = sam;
    final w1 = _bare(clock, dir, me: me.id, username: () => 'matt', friends: () => [_friend('sam', sam)], held: () async => Me.nameKeyOf('matt'));
    dir.hold = Completer<void>();
    // The friend's lookup starts and waits for its answer.
    await clock.pass(_day);
    expect(dir.asked.last.name, 'sam');
    await w1.signedIn();
    expect(dir.asked.where((x) => x.name == 'matt'), isEmpty, reason: 'not while the friend\'s is under way');
    dir.hold!.complete();
    dir.hold = null;
    await clock.pass(const Duration(minutes: 2));
    expect(dir.asked.where((x) => x.name == 'matt'), hasLength(1));
    w1.dispose();
  });

  test('S7 and S2: times kept from a clock that was ahead are held to now, and a phone that runs less than a day still comes to every friend (PROBE 8)', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final friends = [for (var i = 0; i < 60; i++) WatchedName('friend$i', NetCrypto.hex(NetCrypto.randomBytes(16)), 'k')];
    final start = clock.ms;
    // Kept by a clock two days ahead: five friends "asked" in the future.
    final ahead = start + const Duration(days: 2).inMilliseconds;
    final kept = <String, String>{
      NameWatch.keptName: jsonEncode({
        'me': 'a' * 32,
        'r': {
          _relay: {
            'c': {for (final f in friends.take(5)) f.id: ahead},
          },
        },
      }),
    };
    // Five days of a process started again every ten hours, on the same choices.
    for (var i = 0; i < 12; i++) {
      final w1 = _bare(clock, dir, me: 'a' * 32, friends: () => friends, kept: kept);
      await clock.pass(const Duration(hours: 10));
      w1.dispose();
    }
    final asked = dir.asked.map((x) => x.name).toSet();
    expect([for (final f in friends) if (!asked.contains(f.username)) f.username], isEmpty, reason: 'every friend asked');
    final friend0 = [for (final x in dir.asked) if (x.name == 'friend0') x.at];
    expect(friend0.first - start, lessThanOrEqualTo(const Duration(days: 1, hours: 1).inMilliseconds), reason: 'not held back two days by a clock that was ahead');
  });

  test('S1: the relay\'s lookups are the account\'s, so its devices share the friends between them and the watch\'s share of an hour; told too many, a device asks nothing for an hour', () async {
    expect(NameWatch.mostAnHour, lessThanOrEqualTo(Handles.lookupsAnHour ~/ 4), reason: 'most of the relay\'s lookups are left to the person');
    final clock = FakeClock();
    final dir = _Directory(clock);
    final friends = [for (var i = 0; i < 90; i++) WatchedName('friend$i', NetCrypto.hex(NetCrypto.randomBytes(16)), 'k')];
    final start = clock.ms;
    final devices = [for (var d = 0; d < 3; d++) _bare(clock, dir, me: 'a' * 32, friends: () => friends, share: () => (index: d, of: 3), kept: {})];
    await clock.pass(const Duration(hours: 26));
    // Each friend asked by one device a day, never by two.
    final firstDay = [for (final x in dir.asked) if (x.at - start < _day.inMilliseconds) x.name];
    expect([firstDay.toSet().length, firstDay.length], [90, 90]);
    // Never more than the account's share an hour, all devices together.
    final times = [for (final x in dir.asked) x.at];
    for (final t in times) {
      expect(times.where((u) => u >= t && u - t < const Duration(hours: 1).inMilliseconds).length, lessThanOrEqualTo(NameWatch.mostAnHour));
    }
    for (final d in devices) {
      d.dispose();
    }
    // Told too many: nothing for an hour.
    final one = _bare(clock, dir, me: 'b' * 32, friends: () => friends, kept: {});
    await clock.pass(_day);
    dir.refuses = true;
    final at = dir.asked.length;
    await clock.pass(const Duration(minutes: 59));
    expect(dir.asked.length - at, 1, reason: 'the refused one, and nothing after it within the hour');
    one.dispose();
  });

  test('the lookups are spread through the day, each friend once, never more than so many an hour or closer than a minute; a relay that can\'t be reached is asked again ten minutes on', () async {
    final clock = FakeClock();
    final dir = _Directory(clock);
    final friends = [for (var i = 0; i < 300; i++) WatchedName('friend$i', NetCrypto.hex(NetCrypto.randomBytes(16)), 'k')];
    final kept = <String, String>{};
    NameWatch make() => _bare(clock, dir, me: 'a' * 32, friends: () => friends, kept: kept);
    final watch = make();
    final start = clock.ms;
    await clock.pass(const Duration(hours: 26));
    final times = [for (final x in dir.asked) x.at];
    expect(dir.asked.map((x) => x.name).toSet(), hasLength(300));
    final firstDay = [for (final x in dir.asked) if (x.at - start < _day.inMilliseconds) x.name];
    expect(firstDay.toSet().length, firstDay.length);
    for (var i = 1; i < times.length; i++) {
      expect(times[i] - times[i - 1], greaterThanOrEqualTo(NameWatch.gap.inMilliseconds));
    }
    for (final t in times) {
      expect(times.where((u) => u >= t && u - t < const Duration(hours: 1).inMilliseconds).length, lessThanOrEqualTo(NameWatch.mostAnHour));
    }
    for (var h = 0; h < 24; h++) {
      expect(times.any((t) => t - start >= h * 3600000 && t - start < (h + 1) * 3600000), isTrue, reason: 'hour $h');
    }
    watch.dispose();
    final again = make();
    final before = dir.asked.length;
    await clock.pass(const Duration(minutes: 30));
    expect(dir.asked.length - before, lessThanOrEqualTo(30 ~/ NameWatch.gap.inMinutes + 1));
    dir.down = true;
    final downAt = dir.asked.length;
    await clock.pass(const Duration(hours: 2));
    expect(dir.asked.length - downAt, lessThanOrEqualTo(13));
    again.dispose();
  });

  test('S5: what checks the relay starts quietly: nothing it throws, at once or later, stops what starts after it', () async {
    var after = false;
    await Future<void>.value()
        .then((_) => quietly(() => throw StateError('at once')))
        .then((_) => quietly(() async {
              await Future<void>.delayed(Duration.zero);
              throw StateError('later');
            }))
        .then((_) => after = true);
    expect(after, isTrue);
  });
}
