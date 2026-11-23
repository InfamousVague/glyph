import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../platform_info.dart';
import 'node.dart';

/// The direct network's core (native/p2p: Rust on iroh, built by tool/build-p2p.sh), through its C interface: seven
/// functions, commands in and events out as bytes. native/p2p/README.md lays out every one of them; this file is the
/// other end of that page and nothing here is laid out twice.
///
/// What the library does not do for the app, this does:
/// - one thing at a time for [start] and [stop], each done when the library says so;
/// - **taking**: the library counts every frame it has read until it is told the frame was handed on (TAKEN), and
///   reads no more for a stream whose frames are not being taken. So a frame is said to be taken as it reaches
///   whoever listens to [P2pStream.frames], and not while they are paused or nobody listens yet: a slow listener
///   slows the other device down instead of filling this one up.
/// - a stream nobody is there to take ([opened] has no listener) is closed at once.

/// An event as the library hands it over: the node it is for, and bytes that are this side's to give back.
typedef _EventC = Void Function(Uint64 node, Pointer<Uint8> event, Size len);

/// The library, opened once for this isolate.
class _Core {
  _Core._(DynamicLibrary lib)
      : abi = lib.lookupFunction<Uint32 Function(), int Function()>('ghost_p2p_abi', isLeaf: true),
        nodeId = lib.lookupFunction<Int32 Function(Pointer<Uint8>, Pointer<Uint8>), int Function(Pointer<Uint8>, Pointer<Uint8>)>('ghost_p2p_node_id', isLeaf: true),
        make = lib.lookupFunction<Uint64 Function(Uint64, Pointer<NativeFunction<_EventC>>), int Function(int, Pointer<NativeFunction<_EventC>>)>('ghost_p2p_new'),
        command = lib.lookupFunction<Int32 Function(Uint64, Pointer<Uint8>, Size), int Function(int, Pointer<Uint8>, int)>('ghost_p2p_command', isLeaf: true),
        bufferFree = lib.lookupFunction<Void Function(Pointer<Uint8>, Size), void Function(Pointer<Uint8>, int)>('ghost_p2p_buffer_free', isLeaf: true),
        drop = lib.lookupFunction<Void Function(Uint64), void Function(int)>('ghost_p2p_drop'),
        dropOwned = lib.lookupFunction<Void Function(Uint64), void Function(int)>('ghost_p2p_drop_owned');

  final int Function() abi;
  final int Function(Pointer<Uint8> secret, Pointer<Uint8> out) nodeId;
  final int Function(int owner, Pointer<NativeFunction<_EventC>> callback) make;
  final int Function(int node, Pointer<Uint8> command, int len) command;
  final void Function(Pointer<Uint8> buffer, int len) bufferFree;
  final void Function(int node) drop;
  final void Function(int owner) dropOwned;

  /// Where the library's threads hand events to this isolate. It does not keep the isolate alive by itself: a test
  /// that is done is done.
  late final NativeCallable<_EventC> events = NativeCallable<_EventC>.listener(IrohNode._hear)..keepIsolateAlive = false;

  static _Core? _opened;
  static bool _tried = false;

  /// Who this isolate is to the library: its Flutter engine. A hot restart ends the isolate and starts another on
  /// the same engine, which finds the nodes the first left; another engine in the same process (a conversation's
  /// bubble on Android) is someone else, and is left alone.
  static int get owner => PlatformDispatcher.instance.engineId ?? 0;

  /// The library, or null where this build has none, or has one made for another version of this file.
  static _Core? open() {
    if (_tried) return _opened;
    _tried = true;
    for (final lib in _found()) {
      try {
        final core = _Core._(lib);
        if (core.abi() != IrohNode.abi) continue;
        // Nodes a hot restart left up, with nobody to hear them: stopped before anything else is asked.
        core.dropOwned(owner);
        return _opened = core;
      } catch (_) {
        // Something by that name that is not this library.
      }
    }
    return null;
  }

