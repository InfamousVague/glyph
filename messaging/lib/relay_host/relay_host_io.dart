import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ghost_relay/fed_dial.dart' show DialRefused;
import 'package:ghost_relay/federation.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/ws_door.dart' show WireBudget, WireHold;

import '../account/account.dart' show AppAccountProfiles;
import '../net/home_record.dart' show canonicalHub;
import '../net/hub_carrier.dart';
import '../net/hub_link.dart';
import '../net/net.dart';
import '../net/p2p/node.dart';
import '../net/p2p/p2p.dart';
import '../platform_info.dart';
import '../sms.dart';
import 'address.dart';
import 'direct_link.dart' show DirectFrames;
import 'hosting.dart';

/// This device's relay host (lib/relay_host/relay_host.dart): one where the device can host one (the Mac, Windows,
/// Linux, Android), none on an iPhone.
RelayHosting? makeRelayHost() => RelayHost.canHost ? RelayHost() : null;

/// A relay hosted from the app (docs/OPEN_NETWORK.md, section 5; Matt, 2026-11-22: "i'd like everyone to be able to host
/// a relay from their client"): the same hub gogho.st runs (relay/lib/hub.dart), in the app.
///
/// - **Its own key and folder**, under the folder this copy of the app keeps everything in (`relay/`: on a computer
///   beside the app's store, on Android in the app's files): `relay-key.json` (its name to everyone), `homes.json`
///   (where its people said they live), `hub-v2.json` (who signs in the newer way). Nothing anyone said is written.
/// - **Small limits**, through the hub's own: 200 connections, 32 MB kept for people who are away (24 MB held for
///   them, 8 MB of what rooms keep), a budget of 16 MB for what connections hold on their way in and out, and the
///   federation's queue for its public relay 8 MB.
/// - **A pass phrase**, where the person sets one: the hub's own option (relay/lib/hub.dart, `pass`), asked of everyone
///   who uses it, this app included (in memory it gives the proof as anyone does).
/// - **Reached three ways:** by this app in memory ([dialHere]: a HubLink straight to a HubSocket, no socket); by
///   devices on the same network at `ws://address:port/hub` ([lanUrls]); and over Direct by anyone given its address
///   ([directUrl]), a hub connection on channel 1 to this device's node, with Direct on at both ends.
/// - **Linked to a public relay** (`via`, gogho.st's): it dials out as a relay with no address does and asks to stay
///   (relay/lib/federation.dart), so nothing needs to reach in; its people's home records name it
///   (`ghost-relay://<its name>?via=…`) and others reach them through that link. gogho.st doesn't take such links yet
///   ([viaLink] says so, as the public relay answered).
/// - **Up while the app runs:** on a computer as long as it is open; on Android while the app is in use (stopped a
///   minute after it is put away, started as it comes back). Stopping closes every connection (their apps see their
///   relay gone and try again by themselves) and loses what it kept in memory; what it keeps in its folder stays.
class RelayHost extends ChangeNotifier implements RelayHosting {
  RelayHost({
    String Function(String key)? read,
    void Function(String key, String value)? write,
    Future<String?> Function(String name)? secretRead,
    Future<void> Function(String name, String value)? secretKeep,
    Future<Directory?> Function()? folder,
    P2p? Function()? p2p,
    FedDial? viaDial,
    this.viaPorts = const {},
    this.viaPlain = false,
    String? via,
    InternetAddress? listenOn,
    Future<List<String>> Function()? addresses,
    bool? phone,
    Timer Function(Duration after, void Function() then)? timer,
    String Function()? hubUrl,
    Future<String?> Function(String url)? useRelay,
    Future<void> Function(String url)? moveBack,
    void Function(String url)? forgetHub,
    void Function()? passChanged,
  })  : _read = read ?? Net.instance.recall,
        _write = write ?? Net.instance.remember,
        _secretRead = secretRead ?? Sms.instance.secretRead,
        _secretKeep = secretKeep ?? Sms.instance.secretKeep,
        _folder = folder ?? defaultFolder,
        _p2p = p2p ?? (() => Net.instance.p2p),
        _viaDial = viaDial ?? (_inTest ? _noVia : null),
        // Under a test, this machine alone, at a port it is given: a test never opens a door to the network (a
        // computer's firewall would ask the person sitting at it).
        _listenOn = listenOn ?? (_inTest ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4),
        _addresses = addresses ?? (_inTest ? (() async => const ['127.0.0.1']) : lanAddresses),
        phone = phone ?? PlatformInfo.isAndroid,
        _timer = timer ?? Timer.new,
        _hubUrl = hubUrl ?? (() => Net.instance.hubUrl),
        _useRelay = useRelay ?? _netUseRelay,
        _moveBack = moveBack ?? ((url) => Net.instance.setHub(url)),
        _forgetHub = forgetHub ?? ((url) => Net.instance.remember('net_hub', url)),
        _passChanged = passChanged ?? (() => Net.instance.hub?.passAgain()),
        via = via ?? Net.defaultHub;

