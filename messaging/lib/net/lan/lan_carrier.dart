import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../carrier.dart';
import '../crypto.dart';
import '../hub_carrier.dart' show HubCarrier;
import 'lan_wire.dart';
import 'lan_words.dart';

/// How the local network route keeps time: how often it says it is here, how long it believes what it heard, how long
/// a link may be silent. A phone's runs only while the app is in use ([sleepsAway]); a computer's whenever it is on.
class LanPolicy {
  const LanPolicy({
    this.beatEvery = const Duration(seconds: 5),
    this.seenFor = const Duration(seconds: 30),
    this.yieldFor = const Duration(seconds: 2),
    this.dialFor = const Duration(seconds: 3),
    this.proveFor = const Duration(seconds: 5),
    this.pingEvery = const Duration(seconds: 20),
    this.quietFor = const Duration(seconds: 60),
    this.redialAfter = const Duration(seconds: 15),
    this.sweepEvery = const Duration(seconds: 10),
    this.sleepsAway = true,
  });
  const LanPolicy.computer() : this(sleepsAway: false);

  /// How often a beacon is said, and how long a device heard from is taken to be on the network still.
  final Duration beatEvery, seenFor;

  /// How long the device with the greater name waits for the other to connect before connecting itself.
  final Duration yieldFor;

  /// How long a connection is given to be made, and each step of proving whose it is.
  final Duration dialFor, proveFor;

  /// A link with nothing said on it this long is said a word on; with nothing heard on it [quietFor], closed.
  final Duration pingEvery, quietFor;

  /// A device that couldn't be connected to is not tried again for this long.
  final Duration redialAfter;
  final Duration sweepEvery;

  /// Whether the route closes everything while the app is put away (a phone's).
  final bool sleepsAway;
}

/// A link to one device on the network, as Settings › Routes lists it.
@immutable
class LanLinked {
  const LanLinked({required this.peer, required this.address});

  /// The account whose device it is (this account's own name for one of its own).
  final String peer;
  final String address;
}

/// The local network route (GMFB-24: "A LAN route: two devices on the same network find each other (mDNS or similar)
/// and exchange sealed packets directly"; docs/network.md). Straight between this device and the devices of its own
/// account and its friends that are on the same Wi-Fi or wired network, with no server and no internet: it comes
/// after the relay and the direct route in the order (Switchboard.order), the way through when neither can carry
/// something, and by itself when there is no internet at all.
///
/// **Finding each other.** Every few seconds a device says a beacon to the whole network (lan_words.dart, [LanBeacon]):
/// its door's port and, for each person it would link with, a mark only that person's devices can recognise, made
/// from the key the two accounts already seal with and good for ten minutes. It names nobody, and marks of noise are
/// mixed in, so the network learns only that some copy of the app is here. A device that hears a mark of its own
/// knows whose device said it and where.
///
/// **Linking.** One of the two connects to the other's door (the one whose run has the lesser name at once, the other
/// if nothing has come after [LanPolicy.yieldFor]) and each proves to the other that it holds the pair's key, over
/// both accounts, both devices' runs and a nonce from each end, so a proof is good for that connection alone:
///
///     [1][run: 8][nonce: 16][ten minutes: 4][knock: 16]     the one connecting; the knock says who to whom
///     [2][nonce: 16][proof: 32]                            the one connected to, once the knock is one of its people's
///     [3][proof: 32]                                       the one connecting
///     [4][sealed: a count (8), a kind (1), then a packet]  everything after, each way under a key of its own
///
/// Nothing is taken from a connection before its proof, nothing sent on it, and one whose knock is nobody's is closed
/// without a word. Everything after is sealed for the link (AES-256-GCM under keys made for it from the transcript)
/// and counted, so the network sees neither the accounts' names in the packets' headers nor a frame said twice. The
/// packets inside are sealed already, as on every route.
///
/// **Whom.** Only the people [people] names: the app gives it this account's own devices and its friends (never the
/// other members of a group, never someone who only asked), as the direct route. While the person chose Invisible,
/// only their own devices are marked or linked with. Only addresses of a home or office network are heard, connected
/// to or taken connections from ([isLanAddress]).
///
/// **Carrying.** A packet goes to every device of theirs a link is open to; where none is and one of theirs was heard
/// lately, it is connected to first. Passed once a link took it; otherwise it throws and the switchboard goes on.
/// Nothing is ever kept. It holds links of its own ([LiveLinks]): where the relay only kept something for someone who
/// is on this network, it goes by the link too.
class LanCarrier implements Carrier, LiveLinks {
  LanCarrier({required this.me, required this.ground, required this.people, this.policy = const LanPolicy(), DateTime Function()? now, bool Function(String address)? allowed, Random? random})
      : _now = now ?? DateTime.now,
        _allowed = allowed ?? isLanAddress,
        _random = random ?? Random.secure();