  /// Each place the library may be, in the order to try them: named in the environment (GHOST_P2P_LIB) first of
  /// all; by name on Android (the APK's lib folder); inside the app on a Mac (Contents/Frameworks), or the checkout's
  /// own build for `flutter run` and the tests; beside the program on Windows; in its lib folder on Linux; and on an
  /// iPhone in the program itself.
  static Iterable<DynamicLibrary> _found() sync* {
    final named = PlatformInfo.environment['GHOST_P2P_LIB'];
    final beside = File(PlatformInfo.resolvedExecutable).parent;
    final tries = <String>[
      if (named != null && named.isNotEmpty) named,
      if (PlatformInfo.isAndroid) 'libghost_p2p.so',
      if (PlatformInfo.isMacOS) ...['${beside.parent.path}/Frameworks/libghost_p2p.dylib', '${Directory.current.path}/build/p2p/mac/libghost_p2p.dylib'],
      if (PlatformInfo.isWindows) '${beside.path}\\ghost_p2p.dll',
      if (PlatformInfo.isLinux) '${beside.path}/lib/libghost_p2p.so',
    ];
    for (final path in tries) {
      DynamicLibrary? lib;
      try {
        lib = DynamicLibrary.open(path);
      } catch (_) {}
      if (lib != null) yield lib;
    }
    if (PlatformInfo.isIOS) {
      final self = DynamicLibrary.process();
      if (self.providesSymbol('ghost_p2p_abi')) yield self;
    }
  }
}

/// Commands and events by their first byte (native/p2p/README.md).
abstract final class _Cmd {
  static const start = 0x01, stop = 0x02, allow = 0x03, disallow = 0x04, openToAll = 0x05, open = 0x06, send = 0x07, close = 0x08, taken = 0x09, done = 0x0a, networkChanged = 0x0b;
}

abstract final class _Ev {
  static const up = 0x01, down = 0x02, off = 0x03, whereabouts = 0x04, path = 0x05, opened = 0x06, openFailed = 0x07, incoming = 0x08, frame = 0x09, sent = 0x0a, closed = 0x0b;
}

/// What `ghost_p2p_command` answers a SEND with, where it is not 0.
abstract final class _Answer {
  static const overflow = -4, tooLong = -5;
}

/// Why a stream closed, in words to show, by the number CLOSED gives.
const _closedBecause = [
  'The stream was closed.',
  'The other device closed the stream.',
  'The link to the other device was lost.',
  'The direct network was stopped.',
  'The other device is no longer allowed.',
  'More was sent than the stream holds waiting, so it was closed.',
  'The other device sent what is no frame.',
];

const _hexDigits = '0123456789abcdef';

String _hex(Uint8List bytes, int from) {
  final out = StringBuffer();
  for (var i = from; i < from + 32; i++) {
    out
      ..write(_hexDigits[bytes[i] >> 4])
      ..write(_hexDigits[bytes[i] & 15]);
  }
  return out.toString();
}

/// A node id's 32 bytes. [id] is one ([isNodeId]).
Uint8List _unhex(String id) => Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse(id.substring(i, i + 2), radix: 16)]);

/// A command, written from the front.
class _Writer {
  _Writer(int kind) {
    _out.addByte(kind);
  }
  final _out = BytesBuilder(copy: false);