  /// Whether this device can host a relay: a computer, or an Android phone. Not an iPhone (an app there is stopped as
  /// soon as it is put away, and may not listen for others), not a browser.
  static bool get canHost => !PlatformInfo.isWeb && (PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux || PlatformInfo.isAndroid);

  static bool get _inTest => PlatformInfo.environment.containsKey('FLUTTER_TEST');

  /// Under a test, the public relay is never dialled unless the test says how: nothing leaves the machine by itself.
  static Future<HubSocket> _noVia(Uri url) => Future.error(const DialRefused('a test dials no relay it did not set up'));

  static Future<String?> _netUseRelay(String url) async => (await Net.instance.useRelay(url)).problem;

  final String Function(String key) _read;
  final void Function(String key, String value) _write;
  final Future<String?> Function(String name) _secretRead;
  final Future<void> Function(String name, String value) _secretKeep;
  final Future<Directory?> Function() _folder;
  final P2p? Function() _p2p;
  final FedDial? _viaDial;
  final InternetAddress _listenOn;
  final Future<List<String>> Function() _addresses;
  final Timer Function(Duration after, void Function() then) _timer;
  final String Function() _hubUrl;
  final Future<String?> Function(String url) _useRelay;
  final Future<void> Function(String url) _moveBack;
  final void Function(String url) _forgetHub;
  final void Function() _passChanged;

  /// Ports besides 443 the public relay may be dialled at, and whether `ws://` may be (a local relay, for a test).
  final Set<int> viaPorts;
  final bool viaPlain;

  /// Whether this is a phone, where it runs only while the app is in use.
  final bool phone;

  @override
  final String via;

  /// The choices it keeps (with the app's), and the secret: whether it is on, the local network's door and port, the
  /// relay this app used before it moved onto this one, the relay's name once known, the link helpers its people's
  /// direct links use, and the pass phrase.
  static const onKey = 'relay_host_on', lanKey = 'relay_host_lan', portKey = 'relay_host_port', beforeKey = 'relay_host_before', idKey = 'relay_host_id', helpersKey = 'relay_host_helpers', passKey = 'relay_host_pass';

  /// The port devices on the same network reach it at, unless the person chose another.
  static const defaultPort = 7787;

  /// Its limits (the hub's own settings): connections, what it keeps for people away and for rooms, and what
  /// connections hold together and each.
  static const maxConnections = 200, heldBytes = 24 << 20, roomKeepBytes = 8 << 20, wireMost = 16 << 20, wireEach = 4 << 20;

  /// What waits for the public relay while it can't be reached.
  static const viaQueue = 8 << 20;

  /// How long after the app is put away a phone's relay stops.
  static const awayFor = Duration(minutes: 1);

  /// How often what it shows is looked at again while it runs (connections, the link to via, Direct).
  static const lookEvery = Duration(seconds: 2);