  /// This account's name (32 hex digits).
  final String me;
  final LanGround ground;

  /// Whom this device says it is here to and links with, each with the key the two seal with: this account's own
  /// devices (as one peer, by this account's name and its own key) and its friends.
  final List<Peer> Function() people;
  final LanPolicy policy;
  final DateTime Function() _now;
  final bool Function(String address) _allowed;
  final Random _random;

  static const routeId = 'lan', label = 'Local network';

  /// What the route is, in words: its row in Settings › Routes says them whether it is on or off.
  static const aboutWords =
      'Straight between your devices and your friends\' while they are on the same Wi-Fi or wired network as this one, with no server and no internet. Their devices learn this device\'s address on that network. The network sees that a copy of the app is here, never who you are or what is said.';

  /// The longest packet carried: the relay's, so a packet made for one route fits the other.
  static const maxPacket = HubCarrier.maxPacket;

  /// The most proved links held with one device's run (a newer one takes the oldest's place), connections not yet
  /// proved in all and from one address, and knocks taken from one address in a minute.
  static const mostLines = 2, mostProving = 16, mostProvingFrom = 4, knocksAMinute = 12;

  /// The most runs heard of in a minute whose marks are looked at (each costs a mark for every person), and the most
  /// kept.
  static const runsAMinute = 120, mostRuns = 128;

  /// What one link may bring: so many packets at once, and so many more each second after. What comes beyond is dropped
  /// and counted ([dropped]): a packet that matters is sent again until it is answered.
  static const lineBurst = 100, linePerSecond = 10;
  int dropped = 0;

  @override
  String get id => routeId;
  @override
  String get name => label;
  @override
  String get about => aboutWords;
  @override
  CarrierTraits get traits => const CarrierTraits(maxPacket: maxPacket);
  @override
  final ValueNotifier<CarrierState> state = ValueNotifier(CarrierState.off);
  @override
  String? problem;

  final _arrived = StreamController<Arrived>.broadcast();
  @override
  Stream<Arrived> get arrived => _arrived.stream;

  /// Goes up whenever who is seen or linked changes: Settings › Routes draws from it, and what friends were sent and
  /// have not answered goes again when a link is made.
  final ValueNotifier<int> changed = ValueNotifier(0);

  /// This run of the app, to the others on the network: eight random bytes, new each time the route opens.
  Uint8List _run = Uint8List(LanBeacon.instanceLength);
  String _runName = '';

  LanAir? _air;
  LanDoor? _door;
  Timer? _beatTimer, _sweepTimer, _againTimer;
  bool _wanted = false, _away = false, _invisible = false, _opening = false;

  /// The devices heard lately, by their run's name; the links, proved; the runs being connected to, those waited on to
  /// connect first, and when one last couldn't be connected to.
  final Map<String, _Seen> _seen = {};
  final List<_Link> _links = [];
  final Set<String> _dialing = {}, _yielding = {};
  final Map<String, DateTime> _failed = {};

