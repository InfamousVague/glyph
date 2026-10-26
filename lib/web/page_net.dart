/// The page's network, where the phone's is `dart:io`'s (docs/WEB.md): the browser's `fetch` for every [Fetcher],
/// and its `WebSocket` for the relay. Only in the web build; page_net_stub.dart stands in elsewhere, and
/// lib/account/api.dart `ioFetcher` and lib/live/transport.dart `ioLiveSocket` hand over to these in a browser,
/// so the account, sync, the relay and every plugin's calls need no word of where they run.
///
/// What a browser decides that `dart:io` did not: which origins answer at all (CORS). The account's service answers
/// this page's (server/src/main.rs `ORIGINS` lets in https://attack.fm and https://ghostmarkdown.com, and a page on
/// any local port); a third party's that does not is no answer, the status 0 `ApiError` the app already says as
/// "unreachable".
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../account/api.dart' show Fetcher, FetchResponse, isProductionHost;
import '../live/transport.dart' show LiveSocket;

extension on web.Headers {
  /// `Headers.prototype.forEach`, which the bindings leave out: `(value, name)` for each.
  external void forEach(JSFunction callback);
}

/// A [Fetcher] over the browser's `fetch`, its wait kept by aborting, as `ioFetcher`'s is.
Fetcher pageFetcher() => (request) async {
  assert(!isProductionHost(request.url.host), 'A development build never talks to ghostmarkdown.com (docs/STAGE7.md).');
  final abort = web.AbortController();
  final headers = web.Headers();
  request.headers.forEach((name, value) => headers.append(name, value));
  final body = request.body;
  final timer = Timer(request.timeout, () => abort.abort());
  try {
    final answer = await web.window
        .fetch(request.url.toString().toJS, web.RequestInit(method: request.method, headers: headers, body: body?.toJS, signal: abort.signal))
        .toDart;
    final bytes = (await answer.arrayBuffer().toDart).toDart.asUint8List();
    final said = <String, String>{};
    answer.headers.forEach(((JSString value, JSString name) {
      said[name.toDart] = value.toDart;
    }).toJS);
    return FetchResponse(answer.status, headers: said, bytes: Uint8List.fromList(bytes));
  } catch (failure) {
    if (abort.signal.aborted) throw TimeoutException('The request took too long.', request.timeout);
    // The browser's own failure is a JavaScript TypeError, which no `on Exception` catches: said as the Dart
    // exception `dart:io` would have thrown for no answer, so every client reads it as one.
    throw PageFetchFailed('$failure');
  } finally {
    timer.cancel();
  }
};

/// No answer at all from `fetch`: the network, a refused origin (CORS), a blocked port. `SocketException`'s place.
class PageFetchFailed implements Exception {
  const PageFetchFailed(this.said);
  final String said;

  @override
  String toString() => 'No answer: $said';
}

/// The browser's socket to [url]. A connection that never opens is a close, as the page's always was.
LiveSocket pageLiveSocket(String url) => _PageSocket(url);

class _PageSocket extends LiveSocket {
  _PageSocket(String url) {
    try {
      final socket = _socket = web.WebSocket(url);
      socket.onopen = ((web.Event _) => onOpen?.call()).toJS;
      socket.onmessage = ((web.MessageEvent event) {
        final data = event.data;
        onMessage?.call(data.isA<JSString>() ? (data as JSString).toDart : data.dartify());
      }).toJS;
      socket.onclose = ((web.CloseEvent event) => onClose?.call(event.code)).toJS;
    } catch (_) {
      scheduleMicrotask(() => onClose?.call(null));
    }
  }

  web.WebSocket? _socket;

  @override
  void send(String text) {
    final socket = _socket;
    if (socket != null && socket.readyState == web.WebSocket.OPEN) socket.send(text.toJS);
  }

  @override
  void close() => _socket?.close();
}
