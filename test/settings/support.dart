import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

export '../support/render.dart';

/// A phone's screen as the web app's reference pictures and measurements were taken on it (2026-10-07, its dev
/// server in Chromium at 390 x 844 and 1280 x 800): no notch, so every number here is the page's own.
const Size phone = Size(390, 844);
const Size wideWindow = Size(1280, 800);

/// The back stack a test's screen is under: `stack.goBack()` is the phone's back gesture.
late BackStack testBack;

/// Puts [child] under the app's theme and a back scope of the test's own, on [size] with no insets, and lets its
/// arrival finish.
Future<void> pumpSettings(WidgetTester tester, Widget child, {Size size = phone, Preferences prefs = const Preferences(theme: 'light'), bool settle = true}) async {
  testBack = BackStack();
  await pumpApp(tester, size: size, prefs: prefs, home: BackScope(stack: testBack, child: child));
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  if (settle) await settleSettings(tester);
}

/// Past the arrivals: the screen's, a page's, the rows' and the cards'.
Future<void> settleSettings(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Ends a test that drew with real shadows ([pumpApp] turns them on, and the binding checks the switch as it ends).
Future<void> endSettings(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

/// The tokens in force where [finder] is.
Tokens tokensAt(WidgetTester tester, Finder finder) => GlacierTheme.of(tester.element(finder.first));

/// A colour as the page computed it (`oklch(0.955 0 0)`, `#0a6fe0`), in the screen's own terms.
Color cssColor(WidgetTester tester, String css) => tokensAt(tester, find.byType(BackScope)).colorOf(css);

/// Whether two colours are the same to a step of 255 a channel, as the token tests hold the engine to the page.
Matcher sameColor(Color want) => predicate<Color>(
      (got) => (got.r - want.r).abs() < 1.5 / 255 && (got.g - want.g).abs() < 1.5 / 255 && (got.b - want.b).abs() < 1.5 / 255 && (got.a - want.a).abs() < 1.5 / 255,
      'the colour $want',
    );

/// A rect within [by] logical pixels of the one the page measured: `x, y, width, height`.
Matcher rectNear(double x, double y, double w, double h, [double by = 0.5]) => predicate<Rect>(
      (r) => (r.left - x).abs() <= by && (r.top - y).abs() <= by && (r.width - w).abs() <= by && (r.height - h).abs() <= by,
      'a rect within $by of x$x y$y w$w h$h',
    );
