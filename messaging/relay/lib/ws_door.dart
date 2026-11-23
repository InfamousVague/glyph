import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'sha1.dart';

/// A WebSocket's doors, with a ceiling on a message's length in front of Dart's own parser (found in the review of
/// relays that talk, 2026-11-22). Dart's WebSocket holds a whole message in memory before anything can look at its
/// length, and takes as many bytes as arrive: one frame that says it is a terabyte long is read until the process has
/// nothing left, and so are a million small pieces of one message. Compression is off at every door already
/// (no_compression_test.dart); this is the rest of it.
///
/// So the socket is taken from the upgrade here ([upgradeGuarded] for a door that is dialled, [dialGuarded] for a
/// connection this relay makes), and every byte that comes in passes a [FrameGuard] first: it reads only the frames'
/// headers, skips over what they carry, and ends the socket the moment a message would be longer than that door takes,
/// before a byte of it is held. The handshake is made here as Dart's own makes it (RFC 6455, section 4), held to the
/// RFC's own example in test/ws_door_test.dart. Nothing but Dart's own library.

/// The longest first message any door takes: a hello, which is a few hundred bytes.
const firstMost = 16 << 10;

/// RFC 6455's string, added to the key before it is hashed.
const _guid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// What a server answers the key [key] with (`Sec-WebSocket-Accept`, RFC 6455, section 4.2.2).
String acceptOf(String key) => base64Encode(sha1(ascii.encode('${key.trim()}$_guid')));

/// Reads the headers of the frames that come in, and nothing of what they carry: whether each message stays within
/// what its door takes ([most]; [first] for the first message, which is a hello at every door). Told every byte in
/// order ([take]); the first one past a limit, it says no and why ([why]), and says no from then on.
class FrameGuard {
  FrameGuard({required this.most, int? first, this.framesAMessage = 1024}) : first = first ?? most;

  /// The longest a message may be, its frames' payloads together; and the first message.
  final int most;
  final int first;

  /// The most frames one message may come in. Each piece Dart holds is a small object of its own, so a message in a
  /// million one-byte pieces costs far more than its length; no app sends one in more than a few.
  final int framesAMessage;

  /// Why it said no, once it has.
  String? why;

  static const _head = 0, _length = 1, _moreLength = 2, _mask = 3, _payload = 4;
  int _at = _head;
  bool _fin = false, _control = false, _masked = false;
  int _lengthBytes = 0, _len = 0, _left = 0;
  bool _inMessage = false;
  int _messages = 0, _message = 0, _frames = 0;

  int get _ceiling => _messages <= 1 ? first : most;

  /// Reads [bytes], the next that came in; false where the connection must end.
  bool take(List<int> bytes) {
    if (why != null) return false;
    var i = 0;
    final n = bytes.length;
    while (i < n) {
      switch (_at) {
        case _head:
          final b = bytes[i++];
          // No extension is agreed at any door, so the three bits kept for them are always nothing.
          if (b & 0x70 != 0) return _no('a frame with bits no extension agreed');
          _fin = b & 0x80 != 0;
          final op = b & 0x0f;
          _control = op >= 8;
          if (_control) {
            if (op > 10) return _no('a frame of no kind a WebSocket has');
            if (!_fin) return _no('a control frame in pieces');
          } else if (op == 0) {
            if (!_inMessage) return _no('a piece of no message');
            if (++_frames > framesAMessage) return _no('a message in too many pieces');
          } else if (op == 1 || op == 2) {
            if (_inMessage) return _no('a message begun inside another');
            _inMessage = true;
            _messages++;
            _message = 0;
            _frames = 1;
          } else {
            return _no('a frame of no kind a WebSocket has');
          }
          _at = _length;
        case _length:
          final b = bytes[i++];
          _masked = b & 0x80 != 0;
          final len = b & 0x7f;
          if (len < 126) {
            _len = len;
            if (!_lengthDone()) return false;
          } else {
            if (_control) return _no('a control frame too long');
            _len = 0;
            _lengthBytes = len == 126 ? 2 : 8;
            _at = _moreLength;
          }
        case _moreLength:
          _len = (_len << 8) | bytes[i++];
          // What is read of the length so far is already the least it can be: past the ceiling, the rest of a length
          // that may be a terabyte's is not waited for. (And so it never grows past a few bits more than the ceiling.)
          if (_message + _len > _ceiling) return _no('a message longer than this door takes');
          if (--_lengthBytes == 0 && !_lengthDone()) return false;
        case _mask:
          final step = min(_left, n - i);
          i += step;
          _left -= step;
          if (_left == 0) _startPayload();
        default:
          final step = min(_left, n - i);
          i += step;
          _left -= step;
          if (_left == 0) _frameDone();
      }
    }
    return true;
  }