  /// Where it keeps its files: `relay/` under the folder this copy of the app keeps everything in (a computer's store
  /// folder; Android's files); in memory where there is none, and under a test.
  static Future<Directory?> defaultFolder() async {
    if (_inTest) return null;
    if (PlatformInfo.isAndroid) return Directory('${Directory.systemTemp.parent.path}/files/relay');
    final app = AppAccountProfiles.appFolder;
    return app == null ? null : Directory('$app${PlatformInfo.pathSeparator}relay');
  }

  /// This device's addresses on its local networks (IPv4, as the door listens), at most four.
  static Future<List<String>> lanAddresses() async {
    try {
      final all = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
      return [for (final i in all) for (final a in i.addresses) if (!a.isLoopback && !a.isLinkLocal) a.address].take(4).toList();
    } catch (_) {
      return const [];
    }
  }

  Hub? _hub;
  Federation? _fed;
  HttpServer? _server;
  Future<void>? _starting;
  HostState _state = HostState.off;
  String? _problem, _lanProblem;
  String? _pass;
  bool _passRead = false;
  List<String> _lanUrls = const [];
  Timer? _away, _look;
  Object? _shown;
  P2p? _direct;
  StreamSubscription<P2pStream>? _directSub;
  final Set<_DirectSocket> _directSockets = {};
  final Set<_MemoryPair> _pairs = {};

  @override
  bool get on => _read(onKey) == 'on';
  @override
  HostState get state => _state;
  @override
  String? get problem => _state == HostState.failed ? _problem : _lanProblem;
  @override
  String? get relayId => _fed?.id ?? (_read(idKey).length == 32 ? _read(idKey) : null);
  @override
  int get connections => _hub?.connected ?? 0;
  @override
  bool get lan => _read(lanKey) != 'off';
  @override
  int get port => int.tryParse(_read(portKey)) ?? (_inTest ? 0 : defaultPort);
  @override
  List<String> get lanUrls => _lanUrls;
  @override
  bool get directBuilt => _p2p() != null;
  @override
  bool get directOn => _p2p()?.on ?? false;
  @override
  bool get hasPass => (_pass ?? '').isNotEmpty;
  @override
  String? get ownPass => hasPass ? _pass : null;

  /// The hub, while it runs, for a test to look at.
  @visibleForTesting
  Hub? get hub => _hub;

  /// The federation, while it runs, for a test to look at.
  @visibleForTesting
  Federation? get federation => _fed;

  @override
  String? get ownUrl {
    final id = relayId;
    return id == null ? null : '${GhostRelayAddress(relay: id, via: canonicalVia)}';
  }

  /// [via] as hubs' addresses are compared.
  String get canonicalVia => canonicalHub(via) ?? via;

  @override
  String? get directUrl {
    final id = relayId, node = _directNode;
    if (id == null || node == null || _state != HostState.up) return null;
    return '${GhostRelayAddress(relay: id, node: node, via: canonicalVia)}';
  }

  String? get _directNode {
    final p2p = _direct;
    if (p2p == null || !p2p.on) return null;
    try {
      return p2p.node.state.value == P2pState.up ? p2p.nodeId : null;
    } catch (_) {
      return null;
    }
  }

  @override
  bool isMine(String url) {
    final id = relayId;
    return id != null && GhostRelayAddress.parse(url)?.relay == id;
  }

  @override
  bool get inUse => isMine(_hubUrl());

  @override
  String get usedBefore => _read(beforeKey);

  @override
  ViaLink get viaLink {
    final fed = _fed;
    final l = _state == HostState.up ? fed?.viaLink : null;
    if (l == null) return const ViaLink(ViaKind.off);
    if (l.linked) return ViaLink(l.stays ? ViaKind.stays : ViaKind.linkedOnly);
    return switch (l.why) {
      null || 'busy' => ViaLink(ViaKind.linking, next: l.next),
      'down' => ViaLink(ViaKind.down, next: l.next),
      final said => ViaLink(ViaKind.refused, said: said, next: l.next),
    };
  }

