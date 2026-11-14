import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'hub.dart';
import 'sha256.dart';

/// Ghost Messaging's relay (docs/desktop.md): a WebSocket server a phone and the computer it is paired with both dial
/// out to when they are on different networks. It passes what one sends to the other while both are connected, and
/// that is all.
///
/// - A pairing has a **channel** (32 hex digits, the last part of the address) and a **token** (64 hex digits), both
///   made by the two ends from the key only they hold. The first to name a channel sets its token; from then only
///   holders of it get in, one phone and one computer at a time.
/// - **What is kept:** for each channel, the SHA-256 of its token and the day it was last used. No frame is ever
///   written anywhere or held for later: with the other end away a frame is dropped and its sender told.
/// - **What it can see:** that two addresses share a channel, when, and how much they send. The frames are sealed
///   with a key it never has (android/.../DeskCrypto.kt, lib/desktop/link/crypto.dart), and it logs no addresses.
/// - A channel is removed when either end says so (unpairing), or after ninety days unused. One made for pairing
///   (`temp`) lives ten minutes at most, goes as soon as both ends have left it, and is never written to disk.
class Relay {
  Relay({this.dataDir, DateTime Function()? now, this.verbose = false, this.hub}) : _now = now ?? DateTime.now;

  /// Where people's apps find each other (hub.dart), served at any address ending in `/hub`; none where null.
  final Hub? hub;

  /// Where `channels.json` is kept; null keeps nothing across restarts.
  final Directory? dataDir;
  final bool verbose;
  final DateTime Function() _now;

  static const maxFrame = (1 << 20) + 64;
  static const tempLife = Duration(minutes: 10);
  static const idleLife = Duration(days: 90);
  static const authWait = Duration(seconds: 10);
  static const maxChannels = 200000;

  final Map<String, _Channel> _channels = {};
  HttpServer? _server;
  Timer? _sweeper;
  Timer? _saver;

  int get channelCount => _channels.length;

  /// Starts listening; the port it got (ask for 0 to be given a free one).
  Future<int> start({String host = '127.0.0.1', int port = 8787}) async {
    _load();
    final server = await HttpServer.bind(host, port);
    _server = server;
    server.listen(_handle, onError: (_) {});
    hub?.start();
    _sweeper = Timer.periodic(const Duration(minutes: 1), (_) => sweep());
    return server.port;
  }

  Future<void> stop() async {
    _sweeper?.cancel();
    _saver?.cancel();
    hub?.stop();
    _save();
    for (final c in _channels.values) {
      c.phone?.close(WebSocketStatus.goingAway);
      c.desk?.close(WebSocketStatus.goingAway);
    }
    await _server?.close(force: true);
  }

  static final _hexOnly = RegExp(r'^[0-9a-f]+$');
  static bool _hex(Object? text, int length) => text is String && text.length == length && _hexOnly.hasMatch(text);

  String _day() => _now().toUtc().toIso8601String().substring(0, 10);

