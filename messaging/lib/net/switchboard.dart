import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'carrier.dart';
import 'crypto.dart';
import 'forward_secrecy.dart';
import 'packet.dart';

/// What became of something sent.
class Delivery {
  const Delivery(this.id, {this.via, this.handed, this.acked = false, this.tried = const []});
  final String id;

  /// The route that took it; null when none could.
  final String? via;
  final Handed? handed;

  /// The other install said it has it.
  final bool acked;

  /// Each route tried, in order, and what it said where it failed.
  final List<String> tried;

  bool get sent => via != null;

  @override
  String toString() => sent ? 'Delivery($id via $via${acked ? ', acked' : handed == Handed.held ? ', held' : ''})' : 'Delivery($id not sent: ${tried.join('; ')})';
}

/// Something that came, opened and told apart from its copies.
class Received {
  const Received(this.peer, this.envelope, this.via, {this.sealed = true});
  final Peer peer;
  final Envelope envelope;

  /// The route that brought it first.
  final String via;
  final bool sealed;
}

/// Who the routes can reach: the app's list of the installs it has exchanged keys with.
abstract class PeerBook {
  Peer? byId(String id);
  Peer? byAddress(String address);
}

/// Chooses a route for each thing sent, and makes one stream of what all of them bring (Matt, 2026-11-14:
/// "implement a full relay system for the app that's replacable and swappable", "multiple sources to feed data to
/// eachother from wifi locally, p2p, internet, sms, etc").
///
/// **Sending.** The routes are tried in the person's order ([order]; the relay's hub, then the direct route, then
/// the local network, then SMS, where they have not said: the relay comes first, docs/OPEN_NETWORK.md). One is
/// passed over when it is switched off ([off]), is not up, does not reach that person, cannot hold the packet even
/// in pieces, or costs money and this is not something worth money ([send]'s `metered`). On a route where an answer
/// comes at once the answer is waited for, and with none the next route is tried; the other end knows a second copy
/// by the envelope's name and drops it. Kept for someone who is away ([Handed.held]) is good enough, unless it is
/// urgent (a call ringing): then the routes after are tried too, so that one that wakes a closed app gets its turn.
///
/// **Kept, and a link open.** Once a route has only kept a packet, they are away from that route. A route after it
/// that holds links of its own ([LiveLinks], the direct route) is then given the packet only where a link to one of
/// their devices is open right now, by that link alone: nothing is dialled and nothing started for someone who is
/// away. Where it was not urgent that copy is not waited for; the other end takes the envelope once, whichever
/// copy comes first.
///
/// The same holds, for the same reason, where a route before it passed the packet on and no answer came in time
/// (their app is slow, not away: nothing is started or dialled for that; second review, S1); for something urgent
/// while a route that wakes a closed app comes after it (that one goes at once, not after a dial; S6); and for an
/// answer, which goes back on the link the thing it answers came by ([LiveLinks.sendOn]; S7).
///
/// **Sealing.** Everything is sealed with the key the two installs share unless the sender says not to, and
/// nothing unsealed is taken from someone a key is held for (Matt: "everything should habe the option for
/// encryption"). With no key yet, only a greeting in the clear passes ([strangers]).
///
/// **Arriving.** A packet is put back together if it came in pieces, opened, told apart from copies that came
/// another way, answered, and passed on ([received]).
///
/// **Forward secrecy** (GMFB-26, lib/net/forward_secrecy.dart). With [fs] given, everything sealed carries this
/// device's prekey, and what goes to someone whose devices offered theirs is sealed under a one-off key for those
/// devices; to anyone else (a build from before, or someone not heard from in a week) it goes sealed the old way. A
/// route that carries only small packets (a data text) takes the old sealing, without the prekey. A packet sealed for
/// forward secrecy that this device can't open (sealed before its sender heard of it, or under a prekey it deleted)
/// is answered with this device's prekey (`fsk`), so the sender's next try (Friends sends again until answered)
/// reaches it.
class Switchboard {
  Switchboard({required this.me, required this.peers, List<Carrier> carriers = const [], List<String>? order, DateTime Function()? now, Timer Function(Duration after, void Function() then)? timer, this.fs})
      : order = order ?? ['hub', 'p2p', 'lan', 'sms'],
        _now = now ?? DateTime.now,
        _timer = timer ?? Timer.new,
        _joiner = PartJoiner(now: now) {
    carriers.forEach(add);
  }

