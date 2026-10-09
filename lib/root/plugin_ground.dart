/// The plugins put on the phone: what `src/app/plugins/registry.ts` does as its module loads, and what the page's
/// globals (localStorage, Tauri's `invoke`, the opener) were to `plugins/host.ts`. One call, [installPlugins], made
/// by `lib/main.dart` before the first screen is built: Settings' rows, the editor's parser and the Academy's
/// lessons all read the registry.
///
/// What the hosts stand on here (lib/plugins/host.dart `PluginGround`):
/// - **the device's memory** for a plugin's own keys (the app's `stored`);
/// - **the secure store** for tokens and webhooks (`deviceSecureStore()`: the Android Keystore's on a phone);
/// - **the network**, through [pluginFetcher], which follows no redirect: a plugin's host is checked against its
///   manifest before a request leaves (`PluginHost.fetch`), and a redirect would be a second request nobody checked;
/// - **the phone's browser** for an address a plugin opens (lib/core/open_link.dart).
///
/// Then the five that ship (lib/plugins/built_in.dart), and each one's secrets read once (`host.secrets.warm()`),
/// so "is there a token?" is true to the store from the first draw.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../account/api.dart' show FetchResponse, Fetcher, isProductionHost;
import '../account/device_keys.dart' show deviceSecureStore;
import '../core/open_link.dart';
import '../core/preferences.dart';
import '../plugins/built_in.dart';
import '../plugins/host.dart';
import '../plugins/registry.dart';

/// A [Fetcher] over `dart:io` that follows no redirect: a 3xx is answered as it came. A build that is not a release
/// refuses the real service's hosts outright, as every other client of this app does. [client] is the one to use,
/// or one made here and kept.
Fetcher pluginFetcher({HttpClient? client, bool debug = !kReleaseMode}) {
  HttpClient? made;
  return (request) async {
    if (debug && isProductionHost(request.url.host)) throw StateError('A development build never talks to ${request.url.host}.');
    final http = client ?? (made ??= HttpClient());
    HttpClientRequest? sent;
    Future<FetchResponse> ask() async {
      final asked = sent = await http.openUrl(request.method, request.url);
      asked.followRedirects = false;
      request.headers.forEach(asked.headers.set);
      final body = request.body;
      if (body != null) {
        asked.contentLength = body.length;
        asked.add(body);
      }
      final answer = await asked.close();
      final bytes = BytesBuilder(copy: false);
      await answer.forEach(bytes.add);
      final headers = <String, String>{};
      answer.headers.forEach((name, values) => headers[name] = values.join(', '));
      return FetchResponse(answer.statusCode, headers: headers, bytes: bytes.takeBytes());
    }

    return ask().timeout(request.timeout, onTimeout: () {
      sent?.abort();
      throw TimeoutException('The request took too long.', request.timeout);
    });
  };
}

/// Puts the ground under the plugins' hosts and the five that ship in the app's registry, and reads each one's
/// secrets once. Before the first screen is built; answers the registry.
Registry installPlugins({PluginGround? ground, PreferencesStore? prefs}) {
  usePluginGround(ground ?? PluginGround(secrets: deviceSecureStore(), fetch: pluginFetcher(), open: openLink));
  final store = prefs ?? preferences;
  final registry = installBuiltInPlugins(localOnly: () => store.value.localOnly);
  for (final plugin in builtIn) {
    // A store that will not answer leaves a plugin as not connected, which is what it then is.
    unawaited(createHost(plugin.manifest).secrets.warm().then<void>((_) {}, onError: (Object _) {}));
  }
  return registry;
}
