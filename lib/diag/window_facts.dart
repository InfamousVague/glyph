/// What the window is, read off the app itself: the inset it gets at its top (the status bar's height when the app is
/// drawn under it, 0 when it is not), the window against the screen, and what draws it. A port of
/// `src/app/diag/windowFacts.ts`, for Settings › Developer › Window.
///
/// What differs:
/// - The page read `--app-inset-top`, `window.innerWidth`, `screen` and the agent string. Here [windowFacts] reads
///   the view (`MediaQuery`, `View.of`), and the four lines are put together by [windowFactsOf], which is pure and
///   is what the tests hold.
/// - Engine says what draws a Flutter app (lib/diag/frame_clock.dart [drawnBy]) and the platform, where the page
///   named its browser. The page's own reading of an agent string is [engineWords], kept for its test.
/// - lib/settings/panes/developer_pane.dart has a `windowFacts` of its own, written before this file; the two answer
///   alike but for Engine, which there says `Flutter on <platform>`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'frame_clock.dart';

/// The four lines Developer draws (`windowFacts()`'s answer).
typedef WindowFacts = ({String inset, String page, String screen, String engine});

/// A length or a ratio as the page writes one: whole when it is whole, else two decimals with no trailing zeros.
String _n(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final text = v.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// The lines, from the numbers: [inset] is the top inset in logical pixels, [page] the window, [ratio] device pixels
/// to the logical one, [screen] the whole display in logical pixels.
WindowFacts windowFactsOf({required double inset, required Size page, required double ratio, required Size screen, required String engine}) => (
      inset: '${_n(inset)}px',
      page: '${_n(page.width)} × ${_n(page.height)} @${_n(ratio)}',
      screen: '${_n(screen.width)} × ${_n(screen.height)}',
      engine: engine.isEmpty ? 'unknown' : engine,
    );

/// A browser's engine from its agent string, as the page says it: a Chrome by its version, marked when it is a
/// WebView, else the WebKit it names, else `unknown`.
String engineWords(String userAgent) {
  final chrome = RegExp(r'Chrome/([\d.]+)').firstMatch(userAgent)?.group(1);
  if (chrome != null) return 'Chrome $chrome${RegExp(r'\bwv\b').hasMatch(userAgent) ? ' (WebView)' : ''}';
  return RegExp(r'AppleWebKit/([\d.]+)').firstMatch(userAgent)?.group(0) ?? 'unknown';
}

/// What the window is, here and now (`windowFacts`).
WindowFacts windowFacts(BuildContext context) {
  final media = MediaQuery.of(context);
  final view = View.of(context);
  final display = view.display;
  return windowFactsOf(
    inset: media.viewPadding.top,
    page: media.size,
    ratio: media.devicePixelRatio,
    screen: display.size / display.devicePixelRatio,
    engine: '${drawnBy()} on ${defaultTargetPlatform.name}',
  );
}
