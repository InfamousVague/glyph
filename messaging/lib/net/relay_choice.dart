/// Using a relay server of one's own (GMFB-25, "Self-hosting the relay, documented", from the Uplink gap review):
/// what a typed address becomes, whether a Ghost Messaging relay answers at it before the app moves there, and how the
/// relay in use is named in Settings › Routes. How to run one is docs/SELF_HOSTING.md.
///
/// What a relay of one's own does and doesn't reach (said in Settings › Routes and the docs): relays don't talk to
/// each other. Friends, usernames, sealed account backups, circles, spaces, invite words and held messages live on
/// the relay they were made on, so only people using the same relay reach each other through it. Texts (SMS) don't
/// go through any relay. The Marketplace is always read from Ghost Messaging's own relay.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'net.dart';

/// Whether [url] is Ghost Messaging's own relay (gogho.st, or ghost-sms.com from before the move).
bool isOwnRelay(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  return host == 'gogho.st' || host == 'ghost-sms.com' || host == 'www.gogho.st';
}

/// The relay in use, in a line for Settings › Routes.
String relayInUseWords(String hubUrl) {
  if (hubUrl == Net.defaultHub) return 'Ghost Messaging\'s relay (gogho.st)';
  final u = Uri.tryParse(hubUrl);
  final host = u == null ? hubUrl : '${u.host}${u.hasPort ? ':${u.port}' : ''}';
  if (isOwnRelay(hubUrl)) return 'Ghost Messaging\'s relay ($host)';
  return 'Your own relay: $host';
}

/// What a typed address becomes: a WebSocket address ending in /hub. `relay.example.com` is
/// `wss://relay.example.com/hub`; `https://` is `wss://` and `http://` is `ws://`; a path not ending in /hub has /hub
/// put on it; a query or a fragment is dropped. Null where it can't be an address (no host, another scheme, spaces).
/// Empty is empty: Ghost Messaging's own again.
String? tidyRelayAddress(String typed) {
  var s = typed.trim();
  if (s.isEmpty) return '';
  if (s.contains(RegExp(r'\s'))) return null;
  if (!s.contains('://')) s = 'wss://$s';
  final Uri u;
  try {
    u = Uri.parse(s);
  } catch (_) {
    return null;
  }
  final scheme = switch (u.scheme.toLowerCase()) {
    'wss' || 'https' => 'wss',
    'ws' || 'http' => 'ws',
    _ => null,
  };
  if (scheme == null || u.host.isEmpty || u.userInfo.isNotEmpty) return null;
  var path = u.path.replaceAll(RegExp(r'/+$'), '');
  if (!path.endsWith('/hub')) path = '$path/hub';
  return Uri(scheme: scheme, host: u.host.toLowerCase(), port: u.hasPort ? u.port : null, path: path).toString();
}

/// What came of asking an address whether it is a Ghost Messaging relay.
class RelayCheck {
  const RelayCheck.answered(this.took) : problem = null;
  const RelayCheck.failed(this.problem) : took = null;

  /// Why it isn't usable, in words; null where a relay answered.
  final String? problem;

  /// How long it took to answer.
  final Duration? took;

  bool get ok => problem == null;
}

/// Opens a WebSocket to [url] (a test's stand-in where given).
typedef RelayConnect = Future<WebSocket> Function(String url);

/// Asks [url] (already tidied) whether a Ghost Messaging relay's hub is there: it connects and waits for the hub's
/// greeting (`{"hello": <hex>}`, relay/lib/hub.dart), then closes without signing in. Nothing about this install is
/// sent. A server that answers something else, or nothing within [timeout], is not one.
Future<RelayCheck> checkRelay(String url, {Duration timeout = const Duration(seconds: 8), RelayConnect? connect}) async {
  final started = DateTime.now();
  WebSocket ws;
  try {
    ws = await (connect ?? WebSocket.connect)(url).timeout(timeout);
  } on TimeoutException {
    return const RelayCheck.failed('Nothing answered there in time.');
  } catch (e) {
    return RelayCheck.failed('Couldn\'t connect: ${_short(e)}');
  }
  final greeted = Completer<bool>();
  final sub = ws.listen(
    (data) {
      if (greeted.isCompleted) return;
      try {
        final m = data is String ? jsonDecode(data) : null;
        greeted.complete(m is Map && m['hello'] is String && RegExp(r'^[0-9a-f]{16,128}$').hasMatch(m['hello'] as String));
      } catch (_) {
        greeted.complete(false);
      }
    },
    onDone: () => greeted.isCompleted ? null : greeted.complete(false),
    onError: (_) => greeted.isCompleted ? null : greeted.complete(false),
    cancelOnError: true,
  );
  final left = timeout - DateTime.now().difference(started);
  final bool ok;
  try {
    ok = await greeted.future.timeout(left.isNegative ? Duration.zero : left);
  } on TimeoutException {
    await _close(ws, sub);
    return const RelayCheck.failed('A server answered there, but not as a Ghost Messaging relay.');
  }
  await _close(ws, sub);
  if (!ok) return const RelayCheck.failed('A server answered there, but not as a Ghost Messaging relay.');
  return RelayCheck.answered(DateTime.now().difference(started));
}

Future<void> _close(WebSocket ws, StreamSubscription<dynamic> sub) async {
  await sub.cancel().catchError((_) {});
  await ws.close().timeout(const Duration(seconds: 2)).catchError((_) {});
}

String _short(Object e) {
  final s = e is SocketException ? e.message.isEmpty ? '$e' : e.message : e is WebSocketException ? e.message : '$e';
  final line = s.split('\n').first.trim();
  return line.length > 120 ? '${line.substring(0, 120)}…' : line;
}
