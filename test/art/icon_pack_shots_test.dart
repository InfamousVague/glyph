import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_items.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/share/app_links.dart' show MarketKind, MarketPlace;
import 'package:glacier/glacier.dart';

import '../home/support.dart';
import '../support/render.dart';

/// Pictures of the icon packs and styles (Matt, 2026-10-27: "I would like you to add three icon styles (outline,
/// solid and filled) and add a few different icon packs for the app to choose from"), for the eye, written to
/// `build/feature-shots/icon-packs/` by
///
/// ```sh
/// flutter test --no-pub --update-goldens test/art/icon_pack_shots_test.dart
/// ```
///
/// and not held as goldens: every glyph the app draws in each pack and style (Lucide's stand-ins in red, the app's own
/// drawings in blue); then, in each pack and each style, on a phone in the light theme, the home page, its dock close
/// up, Settings' list, and the Market; the Market's Icons shelf light and dark, a pack's page, and Settings ›
/// Appearance with its Icons card in each style.
void main() {
  setUpAll(loadAppFonts);
  final skip = !autoUpdateGoldenFiles;
  const phone = Size(390, 844);

  /// The app as drawn, or the part of it [crop] says, into the folder.
  Future<void> snap(WidgetTester tester, String name, {Finder? crop, Finder? cropTo}) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    // The part [crop] covers, or from [crop] to [cropTo]: the dock from its first ring to its last.
    var rect = boundary.paintBounds;
    if (crop != null && crop.evaluate().isNotEmpty) {
      final from = tester.getRect(crop.first);
      final part = (cropTo == null || cropTo.evaluate().isEmpty ? from : from.expandToInclude(tester.getRect(cropTo.first))).inflate(16);
      // The window's own layer is in device pixels; anything under it in points.
      final scale = boundary is RenderView ? tester.view.devicePixelRatio : 1.0;
      rect = Rect.fromLTRB(part.left * scale, part.top * scale, part.right * scale, part.bottom * scale).intersect(boundary.paintBounds);
    }
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(rect, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/icon-packs/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  }

  Preferences prefsOf(String pack, IconStyle style, {String theme = 'light'}) => Preferences(theme: theme, iconPack: pack, iconStyle: style.name, experience: 'advanced', experienceChosen: true);

  Future<void> noInsets(WidgetTester tester) async {
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  Future<void> market(WidgetTester tester, Preferences prefs, {Size size = phone, MarketShelf? shelf, MarketPlace? link}) async {
    final registry = createRegistry(builtIn, store: MemorySwitches());
    await pumpApp(tester, size: size, prefs: prefs, home: BackScope(child: MarketScreen(onBack: () {}, registry: registry, shelf: shelf, link: link, onPluginSettings: (_) {}, onLocalOnly: () {})));
    await noInsets(tester);
  }

  // Every glyph once, by Lucide's name, and the app's own drawings after them.
  final glyphs = <String, LucideIcon>{for (final icon in Lucide.all.values) icon.name: icon};
  final names = glyphs.keys.toList()..sort();

  for (final pack in iconPacks) {
    testWidgets('every glyph in ${pack.name}', skip: skip, (tester) async {
      await pumpApp(
        tester,
        size: const Size(760, 1000),
        prefs: Preferences(theme: 'light', iconPack: pack.id),
        home: Builder(
          builder: (context) {
            final t = context.tokens;
            return ColoredBox(
              color: t.color('app-paper'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final style in IconStyle.values) ...[
                      Text('${pack.name} · ${style.label}', style: TextStyle(fontSize: 13, color: t.color('app-ink'))),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final name in names)
                            AppIcon(glyphs[name]!, size: 18, color: packGlyphsFor(IconLook(pack.id, style), name) == null && pack.glyphs != null ? const Color(0xFFD6336C) : t.color('app-ink'), look: IconLook(pack.id, style)),
                          for (final drawn in AppIcons.all.values) IconLookScope(look: IconLook(pack.id, style), child: DrawnIconView(drawn, size: 18, color: const Color(0xFF0A6FE0))),
                          IconLookScope(look: IconLook(pack.id, style), child: const HouseIcon(size: 18, color: Color(0xFF0A6FE0))),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
      await snap(tester, 'glyphs-${pack.id}');
    });

    for (final style in IconStyle.values) {
      final look = '${pack.id}-${style.name}';

      testWidgets('the home page and its dock in ${pack.name}, ${style.label}', skip: skip, (tester) async {
        for (final part in ['home', 'dock']) {
          final it = seeded();
          await pumpApp(tester, size: phone, prefs: prefsOf(pack.id, style), ratio: 2, home: Home(library: it.library, workspaces: it.workspaces, asked: it.asked, speak: true, rings: true));
          await noInsets(tester);
          await settle(tester);
          await snap(tester, '$part-$look', crop: part == 'dock' ? find.byKey(const ValueKey('dock-search')) : null, cropTo: find.byKey(const ValueKey('dock-settings')));
        }
      });

      testWidgets('Settings in ${pack.name}, ${style.label}', skip: skip, (tester) async {
        await pumpApp(tester, size: phone, prefs: prefsOf(pack.id, style), home: BackScope(child: SettingsSheet(open: true, onClose: () {})));
        await noInsets(tester);
        await snap(tester, 'settings-$look');
      });

      testWidgets('the Market in ${pack.name}, ${style.label}', skip: skip, (tester) async {
        await market(tester, prefsOf(pack.id, style));
        await snap(tester, 'market-$look');
      });
    }
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('the Market\'s Icons shelf, $theme', skip: skip, (tester) async {
      await market(tester, prefsOf('phosphor', IconStyle.outline, theme: theme), size: const Size(390, 1500), shelf: MarketShelf.icons);
      await snap(tester, 'market-icons-shelf-$theme');
    });

    testWidgets('a pack\'s page, $theme', skip: skip, (tester) async {
      await market(tester, prefsOf('lucide', IconStyle.outline, theme: theme), size: const Size(390, 1900), link: const MarketPlace(kind: MarketKind.icons, id: 'tabler'));
      await snap(tester, 'market-icons-page-tabler-$theme');
    });

    testWidgets('the Icons shelf on a Mac, $theme', skip: skip, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await market(tester, prefsOf('material', IconStyle.solid, theme: theme), size: const Size(1280, 800), shelf: MarketShelf.icons);
      await snap(tester, 'market-icons-shelf-mac-$theme');
    });
  }

  for (final pack in ['lucide', 'phosphor']) {
    for (final style in IconStyle.values) {
      testWidgets('Appearance\'s Icons card, $pack, ${style.label}', skip: skip, (tester) async {
        await pumpApp(tester, size: const Size(390, 1200), prefs: prefsOf(pack, style), home: BackScope(child: SettingsSheet(open: true, onClose: () {}, toPage: const SettingsTarget('theme', nonce: 1))));
        await noInsets(tester);
        await tester.pump(const Duration(seconds: 1));
        await tester.ensureVisible(find.byKey(const ValueKey('settings-icon-style')));
        await tester.pump(const Duration(seconds: 1));
        await snap(tester, 'appearance-$pack-${style.name}', crop: find.byKey(const ValueKey('settings-icon-style')));
      });
    }
  }
}