  void u8(int v) => _out.addByte(v & 0xff);
  void u16(int v) => _out.add([(v >> 8) & 0xff, v & 0xff]);
  void u32(int v) => _out.add([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
  void u64(int v) => _out.add((ByteData(8)..setUint64(0, v)).buffer.asUint8List());
  void bytes(List<int> v) => _out.add(v);
  Uint8List take() => _out.takeBytes();
}

/// This device's node on the direct network, by the Rust core ([P2pNode] says what each member means).
class IrohNode implements P2pNode {
  IrohNode._(this._core, this._number);

  /// The number of the C interface this was written against (`ABI` in native/p2p/src/ffi.rs): a library that says
  /// another is not used.
  static const abi = 1;

  /// Whether this build has the library, and it is the one this file was written against.
  static bool get available => _Core.open() != null;

  /// A node, not started; null where [available] is not.
  static IrohNode? make() {
    final core = _Core.open();
    if (core == null) return null;
    final number = core.make(_Core.owner, core.events.nativeFunction);
    if (number == 0) return null;
    return _nodes[number] = IrohNode._(core, number);
  }

  /// Every node this isolate has made and not let go of, by the library's number for it.
  static final _nodes = <int, IrohNode>{};

  final _Core _core;
  final int _number;
  bool _gone = false;

  final _state = ValueNotifier<P2pState>(P2pState.off);
  final _whereabouts = ValueNotifier<Whereabouts?>(null);
  final _opened = StreamController<P2pStream>.broadcast();
  final _paths = StreamController<P2pPath>.broadcast();
  final _pathNow = <String, P2pPath>{};
  final _streams = <int, _IrohStream>{};
  final _opening = <int, _Opening>{};
  int _nextRequest = 1;
  String? _nodeId, _problem;
  P2pConfig? _config;
  Completer<void>? _started, _stopped;

  /// [start] and [stop] one at a time, in the order they were asked.
  Future<void> _turn = Future<void>.value();

  Future<void> _inTurn(Future<void> Function() what) {
    final done = _turn.then((_) => what());
    _turn = done.then((_) {}, onError: (_) {});
    return done;
  }

  @override
  String? get nodeId => _nodeId;

  @override
  ValueListenable<P2pState> get state => _state;

  @override
  String? get problem => _problem;

  @override
  ValueListenable<Whereabouts?> get whereabouts => _whereabouts;

  @override
  Stream<P2pStream> get opened => _opened.stream;

  @override
  Stream<P2pPath> get paths => _paths.stream;

  @override
  P2pPath? pathTo(String nodeId) => _pathNow[nodeId];

  @override
  Future<String> idOf(Uint8List secret) async => _idOf(secret);

  String _idOf(Uint8List secret) {
    if (secret.length != 32) throw P2pError('A node key is 32 bytes; this one is ${secret.length}.');
    final both = malloc<Uint8>(64);
    try {
      both.asTypedList(32).setAll(0, secret);
      if (_core.nodeId(both, both + 32) != 0) throw P2pError('The direct network could not read the node key.');
      return _hex(both.asTypedList(64), 32);
    } finally {
      // The key does not stay in memory this side no longer holds.
      both.asTypedList(64).fillRange(0, 64, 0);
      malloc.free(both);
    }
  }

  /// Why [config] can't be started with, in words to show; null where it can.
  String? _wrong(P2pConfig config) {
    if (config.secret.length != 32) return 'A node key is 32 bytes; this one is ${config.secret.length}.';
    if (config.helpers.length > 8) return 'A node takes eight link helpers at most; it was given ${config.helpers.length}.';
    for (final helper in config.helpers) {
      if (!helper.startsWith('https://') || utf8.encode(helper).length > 200) return 'This is not a link helper\'s address: $helper';
    }
    if (config.helpersOnly && config.helpers.isEmpty) return 'Only through link helpers was chosen, and there is no link helper.';
    return null;
  }

  /// Done when the node is up, or could not come up ([state] is then [P2pState.down] and [problem] says why): it
  /// does not throw for that.
  @override
  Future<void> start(P2pConfig config) => _inTurn(() async {
        if (_gone) throw P2pError('This node was let go.');
        if (_state.value == P2pState.up && _config == config) return;
        if (_state.value != P2pState.off) await _stop();
        _config = config;
        final wrong = _wrong(config);
        if (wrong != null) {
          _problem = wrong;
          _state.value = P2pState.down;
          return;
        }
        _nodeId = _idOf(config.secret);
        _problem = null;
        _state.value = P2pState.starting;
        final started = _started = Completer<void>();
        final command = _Writer(_Cmd.start)
          ..u8(config.helpersOnly ? 1 : 0)
          ..bytes(config.secret)
          ..u8(config.helpers.length);
        for (final helper in config.helpers) {
          final text = utf8.encode(helper);
          command
            ..u16(text.length)
            ..bytes(text);
        }
        final answer = _command(command.take());
        if (answer != 0) {
          _started = null;
          _problem = 'The direct network did not take the start (it answered $answer).';
          _state.value = P2pState.down;
          return;
        }
        // The library always answers; the wait is only so that a bug there is a node that is down, not one that
        // is starting for ever.
        await started.future.timeout(const Duration(seconds: 30), onTimeout: () {
          if (_state.value == P2pState.starting) {
            _problem = 'The direct network did not start.';
            _state.value = P2pState.down;
          }
        });
      });

  /// Done when everything is closed: every stream, every link, the sockets.
  @override
  Future<void> stop() => _inTurn(() async {
        if (_gone || _state.value == P2pState.off) return;
        await _stop();
      });

  Future<void> _stop() async {
    final stopped = _stopped = Completer<void>();
    if (_command(Uint8List.fromList([_Cmd.stop])) == 0) await stopped.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    _stopped = null;
    _nowOff();
  }

  /// Nothing is up: said by the library (OFF), or taken to be so where it never said.
  void _nowOff() {
    _problem = null;
    _whereabouts.value = null;
    _endEverything('The direct network was stopped.');
    _state.value = P2pState.off;
  }

  /// Every stream ends and every open under way fails: the node is not up to carry them.
  void _endEverything(String why) {
    for (final stream in _streams.values.toList()) {
      stream._ended(why);
    }
    _streams.clear();
    for (final opening in _opening.values.toList()) {
      opening.fail(why);
    }
    _opening.clear();
    for (final path in _pathNow.values.toList()) {
      if (!_paths.isClosed) _paths.add(P2pPath(path.nodeId, P2pPathKind.none));
    }
    _pathNow.clear();
  }

  @override
  void networkChanged() => _command(Uint8List.fromList([_Cmd.networkChanged]));

  /// In force when this returns: a stream that comes after it is judged by it.
  @override
  void allow(String nodeId, Set<int> channels) {
    if (!isNodeId(nodeId)) throw ArgumentError.value(nodeId, 'nodeId', 'not a node id');
    final list = _channels(channels);
    _command((_Writer(_Cmd.allow)
          ..bytes(_unhex(nodeId))
          ..u8(list.length)
          ..bytes(list))
        .take());
  }

  @override
  void disallow(String nodeId) {
    if (!isNodeId(nodeId)) throw ArgumentError.value(nodeId, 'nodeId', 'not a node id');
    _command((_Writer(_Cmd.disallow)..bytes(_unhex(nodeId))).take());
  }

  @override
  void openToAll(Set<int> channels) {
    final list = _channels(channels);
    _command((_Writer(_Cmd.openToAll)
          ..u8(list.length)
          ..bytes(list))
        .take());
  }

  /// A channel is one byte on the wire.
  List<int> _channels(Set<int> channels) {
    for (final c in channels) {
      if (c < 0 || c > 255) throw ArgumentError.value(c, 'channels', 'a channel is 0 to 255');
    }
    return channels.toList()..sort();
  }

  @override
  Future<P2pStream> open(String nodeId, int channel, {Whereabouts? hint, Duration timeout = const Duration(seconds: 5)}) {
    if (!isNodeId(nodeId)) return Future.error(P2pError('That is not a node id.'));
    if (channel < 0 || channel > 255) return Future.error(P2pError('A channel is 0 to 255.'));
    if (_gone || _state.value != P2pState.up) return Future.error(P2pError('The direct network is not up.'));
    final request = _nextRequest;
    _nextRequest = _nextRequest >= 0xffffffff ? 1 : _nextRequest + 1;
    final wait = timeout.inMilliseconds.clamp(0, 0xffffffff);
    // What the other device last said of where it is, as far as the library takes it (a helper of 200 bytes, eight
    // addresses of 64); the library itself uses a helper only where it is one of this node's own.
    final helper = utf8.encode(hint?.helper ?? '');
    final addresses = [
      for (final a in hint?.addresses ?? const <String>[])
        if (a.isNotEmpty && utf8.encode(a).length <= 64) utf8.encode(a),
    ].take(Whereabouts.mostAddresses).toList();
    final command = _Writer(_Cmd.open)
      ..u32(request)
      ..bytes(_unhex(nodeId))
      ..u8(channel)
      ..u32(wait)
      ..u16(helper.length <= 200 ? helper.length : 0)
      ..bytes(helper.length <= 200 ? helper : const [])
      ..u8(addresses.length);
    for (final a in addresses) {
      command
        ..u8(a.length)
        ..bytes(a);
    }
    final opening = _Opening(nodeId, channel);
    _opening[request] = opening;
    if (_command(command.take()) != 0) {
      _opening.remove(request);
      return Future.error(P2pError('The direct network is not up.'));
    }
    // The library answers within the wait it was given. This is that wait and a little, for a library that never
    // answers: the open fails, and a stream that turns up after all is closed.
    opening.late = Timer(Duration(milliseconds: wait) + const Duration(seconds: 5), () {
      if (_opening.remove(request) != null) opening.fail('The direct network did not answer.');
    });
    return opening.done.future;
  }

  /// Stops the node and lets go of it: nothing can be asked of it again. (Not part of [P2pNode]: the app keeps its
  /// node for as long as it runs; a test lets go of the ones it made.)
  void dispose() {
    if (_gone) return;
    _gone = true;
    _nodes.remove(_number);
    // Once this returns the library hands this node's events to nobody.
    _core.drop(_number);
    _started?.complete();
    _stopped?.complete();
    _nowOff();
    _opened.close();
    _paths.close();
  }

  int _command(Uint8List bytes) {
    if (_gone) return -1;
    final at = malloc<Uint8>(bytes.length);
    try {
      at.asTypedList(bytes.length).setAll(0, bytes);
      return _core.command(_number, at, bytes.length);
    } finally {
      malloc.free(at);
    }
  }

  /// SEND, written straight into what the library reads from: a frame of the most is copied once this side.
  int _sendFrame(int stream, Uint8List frame) {
    if (_gone) return -1;
    final len = 9 + frame.length;
    final at = malloc<Uint8>(len);
    try {
      final bytes = at.asTypedList(len);
      bytes[0] = _Cmd.send;
      ByteData.sublistView(bytes).setUint64(1, stream);
      bytes.setRange(9, len, frame);
      return _core.command(_number, at, len);
    } finally {
      malloc.free(at);
    }
  }

  void _taken(int stream, int frames, int bytes) => _command((_Writer(_Cmd.taken)
        ..u64(stream)
        ..u32(frames)
        ..u32(bytes))
      .take());

  void _close(int stream) => _command((_Writer(_Cmd.close)..u64(stream)).take());

  void _done(int stream) => _command((_Writer(_Cmd.done)..u64(stream)).take());

  /// The library's threads said something (through the isolate's port, so this runs in its turn like anything else
  /// here). The bytes are copied and given back before anything is made of them; a frame is copied by itself, so
  /// what a listener is handed is a list of its own and nothing more.
  static void _hear(int number, Pointer<Uint8> event, int len) {
    final core = _Core._opened;
    Uint8List? bytes;
    Uint8List? frame;
    try {
      if (len > 0) {
        final there = event.asTypedList(len);
        if (there[0] == _Ev.frame && len >= 9) {
          bytes = Uint8List.fromList(Uint8List.sublistView(there, 0, 9));
          frame = Uint8List.fromList(Uint8List.sublistView(there, 9));
        } else {
          bytes = Uint8List.fromList(there);
        }
      }
    } finally {
      core?.bufferFree(event, len);
    }
    final node = _nodes[number];
    if (node == null || bytes == null) return;
    try {
      node._on(bytes, frame);
    } catch (error, stack) {
      // One event that could not be read does not stop the ones after it.
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'the direct network', context: ErrorDescription('while reading what the core said')));
    }
  }

