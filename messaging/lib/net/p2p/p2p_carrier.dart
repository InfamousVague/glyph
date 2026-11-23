import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../carrier.dart';
import '../crypto.dart';
import '../hub_carrier.dart' show HubCarrier;
import 'node.dart';
import 'p2p.dart';

/// The direct route (docs/OPEN_NETWORK.md, section 2): packets straight between this device and the devices of its
/// own account and its friends, with no server in between. It comes after the relay's hub (Switchboard.order): a way
/// through when the relay can't carry something. Who those devices are, and when the node runs, is [P2p]'s; this is
/// the carrying.
///
/// **Sending.** A packet goes to every device a card is held for (this account's own other devices where the peer
/// is this account), each on a stream that is open, else dialled by where the device last said it was, with
/// [P2pPolicy.dialFor] for all of it. Where something else carries envelopes and no stream is open, the device is
/// asked to meet as well ([P2p.meet]) and dialled again when its answer says where it is now. Passed as soon as one
/// device took it, while the others are still tried; where none did it throws and the switchboard goes on. Nothing is
/// ever kept. A device that could not be reached is not dialled again for [P2pPolicy.redialAfter], so what is sent
/// meanwhile is not held up by it.
///
/// **Whose device it is.** A card is an account's word that a node is its device, not the node's own (card.dart). So a
/// stream opens with each end's nonce, then each end's proof, the one that dialled first (once the other's nonce has
/// come) and the other once that proof checks out:
///
///     [0][2][a nonce: 16 random bytes]
///     [0][3][HMAC-SHA256(link key, "ghost-p2p link v2\n" | from account (16) | from node (32) | to account (16) |
///            to node (32) | the other end's nonce (16) | this end's (16))]
///
/// under a key made from what the two accounts seal their packets with ([P2p.linkKey]), which only their devices hold.
/// Both accounts are in it, in the order of who is proving to whom: both ends of a pair hold the pair's key, so a proof
/// without them showed only "holds the key", and a friend's card naming a device of this account's own made two of its
/// devices link with each other "as his" (second review, S2). The node ids are the ones the core's handshake vouched
/// for, and the nonces make each proof good for its own stream alone. Until the proof has come, nothing is sent on the
/// stream and nothing taken from it; one whose proof is not that of an account whose card names the node is closed. So
/// a packet for someone only ever goes to a device that holds their key and proved to be theirs, and what arrives is
/// vouched for ([Arrived.from]) as the hub's stamp is.
///
/// **Arriving.** After the proof every frame is a packet, handed on as it came. A stream from a node no card is held
/// for is closed, as is one that sends a frame longer than a packet may be, and one with nothing said on it for
/// [P2pPolicy.quiet].
class P2pCarrier implements Carrier, LiveLinks {
  P2pCarrier(this.p2p) {
    _opened = p2p.node.opened.listen(_adopt, onError: (Object _) {});
  }

  final P2p p2p;

  /// The longest packet carried, each way: the hub's, so a packet made for one route fits the other.
  static const maxPacket = HubCarrier.maxPacket;

  /// The most proved streams held with one node: one newly proved takes the place of the oldest. And the most not yet
  /// proved: a newer one takes the place of the oldest of those, and never of one that has proved whose it is.
  static const mostLines = 2, mostProving = 2;

  static final _words = utf8.encode('ghost-p2p link v2\n');
  static const _mark = 0, _nonceMark = 2, _proofMark = 3, _nonceLength = 16;

  @override
  String get id => 'p2p';
  @override
  String get name => 'Direct';
  @override
  String get about => 'Straight between your devices and your friends\', with no server in between. Their device sees your network address; nobody else does.';
  @override
  CarrierTraits get traits => CarrierTraits(maxPacket: maxPacket, ackWait: p2p.policy.ackWait);
  @override
  final ValueNotifier<CarrierState> state = ValueNotifier(CarrierState.off);
  @override
  String? problem;

  final _arrived = StreamController<Arrived>.broadcast();
  @override
  Stream<Arrived> get arrived => _arrived.stream;

  StreamSubscription<P2pStream>? _opened;
  final Map<String, _Node> _nodes = {};
  bool _wanted = false;

  @override
  Future<void> start() async {
    _wanted = true;
    p2p.setOn(true);
    restate();
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    closeAll();
    p2p.setOn(false);
    restate();
  }