  /// Whose mark each run's beacon would carry for this device, by run, ten minutes and port: worked out once for each,
  /// for a minute.
  final LinkedHashMap<String, ({DateTime at, Map<String, String> marks})> _marks = LinkedHashMap();
  final List<DateTime> _runsLooked = [];

  /// Connections not yet proved, by address; and when each address last knocked.
  final Map<String, int> _proving = {};
  final Map<String, List<DateTime>> _knocks = {};

  /// The key each person's marks are made with, with the key it was made from.
  final Map<String, ({Uint8List from, Uint8List key})> _keys = {};

  Uint8List? _keyOf(Peer p) {
    final pair = p.key;
    if (pair == null) return null;
    final had = _keys[p.id];
    if (had != null && listEquals(had.from, pair)) return had.key;
    final key = LanWords.keyOf(pair);
    _keys[p.id] = (from: pair, key: key);
    return key;
  }

  /// Those of [people] it may say it is here to and link with now: all of them, or this account's own devices alone
  /// while the person chose Invisible.
  List<Peer> _people() => [
        for (final p in people())
          if (p.key != null && p.id.length == 32 && (!_invisible || p.id == me)) p,
      ];

  // --- starting and stopping -------------------------------------------------------------------------------------------

  @override
  Future<void> start() async {
    _wanted = true;
    await _settle();
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    await _settle();
  }

  /// The app put away or in use: a phone's route closes everything while it is away, and opens again as it comes back.
  void setAway(bool away) {
    if (_away == away) return;
    _away = away;
    unawaited(_settle());
  }

  /// How the person chose to be shown (Me.presenceMode): Invisible marks and links with this account's own devices
  /// alone, and lets go of every link to anyone else's.
  void setMode(String mode) {
    final invisible = mode == 'invisible';
    if (_invisible == invisible) return;
    _invisible = invisible;
    if (invisible) {
      for (final l in _links.where((l) => l.peer != me).toList()) {
        _close(l);
      }
      _seen.removeWhere((_, s) => s.peer != me);
    }
    // Whose marks are looked for is another lot now.
    _marks.clear();
    _bump();
    unawaited(beat());
  }

  /// The network may be another than it was (the app came back, Wi-Fi changed): said again at once.
  void networkChanged() => unawaited(beat());

  /// Whom it links with changed (someone became a friend, or is one no longer): links to anyone no longer among them
  /// are closed, and it says it is here again.
  void refresh() {
    final ids = {for (final p in _people()) p.id};
    for (final l in _links.where((l) => !ids.contains(l.peer)).toList()) {
      _close(l);
    }
    _seen.removeWhere((_, s) => !ids.contains(s.peer));
    _keys.removeWhere((id, _) => !ids.contains(id));
    _marks.clear();
    _bump();
    unawaited(beat());
  }

  bool get _shouldRun => _wanted && !(_away && policy.sleepsAway);

  /// Opens or closes everything to match what is wanted now.
  Future<void> _settle() async {
    if (_shouldRun) {
      if (_air == null && !_opening) await _open();
    } else {
      await _shut();
      _set(_wanted ? CarrierState.connecting : CarrierState.off, null);
    }
  }

  Future<void> _open() async {
    _opening = true;
    _againTimer?.cancel();
    _set(CarrierState.connecting, null);
    LanDoor? door;
    LanAir? air;
    try {
      _run = Uint8List.fromList(List.generate(LanBeacon.instanceLength, (_) => _random.nextInt(256)));
      _runName = NetCrypto.hex(_run);
      door = await ground.door(_came);
      air = await ground.air(_heard);
    } catch (e) {
      await door?.close().catchError((Object _) {});
      _opening = false;
      if (!_shouldRun) return _set(_wanted ? CarrierState.connecting : CarrierState.off, null);
      _set(CarrierState.down, 'The local network can\'t be used on this device now ($e).');
      // Tried again in a while: a port another program holds, or no network yet.
      _againTimer = Timer(policy.redialAfter * 2, () => unawaited(_settle()));
      return;
    }
    _opening = false;
    if (!_shouldRun) {
      await door.close().catchError((Object _) {});
      await air.close().catchError((Object _) {});
      return;
    }
    _door = door;
    _air = air;
    _set(CarrierState.up, null);
    _beatTimer = Timer.periodic(policy.beatEvery, (_) => unawaited(beat()));
    _sweepTimer = Timer.periodic(policy.sweepEvery, (_) => sweep());
    unawaited(beat());
  }