  // --- starting and stopping ---------------------------------------------------------------------------------------

  @override
  Future<void> startIfOn() => on ? _start() : Future.value();

  Future<void> _start() {
    if (_hub != null) return Future.value();
    return _starting ??= _startNow().whenComplete(() => _starting = null);
  }

  Future<void> _startNow() async {
    _state = HostState.starting;
    _problem = null;
    notifyListeners();
    try {
      final dir = await _folder();
      if (dir != null) await dir.create(recursive: true);
      if (!_passRead) {
        final kept = await _secretRead(passKey).catchError((Object _) => null);
        _pass = (kept ?? '').isEmpty ? null : kept;
        _passRead = true;
      }
      // Linked to the public relay as a relay with no address is: it dials out and asks to stay, and links with no
      // other (list mode, with nobody on the list: its via is always let).
      final fed = Federation(
        dataDir: dir,
        config: FedConfig(mode: FedMode.list, via: canonicalVia, plain: viaPlain, ports: viaPorts),
        dial: _viaDial,
        queueBytes: viaQueue,
        queuedBytes: viaQueue,
        maxLinks: 4,
        maxPeers: 16,
      );
      final hub = Hub(
        federation: fed,
        dataDir: dir,
        maxConnections: maxConnections,
        heldBytes: heldBytes,
        roomKeepBytes: roomKeepBytes,
        wire: WireBudget(most: wireMost, eachOut: wireEach),
        pass: _pass,
        hosted: true,
        trustsProxy: false,
        helpers: _helpers(),
        // A sign-in bound to its own name (this app, in memory); the local network's addresses and its node id over
        // Direct are added as they open.
        names: [fed.id],
      );
      hub.start();
      _fed = fed;
      _hub = hub;
      if (_read(idKey) != fed.id) _write(idKey, fed.id);
      _state = HostState.up;
      if (lan) await _openLan();
      _openDirect();
      _watch();
    } catch (e) {
      await _teardown();
      _state = HostState.failed;
      _problem = 'It couldn\'t start: ${'$e'.split('\n').first}';
    }
    notifyListeners();
  }

