// Pictures of the plugins wearing their companies' marks (Matt, 2026-10-29: "Iconize real company logos for openAI
// todoist, GitHub, Google meets, zoom etc and use those for the plugin icons"), for the eye: written only by
// `flutter test --update-goldens test/plugins/brand_icons_shots_test.dart`, into build/feature-shots/brand-icons/ (not
// committed). Settings' list with every plugin added and the Market's plugins, on a phone and on the Mac, light and
// dark; the first step of six companies' setups; and a contact sheet of every plugin's icon beside Lucide glyphs at the sizes the app draws them, in each icon
// style, with the Market's tiles, as the app has them and as a store-shot build has them.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/art/brand_marks.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/market/market_items.dart' show MarketShelf;
import 'package:ghost_md/market/market_plugins.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/catalogue.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart' show SetupMemory;
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart' show PluginSetupSheet;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/kit/settings_type.dart' show pageText;
import 'package:ghost_md/settings/panes/plugins_pane.dart' show pluginIcon;
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:glacier/glacier.dart';

import '../settings/support.dart';

const Size _phone = Size(390, 2400);
const Size _mac = Size(1280, 1500);

Future<void> _picture(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/brand-icons/$name.png'));
}

/// Every plugin that ships, all of them added.
Registry _everyOn() {
  final registry = createRegistry(builtIn, store: MemorySwitches(), localOnly: () => false);
  for (final plugin in builtIn) {
    registry.setEnabled(plugin.manifest.id, true);
  }
  return registry;
}

/// Every plugin's icon in a row of its own: the icon at 16, 20 and 24 in each style, with Lucide's store and its
/// puzzle beside it for the weight, and its Market tile.
class _Sheet extends StatelessWidget {
  const _Sheet();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    final label = pageText(t, 12, color: t.color('app-ink-2'));
    Widget cell(Widget child) => SizedBox(width: 30, height: 30, child: Center(child: child));
    Widget styled(IconStyle style, Widget child) => IconLookScope(look: IconLook('lucide', style), child: child);
    return ColoredBox(
      color: t.color('app-paper'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
        child: IconTheme(
          data: IconThemeData(color: ink),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [SizedBox(width: 120, child: Text('', style: label)), for (final style in IconStyle.values) SizedBox(width: 6 * 30 + 12, child: Text(style.label, style: label)), Text('Tile', style: label)]),
              for (final plugin in catalogueOrder(builtIn))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 120, child: Text(plugin.manifest.name, style: pageText(t, 13, color: ink), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      for (final style in IconStyle.values)
                        styled(
                          style,
                          SizedBox(
                            width: 6 * 30 + 12,
                            child: Row(
                              children: [
                                for (final size in [16.0, 20.0, 24.0]) cell(pluginIcon(plugin, size)),
                                cell(const AppIcon(Lucide.store, size: 20)),
                                cell(const AppIcon(Lucide.puzzle, size: 20)),
                                cell(const AppIcon(Lucide.calendarDays, size: 20)),
                              ],
                            ),
                          ),
                        ),
                      PluginTile(plugin: plugin, size: 40),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => debugStoreShots = null);

  for (final theme in ['light', 'dark']) {
    for (final (size, where) in [(_phone, 'phone'), (_mac, 'mac')]) {
      testWidgets('Settings’ list with every plugin added, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        final before = plugins;
        usePlugins(_everyOn());
        addTearDown(() => usePlugins(before));
        await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: size, prefs: Preferences(theme: theme, experience: 'advanced', experienceChosen: true));
        await _picture(tester, 'settings-$where-$theme');
        await endSettings(tester);
      });

      testWidgets('the Market’s plugins, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        await pumpSettings(tester, MarketScreen(onBack: () {}, registry: _everyOn(), shelf: MarketShelf.plugins, offerSetup: false), size: size, prefs: Preferences(theme: theme));
        await _picture(tester, 'market-$where-$theme');
        await endSettings(tester);
      });

      testWidgets('the Market’s front, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        await pumpSettings(tester, MarketScreen(onBack: () {}, registry: createRegistry(builtIn, store: MemorySwitches(), localOnly: () => false), offerSetup: false), size: size, prefs: Preferences(theme: theme));
        await _picture(tester, 'market-front-$where-$theme');
        await endSettings(tester);
      });

      testWidgets('a plugin’s page in the Market, Todoist, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        await pumpSettings(tester, MarketScreen(onBack: () {}, registry: _everyOn(), plugin: 'todoist', offerSetup: false), size: size, prefs: Preferences(theme: theme));
        await _picture(tester, 'market-todoist-$where-$theme');
        await endSettings(tester);
      });
    }

    testWidgets('the setups’ first steps with the company’s mark in the band, $theme', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      for (final id in ['todoist', 'github', 'google-meet', 'gemini', 'notion', 'discord']) {
        final setup = builtIn.singleWhere((p) => p.manifest.id == id).setup!();
        await pumpSettings(tester, PluginSetupSheet(key: UniqueKey(), setup: setup, memory: SetupMemory(MemoryStored()), onClose: () {}), size: const Size(390, 844), prefs: Preferences(theme: theme, experience: 'advanced', experienceChosen: true));
        await _picture(tester, 'setup-$id-$theme');
        await endSettings(tester);
      }
    });

    for (final store in [false, true]) {
      testWidgets('the contact sheet, $theme${store ? ', a store-shot build' : ''}', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        debugStoreShots = store;
        await pumpSettings(tester, const _Sheet(), size: const Size(1000, 1200), prefs: Preferences(theme: theme));
        await _picture(tester, 'sheet-$theme${store ? '-store' : ''}');
        await endSettings(tester);
      });
    }
  }
}
