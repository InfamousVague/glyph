import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'carrier.dart';
import 'crypto.dart';
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
/// **Sending.** The routes are tried in the person's order ([order]; the local network, then peer to peer, then the
/// hub, then SMS, where they have not said). One is passed over when it is switched off ([off]), is not up, does
/// not reach that person, cannot hold the packet even in pieces, or costs money and this is not something worth
/// money ([send]'s `metered`). On a route where an answer comes at once the answer is waited for, and with none
/// the next route is tried; the other end knows a second copy by the envelope's name and drops it. Kept for
/// someone who is away ([Handed.held]) is good enough, unless it is urgent (a call ringing): then the routes after
/// are tried too, so that one that wakes a closed app gets its turn.
///
/// **Sealing.** Everything is sealed with the key the two installs share unless the sender says not to, and
/// nothing unsealed is taken from someone a key is held for (Matt: "everything should habe the option for
/// encryption"). With no key yet, only a greeting in the clear passes ([strangers]).
///
/// **Arriving.** A packet is put back together if it came in pieces, opened, told apart from copies that came
/// another way, answered, and passed on ([received]).
class Switchboard {
  Switchboard({required this.me, required this.peers, List<Carrier> carriers = const [], List<String>? order, DateTime Function()? now})
      : order = order ?? ['lan', 'p2p', 'hub', 'sms'],
        _joiner = PartJoiner(now: now) {
    carriers.forEach(add);
  }

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
    _subs[c.id] = c.arrived.listen(_arrived);
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
              (size <= c.traits.maxPacket || (c.traits.maxParts > 1 && size - Packet.head <= (c.traits.maxPacket - Packet.partHead) * c.traits.maxParts)))
            c,
      ];

  /// Sends [envelope] to [peer] by the first route that will take it.
  ///
  /// [metered] lets it go by a route that may cost money. [urgent] tries the routes after one that only kept it.
  /// [sealed] false sends it in the clear (a greeting to someone no key is held for). [only] keeps it to those
  /// routes.
  Future<Delivery> send(Peer peer, Envelope envelope, {bool metered = false, bool urgent = false, bool sealed = true, Set<String>? only}) async {
    final key = peer.key;
    if (sealed && key == null) return Delivery(envelope.id, tried: const ['no key is held for them, and it was to be sealed']);
    final clear = envelope.encode();
    final packet = Packet.wrap(from: me, sealed: sealed, payload: sealed ? NetCrypto.seal(key!, clear) : clear);
    final tried = <String>[];
    Delivery? kept;
    final candidates = routes(peer, size: packet.length, metered: metered, only: only);
    if (candidates.isEmpty) tried.add('no route reaches them now');
    for (final c in candidates) {
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
          if (await c.send(peer, piece) == Handed.held) all = Handed.held;
        }
        handed = all;
      } catch (e) {
        tried.add('${c.id}: $e');
        continue;
      }
      tried.add(c.id);
      if (handed == Handed.held) {
        kept ??= Delivery(envelope.id, via: c.id, handed: handed, tried: List.of(tried));
        if (urgent) continue;
        _waiting.remove(envelope.id);
        return kept;
      }
      if (wait == null) {
        _waiting.remove(envelope.id);
        return Delivery(envelope.id, via: c.id, handed: handed, tried: tried);
      }
      final got = await wait.future.then((_) => true).timeout(c.traits.ackWait, onTimeout: () => false);
      if (got) {
        _waiting.remove(envelope.id);
        return Delivery(envelope.id, via: c.id, handed: handed, acked: true, tried: tried);
      }
      kept ??= Delivery(envelope.id, via: c.id, handed: handed, tried: List.of(tried));
    }
    _waiting.remove(envelope.id);
    return kept == null ? Delivery(envelope.id, tried: tried) : Delivery(envelope.id, via: kept.via, handed: kept.handed, tried: tried);
  }

  void _arrived(Arrived a) {
    final parsed = Packet.parse(a.bytes);
    if (parsed == null || parsed.from == me) return;
    final whole = _joiner.add(parsed);
    if (whole == null) return;
    final peer = peers.byId(whole.from);
    final Uint8List? clear;
    if (whole.sealed) {
      if (peer?.key == null) return;
      clear = NetCrypto.open(peer!.key!, whole.payload);
    } else {
      clear = whole.payload;
    }
    if (clear == null) return;
    final envelope = Envelope.decode(clear);
    if (envelope == null) return;
    if (peer == null || peer.key == null) {
      // Nothing is taken on trust from a name no key is held for, but a greeting, which the app looks at.
      if (envelope.kind == 'hello' && _fresh('${whole.from}:${envelope.id}')) _strangers.add((from: whole.from, envelope: envelope, via: a.carrier, address: a.address));
      return;
    }
    // From someone a key is held for, only what was sealed with it: anything else could be anyone's.
    if (!whole.sealed) return;
    if (envelope.kind == 'ack') {
      final id = envelope.body['i'];
      if (id is String) {
        _waiting.remove(id)?.complete();
        _acks.add(id);
      }
      return;
    }
    // Answered every time it comes, since the first answer may be the thing that was lost; passed on once.
    if (envelope.ack) {
      unawaited(send(peer, Envelope(kind: 'ack', body: {'i': envelope.id}, ack: false), only: {a.carrier}).catchError((_) => Delivery(envelope.id)));
    }
    if (!_fresh('${peer.id}:${envelope.id}')) return;
    _received.add(Received(peer, envelope, a.carrier));
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
