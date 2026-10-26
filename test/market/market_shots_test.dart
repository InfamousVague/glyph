import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_items.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';

import '../support/render.dart';

/// Pictures of the Market (Matt, 2026-10-26: "Make the plugins a dedicated "Market" section in the app, include some
/// more themes, fonts an of course all our plugins with vivid iconography and imagery where possible include mobile
/// and desktop support"): each shelf and a plugin's page, on a phone (390 by 844) and a Mac's window (1280 by 800),
/// light and dark, and the Fold's inner screen. Written to `build/feature-shots/market/<name>.png` to be looked at,
/// not held as goldens, and drawn only with `--update-goldens`.
void main() {
  setUpAll(loadAppFonts);
  final skip = !autoUpdateGoldenFiles;

  Future<void> snap(WidgetTester tester, String name) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/market/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  }

  /// The Market over a fresh install's plugins, Lovart added, with nowhere for its links to go.
  Future<void> open(WidgetTester tester, String theme, {required Size size, bool mac = false, MarketShelf? shelf, String? plugin, bool localOnly = false}) async {
    if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final registry = createRegistry(builtIn, store: MemorySwitches(), localOnly: () => localOnly);
    registry.setEnabled('lovart', true);
    await pumpApp(
      tester,
      size: size,
      prefs: Preferences(theme: theme, localOnly: localOnly),
      home: BackScope(child: MarketScreen(onBack: () {}, registry: registry, shelf: shelf, plugin: plugin, onPluginSettings: (_) {}, onLocalOnly: () {})),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  const phone = Size(390, 844);
  const fold = Size(840, 900);
  const mac = Size(1280, 800);

  for (final theme in ['light', 'dark']) {
    for (final shelf in MarketShelf.values) {
      testWidgets('${shelf.name} on a phone, $theme', skip: skip, (tester) async {
        await open(tester, theme, size: phone, shelf: shelf);
        await snap(tester, 'phone-${shelf.name}-$theme');
      });
      testWidgets('${shelf.name} on a phone, the whole page, $theme', skip: skip, (tester) async {
        await open(tester, theme, size: const Size(390, 3000), shelf: shelf);
        await snap(tester, 'phone-${shelf.name}-whole-$theme');
      });
      testWidgets('${shelf.name} on a Mac, $theme', skip: skip, (tester) async {
        await open(tester, theme, size: mac, mac: true, shelf: shelf);
        await snap(tester, 'mac-${shelf.name}-$theme');
      });
    }
    testWidgets('a plugin on a phone, $theme', skip: skip, (tester) async {
      await open(tester, theme, size: phone, plugin: 'notion');
      await snap(tester, 'phone-plugin-$theme');
    });
    testWidgets('a plugin on a phone, the whole page, $theme', skip: skip, (tester) async {
      await open(tester, theme, size: const Size(390, 1800), plugin: 'lovart');
      await snap(tester, 'phone-plugin-whole-$theme');
    });
    testWidgets('a plugin on a Mac, $theme', skip: skip, (tester) async {
      await open(tester, theme, size: mac, mac: true, plugin: 'claude', shelf: MarketShelf.plugins);
      await snap(tester, 'mac-plugin-$theme');
    });
    testWidgets('the Fold open, $theme', skip: skip, (tester) async {
      await open(tester, theme, size: fold);
      await snap(tester, 'fold-all-$theme');
    });
  }

  testWidgets('Local only on a phone', skip: skip, (tester) async {
    await open(tester, 'light', size: phone, shelf: MarketShelf.plugins, localOnly: true);
    await snap(tester, 'phone-local-only-light');
  });
}