  bool _lengthDone() {
    if (_control) {
      if (_len > 125) return _no('a control frame too long');
    } else {
      _message += _len;
      if (_message > _ceiling) return _no('a message longer than this door takes');
    }
    if (_masked) {
      _left = 4;
      _at = _mask;
    } else {
      _startPayload();
    }
    return true;
  }

  void _startPayload() {
    _left = _len;
    _at = _payload;
    if (_left == 0) _frameDone();
  }

  void _frameDone() {
    if (!_control && _fin) _inMessage = false;
    _at = _head;
  }

  bool _no(String reason) {
    why = reason;
    return false;
  }
}

/// A socket whose every incoming byte passes a [FrameGuard] before anything else reads it; one past the guard's limit
/// destroys the socket, and what reads it is told it is done. Everything else is the socket's own.
class GuardedSocket extends Stream<Uint8List> implements Socket {
  GuardedSocket(this._socket, this.guard, {Stream<Uint8List>? incoming}) : _incoming = incoming ?? _socket;

  final Socket _socket;
  final FrameGuard guard;
  final Stream<Uint8List> _incoming;

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    var ended = false;
    return _incoming
        .transform(StreamTransformer<Uint8List, Uint8List>.fromHandlers(handleData: (data, sink) {
          if (ended) return;
          if (guard.take(data)) return sink.add(data);
          ended = true;
          _socket.destroy();
          sink.close();
        }))
        .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  Encoding get encoding => _socket.encoding;
  @override
  set encoding(Encoding value) => _socket.encoding = value;
  @override
  void add(List<int> data) => _socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _socket.addError(error, stackTrace);
  @override
  Future addStream(Stream<List<int>> stream) => _socket.addStream(stream);
  @override
  Future close() => _socket.close();
  @override
  Future get done => _socket.done;
  @override
  Future flush() => _socket.flush();
  @override
  void write(Object? object) => _socket.write(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) => _socket.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
  @override
  void destroy() => _socket.destroy();
  @override
  bool setOption(SocketOption option, bool enabled) => _socket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => _socket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
  @override
  int get port => _socket.port;
  @override
  int get remotePort => _socket.remotePort;
  @override
  InternetAddress get address => _socket.address;
  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
}

/// Upgrades [request] to a WebSocket as Dart's own upgrade does (WebSocketTransformer.upgrade: the same answer,
/// without compression), with a [FrameGuard] holding each message to [most] bytes, the first to [first], before Dart's
/// parser reads it. Null where it is not a WebSocket's request (answered 400) or the socket could not be had.
Future<WebSocket?> upgradeGuarded(HttpRequest request, {required int most, int first = firstMost}) async {
  final key = request.headers.value('sec-websocket-key');
  if (!WebSocketTransformer.isUpgradeRequest(request) || key == null) {
    try {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    } catch (_) {}
    return null;
  }
  final Socket socket;
  try {
    request.response
      ..statusCode = HttpStatus.switchingProtocols
      ..headers.add(HttpHeaders.connectionHeader, 'Upgrade')
      ..headers.add(HttpHeaders.upgradeHeader, 'websocket')
      ..headers.add('Sec-WebSocket-Accept', acceptOf(key))
      ..headers.contentLength = 0;
    socket = await request.response.detachSocket();
  } catch (_) {
    return null;
  }
  return WebSocket.fromUpgradedSocket(GuardedSocket(socket, FrameGuard(most: most, first: first)), serverSide: true, compression: CompressionOptions.compressionOff);
}

/// Why a WebSocket this relay dialled was not made ([dialGuarded]).
class WsRefused implements Exception {
  const WsRefused(this.why);
  final String why;
  @override
  String toString() => why;
}

/// The longest answer to a handshake read before it is given up on.
const _mostHead = 8192;

