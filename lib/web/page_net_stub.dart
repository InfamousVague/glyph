/// page_net.dart's names on a device, where nothing asks for them: `ioFetcher` and `ioLiveSocket` hand over to the
/// page's only in a browser (`kIsWeb`).
library;

import '../account/api.dart' show Fetcher;
import '../live/transport.dart' show LiveSocket;

Fetcher pageFetcher() => throw UnsupportedError('The browser\'s fetch is only in the web build.');

LiveSocket pageLiveSocket(String url) => throw UnsupportedError('The browser\'s WebSocket is only in the web build.');