  Future<void> _shut() async {
    _beatTimer?.cancel();
    _sweepTimer?.cancel();
    _againTimer?.cancel();
    _beatTimer = _sweepTimer = _againTimer = null;
    final air = _air, door = _door;
    _air = null;
    _door = null;
    for (final l in _links.toList()) {
      _close(l);
    }
    final had = _seen.isNotEmpty;
    _seen.clear();
    _marks.clear();
    _failed.clear();
    _yielding.clear();
    _knocks.clear();
    await air?.close().catchError((Object _) {});
    await door?.close().catchError((Object _) {});
    if (had) _bump();
  }

  void _set(CarrierState next, String? why) {
    problem = why;
    if (state.value != next) state.value = next;
  }

  void _bump() => changed.value++;

  // --- saying it is here, and hearing who is --------------------------------------------------------------------------

  /// Which of the people's marks the next beacon starts from, where there are more than one beacon holds.
  int _turn = 0;

  /// Says a beacon now (and every [LanPolicy.beatEvery] by itself): a mark for each person, noise beside them.
  Future<void> beat() async {
    final air = _air, door = _door;
    if (air == null || door == null) return;
    final bucket = LanWords.bucketOf(_now().millisecondsSinceEpoch);
    final all = _people();
    // More people than a beacon holds: a different lot each time, in turn.
    final named = <Peer>[];
    if (all.length <= LanBeacon.mostMarks) {
      named.addAll(all);
    } else {
      for (var i = 0; i < LanBeacon.mostMarks; i++) {
        named.add(all[(_turn + i) % all.length]);
      }
      _turn = (_turn + LanBeacon.mostMarks) % all.length;
    }
    final marks = <Uint8List>[
      for (final p in named)
        if (_keyOf(p) case final key?) LanWords.mark(key, from: me, to: p.id, bucket: bucket, instance: _run, port: door.port),
    ];
    final want = min(LanBeacon.mostMarks, max(LanBeacon.padTo, (marks.length + LanBeacon.padTo - 1) ~/ LanBeacon.padTo * LanBeacon.padTo));
    while (marks.length < want) {
      marks.add(Uint8List.fromList(List.generate(LanWords.markLength, (_) => _random.nextInt(256))));
    }
    marks.shuffle(_random);
    try {
      await air.say(LanBeacon(instance: _run, port: door.port, bucket: bucket, marks: marks).encode());
      if (identical(air, _air)) _set(CarrierState.up, null);
    } catch (e) {
      // Nothing could be said: no network now, or the system keeps the app off it (macOS's Local Network switch).
      if (identical(air, _air)) _set(CarrierState.down, 'Nothing can be said on the local network now: this device is on none, or its system settings keep Ghost Messaging off the local network.');
    }
  }

  /// A beacon came from [address].
  void _heard(Uint8List bytes, String address) {
    if (_air == null || !_allowed(address)) return;
    final b = LanBeacon.decode(bytes);
    if (b == null) return;
    final run = NetCrypto.hex(b.instance);
    if (run == _runName) return;
    final now = _now();
    if ((b.bucket - LanWords.bucketOf(now.millisecondsSinceEpoch)).abs() > 1) return;
    final who = _marked(b, run, now);
    // Nobody's of ours, or someone's who is not one of the people any more (what was worked out a moment ago is kept).
    if (who == null || !_people().any((p) => p.id == who)) return;
    final fresh = _seen[run];
    _seen[run] = _Seen(who, address, b.port, now);
    if (fresh == null || fresh.peer != who || fresh.address != address || fresh.port != b.port) _bump();
    _meet(run);
  }

