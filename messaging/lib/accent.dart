import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app_state.dart';
import 'backgrounds.dart';

/// The app's accent: the colour of your bubbles everywhere, worn by what is pressed and chosen across the app too
/// (Matt, 2026-11-14: "make the bubble color the accent color for the app so the send button, segmented toggles,
/// etc all get the same color as the bubbles if set globally and only settings inside a chat soley change the
/// bubble color"). Send, a chosen tab of a toggle, a switch that is on, the ring of the page shown in the
/// navigation pill and the ring round what has the keyboard draw it, through two tokens of the app's own,
/// `--app-accent` and `--app-on-accent` (the words on it), which are the page's ink and paper unless a bubble
/// colour says otherwise. A conversation's own colour (`bubble_<thread>`) is its bubbles' alone.
///
/// The kit draws from its stylesheets, so the accent is a rule laid over them: the stylesheets are kept as they
/// were read and parsed again with it whenever the colour changes ([AccentSheets.of]).
///
/// Where the bubble colour would not be seen against the page it stands on (white or silver on the light page) the
/// accent stays the page's ink on that theme: a white Send on white paper is no button.
class AccentSheets {
  AccentSheets(this._sources) : base = TokenSheet.parseAll(_sources);

  /// The kit's stylesheet and the app's, read as [loadTokenSheet] reads them.
  static Future<AccentSheets> load({List<String> more = const ['assets/css/ink.css', 'assets/css/app.css']}) async {
    final sources = <String>[];
    for (final asset in [glacierTokensAsset, ...more]) {
      sources.add(await rootBundle.loadString(asset));
    }
    return AccentSheets(sources);
  }

  final List<String> _sources;

  /// The sheet with no accent of a bubble's: the page's ink.
  final TokenSheet base;

  String? _css;
  TokenSheet? _sheet;

  /// The sheet for the bubble colour chosen everywhere in [app].
  TokenSheet of(AppState app) {
    final css = accentCss(app.bubble);
    if (css == null) return base;
    if (css != _css) {
      _css = css;
      _sheet = TokenSheet.parseAll([..._sources, css]);
    }
    return _sheet!;
  }
}

/// The page each theme's accent stands on: near white, and near black.
const _lightPage = Color(0xFFFDFDFD), _darkPage = Color(0xFF0B0B0C);

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

/// The bubble colour [id] as the accent on the light page and on the dark: the colour and the words on it, or null
/// where it is the page's own ink or would not be seen.
({(Color, Color)? light, (Color, Color)? dark}) accentPair(String id) {
  (Color, Color)? on(bool dark) {
    (Color, Color)? pair;
    switch (id) {
      case 'ink':
        return null;
      case 'wallpaper':
        pair = PhonePalette.current?.bubble(dark);
        if (pair != null) break;
        continue ghost;
      ghost:
      case 'ghost':
        pair = (Color(dark ? 0xFF51FCFB : 0xFF008B8A), Color(dark ? 0xFF00302F : 0xFFFFFFFF));
      default:
        final c = bubbleColor(id).color;
        pair = c == null ? (Color(dark ? 0xFF51FCFB : 0xFF008B8A), Color(dark ? 0xFF00302F : 0xFFFFFFFF)) : (c, inkOn(c));
    }
    return _contrast(pair.$1, dark ? _darkPage : _lightPage) < 1.5 ? null : pair;
  }

  return (light: on(false), dark: on(true));
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The rule that makes the bubble colour [id] the accent, or null where it is the page's ink on both themes. It
/// outranks every rule of the app's stylesheets that names the two tokens.
String? accentCss(String id) {
  final p = accentPair(id);
  if (p.light == null && p.dark == null) return null;
  String block(String theme, (Color, Color) pair) =>
      ':root:root:root:root:root[data-theme=\'$theme\'] { --app-accent: ${_hex(pair.$1)}; --app-on-accent: ${_hex(pair.$2)}; }\n';
  return [if (p.light != null) block('light', p.light!), if (p.dark != null) block('dark', p.dark!)].join();
}