  /// What an answer is waited for by: `Timer.new`, or a test's clock.
  final Timer Function(Duration after, void Function() then) _timer;

  /// This device's forward secrecy; null where it has none (a build or a test without it): everything is sealed the
  /// old way then, as before.
  final ForwardSecrecy? fs;
  final DateTime Function() _now;

  /// What a device that couldn't open a forward-secret packet answers with: nothing but its prekey (Envelope.fs).
  static const fsAsk = 'fsk';

  /// When each peer was last answered so ([fsAsk]), so a burst of packets is answered once.
  final Map<String, DateTime> _fsAsked = {};

  /// A route whose packets are at most this long carries the old sealing, with no prekey: a data text holds 133 bytes.
  static const smallRoute = 512;

  /// What was sent sealed and has had no answer yet, by envelope id, for [unackedFor]: sent again, sealed anew, when the
  /// peer's device answers that it couldn't open something ([fsAsk]). Every kind, not only what Friends sends again
  /// itself: a call ringing, a group's words, a copy to this account's devices (GMFB-26 review, finding 1).
  final Map<String, _Unacked> _unacked = {};
  static const unackedFor = Duration(minutes: 5);
  static const mostUnacked = 200;

  /// What came, handled one after another ([add]).
  Future<void> _arrivals = Future.value();

  /// The most arrivals from one route of live links (the direct route) that wait to be handled at once; one that comes
  /// beyond is dropped and counted ([droppedArrivals]). What other people's devices send straight is never let hold
  /// the relay's arrivals up behind more than that (second review, S12).
  static const mostQueued = 128;
  final Map<String, int> _queued = {};
  int droppedArrivals = 0;

  /// Holds what comes until [until] completes, as an open that takes long does: for a test of what waits meanwhile.
  @visibleForTesting
  void holdArrivals(Future<void> until) => _arrivals = _arrivals.then((_) => until);

  /// How many bytes this device has passed on to its own name in the current window ([passOnBytes] per [passOnWindow]):
  /// forged junk sealed for nobody can't be made to echo through the account (second review, A6).
  int _passedBytes = 0;
  DateTime? _passWindow;
  static const passOnBytes = 256 * 1024;
  static const passOnWindow = Duration(minutes: 10);

  /// How long a call rings (FriendCalls.ringFor): a ring older than this is not sent again (A7).
  static const ringFor = Duration(seconds: 35);

  /// How far an envelope's time may be from now and still count as fresh evidence of a device without forward secrecy
  /// (A2): a replayed old packet is not.
  static const freshFor = Duration(minutes: 5);

  /// This install's name.
  final String me;
  final PeerBook peers;

  /// The routes' names in the order they are tried. A route not named comes after those that are.
  List<String> order;

  /// The routes the person has switched off.
  final Set<String> off = {};

  final Map<String, Carrier> _carriers = {};
  final Map<String, StreamSubscription<Arrived>> _subs = {};
  final PartJoiner _joiner;
  final _received = StreamController<Received>.broadcast();
  final _strangers = StreamController<({String from, Envelope envelope, String via, String? address})>.broadcast();
  final _acks = StreamController<String>.broadcast();
  final LinkedHashSet<String> _seen = LinkedHashSet();
  final Map<String, Completer<void>> _waiting = {};

  /// Told whenever a route is added, taken out, or changes state: Settings draws from it.
  final changed = ValueNotifier<int>(0);

  /// What came, from people a key is held for.
  Stream<Received> get received => _received.stream;

  /// What came in the clear from a name no key is held for: a greeting, which the app decides what to do with.
  Stream<({String from, Envelope envelope, String via, String? address})> get strangers => _strangers.stream;

  /// The name of each thing sent as the other install says it has it, however late.
  Stream<String> get acked => _acks.stream;

