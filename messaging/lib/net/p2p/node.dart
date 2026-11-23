import 'dart:async';

import 'package:flutter/foundation.dart';

/// The direct network as the app holds it (docs/OPEN_NETWORK.md, section 2; Matt, 2026-11-22: "p2p as a secondary
/// back up that validates everything our relay says ... look at iroh as the rust backend for the p2p side").
///
/// A device is a **node**: a key made on the device, whose public half is its **node id** (64 hex digits). A node
/// offers one thing, framed streams to another node by its id, on a numbered **channel**. How a stream gets there
/// (dialling, getting through a NAT, falling back to a link helper) is the core's business (native/p2p, Rust on
/// iroh, reached by node_ffi.dart); nothing above this file knows. A test puts a stand-in in its place
/// (test/support/fake_p2p.dart), and a build without the core has no node at all.
///
/// Nothing here knows of accounts, friends or packets: the direct route (p2p_carrier.dart) says who may connect
/// ([P2pNode.allow]) and what the frames mean.

/// The channels a stream can be opened on.
abstract final class P2pChannel {
  /// Packets between two devices: the direct route.
  static const packets = 0;

  /// A hub connection to a relay hosted from an app (lib/relay_host).
  static const hub = 1;

  /// A relay talking to a relay (relay/lib/federation.dart).
  static const relays = 2;

  static const all = {packets, hub, relays};
}

/// Where a device can be found now: what it tells its account's devices and its friends', and what they dial with.
@immutable
class Whereabouts {
  const Whereabouts({this.helper, this.addresses = const [], this.at = 0});

  /// The link helper it can be reached through (`https://…`), where it has one.
  final String? helper;

  /// Its own addresses (`ip:port`), where it tells them; none where the person chose "Only through link helpers".
  final List<String> addresses;

  /// When it said so, in milliseconds.
  final int at;

  bool get isEmpty => helper == null && addresses.isEmpty;

  Map<String, dynamic> toJson() => {'r': ?helper, if (addresses.isNotEmpty) 'a': addresses, 't': at};

  /// Null where [j] isn't one. No more than [mostAddresses] are kept, none longer than 64 characters: it comes from
  /// someone else's device.
  static Whereabouts? fromJson(Object? j) {
    if (j is! Map) return null;
    final r = j['r'], a = j['a'], t = j['t'];
    if (r != null && (r is! String || r.length > 200 || !r.startsWith('https://'))) return null;
    final list = <String>[];
    if (a is List) {
      for (final x in a) {
        if (x is String && x.length <= 64 && list.length < mostAddresses) list.add(x);
      }
    }
    return Whereabouts(helper: r as String?, addresses: List.unmodifiable(list), at: t is num ? t.toInt() : 0);
  }

  static const mostAddresses = 8;

  @override
  bool operator ==(Object other) => other is Whereabouts && other.helper == helper && listEquals(other.addresses, addresses);

  @override
  int get hashCode => Object.hash(helper, Object.hashAll(addresses));
}

/// How a node stands.
enum P2pState {
  /// Not started, or stopped.
  off,
  starting,

  /// Ready: it has a node id, and can dial and be dialled.
  up,

  /// It could not start, or stopped by itself; [P2pNode.problem] says why.
  down,
}

/// How the path to another node stands.
enum P2pPathKind {
  /// No link to it.
  none,

  /// Through a link helper: sealed end to end still, but slower, and the helper sees how much is said.
  helper,

  /// Straight between the two devices.
  direct,
}

@immutable
class P2pPath {
  const P2pPath(this.nodeId, this.kind, {this.rttMs});
  final String nodeId;
  final P2pPathKind kind;

  /// The round trip, in milliseconds, where the core has measured one.
  final int? rttMs;
}

/// What a node is started with.
@immutable
class P2pConfig {
  const P2pConfig({required this.secret, this.helpers = const [], this.helpersOnly = false});

  /// The node key: 32 bytes, made once on this device and kept in its secret store.
  final Uint8List secret;