  /// Ready while Direct is on and what is kept has been read; a phone's node being down is ready too, since it is
  /// started for a send. Down only where the node could not start.
  void restate() {
    final next = !_wanted || p2p.wiped ? CarrierState.off : !p2p.loaded ? CarrierState.connecting : p2p.failed ? CarrierState.down : CarrierState.up;
    problem = next == CarrierState.down ? p2p.problem : null;
    state.value = next;
  }

  /// Direct is on, and a good card is held for one of their devices.
  @override
  bool reaches(Peer peer) => _wanted && p2p.loaded && p2p.mayLink(peer.id) && p2p.devicesOf(peer.id).isNotEmpty;

  // --- streams ---------------------------------------------------------------------------------------------------------

  /// How many streams are open, proved or not: a phone's node stops some time after the last closes.
  int get lines => _nodes.values.fold(0, (n, node) => n + node.lines.length);

  /// The devices linked now, each with whose it proved to be and how the path to it stands (Settings › Routes).
  List<({String account, String nodeId, P2pPathKind kind})> get links => [
        for (final e in _nodes.entries)
          for (final account in {for (final l in e.value.lines) ?l.account})
            (account: account, nodeId: e.key, kind: _pathTo(e.key)),
      ];

  P2pPathKind _pathTo(String nodeId) {
    try {
      return p2p.node.pathTo(nodeId)?.kind ?? P2pPathKind.none;
    } catch (_) {
      return P2pPathKind.none;
    }
  }

  /// Whether a stream to [account]'s device at [nodeId] is open and proved.
  bool linkedTo(String account, String nodeId) => _nodes[nodeId]?.proved(account) != null;

  @override
  bool linked(Peer peer) => _wanted && p2p.devicesOf(peer.id).any((d) => linkedTo(peer.id, d.nodeId));

  /// A stream this device dialled ([dialled]: whose device it dialled), or one another node opened.
  void _adopt(P2pStream s, {String? dialled}) {
    if (s.channel != P2pChannel.packets) {
      // Another channel's (a relay hosted here): whoever that is for takes it.
      if (dialled != null) unawaited(s.close().catchError((Object _) {}));
      return;
    }
    // Whose device the node at the other end is said to be: a stream from a node no card is held for is closed.
    final claimed = dialled != null ? (p2p.deviceAt(dialled, s.nodeId) != null && p2p.mayLink(dialled) ? [dialled] : const <String>[]) : p2p.accountsOf(s.nodeId);
    if (!_wanted || p2p.nodeId == null || claimed.isEmpty) {
      unawaited(s.close().catchError((Object _) {}));
      return;
    }
    final node = _nodes[s.nodeId] ??= _Node();
    // A stream that has not proved whose it is takes the place of another such, never of one that has (second review,
    // S3): a friend who names someone else's node as his can't close her links with this device by dialling it.
    for (var proving = node.lines.where((l) => l.account == null).toList(); proving.length >= mostProving; proving.removeAt(0)) {
      _close(node, proving.first);
    }
    final line = _Line(s, claimed, dialled: dialled, nonce: NetCrypto.randomBytes(_nonceLength));
    node.lines.add(line);
    // Not proved in the time a dial has, it is closed.
    line.timer = p2p.timer(p2p.policy.dialFor, () => _close(node, line));
    line.sub = s.frames.listen((f) => _frame(node, line, f), onDone: () => _gone(node, line), onError: (Object _) => _gone(node, line));
    // Each end's nonce first, whichever opened it.
    _send(node, line, Uint8List.fromList([_mark, _nonceMark, ...line.nonce]));
    p2p.linesChanged();
    node.bump();
  }

  /// Puts a frame of the handshake on [line]; a stream that won't take it is closed.
  void _send(_Node node, _Line line, Uint8List frame) {
    try {
      line.stream.add(frame).catchError((Object _) => _close(node, line));
    } catch (_) {
      _close(node, line);
    }
  }

  /// What [fromAccount]'s device at [fromNode] says to [toAccount]'s at [toNode] to prove whose it is, on a stream whose
  /// nonces are [toNonce] (the other end's) and [fromNonce] (its own); null where no key is held with [account], the
  /// one of the two that is not this account (or this account's own, for its own devices).
  Uint8List? _proof(String account, {required String fromAccount, required String fromNode, required String toAccount, required String toNode, required List<int> toNonce, required List<int> fromNonce}) {
    final key = p2p.linkKey(account);
    if (key == null) return null;
    return Uint8List.fromList([
      _mark,
      _proofMark,
      ...NetCrypto.hmac(key, [..._words, ...NetCrypto.unhex(fromAccount), ...NetCrypto.unhex(fromNode), ...NetCrypto.unhex(toAccount), ...NetCrypto.unhex(toNode), ...toNonce, ...fromNonce]),
    ]);
  }