  List<Carrier> get carriers {
    final list = _carriers.values.toList();
    int at(Carrier c) {
      final i = order.indexOf(c.id);
      return i < 0 ? order.length : i;
    }

    list.sort((a, b) => at(a).compareTo(at(b)));
    return list;
  }

  Carrier? carrier(String id) => _carriers[id];

  /// Puts a route in, in place of any of the same name.
  void add(Carrier c) {
    remove(c.id);
    _carriers[c.id] = c;
    // One at a time, in the order they came (second review, A7): a ring, its cancel, an edit, never reordered by one
    // taking longer to open than the next. From a route of live links, no more than [mostQueued] wait at once.
    final bounded = c is LiveLinks;
    _subs[c.id] = c.arrived.listen((a) {
      if (bounded) {
        final waiting = _queued[c.id] ?? 0;
        if (waiting >= mostQueued) {
          droppedArrivals++;
          return;
        }
        _queued[c.id] = waiting + 1;
      }
      _arrivals = _arrivals.then((_) async {
        try {
          await _arrived(a);
        } finally {
          if (bounded) _queued[c.id] = (_queued[c.id] ?? 1) - 1;
        }
      }).catchError((_) {});
    });
    c.state.addListener(_bump);
    _bump();
  }

  /// Takes a route out. It is not stopped: whoever made it does that.
  void remove(String id) {
    final had = _carriers.remove(id);
    if (had == null) return;
    _subs.remove(id)?.cancel();
    had.state.removeListener(_bump);
    _bump();
  }

  void _bump() => changed.value++;

  Future<void> start() async {
    for (final c in carriers) {
      if (!off.contains(c.id)) unawaited(c.start().catchError((_) {}));
    }
  }

  Future<void> stop() async {
    for (final c in _carriers.values) {
      await c.stop().catchError((_) {});
    }
  }

  /// Switches a route on or off, starting or stopping it.
  Future<void> setOn(String id, bool on) async {
    final c = _carriers[id];
    if (on) {
      off.remove(id);
      await c?.start().catchError((_) {});
    } else {
      off.add(id);
      await c?.stop().catchError((_) {});
    }
    _bump();
  }

  /// The routes [packet] could go to [peer] by now, in order.
  List<Carrier> routes(Peer peer, {int size = 0, bool metered = false, Set<String>? only}) => [
        for (final c in carriers)
          if (!off.contains(c.id) &&
              (only == null || only.contains(c.id)) &&
              c.state.value == CarrierState.up &&
              (metered || !c.traits.metered) &&
              c.reaches(peer) &&
              _fits(c, size))
            c,
      ];

  /// Whether a packet of [size] bytes can go by [c], whole or in pieces.
  static bool _fits(Carrier c, int size) => size <= c.traits.maxPacket || (c.traits.maxParts > 1 && size - Packet.head <= (c.traits.maxPacket - Packet.partHead) * c.traits.maxParts);