  void _say(String what) {
    // Never an address, never a whole channel: enough to follow a pairing while trying the relay on a desk.
    if (verbose) stdout.writeln('${_now().toIso8601String()} $what');
  }

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final name = segments.isEmpty ? '' : segments.last;
    final upgrade = WebSocketTransformer.isUpgradeRequest(request);
    // The hub is its own thing with its own way in (hub.dart): `/hub`, behind whatever the web server puts before it.
    if (upgrade && name == 'hub' && hub != null) return hub!.accept(request);
    if (!upgrade || !_hex(name, 32)) {
      request.response
        ..statusCode = upgrade ? HttpStatus.notFound : HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('Ghost Messaging relay\n');
      await request.response.close();
      return;
    }
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      return;
    }
    ws.pingInterval = const Duration(seconds: 30);

    _Channel? channel;
    String role = '';
    final waiting = Timer(authWait, () {
      if (channel == null) ws.close(4401, 'no token');
    });

    void leave() {
      waiting.cancel();
      final c = channel;
      if (c == null) return;
      channel = null;
      if (c.socket(role) != ws) return; // replaced by a newer connection of the same end
      c.set(role, null);
      _tell(c.other(role), {'peer': false});
      _say('${name.substring(0, 6)} $role left');
      // A channel made for pairing is done with once both ends have gone: it does not wait out its ten minutes.
      if (c.expires != null && c.phone == null && c.desk == null && identical(_channels[name], c)) _channels.remove(name);
    }

    ws.listen((data) {
      final c = channel;
      if (c == null) {
        // The first thing said is the token and which end this is.
        Map? hello;
        try {
          hello = data is String ? jsonDecode(data) as Map : null;
        } catch (_) {}
        final token = hello?['auth'];
        final asRole = hello?['role'];
        if (!_hex(token, 64) || (asRole != 'phone' && asRole != 'desk')) {
          _tell(ws, {'ok': false, 'err': 'bad hello'});
          ws.close(4400, 'bad hello');
          return;
        }
        final joined = _join(name, token as String, hello?['temp'] == true);
        if (joined == null) {
          _tell(ws, {'ok': false, 'err': 'refused'});
          ws.close(4403, 'refused');
          return;
        }
        waiting.cancel();
        role = asRole as String;
        joined.socket(role)?.close(4409, 'replaced');
        joined.set(role, ws);
        channel = joined;
        _tell(ws, {'ok': true, 'peer': joined.other(role) != null});
        _tell(joined.other(role), {'peer': true});
        _say('${name.substring(0, 6)} $role joined${joined.expires != null ? ' (pairing)' : ''}');
        return;
      }
      if (data is List<int>) {
        if (data.length > maxFrame) {
          ws.close(WebSocketStatus.messageTooBig, 'too big');
          return;
        }
        final other = c.other(role);
        if (other == null || other.readyState != WebSocket.open) {
          _tell(ws, {'dropped': true});
        } else {
          other.add(data);
        }
        return;
      }
      Map? said;
      try {
        said = jsonDecode(data as String) as Map;
      } catch (_) {}
      if (said?['delete'] == true) {
        _remove(name, 'deleted');
      } else if (said != null && said.containsKey('ping')) {
        _tell(ws, {'pong': said['ping']});
      }
    }, onDone: leave, onError: (_) => leave(), cancelOnError: true);
  }

  /// Something the relay itself says to an end, in words; nothing is said to one that has gone.
  void _tell(WebSocket? ws, Map<String, Object?> what) {
    if (ws == null || ws.readyState != WebSocket.open) return;
    try {
      ws.add(jsonEncode(what));
    } catch (_) {}
  }

  /// The channel [name] for a holder of [token]: made if it is new, null if the token is not its own.
  _Channel? _join(String name, String token, bool temp) {
    final hash = hexOf(sha256(utf8.encode(token)));
    final had = _channels[name];
    if (had != null && had.expires != null && !_now().isBefore(had.expires!)) {
      _remove(name, 'expired');
    }
    final c = _channels[name];
    if (c != null) {
      if (c.hash != hash) return null;
      if (c.expires == null && c.day != _day()) {
        c.day = _day();
        _saveSoon();
      }
      return c;
    }
    if (_channels.length >= maxChannels) return null;
    final made = _Channel(hash, _day(), temp ? _now().add(tempLife) : null);
    _channels[name] = made;
    if (!temp) _saveSoon();
    return made;
  }

  void _remove(String name, String why) {
    final c = _channels.remove(name);
    if (c == null) return;
    final ends = [c.phone, c.desk];
    c.phone = null;
    c.desk = null;
    for (final ws in ends) {
      ws?.close(4410, why);
    }
    if (c.expires == null) _saveSoon();
    _say('${name.substring(0, 6)} $why');
  }

  /// Removes pairing channels past their ten minutes, and channels nobody has used for ninety days.
  void sweep() {
    final now = _now();
    final cutoff = now.subtract(idleLife).toUtc().toIso8601String().substring(0, 10);
    for (final name in _channels.keys.toList()) {
      final c = _channels[name]!;
      if (c.expires != null) {
        if (!now.isBefore(c.expires!)) _remove(name, 'expired');
      } else if (c.phone == null && c.desk == null && c.day.compareTo(cutoff) < 0) {
        _remove(name, 'unused');
      }
    }
  }

  // --- what is kept ----------------------------------------------------------------------------------------------------

  File? get _file => dataDir == null ? null : File('${dataDir!.path}/channels.json');

  void _load() {
    final f = _file;
    if (f == null || !f.existsSync()) return;
    try {
      final all = (jsonDecode(f.readAsStringSync()) as Map)['channels'] as Map;
      for (final e in all.entries) {
        final v = e.value as Map;
        if (_hex(e.key, 32) && _hex(v['h'], 64) && v['d'] is String) _channels[e.key as String] = _Channel(v['h'] as String, v['d'] as String, null);
      }
    } catch (e) {
      stderr.writeln('channels.json could not be read: $e');
    }
    sweep();
  }

  void _saveSoon() {
    if (dataDir == null) return;
    _saver?.cancel();
    _saver = Timer(const Duration(seconds: 2), _save);
  }

  void _save() {
    final f = _file;
    if (f == null) return;
    try {
      dataDir!.createSync(recursive: true);
      final kept = {
        for (final e in _channels.entries)
          if (e.value.expires == null) e.key: {'h': e.value.hash, 'd': e.value.day},
      };
      final tmp = File('${f.path}.tmp')..writeAsStringSync(jsonEncode({'v': 1, 'channels': kept}));
      tmp.renameSync(f.path);
    } catch (e) {
      stderr.writeln('channels.json could not be written: $e');
    }
  }
}

class _Channel {
  _Channel(this.hash, this.day, this.expires);

  /// SHA-256 of the channel's token, in hex.
  final String hash;

  /// The day (UTC) it was last joined.
  String day;

  /// When a channel made for pairing ends; null for a pairing's own.
  final DateTime? expires;
  WebSocket? phone;
  WebSocket? desk;

  WebSocket? socket(String role) => role == 'phone' ? phone : desk;
  WebSocket? other(String role) => role == 'phone' ? desk : phone;
  void set(String role, WebSocket? ws) => role == 'phone' ? phone = ws : desk = ws;
}