  /// The link helpers its people's direct links use (relay/lib/hub.dart `helpers`): those this device's own relay last
  /// named, kept so the relay names them still once this app is on it.
  List<String> _helpers() {
    final now = _p2p()?.helpers ?? const <String>[];
    if (now.isNotEmpty) {
      final said = jsonEncode(now);
      if (_read(helpersKey) != said) _write(helpersKey, said);
      return now;
    }
    try {
      return [for (final h in jsonDecode(_read(helpersKey)) as List) if (h is String) h];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _stop() async {
    _away?.cancel();
    _away = null;
    final starting = _starting;
    if (starting != null) await starting;
    await _teardown();
    _state = HostState.off;
    _problem = null;
    _lanProblem = null;
    notifyListeners();
  }

  /// Everything closed: the door, Direct's channel, every connection (each told the relay is going), the link to the
  /// public relay; what it keeps in its folder written.
  Future<void> _teardown() async {
    _look?.cancel();
    _look = null;
    final hub = _hub, server = _server;
    _hub = null;
    _fed = null;
    _server = null;
    _lanUrls = const [];
    await _closeDirect();
    for (final p in _pairs.toList()) {
      p.cut();
    }
    _pairs.clear();
    hub?.stop();
    await server?.close(force: true);
  }

  // --- the local network's door ------------------------------------------------------------------------------------

  Future<void> _openLan() async {
    final hub = _hub;
    if (hub == null || _server != null) return;
    try {
      final server = await HttpServer.bind(_listenOn, port);
      // Stopped while it was being opened.
      if (!identical(hub, _hub)) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen((r) => unawaited(_door(r).catchError((Object _) {})), onError: (Object _) {});
      final found = await _addresses();
      _lanUrls = [for (final a in found) lanHubUrl(a, server.port)];
      for (final url in _lanUrls) {
        hub.names.add(HubCarrier.hostOf(url));
      }
      _lanProblem = null;
    } catch (e) {
      final taken = e is SocketException && const {48, 98, 10048}.contains(e.osError?.errorCode);
      _lanProblem = taken ? 'Devices on this network can\'t reach it: port $port is taken on this device. Choose another port.' : 'Devices on this network can\'t reach it: port $port couldn\'t be opened (${e is SocketException ? e.message : e}).';
    }
  }

  Future<void> _closeLan() async {
    final server = _server;
    _server = null;
    _lanUrls = const [];
    await server?.close(force: true);
  }

  /// A request at the local network's door: the hub, at any address ending `/hub`; a line saying what this is,
  /// anywhere else.
  Future<void> _door(HttpRequest r) async {
    final hub = _hub;
    final upgrade = WebSocketTransformer.isUpgradeRequest(r);
    if (hub != null && upgrade && r.uri.path.endsWith('/hub')) return hub.accept(r);
    r.response
      ..statusCode = upgrade ? HttpStatus.notFound : HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write('Ghost Messaging relay, hosted from an app\n');
    await r.response.close();
  }

  // --- Direct ------------------------------------------------------------------------------------------------------

  /// Opens channel 1 to anyone on the direct network, where this build has it and Direct is on: hub connections from
  /// devices it never heard of (lib/net/p2p/node.dart, openToAll), each taken as one more connection to the hub. A
  /// phone's node is kept up meanwhile ([P2p.busy]).
  void _openDirect() {
    final p2p = _p2p();
    if (p2p == null) return;
    if (!identical(p2p, _direct)) {
      _direct?.removeListener(_directChanged);
      _direct = p2p;
      p2p.addListener(_directChanged);
    }
    _directChanged();
  }

  bool _channelOpen = false;

  /// Direct switched on or off, or its node came up with an id: channel 1 follows.
  void _directChanged() {
    final p2p = _direct, hub = _hub;
    if (p2p == null) return;
    final want = hub != null && p2p.on;
    if (want && !_channelOpen) {
      _channelOpen = true;
      p2p.busy(true);
      try {
        p2p.node.openToAll(const {P2pChannel.hub});
      } catch (_) {}
      try {
        _directSub = p2p.node.opened.listen((s) {
          if (s.channel == P2pChannel.hub) _takeStream(s);
        }, onError: (Object _) {});
      } catch (_) {}
      unawaited(p2p.up().then((_) => _directChanged(), onError: (Object _) {}));
    } else if (!want && _channelOpen) {
      unawaited(_closeDirect(keepListening: true));
    }
    final node = _directNode;
    if (hub != null && node != null) hub.names.add(node);
    _notifyIfChanged();
  }

  void _takeStream(P2pStream s) {
    final hub = _hub;
    if (hub == null) {
      unawaited(s.close().catchError((Object _) {}));
      return;
    }
    final socket = _DirectSocket(s, hub.wire, onGone: (x) => _directSockets.remove(x));
    _directSockets.add(socket);
    // Its place, for what the hub counts by place: the node it came from (keys are free, so everyone's counts hold
    // too).
    hub.attach(socket, from: 'p2p:${s.nodeId}');
  }

  Future<void> _closeDirect({bool keepListening = false}) async {
    final p2p = _direct;
    if (_channelOpen && p2p != null) {
      _channelOpen = false;
      try {
        p2p.node.openToAll(const {});
      } catch (_) {}
      p2p.busy(false);
    }
    await _directSub?.cancel();
    _directSub = null;
    for (final s in _directSockets.toList()) {
      await s.close(1001, 'stopped');
    }
    _directSockets.clear();
    if (!keepListening) {
      p2p?.removeListener(_directChanged);
      _direct = null;
    }
  }

  // --- this app, in memory -----------------------------------------------------------------------------------------

  @override
  Future<HubLink> dialHere() async {
    final starting = _starting;
    if (starting != null) await starting;
    final hub = _hub;
    if (hub == null) throw const HubDialRefused('The relay on this device isn\'t running.');
    final pair = _MemoryPair(onCut: (p) => _pairs.remove(p));
    _pairs.add(pair);
    hub.attach(pair.socket);
    return pair.link;
  }

  // --- what it shows -----------------------------------------------------------------------------------------------

  /// Looks again every [lookEvery] while it runs: listeners are told when how many are connected, the link to the
  /// public relay, or the address over Direct changed.
  void _watch() {
    _look?.cancel();
    _look = _timer(lookEvery, () {
      _look = null;
      if (_hub == null) return;
      _notifyIfChanged();
      _watch();
    });
  }

  void _notifyIfChanged() {
    final v = viaLink;
    final now = (connections, v.kind, v.said, directUrl, _lanUrls.length);
    if (now == _shown) return;
    _shown = now;
    notifyListeners();
  }

  // --- what the person does ----------------------------------------------------------------------------------------

  @override
  Future<void> setOn(bool on) async {
    if (on) {
      _write(onKey, 'on');
      notifyListeners();
      await _start();
      return;
    }
    _write(onKey, '');
    // This app first goes back to the relay it used before, while this one can still pass its new record on.
    if (inUse) {
      try {
        await _moveBack(_read(beforeKey));
      } catch (_) {}
    }
    await _stop();
  }

  @override
  Future<void> setLan(bool on) async {
    _write(lanKey, on ? '' : 'off');
    if (_hub != null) {
      if (on) {
        await _openLan();
      } else {
        await _closeLan();
        _lanProblem = null;
      }
    }
    notifyListeners();
  }

  @override
  Future<String?> setPort(int port) async {
    if (port < 1024 || port > 65535) return 'A port is a number from 1024 to 65535.';
    _write(portKey, '$port');
    if (_hub != null && lan) {
      await _closeLan();
      await _openLan();
    }
    notifyListeners();
    return _lanProblem;
  }

  @override
  Future<void> setPass(String? phrase) async {
    final p = phrase?.trim() ?? '';
    await _secretKeep(passKey, p);
    _pass = p.isEmpty ? null : p;
    _passRead = true;
    // The hub's phrase is its own from its start: it starts again with this one, and everyone signs in again.
    if (_hub != null) {
      await _stop();
      await _start();
    }
    if (inUse) _passChanged();
    notifyListeners();
  }

  @override
  Future<String?> useHere() async {
    await _start();
    final own = ownUrl;
    if (_hub == null || own == null) return problem ?? 'The relay on this device isn\'t running.';
    final now = _hubUrl();
    if (!isMine(now)) _write(beforeKey, now == Net.defaultHub ? '' : now);
    return _useRelay(own);
  }

  @override
  void appAway(bool away) {
    if (!phone) return;
    _away?.cancel();
    _away = null;
    if (away) {
      if (_hub == null && _starting == null) return;
      _away = _timer(awayFor, () {
        _away = null;
        unawaited(_stop());
      });
    } else if (on && _hub == null) {
      unawaited(_start());
    }
  }

  @override
  Future<void> signedOut() async {
    _write(onKey, '');
    // Its pass phrase is the person's: forgotten with them. Its folder stays, as when it is switched off.
    _pass = null;
    _passRead = true;
    try {
      await _secretKeep(passKey, '');
    } catch (_) {}
    // The next to sign in here starts on the relay this app used before, not on one that is switched off.
    if (inUse) _forgetHub(_read(beforeKey));
    await _stop();
  }

  @override
  Future<void> shutdown() async {
    await _stop();
    _direct?.removeListener(_directChanged);
    _direct = null;
  }
}

/// A hub connection over the direct network, as the hub holds it ([HubSocket]): each message one frame of the stream
/// ([DirectFrames]), what waits to go out counted against the hub's budget as a WebSocket's is (relay/lib/ws_door.dart),
/// so a device that reads nothing can't make the app hold more than its share.
class _DirectSocket implements HubSocket {
  _DirectSocket(this._stream, WireBudget budget, {required this.onGone}) {
    _hold = budget.open(() => scheduleMicrotask(() => unawaited(close(1008, 'too much'))));
    _sub = _stream.frames.listen((frame) {
      // The first message (a hello) no longer than at any door: 16 KB.
      if (_first && frame.length > 16 << 10) {
        unawaited(close(1009, 'too big'));
        return;
      }
      _first = false;
      final m = DirectFrames.decode(frame);
      if (m == null) {
        unawaited(close(1003, 'not a hub\'s'));
        return;
      }
      if (!_in.isClosed) _in.add(m);
    }, onDone: _end, onError: (Object _) => _end(), cancelOnError: true);
  }

  final P2pStream _stream;
  final void Function(_DirectSocket) onGone;
  late final WireHold _hold;
  late final StreamSubscription<Uint8List> _sub;
  final _in = StreamController<Object?>();
  final Queue<Uint8List> _out = Queue();
  bool _first = true, _closed = false, _sending = false;

  @override
  Stream<Object?> get incoming => _in.stream;

  @override
  bool get isOpen => !_closed;

  @override
  void add(Object data) {
    if (_closed) return;
    final frame = DirectFrames.encode(data);
    if (frame.length > P2pNode.maxFrame) return;
    if (!_hold.queued(frame.length)) return;
    _out.add(frame);
    unawaited(_send());
  }

  /// One frame at a time, each once the one before it has been taken.
  Future<void> _send() async {
    if (_sending) return;
    _sending = true;
    while (_out.isNotEmpty && !_closed) {
      final frame = _out.removeFirst();
      try {
        await _stream.add(frame);
      } catch (_) {
        unawaited(close());
        break;
      }
      _hold.sent(frame.length);
    }
    _sending = false;
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    _out.clear();
    _hold.close();
    try {
      await _stream.close();
    } catch (_) {}
    _end();
  }

  void _end() {
    _closed = true;
    _hold.close();
    if (!_in.isClosed) unawaited(_in.close());
    unawaited(_sub.cancel());
    onGone(this);
  }
}

/// This app's connection to its own relay, in memory: [link] is the app's end (what a HubDial hands a HubCarrier),
/// [socket] the hub's (what Hub.attach takes). What one end says the other hears a moment later, in order, as a copy of
/// its own; closed by either end it is closed for both.
class _MemoryPair {
  _MemoryPair({required this.onCut});
  final void Function(_MemoryPair) onCut;
  final _toApp = StreamController<Object>();
  final _toHub = StreamController<Object?>();
  bool _open = true;

  late final HubLink link = _AppEnd(this);
  late final HubSocket socket = _HubEnd(this);

  void cut() {
    if (!_open) return;
    _open = false;
    unawaited(_toApp.close());
    unawaited(_toHub.close());
    onCut(this);
  }

  static Object _copy(Object said) => said is String ? said : Uint8List.fromList(said as List<int>);
}

class _AppEnd implements HubLink {
  _AppEnd(this._pair);
  final _MemoryPair _pair;

  @override
  Stream<Object> get said => _pair._toApp.stream;

  @override
  void say(Object message) {
    if (_pair._open) _pair._toHub.add(_MemoryPair._copy(message));
  }

  @override
  Future<void> close() async => _pair.cut();
}

class _HubEnd implements HubSocket {
  _HubEnd(this._pair);
  final _MemoryPair _pair;

  @override
  Stream<Object?> get incoming => _pair._toHub.stream;

  @override
  void add(Object data) {
    if (_pair._open) _pair._toApp.add(_MemoryPair._copy(data));
  }

  @override
  bool get isOpen => _pair._open;

  @override
  Future<void> close([int? code, String? reason]) async => _pair.cut();
}