  /// Says, on [line], that this device is this account's and is talking to [account]'s.
  void _prove(_Node node, _Line line, String account) {
    final mine = p2p.nodeId, theirs = line.theirs;
    final proof = mine == null || theirs == null ? null : _proof(account, fromAccount: p2p.me, fromNode: mine, toAccount: account, toNode: line.stream.nodeId, toNonce: theirs, fromNonce: line.nonce);
    if (proof == null) return _close(node, line);
    _send(node, line, proof);
  }

  /// Whose device the other end of [line] has proved to be with [frame], of those its node is said to be; null where it
  /// is no proof of any.
  String? _whose(_Line line, Uint8List frame) {
    final mine = p2p.nodeId, theirs = line.theirs;
    if (mine == null || theirs == null) return null;
    for (final account in line.claimed) {
      final want = _proof(account, fromAccount: account, fromNode: line.stream.nodeId, toAccount: p2p.me, toNode: mine, toNonce: line.nonce, fromNonce: theirs);
      if (want != null && _same(want, frame)) return account;
    }
    return null;
  }

  /// Compared whole, however early they differ.
  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  void _frame(_Node node, _Line line, Uint8List frame) {
    if (line.closed) return;
    // Longer than a packet may be: refused, and whoever sends such is not listened to further.
    if (frame.length > maxPacket) return _close(node, line);
    if (line.account == null) {
      // The other end's nonce, then its proof; anything else, and the stream is closed.
      if (frame.length < 2 || frame[0] != _mark) return _close(node, line);
      if (line.theirs == null) {
        if (frame[1] != _nonceMark || frame.length != 2 + _nonceLength) return _close(node, line);
        line.theirs = Uint8List.fromList(frame.sublist(2));
        // The end that dialled proves first.
        final dialled = line.dialled;
        if (dialled != null) _prove(node, line, dialled);
        return;
      }
      if (frame[1] != _proofMark || frame.length != 2 + 32) return _close(node, line);
      final who = _whose(line, frame);
      if (who == null || !p2p.mayLink(who)) return _close(node, line);
      line.account = who;
      if (line.stream.incoming) _prove(node, line, who);
      _said(node, line);
      // Proved: it takes the place of the oldest proved one, where there are as many as are held.
      for (var proved = node.lines.where((l) => l.account != null && !identical(l, line)).toList(); proved.length >= mostLines; proved.removeAt(0)) {
        _close(node, proved.first);
      }
      p2p.linesChanged();
      node.bump();
      return;
    }
    // A packet's first byte is never 0 (packet.dart): anything else that is not one is passed over.
    if (frame.isEmpty || frame[0] == _mark) return;
    _said(node, line);
    _arrived.add(Arrived(id, frame, from: line.account));
  }

  /// Something was said on [line]: it is let go once nothing has been for [P2pPolicy.quiet].
  void _said(_Node node, _Line line) {
    line.timer?.cancel();
    line.timer = p2p.timer(p2p.policy.quiet, () => _close(node, line));
  }

  void _close(_Node node, _Line line) {
    if (line.closed) return;
    _gone(node, line);
    unawaited(line.stream.close().catchError((Object _) {}));
  }

  void _gone(_Node node, _Line line) {
    if (line.closed) return;
    line.closed = true;
    line.timer?.cancel();
    line.sub?.cancel();
    node.lines.remove(line);
    // Dialled for an account, and never proved to be its: as good as not reached, for that account alone. The same
    // node dialled for another account is another matter (second review, S3).
    final dialled = line.dialled;
    if (line.account == null && dialled != null) node.dialFor(dialled).failed = p2p.nowMs;
    p2p.linesChanged();
    node.bump();
  }

  /// Every stream is closed: Direct was switched off, or the app is closing.
  void closeAll() {
    for (final node in _nodes.values.toList()) {
      for (final line in node.lines.toList()) {
        _close(node, line);
      }
    }
  }

  /// No card is held for [nodeId] any more: nothing of it is kept here. (The node itself closes its streams.)
  void forget(String nodeId) {
    final node = _nodes[nodeId];
    if (node == null) return;
    for (final line in node.lines.toList()) {
      _close(node, line);
    }
    if (node.dials.values.every((d) => d.dials == 0)) _nodes.remove(nodeId);
    node.bump();
  }

