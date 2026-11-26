import 'dart:async';
import 'dart:typed_data';

/// What the local network route (lan_carrier.dart) stands on, apart from what carries it: a way to say a few bytes to
/// everyone on the network this device is on and to hear what they say (the **air**: UDP broadcast, lan_ground_io.dart),
/// and a way to connect to one of them and be connected to (a **door** and **wires**: TCP). Nothing here knows which,
/// so a test puts a network of its own under several routes (test/support/fake_lan.dart), and a build with no sockets
/// (a browser) has none and no route.
abstract class LanGround {
  /// Opens the air: [heard] is told every beacon said on the network, with the address it came from.
  Future<LanAir> air(void Function(Uint8List bytes, String address) heard);

  /// Opens a door for the others to connect to: [came] is told each wire as it is made.
  Future<LanDoor> door(void Function(LanWire wire) came);

  /// Connects to the door at [address], [port]; throws where it can't within [timeout].
  Future<LanWire> dial(String address, int port, {Duration timeout = const Duration(seconds: 3)});
}

/// The air, open: says a beacon to everyone on the network, until closed.
abstract class LanAir {
  Future<void> say(Uint8List beacon);
  Future<void> close();
}

/// A door, open at [port].
abstract class LanDoor {
  int get port;
  Future<void> close();
}

/// One connection between two devices, as whole frames each way. [frames] is done when it has closed, whoever closed
/// it; a frame longer than [LanFramer.longest] closes it.
abstract class LanWire {
  /// The other end's address on the network.
  String get address;
  Stream<Uint8List> get frames;
  void send(Uint8List frame);
  Future<void> close();
}

/// Frames over a stream of bytes: each a length of four bytes, big-endian, then that many bytes. What a wire over TCP
/// is made of (lan_ground_io.dart); here, apart from any socket, so it is tried without one.
class LanFramer {
  /// The longest frame taken: a packet as the routes carry them (HubCarrier.maxPacket, 60 KB), with room for its
  /// sealing.
  static const longest = 64 * 1024;

  final BytesBuilder _held = BytesBuilder(copy: false);

  /// Whether what came could not be frames: a length longer than [longest]. Nothing more is taken once it is.
  bool broken = false;

  /// [frame] with its length before it.
  static Uint8List wrap(Uint8List frame) {
    final out = Uint8List(4 + frame.length);
    ByteData.sublistView(out).setUint32(0, frame.length);
    out.setRange(4, out.length, frame);
    return out;
  }

  /// Takes more of the stream, and gives back the frames that are now whole, in order.
  List<Uint8List> add(List<int> bytes) {
    if (broken) return const [];
    _held.add(bytes);
    final all = _held.takeBytes();
    final out = <Uint8List>[];
    var at = 0;
    while (all.length - at >= 4) {
      final n = ByteData.sublistView(all, at, at + 4).getUint32(0);
      if (n > longest) {
        broken = true;
        return out;
      }
      if (all.length - at - 4 < n) break;
      out.add(Uint8List.sublistView(all, at + 4, at + 4 + n));
      at += 4 + n;
    }
    if (at < all.length) _held.add(Uint8List.sublistView(all, at));
    return out;
  }
}

/// Whether [address] is one a device on a home or office network has: 10/8, 172.16/12 or 192.168/16. The route says
/// nothing to, hears nothing from and connects to nothing at any other (the open internet, a carrier's own network,
/// loopback, the link-local addresses a cloud's machines answer on).
bool isLanAddress(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  final b = [for (final p in parts) int.tryParse(p) ?? -1];
  if (b.any((x) => x < 0 || x > 255)) return false;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
}