  void _on(Uint8List b, Uint8List? frame) {
    final d = ByteData.sublistView(b);
    switch (b[0]) {
      case _Ev.up:
        if (b.length < 33) return;
        _nodeId = _hex(b, 1);
        _problem = null;
        _state.value = P2pState.up;
        _started?.complete();
        _started = null;
      case _Ev.down:
        _problem = b.length > 1 ? utf8.decode(Uint8List.sublistView(b, 1), allowMalformed: true) : 'The direct network could not start.';
        _whereabouts.value = null;
        _endEverything('The direct network is down.');
        _state.value = P2pState.down;
        _started?.complete();
        _started = null;
      case _Ev.off:
        final stopped = _stopped;
        if (stopped != null && !stopped.isCompleted) {
          stopped.complete();
        } else {
          // Stopped by a start with other settings inside the library, not by this side's asking.
          _nowOff();
        }
      case _Ev.whereabouts:
        if (b.length < 4) return;
        final helperLen = d.getUint16(1);
        var at = 3 + helperLen;
        if (b.length < at + 1) return;
        final helper = helperLen == 0 ? null : utf8.decode(Uint8List.sublistView(b, 3, at), allowMalformed: true);
        final addresses = <String>[];
        final count = b[at++];
        for (var i = 0; i < count; i++) {
          if (b.length < at + 1) return;
          final n = b[at++];
          if (b.length < at + n) return;
          addresses.add(utf8.decode(Uint8List.sublistView(b, at, at + n), allowMalformed: true));
          at += n;
        }
        if (_state.value == P2pState.up) _whereabouts.value = Whereabouts(helper: helper, addresses: List.unmodifiable(addresses), at: DateTime.now().millisecondsSinceEpoch);
      case _Ev.path:
        if (b.length < 38) return;
        final node = _hex(b, 1);
        final kind = switch (b[33]) { 1 => P2pPathKind.helper, 2 => P2pPathKind.direct, _ => P2pPathKind.none };
        final rtt = d.getUint32(34);
        final path = P2pPath(node, kind, rttMs: rtt == 0xffffffff ? null : rtt);
        if (kind == P2pPathKind.none) {
          _pathNow.remove(node);
        } else {
          _pathNow[node] = path;
        }
        _paths.add(path);
      case _Ev.opened:
        if (b.length < 13) return;
        final opening = _opening.remove(d.getUint32(1));
        final id = d.getUint64(5);
        if (opening == null) {
          // Nobody is waiting for it any longer.
          _close(id);
          _done(id);
          return;
        }
        final stream = _streams[id] = _IrohStream(this, id, opening.nodeId, opening.channel, incoming: false);
        opening.late?.cancel();
        opening.done.complete(stream);
      case _Ev.openFailed:
        if (b.length < 6) return;
        _opening.remove(d.getUint32(1))?.fail(b.length > 6 ? utf8.decode(Uint8List.sublistView(b, 6), allowMalformed: true) : 'It could not be reached.');
      case _Ev.incoming:
        if (b.length < 42) return;
        final id = d.getUint64(1);
        final stream = _streams[id] = _IrohStream(this, id, _hex(b, 9), b[41], incoming: true);
        if (_opened.hasListener) {
          _opened.add(stream);
        } else {
          // Nobody is there to take it.
          stream.close();
        }
      case _Ev.frame:
        if (frame == null) return;
        final id = d.getUint64(1);
        final stream = _streams[id];
        if (stream == null) {
          _taken(id, 1, frame.length);
        } else {
          stream._frame(frame);
        }
      case _Ev.sent:
        if (b.length < 17) return;
        _streams[d.getUint64(1)]?._sent(d.getUint64(9));
      case _Ev.closed:
        if (b.length < 10) return;
        final id = d.getUint64(1);
        _streams.remove(id)?._ended(b[9] < _closedBecause.length ? _closedBecause[b[9]] : 'The stream was closed.');
        // Its end is handled: whatever the library still counted for it is let go.
        _done(id);
    }
  }
}

