// Pictures of the ElevenLabs plugin (Matt, 2026-10-27: "Build a plugin for elevenlabs"): its page in Settings, with no
// key and with one kept, and its card and page in the Market, light and dark, on a phone. Written to
// `build/feature-shots/elevenlabs/<name>.png` to be looked at, not held as goldens, and drawn only with
// `--update-goldens`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_items.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/elevenlabs/elevenlabs.dart';
import 'package:ghost_md/plugins/elevenlabs/manifest.dart' as eleven;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/registry.dart';

import '../github/support.dart';

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
    File('build/feature-shots/elevenlabs/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  tearDown(() {
    elevenLabsClient = () => ElevenLabsClient.kept();
    usePluginGround(PluginGround());
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('the page with no key, $theme', skip: skip, (tester) async {
      useGround();
      tester.view.physicalSize = const Size(390, 1900) * tester.view.devicePixelRatio;
      addTearDown(tester.view.reset);
      await pumpPane(tester, const ElevenLabsPane(), theme: theme);
      await snap(tester, 'pane-new-$theme');
    });

    testWidgets('the page with a key kept, $theme', skip: skip, (tester) async {
      useGround((request) async => request.url.path == '/v1/user'
          ? FetchResponse.json(200, {
              'subscription': {'tier': 'creator', 'character_count': 18240, 'character_limit': 100000, 'next_character_count_reset_unix': 1764547200},
            })
          : FetchResponse.json(200, {
              'voices': [
                {'voice_id': 'mine1', 'name': 'Matt', 'category': 'cloned', 'description': 'Cloned from a memo'},
              ],
            }));
      await eleven.host.secrets.write(apiKeySecret, 'sk_0123456789abcdef0123456789abcdef');
      tester.view.physicalSize = const Size(390, 2100) * tester.view.devicePixelRatio;
      addTearDown(tester.view.reset);
      await pumpPane(tester, const ElevenLabsPane(), theme: theme);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(tester);
      await snap(tester, 'pane-kept-$theme');
    });

    Future<void> market(WidgetTester tester, String theme, {MarketShelf? shelf, String? plugin, required Size size}) async {
      final registry = createRegistry(builtIn, store: MemorySwitches());
      await pumpApp(
        tester,
        size: size,
        prefs: Preferences(theme: theme),
        home: BackScope(child: MarketScreen(onBack: () {}, registry: registry, shelf: shelf, plugin: plugin, onPluginSettings: (_) {}, onLocalOnly: () {})),
      );
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
      await tester.pump();
    }

    testWidgets('its card on the Market’s Plugins, $theme', skip: skip, (tester) async {
      await market(tester, theme, shelf: MarketShelf.plugins, size: const Size(390, 1400));
      await snap(tester, 'market-plugins-$theme');
    });

    testWidgets('its page in the Market, $theme', skip: skip, (tester) async {
      await market(tester, theme, plugin: 'elevenlabs', size: const Size(390, 1500));
      await snap(tester, 'market-page-$theme');
    });
  }
}