  /// The device at [nodeId] said anew where it is, or its card came: whoever waits for it looks again.
  void heard(String nodeId) => _nodes[nodeId]?.bump();

  /// Whoever waits for anything looks again.
  void poke() {
    for (final node in _nodes.values.toList()) {
      node.bump();
    }
  }

  /// The network changed: devices that could not be reached may be now.
  void networkChanged() {
    for (final node in _nodes.values.toList()) {
      for (final dial in node.dials.values) {
        dial.failed = 0;
        dial.dialledAt = -1;
      }
      node.bump();
    }
  }

  // --- dialling ----------------------------------------------------------------------------------------------------------

  /// Dials [account]'s device at [nodeId] where no stream to it is open, with the time a dial has: when a friend's
  /// device asked to meet, and when the relay has gone.
  void reach(String nodeId, String account) {
    p2p.busy(true);
    unawaited(_reach(nodeId, account, p2p.nowMs + p2p.policy.dialFor.inMilliseconds).then((_) {}, onError: (Object _) {}).whenComplete(() => p2p.busy(false)));
  }

  /// A proved stream to [account]'s device at [nodeId], dialled where none is open; null where none could be had by
  /// [until]. A stream the device opens meanwhile serves as well as one dialled.
  Future<_Line?> _reach(String nodeId, String account, int until) async {
    while (true) {
      if (!_wanted) return null;
      final node = _nodes[nodeId] ??= _Node();
      final line = node.proved(account);
      if (line != null) return line;
      final device = p2p.deviceAt(account, nodeId);
      final now = p2p.nowMs;
      if (device == null || !p2p.mayLink(account) || now >= until || p2p.nodeState != P2pState.up) return null;
      // Dialled where nothing is on its way already: by where it last said it was, again when it says anew, and
      // not again within a while of failing. All of it for this account at this node: what became of a dial for
      // another account to the same node says nothing of this one (second review, S3).
      final dial = node.dialFor(account);
      final said = device.where?.at ?? 0;
      final anew = said > dial.dialledAt;
      if (!node.proving(account) && (dial.dials == 0 || anew) && (anew || now - dial.failed >= p2p.policy.redialAfter.inMilliseconds)) {
        dial.dials++;
        dial.dialledAt = said;
        Future<P2pStream> opening;
        try {
          opening = p2p.node.open(nodeId, P2pChannel.packets, hint: p2p.hintFor(device), timeout: Duration(milliseconds: until - now));
        } catch (e) {
          opening = Future.error(e);
        }
        unawaited(opening.then((s) {
          dial.dials--;
          dial.failed = 0;
          _adopt(s, dialled: account);
          node.bump();
        }, onError: (Object _) {
          dial.dials--;
          dial.failed = p2p.nowMs;
          node.bump();
        }));
      }
      // Nothing on its way, and no answer to a meet to wait for: there is no more to hope for now.
      if (dial.dials == 0 && !node.proving(account) && !p2p.awaited(account)) return null;
      await _changed(node, until);
    }
  }