  /// Whose device said [b], where it carries a mark one of the people's devices would make for this one; null where it
  /// names nobody here.
  String? _marked(LanBeacon b, String run, DateTime now) {
    final name = '$run:${b.bucket}:${b.port}';
    var known = _marks[name];
    if (known != null && now.difference(known.at) > const Duration(minutes: 1)) {
      _marks.remove(name);
      known = null;
    }
    if (known == null) {
      // A run not looked at before costs a mark for every person: so many a minute, and no more.
      _runsLooked.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
      if (_runsLooked.length >= runsAMinute) return null;
      _runsLooked.add(now);
      final marks = <String, String>{};
      for (final p in _people()) {
        final key = _keyOf(p);
        if (key == null) continue;
        marks[NetCrypto.hex(LanWords.mark(key, from: p.id, to: me, bucket: b.bucket, instance: b.instance, port: b.port))] = p.id;
      }
      known = (at: now, marks: marks);
      _marks[name] = known;
      while (_marks.length > mostRuns) {
        _marks.remove(_marks.keys.first);
      }
    }
    for (final m in b.marks) {
      final who = known.marks[NetCrypto.hex(m)];
      if (who != null) return who;
    }
    return null;
  }

  /// Links with the device whose run is [run], heard just now, where no link is open or being made: at once where this
  /// run's name is the lesser, else once the other has had [LanPolicy.yieldFor] to connect first.
  void _meet(String run) {
    if (_linkTo(run) != null || _dialing.contains(run) || _yielding.contains(run)) return;
    if (_runName.compareTo(run) < 0) {
      unawaited(_dial(run));
      return;
    }
    _yielding.add(run);
    Timer(policy.yieldFor, () {
      _yielding.remove(run);
      if (_air != null && _linkTo(run) == null) unawaited(_dial(run));
    });
  }

  // --- links ----------------------------------------------------------------------------------------------------------

  /// The newest link open to the device whose run is [run]; null where there is none.
  _Link? _linkTo(String run) => _links.where((l) => l.run == run).lastOrNull;

  /// The links open to [peer]'s devices, one for each device.
  List<_Link> _linksOf(String peer) {
    final byRun = <String, _Link>{};
    for (final l in _links) {
      if (l.peer == peer) byRun[l.run] = l;
    }
    return byRun.values.toList();
  }

  /// The devices linked now, as Settings › Routes lists them; and how many of the people's devices are known to be on
  /// the network: those heard lately and those linked (one that connected here may never have been heard).
  List<LanLinked> get links => [
        for (final l in {for (final l in _links) l.run: l}.values) LanLinked(peer: l.peer, address: l.wire.address),
      ];
  int get seen => {..._seen.keys, for (final l in _links) l.run}.length;