  /// Sends [envelope] to [peer] by the first route that will take it.
  ///
  /// [metered] lets it go by a route that may cost money. [urgent] tries the routes after one that only kept it.
  /// [sealed] false sends it in the clear (a greeting to someone no key is held for). [only] keeps it to those
  /// routes. [answering] is what this answers: it goes by the route that came by, and on a route of live links by the
  /// link it came on.
  Future<Delivery> send(Peer peer, Envelope envelope, {bool metered = false, bool urgent = false, bool sealed = true, Set<String>? only, Arrived? answering}) async {
    if (answering != null) only = {answering.carrier};
    final key = peer.key;
    if (sealed && key == null) return Delivery(envelope.id, tried: const ['no key is held for them, and it was to be sealed']);
    // The packet for routes that carry big ones: with this device's prekey, and sealed for forward secrecy where the
    // other end's devices have offered theirs. The one for small routes: sealed the old way, nothing added.
    Uint8List? big, small, oldCopy;
    if (sealed && envelope.ack) _remember(peer, envelope, metered: metered, only: only);
    final fs = sealed ? this.fs : null;
    if (fs != null && fs.loaded) {
      if (fs.due) {
        try {
          await fs.refresh();
        } catch (_) {}
      }
      final bundle = fs.bundle;
      final clear = (bundle == null ? envelope : envelope.withFs(bundle.toJson())).encode();
      final targets = fs.targets(peer.id);
      // The old way: an answer or an ask carries nothing to keep secret; and where one of their devices can't open
      // forward-secret packets (a build from before, or one gone quiet), everything goes so that it can.
      final old = envelope.kind == 'ack' || envelope.kind == fsAsk || targets.isEmpty;
      big = old
          ? Packet.wrap(from: me, sealed: true, payload: NetCrypto.seal(key!, clear))
          : Packet.wrap(from: me, sealed: true, fs: true, payload: await ForwardSecrecy.sealAway(from: me, to: peer.id, pairKey: key!, clear: clear, targets: targets));
      // A device of theirs that can't do forward secrecy now: an old-sealed copy besides, for it (third review, item
      // 3). Their other devices take the forward-secret one; the envelope's id drops whichever comes second.
      if (!old && fs.needsOld(peer.id)) oldCopy = Packet.wrap(from: me, sealed: true, payload: NetCrypto.seal(key, clear));
    }
    Uint8List packetFor(Carrier c) {
      if (big != null && c.traits.maxPacket > smallRoute) return big;
      final clear = envelope.encode();
      return small ??= Packet.wrap(from: me, sealed: sealed, payload: sealed ? NetCrypto.seal(key!, clear) : clear);
    }

    final tried = <String>[];
    Delivery? kept;
    final candidates = [
      for (final c in routes(peer, metered: metered, only: only))
        if (_fits(c, packetFor(c).length)) c,
    ];
    if (candidates.isEmpty) tried.add('no route reaches them now');
    // The old-sealed copy goes first by the first route that takes big packets, unanswered.
    final copy = oldCopy;
    if (copy != null) {
      final c = candidates.where((c) => c.traits.maxPacket > smallRoute).firstOrNull;
      final pieces = c == null ? null : Packet.split(copy, c.traits.maxPacket, maxParts: c.traits.maxParts);
      if (c != null && pieces != null) {
        try {
          for (final p in pieces) {
            await c.send(peer, p);
          }
        } catch (_) {}
      }
    }
    // A route before this one only kept it (they are away from that route), or passed it on and no answer came.
    var away = false, unanswered = false;
    for (final (i, c) in candidates.indexed) {
      // Then a route of live links carries it only by a link that is open now, and is passed over where none is:
      // nothing is dialled or started for someone who is away, or whose app is slow to answer. So too for something
      // urgent while a route that wakes a closed app comes after (it is not kept waiting on a dial), and for an answer.
      final live = c is LiveLinks ? c as LiveLinks : null;
      final links = live != null && (away || unanswered || answering != null || (urgent && candidates.skip(i + 1).any((l) => l.traits.wakes))) ? live : null;
      if (links != null && answering == null && !links.linked(peer)) continue;
      final packet = packetFor(c);
      final pieces = Packet.split(packet, c.traits.maxPacket, maxParts: c.traits.maxParts);
      if (pieces == null) {
        tried.add('${c.id}: too long');
        continue;
      }
      final wait = envelope.ack && c.traits.live ? (_waiting[envelope.id] ??= Completer<void>()) : null;
      final Handed handed;
      try {
        var all = Handed.passed;
        for (final piece in pieces) {
          final Future<Handed> handing = links == null
              ? c.send(peer, piece)
              : answering != null
                  ? links.sendOn(peer, answering.line, piece)
                  : links.sendLinked(peer, piece);
          if (await handing == Handed.held) all = Handed.held;
        }
        handed = all;
      } catch (e) {
        tried.add('${c.id}: $e');
        continue;
      }
      tried.add(c.id);
      if (handed == Handed.held) {
        away = true;
        // Kept for them, and not urgent: that is enough, but where a link to one of their devices is open right now
        // it goes by that too, without waiting for it.
        if (!urgent) {
          final also = _byOpenLink(peer, candidates.skip(i + 1), packetFor);
          if (also != null) tried.add(also);
        }
        kept ??= Delivery(envelope.id, via: c.id, handed: handed, tried: List.of(tried));
        if (urgent) continue;
        _waiting.remove(envelope.id);
        return kept;
      }
      if (wait == null) {
        _waiting.remove(envelope.id);
        return Delivery(envelope.id, via: c.id, handed: handed, tried: tried);
      }
      if (await _answered(wait.future, c.traits.ackWait)) {
        _waiting.remove(envelope.id);
        return Delivery(envelope.id, via: c.id, handed: handed, acked: true, tried: tried);
      }
      unanswered = true;
      kept ??= Delivery(envelope.id, via: c.id, handed: handed, tried: List.of(tried));
    }
    _waiting.remove(envelope.id);
    return kept == null ? Delivery(envelope.id, tried: tried) : Delivery(envelope.id, via: kept.via, handed: kept.handed, tried: tried);
  }

