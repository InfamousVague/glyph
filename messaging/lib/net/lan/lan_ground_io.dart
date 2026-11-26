import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../platform_info.dart';
import 'lan_wire.dart';

/// The local network route's own network where there is dart:io: beacons as UDP broadcasts on [LanSockets.port], and
/// wires as TCP connections to a door on a port the system chose. On Android, the Mac, Windows and Linux. Not on an
/// iPhone: Apple lets an app say something to a whole network only with an entitlement it grants app by app
/// (com.apple.developer.networking.multicast), which this app has not asked for.
LanGround? makeLanGround() => PlatformInfo.isIOS ? null : LanSockets();

/// Why this build has no local network route, in words for Settings › Routes; null where it has one.
String? lanGroundMissing() => PlatformInfo.isIOS ? 'An iPhone lets an app find others on a network only with Apple\'s leave, which this app doesn\'t have yet.' : null;

/// [LanGround] over sockets. [beaconTo], where given, is where beacons are said in place of the network's broadcast
/// addresses, [sayPort] the port they are said to where it is not [port], and [bind] the address everything listens at:
/// a test on one machine, where nothing is broadcast and two copies can't both hear one port.
class LanSockets implements LanGround {
  LanSockets({this.port = defaultPort, this.bind, this.beaconTo, int? sayPort}) : sayPort = sayPort ?? port;

  /// The UDP port beacons are said to and heard on: the SMS route's port and one more (lib/net/sms_carrier.dart).
  static const defaultPort = 16963;

  final int port, sayPort;
  final InternetAddress? bind;
  final List<InternetAddress>? beaconTo;

  @override
  Future<LanAir> air(void Function(Uint8List bytes, String address) heard) async {
    // Shared with any other copy of the app on this device where the system lets a port be shared (not Windows).
    final socket = await RawDatagramSocket.bind(bind ?? InternetAddress.anyIPv4, port, reuseAddress: true, reusePort: !PlatformInfo.isWindows);
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      for (var d = socket.receive(); d != null; d = socket.receive()) {
        heard(d.data, d.address.address);
      }
    }, onError: (Object _) {});
    return _Air(socket, sayPort, beaconTo);
  }

  @override
  Future<LanDoor> door(void Function(LanWire wire) came) async {
    final server = await ServerSocket.bind(bind ?? InternetAddress.anyIPv4, 0);
    server.listen((s) => came(_Wire(s)), onError: (Object _) {});
    return _Door(server);
  }

  @override
  Future<LanWire> dial(String address, int port, {Duration timeout = const Duration(seconds: 3)}) async => _Wire(await Socket.connect(address, port, timeout: timeout));
}

class _Air implements LanAir {
  _Air(this._socket, this._port, this._to);
  final RawDatagramSocket _socket;
  final int _port;
  final List<InternetAddress>? _to;

  /// Where a beacon is said: the network's own "everyone" address, and for each address this device has on a home or
  /// office network, everyone on its last 256 (a network is nearly always that or smaller; a Mac says the first only
  /// on one of its networks).
  Future<List<InternetAddress>> _everyone() async {
    final to = _to;
    if (to != null) return to;
    final out = <String>{'255.255.255.255'};
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final a in i.addresses) {
          if (!isLanAddress(a.address)) continue;
          out.add('${a.address.substring(0, a.address.lastIndexOf('.'))}.255');
        }
      }
    } catch (_) {}
    return [for (final a in out) InternetAddress(a)];
  }

  @override
  Future<void> say(Uint8List beacon) async {
    var sent = 0;
    Object? why;
    for (final to in await _everyone()) {
      try {
        if (_socket.send(beacon, to, _port) > 0) sent++;
      } catch (e) {
        why = e;
      }
    }
    // Said nowhere: no network, or the system forbids it (macOS's Local Network switch). The route says so.
    if (sent == 0 && why != null) throw why;
  }

  @override
  Future<void> close() async => _socket.close();
}

class _Door implements LanDoor {
  _Door(this._server);
  final ServerSocket _server;
  @override
  int get port => _server.port;
  @override
  Future<void> close() async {
    await _server.close();
  }
}

/// A wire over a TCP connection: [LanFramer]'s frames each way.
class _Wire implements LanWire {
  _Wire(this._socket) : address = _socket.remoteAddress.address {
    try {
      _socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _socket.listen(
      (bytes) {
        for (final f in _framer.add(bytes)) {
          if (!_frames.isClosed) _frames.add(f);
        }
        if (_framer.broken) unawaited(close());
      },
      onError: (Object _) => unawaited(close()),
      onDone: () => unawaited(close()),
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final LanFramer _framer = LanFramer();
  final _frames = StreamController<Uint8List>();
  bool _closed = false;

  @override
  final String address;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  void send(Uint8List frame) {
    if (_closed) return;
    try {
      _socket.add(LanFramer.wrap(frame));
    } catch (_) {
      unawaited(close());
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    // Not waited for: with nobody listening yet, a controller's close never ends.
    if (!_frames.isClosed) unawaited(_frames.close());
  }
}