  /// Connects to the device whose run is [run], as it was last heard, and proves each end to the other. Whether a link
  /// to it is open after.
  Future<bool> _dial(String run) async {
    if (_linkTo(run) != null) return true;
    final seen = _seen[run];
    if (seen == null || _air == null || _dialing.contains(run)) return false;
    final failed = _failed[run];
    if (failed != null && _now().difference(failed) < policy.redialAfter) return false;
    final peer = _people().where((p) => p.id == seen.peer).firstOrNull;
    final key = peer == null ? null : _keyOf(peer);
    if (peer == null || key == null) return false;
    _dialing.add(run);
    LanWire? wire;
    try {
      wire = await ground.dial(seen.address, seen.port, timeout: policy.dialFor);
      final frames = StreamIterator(wire.frames);
      final listener = NetCrypto.unhex(run);
      final nonce = _bytes(16);
      final bucket = LanWords.bucketOf(_now().millisecondsSinceEpoch);
      wire.send(Uint8List.fromList([1, ..._run, ...nonce, (bucket >> 24) & 0xff, (bucket >> 16) & 0xff, (bucket >> 8) & 0xff, bucket & 0xff, ...LanWords.knock(key, from: me, to: peer.id, dialer: _run, listener: listener, nonce: nonce, bucket: bucket)]));
      if (!await frames.moveNext().timeout(policy.proveFor)) throw const _Refused();
      final answer = frames.current;
      if (answer.length != 1 + 16 + 32 || answer[0] != 2) throw const _Refused();
      final transcript = LanWords.transcript(dialerAccount: me, listenerAccount: peer.id, dialer: _run, listener: listener, dialerNonce: nonce, listenerNonce: answer.sublist(1, 17));
      if (!LanWords.same(answer.sublist(17), LanWords.proof(key, transcript, dialing: false))) throw const _Refused();
      wire.send(Uint8List.fromList([3, ...LanWords.proof(key, transcript, dialing: true)]));
      // Closed meanwhile (the route stopped, the person went Invisible): nothing is held.
      if (_air == null || !_people().any((p) => p.id == peer.id)) throw const _Refused();
      final link = _Link(peer.id, run, wire, LanWords.sealKey(key, transcript, dialing: true), LanWords.sealKey(key, transcript, dialing: false), _now());
      _adopt(link);
      unawaited(_listen(link, frames));
      return true;
    } catch (_) {
      _failed[run] = _now();
      unawaited(wire?.close().catchError((Object _) {}));
      return false;
    } finally {
      _dialing.remove(run);
    }
  }

  /// Someone connected to this device's door.
  void _came(LanWire wire) => unawaited(_take(wire).catchError((Object _) {}));

  Future<void> _take(LanWire wire) async {
    final from = wire.address;
    final now = _now();
    final knocks = _knocks.putIfAbsent(from, () => [])..removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    final proving = _proving.values.fold(0, (a, b) => a + b);
    if (_air == null || !_allowed(from) || knocks.length >= knocksAMinute || proving >= mostProving || (_proving[from] ?? 0) >= mostProvingFrom) {
      await wire.close().catchError((Object _) {});
      return;
    }
    knocks.add(now);
    _proving[from] = (_proving[from] ?? 0) + 1;
    try {
      final frames = StreamIterator(wire.frames);
      if (!await frames.moveNext().timeout(policy.proveFor)) throw const _Refused();
      final knock = frames.current;
      if (knock.length != 1 + LanBeacon.instanceLength + 16 + 4 + LanWords.knockLength || knock[0] != 1) throw const _Refused();
      final dialer = knock.sublist(1, 9), nonce = knock.sublist(9, 25);
      final bucket = ByteData.sublistView(knock, 25, 29).getUint32(0);
      final said = knock.sublist(29);
      final run = NetCrypto.hex(dialer);
      if (run == _runName || (bucket - LanWords.bucketOf(_now().millisecondsSinceEpoch)).abs() > 1) throw const _Refused();
      // Whose device it is: the one of the people whose key makes this knock, to this very run. Nobody's: closed
      // without a word.
      Peer? peer;
      Uint8List? key;
      for (final p in _people()) {
        final k = _keyOf(p);
        if (k == null) continue;
        if (LanWords.same(said, LanWords.knock(k, from: p.id, to: me, dialer: dialer, listener: _run, nonce: nonce, bucket: bucket))) {
          peer = p;
          key = k;
          break;
        }
      }
      if (peer == null || key == null) throw const _Refused();
      final mine = _bytes(16);
      final transcript = LanWords.transcript(dialerAccount: peer.id, listenerAccount: me, dialer: dialer, listener: _run, dialerNonce: nonce, listenerNonce: mine);
      wire.send(Uint8List.fromList([2, ...mine, ...LanWords.proof(key, transcript, dialing: false)]));
      if (!await frames.moveNext().timeout(policy.proveFor)) throw const _Refused();
      final proof = frames.current;
      if (proof.length != 1 + 32 || proof[0] != 3 || !LanWords.same(proof.sublist(1), LanWords.proof(key, transcript, dialing: true))) throw const _Refused();
      if (_air == null || !_people().any((p) => p.id == peer!.id)) throw const _Refused();
      final link = _Link(peer.id, run, wire, LanWords.sealKey(key, transcript, dialing: false), LanWords.sealKey(key, transcript, dialing: true), _now());
      // It connected from where it is: heard there, whether or not its beacon was.
      _adopt(link);
      unawaited(_listen(link, frames));
    } catch (_) {
      await wire.close().catchError((Object _) {});
    } finally {
      final left = (_proving[from] ?? 1) - 1;
      if (left <= 0) {
        _proving.remove(from);
      } else {
        _proving[from] = left;
      }
    }
  }