  /// The link helpers' addresses (`https://…`), as the relay this app is on hands them out. With none, only devices
  /// that can reach each other's addresses as they are link up: on one network, or two nodes on one machine in a test.
  /// Nothing is ever looked up in, or told to, a public directory.
  final List<String> helpers;

  /// Never a straight path: the other device sees a link helper's address, not this one's.
  final bool helpersOnly;

  @override
  bool operator ==(Object other) => other is P2pConfig && listEquals(other.secret, secret) && listEquals(other.helpers, helpers) && other.helpersOnly == helpersOnly;

  @override
  int get hashCode => Object.hash(Object.hashAll(secret), Object.hashAll(helpers), helpersOnly);
}

/// One stream to or from another node: whole frames, in the order they were sent.
abstract class P2pStream {
  /// The node at the other end.
  String get nodeId;
  int get channel;

  /// Whether the other end opened it.
  bool get incoming;

  /// What the other end sends, a frame at a time. Done when the stream has closed, by either end or with the link.
  Stream<Uint8List> get frames;

  /// Sends a frame of at most [P2pNode.maxFrame] bytes. Throws [P2pError] where the stream has closed.
  Future<void> add(Uint8List frame);

  /// Closes it; the other end's [frames] is done. Closing twice is nothing.
  Future<void> close();
}

abstract class P2pNode {
  /// The longest frame a stream carries.
  static const maxFrame = 1 << 20;

  /// This device's node id, 64 hex digits; null until it has started once.
  String? get nodeId;

  /// The node id that [secret] (a node key, 32 bytes) makes, worked out without starting anything: a phone makes its
  /// device card with its node down.
  Future<String> idOf(Uint8List secret);

  ValueListenable<P2pState> get state;

  /// Why it is down, in words to show; null while it is not.
  String? get problem;

  /// Where this device can be found now; it changes as the network does. Null until the core knows.
  ValueListenable<Whereabouts?> get whereabouts;

  /// Starts it. Does nothing where it is up already with the same [config]; with another, it is stopped and started
  /// again. Who was allowed ([allow], [openToAll]) is kept across a stop and a start.
  Future<void> start(P2pConfig config);

  /// Stops it: every stream closes, and nothing can dial it. A node costs a phone battery while it is up (it keeps
  /// its paths and its link helper warm every few seconds), so a phone runs one only while there is something to say.
  Future<void> stop();

  /// The device's network changed (Wi-Fi to mobile data, back from sleep): the core looks at its paths again. Android
  /// doesn't tell native code by itself.
  void networkChanged();

  /// Lets [nodeId] open streams to this device on [channels], in place of what it was allowed before. A node that was
  /// never allowed is turned away before it can say anything, unless the channel is open to all ([openToAll]).
  void allow(String nodeId, Set<int> channels);

  /// Takes back what [allow] gave, and closes every stream with [nodeId].
  void disallow(String nodeId);

  /// The channels anyone at all may open: a relay hosted here takes hub connections from devices it never heard of.
  /// None to begin with.
  void openToAll(Set<int> channels);

  /// Opens a stream to [nodeId] on [channel], dialling it first where no link is up, by [hint] (where it last said it
  /// is) and by what the core already knows of it. Throws [P2pError] when it can't be reached within [timeout], when
  /// it turns this device away, or when this node isn't up.
  Future<P2pStream> open(String nodeId, int channel, {Whereabouts? hint, Duration timeout = const Duration(seconds: 5)});

  /// The streams other nodes opened to this one, each already allowed.
  Stream<P2pStream> get opened;

  /// How the path to each linked node stands, each time that changes.
  Stream<P2pPath> get paths;

  /// How it stands with [nodeId] now; null where there is no link.
  P2pPath? pathTo(String nodeId);
}

/// What a node says when it can't do what was asked.
class P2pError implements Exception {
  P2pError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Whether [s] is a node id: 64 hex digits, lower case.
bool isNodeId(Object? s) => s is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(s);