/// Makes a WebSocket to [url] over [socket], a connection made already (and secured, for `wss`): the handshake is
/// made here (RFC 6455, section 4.1), asking for no extension and no protocol, and taken only where the answer is
/// `101` with the accept the key asks for and neither of them; nothing else is followed anywhere (a redirect is a
/// refusal). Then each message is held to [most] bytes, the first to [first], before Dart's parser reads it.
Future<WebSocket> dialGuarded(Socket socket, Uri url, {required int most, int first = firstMost, Random? random}) async {
  final r = random ?? Random.secure();
  final key = base64Encode([for (var i = 0; i < 16; i++) r.nextInt(256)]);
  final usual = url.scheme == 'wss' ? 443 : 80;
  final port = url.hasPort ? url.port : usual;
  final host = url.host.contains(':') ? '[${url.host}]' : url.host;
  final path = '${url.path.isEmpty ? '/' : url.path}${url.hasQuery ? '?${url.query}' : ''}';
  final ask = 'GET $path HTTP/1.1\r\nHost: $host${port == usual ? '' : ':$port'}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: $key\r\nSec-WebSocket-Version: 13\r\n\r\n';

  // One listener on the socket for the whole of it: the answer's head is read here, and what follows it (the first of
  // the frames, it may be, in the same read) and everything after goes to the WebSocket.
  final rest = StreamController<Uint8List>(sync: true);
  final head = BytesBuilder(copy: true);
  final answered = Completer<Uint8List>();
  var upgraded = false;
  late final StreamSubscription<Uint8List> sub;
  sub = socket.listen((data) {
    if (upgraded) return rest.add(data);
    head.add(data);
    final bytes = head.toBytes();
    final end = _endOfHead(bytes);
    if (end < 0) {
      if (bytes.length > _mostHead && !answered.isCompleted) answered.completeError(const WsRefused('an answer too long to be a handshake\'s'));
      return;
    }
    upgraded = true;
    sub.pause();
    if (!answered.isCompleted) answered.complete(bytes);
  }, onError: (Object e, StackTrace s) {
    if (!answered.isCompleted) return answered.completeError(e, s);
    rest.addError(e, s);
  }, onDone: () {
    if (!answered.isCompleted) return answered.completeError(const WsRefused('closed before it answered'));
    rest.close();
  }, cancelOnError: false);
  rest
    ..onPause = sub.pause
    ..onResume = sub.resume
    ..onCancel = sub.cancel;

  try {
    socket.add(ascii.encode(ask));
    final bytes = await answered.future;
    final end = _endOfHead(bytes);
    final lines = latin1.decode(bytes.sublist(0, end)).split('\r\n');
    final status = RegExp(r'^HTTP/1\.1 (\d{3})(?: |$)').firstMatch(lines.first);
    if (status == null || status.group(1) != '101') throw WsRefused('answered ${status?.group(1) ?? 'with no status'}, not 101');
    final said = <String, List<String>>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) throw const WsRefused('a header that is not one');
      (said[line.substring(0, colon).trim().toLowerCase()] ??= []).add(line.substring(colon + 1).trim());
    }
    String? one(String name) => said[name]?.join(', ');
    if (one('upgrade')?.toLowerCase() != 'websocket') throw const WsRefused('not upgraded to a WebSocket');
    if (!(one('connection') ?? '').toLowerCase().split(',').map((t) => t.trim()).contains('upgrade')) throw const WsRefused('not upgraded to a WebSocket');
    if (one('sec-websocket-accept') != acceptOf(key)) throw const WsRefused('an accept that is not the key\'s');
    if ((one('sec-websocket-extensions') ?? '').isNotEmpty) throw const WsRefused('an extension nobody asked for');
    if ((one('sec-websocket-protocol') ?? '').isNotEmpty) throw const WsRefused('a protocol nobody asked for');
    // What came after the head goes first, through the guard like everything else.
    if (bytes.length > end + 4) rest.add(Uint8List.sublistView(bytes, end + 4));
    sub.resume();
    return WebSocket.fromUpgradedSocket(GuardedSocket(socket, FrameGuard(most: most, first: first), incoming: rest.stream), serverSide: false, compression: CompressionOptions.compressionOff);
  } catch (_) {
    await sub.cancel();
    socket.destroy();
    rethrow;
  }
}

/// Where the head of an HTTP message ends (the index of its blank line's `\r\n\r\n`), or -1 where it hasn't yet.
int _endOfHead(List<int> b) {
  for (var i = 0; i + 3 < b.length; i++) {
    if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
  }
  return -1;
}
