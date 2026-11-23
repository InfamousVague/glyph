import 'package:flutter/services.dart';

import '../emoji_sets.dart';

/// Emoji in a browser (Matt: "the full web client"). A page draws every letter itself, so emoji need one of the
/// app's own fonts; the four of them are eleven megabytes, which a browser would otherwise fetch before the page's
/// first frame whether or not a set was ever chosen. So the build leaves them out of what is loaded at the start
/// (tool/build-web.mjs takes them off the font list), and a set is fetched here when it is first wanted: the one
/// chosen as the app starts, another as it is chosen or shown in Settings. From the page's own address, as every
/// asset is.
final Map<String, Future<void>> _fetching = {};

Future<void> loadEmojiFont(String family) => _fetching[family] ??= () async {
      final asset = emojiFontAssets[family];
      if (asset == null) return;
      try {
        await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
      } catch (_) {
        // Not had this time (the connection): asked for again the next time it is wanted.
        _fetching.remove(family)?.ignore();
      }
    }();