/// An [IrohNode.open] under way.
class _Opening {
  _Opening(this.nodeId, this.channel);
  final String nodeId;
  final int channel;
  final done = Completer<P2pStream>();
  Timer? late;

  void fail(String why) {
    late?.cancel();
    if (!done.isCompleted) done.completeError(P2pError(why));
  }
}

class _IrohStream implements P2pStream {
  _IrohStream(this._node, this._id, this.nodeId, this.channel, {required this.incoming});

  final IrohNode _node;
  final int _id;

  @override
  final String nodeId;
  @override
  final int channel;
  @override
  final bool incoming;

  /// Frames wait here until someone listens, and while whoever listens is paused: the library is told they were
  /// taken only as they go on from here, so it reads no more than a stream's worth ahead of a listener.
  late final StreamController<Uint8List> _frames = StreamController<Uint8List>(onListen: _flow, onResume: _flow, onCancel: _unheard);

  /// Frames that are in [_frames] and not yet said to be taken, and their bytes.
  int _heldFrames = 0, _heldBytes = 0;

  /// The listener went away: what comes is taken and dropped.
  bool _deaf = false;

  /// Closed here ([close] was called), and over (the library said so, or the node stopped).
  bool _closing = false, _over = false;
  String _why = 'The stream has closed.';
  Completer<void>? _closed;

