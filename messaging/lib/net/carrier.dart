import 'package:flutter/foundation.dart';

/// Someone else's install, as the routes know it: its name, the key this install shares with it, and whatever a
/// route needs to find it (a phone number for SMS).
class Peer {
  const Peer({required this.id, this.key, this.address, this.name});

  /// Their name: NetCrypto.idOf their public key, 32 hex digits.
  final String id;

  /// What packets to and from them are sealed with (NetCrypto.netKey); null where no keys have been exchanged, and
  /// then only what is said in the clear can pass.
  final Uint8List? key;

  /// Their phone number, where it is known.
  final String? address;
  final String? name;

  @override
  String toString() => 'Peer(${id.length >= 6 ? id.substring(0, 6) : id}${name == null ? '' : ' $name'})';
}

/// How a route stands.
enum CarrierState {
  /// Switched off, or not started.
  off,

  /// Starting, or trying again after it was lost.
  connecting,

  /// Ready to carry.
  up,

  /// Cannot carry now; [Carrier.problem] says why.
  down,
}

/// What became of a packet a route took.
enum Handed {
  /// It was passed to the other install, or sent on its way with nothing more this route can know.
  passed,

  /// They are not there now: it is kept for them and handed over when they next are.
  held,
}

/// What a route is like, which is what the switchboard chooses by.
class CarrierTraits {
  const CarrierTraits({required this.maxPacket, this.maxParts = 1, this.metered = false, this.live = true, this.wakes = false, this.ackWait = const Duration(seconds: 4)});

  /// The longest packet it carries in one piece, in bytes, and how many pieces it will carry of one too long.
  final int maxPacket;
  final int maxParts;

  /// It may cost the person money or count against a plan (SMS): used only for what is allowed to.
  final bool metered;

  /// What it passes arrives within moments while both are there, so an answer can be waited for.
  final bool live;

  /// It reaches a phone whose app is closed (SMS).
  final bool wakes;

  /// How long an answer is waited for before the next route is tried.
  final Duration ackWait;
}

/// Something a route brought.
class Arrived {
  const Arrived(this.carrier, this.bytes, {this.address});
  final String carrier;
  final Uint8List bytes;

  /// Where the route itself knows it came from (the number a text came from).
  final String? address;
}

/// One way of getting a packet from this install to another: this server's hub, the local network, SMS, and later
/// a peer-to-peer network (Matt, 2026-11-14: "The goal will be to have multiple sources to feed data to eachother
/// from wifi locally, p2p, internet, sms, etc"). Everything above the routes speaks only to this, so one can be
/// taken out and another put in its place without the rest knowing (Switchboard.add, remove, replace).
///
/// A route carries bytes and knows nothing of what they are: packets are sealed before they reach it.
abstract class Carrier {
  /// A short name that does not change: `hub`, `lan`, `sms`, `p2p`.
  String get id;

  /// What it is called in Settings, and a line on what it is.
  String get name;
  String get about;
  CarrierTraits get traits;
  ValueListenable<CarrierState> get state;

  /// Why it is down, in words to show; null while it is not.
  String? get problem;

  Future<void> start();
  Future<void> stop();

  /// Whether a packet handed over now could be expected to get to [peer].
  bool reaches(Peer peer);

  /// Takes a packet for [peer]. Throws when it cannot.
  Future<Handed> send(Peer peer, Uint8List packet);

  /// What it brings.
  Stream<Arrived> get arrived;
}

/// A route that cannot carry a packet says why by throwing this.
class CarrierError implements Exception {
  CarrierError(this.message);
  final String message;
  @override
  String toString() => message;
}