  Uint8List _bytes(int n) => Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  /// Holds [link], proved: with [mostLines] to its device already, the oldest is let go.
  void _adopt(_Link link) {
    final same = _links.where((l) => l.run == link.run).toList();
    while (same.length >= mostLines) {
      _close(same.removeAt(0));
    }
    _links.add(link);
    _failed.remove(link.run);
    _bump();
  }

  /// Takes what [link] brings until it closes: each frame opened under the link's key and counted, a packet handed on
  /// as whose the link proved to be.
  Future<void> _listen(_Link link, StreamIterator<Uint8List> frames) async {
    try {
      while (await frames.moveNext()) {
        final f = frames.current;
        if (f.isEmpty || f[0] != 4) break;
        final clear = NetCrypto.open(link.opens, Uint8List.sublistView(f, 1));
        if (clear == null || clear.length < 9) break;
        final d = ByteData.sublistView(clear);
        // Each frame once and in order: one said again, or out of turn, ends the link.
        if (d.getUint32(0) != link.heardHigh || d.getUint32(4) != link.heardLow) break;
        link.countHeard();
        link.heardAt = _now();
        if (clear[8] != 1) continue;
        if (!link.mayBring(_now())) {
          dropped++;
          continue;
        }
        if (!_arrived.isClosed) _arrived.add(Arrived(routeId, Uint8List.sublistView(clear, 9), from: link.peer, line: link));
      }
    } catch (_) {
    } finally {
      _close(link);
    }
  }

  void _close(_Link link) {
    final had = _links.remove(link);
    link.open = false;
    unawaited(link.wire.close().catchError((Object _) {}));
    if (had) _bump();
  }

  /// Forgets devices not heard from in [LanPolicy.seenFor] (but ones a link is open to), says a word on links with
  /// nothing said lately, and closes those nothing has been heard on. By itself every [LanPolicy.sweepEvery].
  @visibleForTesting
  void sweep() {
    final now = _now();
    final before = _seen.length;
    // Links first: a device whose link has just been closed for silence is forgotten in the same turn.
    for (final l in _links.toList()) {
      if (now.difference(l.heardAt) > policy.quietFor) {
        _close(l);
      } else if (now.difference(l.saidAt) > policy.pingEvery) {
        l.say(0, const [], now);
      }
    }
    _seen.removeWhere((run, s) => now.difference(s.at) > policy.seenFor && _linkTo(run) == null);
    _failed.removeWhere((_, at) => now.difference(at) > policy.redialAfter);
    if (_seen.length != before) _bump();
  }

  // --- carrying -------------------------------------------------------------------------------------------------------

  /// A link is open to one of their devices, or one of theirs was heard on this network lately.
  @override
  bool reaches(Peer peer) {
    if (_air == null) return false;
    if (_links.any((l) => l.peer == peer.id)) return true;
    final now = _now();
    return _seen.values.any((s) => s.peer == peer.id && now.difference(s.at) <= policy.seenFor);
  }

  @override
  Future<Handed> send(Peer peer, Uint8List packet) async {
    if (packet.length > maxPacket) throw CarrierError('too long for the local network');
    if (_air == null) throw CarrierError('the local network route is not running');
    var links = _linksOf(peer.id);
    if (links.isEmpty) {
      final runs = [for (final e in _seen.entries) if (e.value.peer == peer.id) e.key];
      if (runs.isEmpty) throw CarrierError('they are not on this network now');
      await Future.wait([for (final r in runs) _dial(r)]);
      links = _linksOf(peer.id);
      if (links.isEmpty) throw CarrierError('their device on this network could not be linked with');
    }
    return _put(links, packet);
  }