  /// One for each frame queued and not yet written, oldest first; and how many the library has said it wrote.
  final _sending = Queue<Completer<void>>();
  int _written = 0;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  void _flow() {
    if (_heldFrames == 0 || _over) return;
    _node._taken(_id, _heldFrames, _heldBytes);
    _heldFrames = 0;
    _heldBytes = 0;
  }

  void _unheard() {
    _deaf = true;
    _flow();
  }

  void _frame(Uint8List frame) {
    if (_closing || _deaf || _frames.isClosed) {
      _node._taken(_id, 1, frame.length);
      return;
    }
    _frames.add(frame);
    if (_frames.hasListener && !_frames.isPaused) {
      _node._taken(_id, 1, frame.length);
    } else {
      _heldFrames++;
      _heldBytes += frame.length;
    }
  }

  void _sent(int written) {
    while (_written < written && _sending.isNotEmpty) {
      _sending.removeFirst().complete();
      _written++;
    }
  }

  void _ended(String why) {
    if (_over) return;
    _over = true;
    if (!_closing) _why = why;
    for (final waiting in _sending) {
      waiting.completeError(P2pError(_why));
    }
    _sending.clear();
    if (!_frames.isClosed) _frames.close();
    _closed?.complete();
  }

  Future<void> _no(String why) {
    // Failed for whoever awaits it; not an error with nobody to hear it for whoever does not.
    final failed = Future<void>.error(P2pError(why));
    failed.ignore();
    return failed;
  }

  /// Done when the frame has been handed to the link, in its turn after the ones before it.
  @override
  Future<void> add(Uint8List frame) {
    if (_closing || _over) return _no(_why);
    if (frame.length > P2pNode.maxFrame) return _no('A frame is ${P2pNode.maxFrame} bytes at most; this one is ${frame.length}.');
    switch (_node._sendFrame(_id, frame)) {
      case 0:
        final written = Completer<void>();
        written.future.ignore();
        _sending.add(written);
        return written.future;
      case _Answer.overflow:
        _why = _closedBecause[5];
        return _no(_why);
      case _Answer.tooLong:
        return _no('A frame is ${P2pNode.maxFrame} bytes at most; this one is ${frame.length}.');
      default:
        return _no(_why);
    }
  }

  /// Done when the other end has seen the end (or was given a few seconds to), after everything added before.
  @override
  Future<void> close() {
    if (_over) return Future.value();
    if (!_closing) {
      _closing = true;
      _closed = Completer<void>();
      _node._close(_id);
      // What had come is still there for whoever listens; nothing more is.
      _frames.close();
    }
    return _closed!.future;
  }
}
