import 'dart:async';
import 'dart:typed_data';

import 'package:ghost_messaging/net/hub_link.dart';
import 'package:ghost_relay/hub.dart';

/// The app and a real hub in one process with nothing between them but memory: no server, no socket, no network to
/// wait on. It stands on the two seams, the app's [HubLink] (lib/net/hub_link.dart) and the hub's [HubSocket]
/// (relay/lib/hub.dart, [Hub.attach]).
///
///   final memory = MemoryHub();                                  // a Hub of its own, or MemoryHub(hub)
///   final c = HubCarrier(url: memory.url, signer: KeysSigner(keys), dial: memory.dial);
///   await c.start();                                             // signs in to memory.hub
///   memory.pairs.last.cut();                                     // the network went: c dials again
///   memory.down = true;                                          // nothing answers until it is false again

/// One connection held in memory, as its two ends: [link] is the app's (what a [HubDial] hands a HubCarrier) and
/// [socket] the hub's (what [Hub.attach] takes). What one end says the other hears a moment later, in order, as a
/// copy of its own. Closed by either end, or [cut], it is closed for both, once what was already said has been heard.
class HubPair {
  final _toApp = StreamController<Object>();
  final _toHub = StreamController<Object?>();
  bool _open = true;

  /// The app's end.
  late final HubLink link = _AppEnd(this);

  /// The hub's end.
  late final HubSocket socket = _HubEnd(this);

  /// Whether it still carries: neither end has closed it, and it has not been [cut].
  bool get isOpen => _open;

  /// What the hub closed it with, where it was the hub that did (4409 and "replaced", say).
  int? code;
  String? reason;

  /// Drops it as a network going does: neither end says anything more, and both find it closed.
  void cut() {
    if (!_open) return;
    _open = false;
    _toApp.close();
    _toHub.close();
  }

  /// What crosses: words as they are, bytes as the other end's own copy.
  static Object _carried(Object said) => said is String ? said : Uint8List.fromList(said as List<int>);
}

class _AppEnd implements HubLink {
  _AppEnd(this._pair);
  final HubPair _pair;

  @override
  Stream<Object> get said => _pair._toApp.stream;

  @override
  void say(Object message) {
    if (_pair._open) _pair._toHub.add(HubPair._carried(message));
  }

  @override
  Future<void> close() async => _pair.cut();
}

class _HubEnd implements HubSocket {
  _HubEnd(this._pair);
  final HubPair _pair;

  @override
  Stream<Object?> get incoming => _pair._toHub.stream;

  @override
  void add(Object data) {
    if (_pair._open) _pair._toApp.add(HubPair._carried(data));
  }

  @override
  bool get isOpen => _pair._open;

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_pair._open) return;
    _pair.code = code;
    _pair.reason = reason;
    _pair.cut();
  }
}

/// A real [Hub] and the way to it in memory: [dial] is a HubCarrier's `dial` (and checkRelay's `connect`), and every
/// dial makes a [HubPair] and attaches its hub's end.
class MemoryHub {
  MemoryHub([Hub? hub]) : hub = hub ?? Hub();
  final Hub hub;

  /// An address to give a HubCarrier. Nothing is looked up by it: whatever is dialled reaches [hub].
  final String url = 'wss://memory.test/hub';

  /// Every address dialled, in order, those that failed while [down] too.
  final List<String> dialled = [];

  /// Every connection made, oldest first.
  final List<HubPair> pairs = [];

  /// While true nothing answers: a dial fails, as one to a server that is not there does.
  bool down = false;

  Future<HubLink> dial(String url) async {
    dialled.add(url);
    if (down) throw StateError('nothing answers at $url');
    final pair = HubPair();
    pairs.add(pair);
    hub.attach(pair.socket);
    return pair.link;
  }
}