  Handed _put(List<_Link> links, Uint8List packet) {
    final now = _now();
    var took = false;
    for (final l in links) {
      if (l.say(1, packet, now)) took = true;
    }
    if (!took) throw CarrierError('no link on this network took it');
    return Handed.passed;
  }

  @override
  bool linked(Peer peer) => _links.any((l) => l.peer == peer.id);

  @override
  bool get linkedToSomeone => _links.any((l) => l.peer != me);

  @override
  Future<Handed> sendLinked(Peer peer, Uint8List packet) async {
    if (packet.length > maxPacket) throw CarrierError('too long for the local network');
    final links = _linksOf(peer.id);
    if (links.isEmpty) throw CarrierError('no link to them is open on this network');
    return _put(links, packet);
  }

  @override
  Future<Handed> sendOn(Peer peer, Object? line, Uint8List packet) async {
    if (packet.length > maxPacket) throw CarrierError('too long for the local network');
    if (line is _Link && line.open && line.peer == peer.id && _links.contains(line)) return _put([line], packet);
    return sendLinked(peer, packet);
  }

  /// Closes everything, for good: the app is closing, or a test is over.
  Future<void> dispose() async {
    _wanted = false;
    await _shut();
    _set(CarrierState.off, null);
    await _arrived.close();
  }
}

/// A device heard on the network: whose it is, where, and when it was last heard.
class _Seen {
  const _Seen(this.peer, this.address, this.port, this.at);
  final String peer, address;
  final int port;
  final DateTime at;
}

/// A link to one device, proved: whose it is, the run of the app at its other end, and the keys and counts of what goes
/// each way.
class _Link {
  _Link(this.peer, this.run, this.wire, this.seals, this.opens, DateTime now)
      : heardAt = now,
        saidAt = now,
        _budgetAt = now;
  final String peer, run;
  final LanWire wire;
  final Uint8List seals, opens;
  bool open = true;
  DateTime heardAt, saidAt;

  // The count of what was said and heard, each as two halves of 32 bits (a browser's numbers hold no more whole).
  int _saidHigh = 0, _saidLow = 0;
  int heardHigh = 0, heardLow = 0;

  void countHeard() {
    heardLow++;
    if (heardLow > 0xffffffff) {
      heardLow = 0;
      heardHigh++;
    }
  }

  /// Says [body] of [kind] (0 a word to keep the link, 1 a packet), sealed and counted. Whether it was handed to the
  /// wire.
  bool say(int kind, List<int> body, DateTime now) {
    if (!open) return false;
    final clear = Uint8List(9 + body.length);
    ByteData.sublistView(clear)
      ..setUint32(0, _saidHigh)
      ..setUint32(4, _saidLow);
    clear[8] = kind;
    clear.setRange(9, clear.length, body);
    _saidLow++;
    if (_saidLow > 0xffffffff) {
      _saidLow = 0;
      _saidHigh++;
    }
    wire.send(Uint8List.fromList([4, ...NetCrypto.seal(seals, clear)]));
    saidAt = now;
    return true;
  }

  // What it may still bring now: [LanCarrier.lineBurst] at once, [LanCarrier.linePerSecond] more each second.
  double _budget = LanCarrier.lineBurst.toDouble();
  DateTime _budgetAt;

  bool mayBring(DateTime now) {
    final gone = now.difference(_budgetAt).inMilliseconds;
    if (gone > 0) {
      _budget = min(LanCarrier.lineBurst.toDouble(), _budget + gone * LanCarrier.linePerSecond / 1000);
      _budgetAt = now;
    }
    if (_budget < 1) return false;
    _budget -= 1;
    return true;
  }
}

/// A connection that didn't prove whose it was, or said something that is no part of proving.
class _Refused implements Exception {
  const _Refused();
}