  /// Whether [answer] comes within [within], by [_timer].
  Future<bool> _answered(Future<void> answer, Duration within) {
    final done = Completer<bool>();
    final wait = _timer(within, () {
      if (!done.isCompleted) done.complete(false);
    });
    answer.then((_) {
      wait.cancel();
      if (!done.isCompleted) done.complete(true);
    });
    return done.future;
  }

  /// Gives [peer]'s packet to the first of the routes in [later] that holds a link to one of their devices open right
  /// now ([LiveLinks]), by that link alone and without waiting for it. The route's name, where one was given it.
  String? _byOpenLink(Peer peer, Iterable<Carrier> later, Uint8List Function(Carrier) packetFor) {
    for (final c in later) {
      final links = c is LiveLinks ? c as LiveLinks : null;
      if (links == null || !links.linked(peer)) continue;
      final pieces = Packet.split(packetFor(c), c.traits.maxPacket, maxParts: c.traits.maxParts);
      if (pieces == null) continue;
      unawaited(() async {
        for (final piece in pieces) {
          await links.sendLinked(peer, piece);
        }
      }().catchError((_) {}));
      return c.id;
    }
    return null;
  }

  /// Keeps [envelope] to [peer] until it is answered, for [unackedFor].
  void _remember(Peer peer, Envelope envelope, {required bool metered, Set<String>? only}) {
    final now = _now();
    _unacked.removeWhere((_, u) => now.difference(u.at) > unackedFor);
    final had = _unacked[envelope.id];
    _unacked[envelope.id] = _Unacked(peer, envelope, had?.at ?? now, metered: metered, only: only);
    while (_unacked.length > mostUnacked) {
      _unacked.remove(_unacked.keys.first);
    }
  }

  /// Sends again, sealed anew, what [peer] has not answered: one of their devices has just said its prekey.
  void _sendAgain(Peer peer) {
    final now = _now();
    final list = _unacked.values.where((u) => u.peer.id == peer.id && now.difference(u.at) <= unackedFor).toList();
    bool isCall(Envelope e, String t) => e.kind == 'voice' && e.body['t'] == t;
    final cancelled = {for (final u in list) if (isCall(u.envelope, 'cancel')) u.envelope.body['i']};
    for (final u in list) {
      // A ring that has stopped ringing, or been called off, is not sent again (A7).
      if (isCall(u.envelope, 'call') && (now.millisecondsSinceEpoch - u.envelope.at > ringFor.inMilliseconds || cancelled.contains(u.envelope.body['i']))) {
        _unacked.remove(u.envelope.id);
        continue;
      }
      unawaited(send(peer, u.envelope, metered: u.metered, only: u.only).catchError((_) => Delivery(u.envelope.id)));
    }
  }

  /// What is waiting for an answer, for a test.
  @visibleForTesting
  int get unanswered => _unacked.length;