  /// Waits until something about [node] changes, or [until].
  Future<void> _changed(_Node node, int until) {
    final left = until - p2p.nowMs;
    if (left <= 0) return Future.value();
    final done = Completer<void>();
    final wait = p2p.timer(Duration(milliseconds: left), () {
      if (!done.isCompleted) done.complete();
    });
    (node.changed ??= Completer<void>()).future.then((_) {
      wait.cancel();
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  /// Puts [packet] on [line], waiting no longer than [until] for the stream to take it. False where it did not.
  Future<bool> _put(_Node node, _Line line, Uint8List packet, int until) async {
    final done = Completer<bool>();
    final left = until - p2p.nowMs;
    final wait = p2p.timer(Duration(milliseconds: left < 1 ? 1 : left), () {
      if (!done.isCompleted) done.complete(false);
    });
    line.stream.add(packet).then((_) {
      if (!done.isCompleted) done.complete(true);
    }, onError: (Object _) {
      if (!done.isCompleted) done.complete(false);
    });
    final took = await done.future;
    wait.cancel();
    if (took) {
      if (!line.closed) _said(node, line);
    } else {
      _close(node, line);
    }
    return took;
  }

  /// Gets [packet] to [account]'s device at [nodeId] by [until], on a stream that is open or one that can be had.
  Future<bool> _give(String nodeId, String account, Uint8List packet, int until) async {
    try {
      while (true) {
        final line = await _reach(nodeId, account, until);
        final node = _nodes[nodeId];
        if (line == null || node == null) return false;
        if (await _put(node, line, packet, until)) return true;
        if (p2p.nowMs >= until) return false;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Handed> send(Peer peer, Uint8List packet) async {
    if (!_wanted || !p2p.loaded) throw CarrierError('Direct is switched off');
    if (packet.length > maxPacket) throw CarrierError('too long for a direct link');
    final account = peer.id;
    if (!p2p.mayLink(account)) throw CarrierError('this device does not link with them now');
    final devices = p2p.devicesOf(account);
    if (devices.isEmpty) throw CarrierError('no device of theirs is known');
    final until = p2p.nowMs + p2p.policy.dialFor.inMilliseconds;
    p2p.busy(true);
    final took = Completer<bool>();
    try {
      // A phone's node is started for this.
      await p2p.up();
      // No stream open to any of their devices: asked to meet as well, where something else carries the asking.
      if (!devices.any((d) => linkedTo(account, d.nodeId))) unawaited(p2p.meet(account, until).then((_) {}, onError: (Object _) {}));
      var left = devices.length;
      for (final d in devices) {
        p2p.busy(true);
        unawaited(_give(d.nodeId, account, packet, until).then((ok) {
          p2p.busy(false);
          if (ok && !took.isCompleted) took.complete(true);
          if (--left == 0 && !took.isCompleted) took.complete(false);
        }));
      }
      // Passed as soon as one device took it; the others are still tried until the time is up.
      if (!await took.future) throw CarrierError('none of their devices could be reached directly');
      return Handed.passed;
    } finally {
      p2p.busy(false);
    }
  }

  @override
  Future<Handed> sendLinked(Peer peer, Uint8List packet) async {
    if (!_wanted || !p2p.loaded) throw CarrierError('Direct is switched off');
    if (packet.length > maxPacket) throw CarrierError('too long for a direct link');
    final until = p2p.nowMs + p2p.policy.dialFor.inMilliseconds;
    var took = false;
    for (final d in p2p.mayLink(peer.id) ? p2p.devicesOf(peer.id) : const <P2pDevice>[]) {
      final node = _nodes[d.nodeId], line = node?.proved(peer.id);
      if (node == null || line == null) continue;
      if (await _put(node, line, packet, until)) took = true;
    }
    if (!took) throw CarrierError('no link to them is open now');
    return Handed.passed;
  }

  Future<void> dispose() async {
    await _opened?.cancel();
    _opened = null;
    await _arrived.close();
  }
}

/// One stream with a device, and whose the device has proved to be.
class _Line {
  _Line(this.stream, this.claimed, {this.dialled, required this.nonce});
  final P2pStream stream;

  /// The accounts whose cards name the node at the other end (for a stream this device dialled, the one it dialled).
  final List<String> claimed;

  /// The account whose device this one dialled; null for a stream the other end opened.
  final String? dialled;

  /// This end's nonce, and the other end's once it has come.
  final Uint8List nonce;
  Uint8List? theirs;

  /// Which of them it proved to be; null until its proof has come.
  String? account;
  StreamSubscription<Uint8List>? sub;
  Timer? timer;
  bool closed = false;
}

/// What is under way with one node: its streams, the dials on their way to it for each account it is said to be a
/// device of, and whoever waits for either.
class _Node {
  final List<_Line> lines = [];

  /// The dials to it, for each account whose device it was dialled as.
  final Map<String, _Dial> dials = {};
  Completer<void>? changed;

  _Dial dialFor(String account) => dials[account] ??= _Dial();

  _Line? proved(String account) => lines.where((l) => l.account == account && !l.closed).firstOrNull;

  /// Whether a stream that may yet prove to be [account]'s is open: one dialled for it, or one the other end opened
  /// that [account]'s card names.
  bool proving(String account) => lines.any((l) => l.account == null && !l.closed && (l.dialled == null ? l.claimed.contains(account) : l.dialled == account));

  /// Something changed: whoever waits looks again.
  void bump() {
    final c = changed;
    changed = null;
    c?.complete();
  }
}

/// The dials to one node for one account: how many are on their way, the time on the whereabouts the last went by
/// (-1 before any), and when it last could not be reached (0 where it since could, or the network changed).
class _Dial {
  int dials = 0;
  int dialledAt = -1;
  int failed = 0;
}