  /// Passes a forward-secret packet this device couldn't open on to its own name, still sealed: another device of
  /// this account may hold a prekey it was sealed for, and the relay hands it to them, or keeps it for the first to
  /// come (GMFB-26 review, finding 1). Once per packet.
  ///
  /// Only where its header names a sibling device this one knows of, never one passed on already (flag 8, from this
  /// account), each once even across restarts, and no more than [passOnBytes] a window (second review, A6).
  ///
  /// Third review, item 2: whenever its header names any device other than this one (the hub's stamp must match its
  /// sender, so nobody else's junk gets this far), also from a device whose forward secrecy hasn't loaded, under the
  /// byte cap. One that comes back to the device that passed it on (it was the only one online, and the relay handed
  /// it back) is put back on the account's name, at most [ForwardSecrecy.mostPassTries] times in all.
  void _passOn(Packet whole, String via) {
    final fs = this.fs;
    if (fs == null) return;
    if (!ForwardSecrecy.devicesIn(whole.payload).any((d) => d != fs.device)) return;
    final tag = NetCrypto.hex(NetCrypto.sha256(whole.payload).sublist(0, 8));
    // Passed on already, by another device of this account, or by this one and come back to it.
    if (whole.passed && !fs.passAgain(tag)) return;
    final now = _now();
    if (_passWindow == null || now.difference(_passWindow!) > passOnWindow) {
      _passWindow = now;
      _passedBytes = 0;
    }
    if (_passedBytes + whole.payload.length > passOnBytes) return;
    // Passed on already by this device, or being passed on now: once.
    if (!whole.passed && (fs.wasPassed(tag) || _passing.contains(tag))) return;
    final packet = Packet.wrap(from: whole.from, sealed: true, fs: true, passed: true, payload: whole.payload);
    final self = Peer(id: me);
    // By the relay first, which keeps it for a sibling that is away; else by the route it came by. Marked passed on only
    // once a route has taken it: the direct route with no sibling linked can't, and the relay's own copy must then still
    // be passed on when it comes (second review, S4).
    final routes = [_carriers['hub'], if (via != 'hub') _carriers[via]].whereType<Carrier>().where((c) => c.state.value == CarrierState.up && c.traits.maxPacket > smallRoute && c.reaches(self)).toList();
    if (routes.isEmpty) return;
    _passedBytes += whole.payload.length;
    _passing.add(tag);
    unawaited(() async {
      try {
        for (final c in routes) {
          final pieces = Packet.split(packet, c.traits.maxPacket, maxParts: c.traits.maxParts);
          if (pieces == null) continue;
          try {
            for (final p in pieces) {
              await c.send(self, p);
            }
          } catch (_) {
            continue;
          }
          if (!whole.passed) fs.markPassed(tag);
          return;
        }
      } finally {
        _passing.remove(tag);
      }
    }());
  }

  /// The packets being passed on now, by tag ([_passOn]).
  final Set<String> _passing = {};

  Future<void> _arrived(Arrived a) async {
    final parsed = Packet.parse(a.bytes);
    // From this install's own name: only another device of the same account (a copy, GMFB-21), sealed with the
    // account's key; anything else from it is this install's own come back.
    if (parsed == null || (parsed.from == me && peers.byId(me)?.key == null)) return;
    // Who the route vouches sent it (the hub's stamp): the packet's own name, or this account's for one passed on.
    final vouched = a.from;
    if (vouched != null && vouched != (parsed.passed ? me : parsed.from)) return;
    final whole = _joiner.add(parsed);
    if (whole == null) return;
    final peer = peers.byId(whole.from);
    final Uint8List? clear;
    var replay = false;
    if (whole.sealed) {
      if (peer?.key == null) return;
      if (whole.fs) {
        final fs = this.fs;
        if (fs == null || !fs.loaded) {
          // Not answered; passed on to a sibling that may open it, and asked for again with `nofs` and this device's
          // name: the sender sends this device an old-sealed copy until it offers a prekey (third review, item 3).
          _askForKeys(peer!, a);
          _passOn(whole, a.carrier);
          return;
        }
        final o = await fs.openAway(from: whole.from, to: me, pairKey: peer!.key!, payload: whole.payload);
        switch (o.result) {
          case FsResult.opened:
            break;
          case FsResult.replay:
            replay = true;
          case FsResult.notForThisDevice || FsResult.noPrekey:
            _askForKeys(peer, a);
            _passOn(whole, a.carrier);
            return;
          case FsResult.bad:
            return;
        }
        clear = o.clear;
      } else {
        clear = NetCrypto.open(peer!.key!, whole.payload);
      }
    } else {
      clear = whole.payload;
    }
    if (clear == null) return;
    final envelope = Envelope.decode(clear);
    if (envelope == null) return;
    // A prekey offered by one of their devices, in what only they could have sealed.
    if (whole.sealed && envelope.fs != null) fs?.heard(peer!.id, envelope.fs);
    // Sealed the old way with none, by a route that carries them: they have a device without forward secrecy, which
    // what goes to them must reach. Taken only from an envelope that is new and of now (A2), so a replayed one can't
    // turn forward secrecy off.
    void maybeOld() {
      if (!whole.sealed || whole.fs || envelope.fs != null || (_carriers[a.carrier]?.traits.maxPacket ?? 0) <= smallRoute) return;
      if ((_now().millisecondsSinceEpoch - envelope.at).abs() > freshFor.inMilliseconds) return;
      if (!(fs?.loaded ?? false)) return;
      // A device that said which it is ('nofs' in an ask), or one that can't (a build from before).
      final d = envelope.kind == fsAsk && envelope.body['nofs'] == 1 && envelope.body['d'] is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(envelope.body['d'] as String) ? envelope.body['d'] as String : '';
      fs!.sawOld(peer!.id, device: d);
    }

    if (peer == null || peer.key == null) {
      // Nothing is taken on trust from a name no key is held for, but a greeting, which the app looks at.
      if (envelope.kind == 'hello' && _fresh('${whole.from}:${envelope.id}')) _strangers.add((from: whole.from, envelope: envelope, via: a.carrier, address: a.address));
      return;
    }
    // From someone a key is held for, only what was sealed with it: anything else could be anyone's.
    if (!whole.sealed) return;
    // Only a prekey, taken above: what they have not answered goes again, sealed for it too.
    if (envelope.kind == fsAsk) {
      if (_fresh('${peer.id}:${envelope.id}')) maybeOld();
      _sendAgain(peer);
      return;
    }
    if (envelope.kind == 'ack') {
      final id = envelope.body['i'];
      if (id is String) {
        _unacked.remove(id);
        _waiting.remove(id)?.complete();
        _acks.add(id);
      }
      return;
    }
    // Answered every time it comes, since the first answer may be the thing that was lost; passed on once.
    if (envelope.ack) {
      unawaited(send(peer, Envelope(kind: 'ack', body: {'i': envelope.id}, ack: false), answering: a).catchError((_) => Delivery(envelope.id)));
    }
    // Opened before (ForwardSecrecy remembers it across restarts): answered, not passed on again.
    if (replay) return;
    if (!_fresh('${peer.id}:${envelope.id}')) return;
    maybeOld();
    _received.add(Received(peer, envelope, a.carrier));
  }

  /// Answers [peer] with this device's prekey, at most every ten minutes: they sealed something this device can't open.
  ///
  /// Where this device's forward secrecy isn't loaded it asks all the same, with no prekey: sealed the old way and new,
  /// it tells them to seal the old way, and what they sent is sent again so (A6).
  void _askForKeys(Peer peer, Arrived a) {
    final now = _now();
    final last = _fsAsked[peer.id];
    if (last != null && now.difference(last) < const Duration(minutes: 10)) return;
    _fsAsked[peer.id] = now;
    final f = fs;
    final body = f != null && !f.loaded ? {'d': f.device, 'nofs': 1} : const <String, dynamic>{};
    unawaited(send(peer, Envelope(kind: fsAsk, body: body, ack: false), answering: a).catchError((_) => const Delivery('')));
  }

  /// Whether this name has not been seen before; the last two thousand are remembered.
  bool _fresh(String name) {
    if (!_seen.add(name)) return false;
    if (_seen.length > 2000) _seen.remove(_seen.first);
    return true;
  }

  Future<void> dispose() async {
    for (final s in _subs.values) {
      await s.cancel();
    }
    for (final c in _carriers.values) {
      c.state.removeListener(_bump);
    }
    await _received.close();
    await _strangers.close();
    await _acks.close();
    changed.dispose();
  }
}

/// Something sent and not answered yet ([Switchboard._unacked]).
class _Unacked {
  _Unacked(this.peer, this.envelope, this.at, {required this.metered, this.only});
  final Peer peer;
  final Envelope envelope;
  final DateTime at;
  final bool metered;
  final Set<String>? only;
}
