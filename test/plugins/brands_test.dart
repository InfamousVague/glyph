import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/art/brand_marks.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_items.dart' show MarketShelf;
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/brands.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/elevenlabs/elevenlabs_mark.dart';
import 'package:ghost_md/plugins/lovart/lovart_mark.dart';
import 'package:ghost_md/plugins/notion/marks.dart' show NotionMark;
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart' show setupMarkOf;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/settings/panes/plugins_pane.dart' show pluginIcon;
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:glacier/glacier.dart';

import '../settings/support.dart';

/// The plugins wearing their companies' marks (lib/plugins/brands.dart; Matt, 2026-10-29: "Iconize real company logos
/// for openAI todoist, GitHub, Google meets, zoom etc and use those for the plugin icons"): which wear one and which
/// keep their glyph, a row of Settings' list and a card in the Market in light and dark, and a store-shot build, which
/// shows no brand's mark anywhere a plugin's icon is drawn (Apple's 4.1(a), 2026-10-19).
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => debugStoreShots = null);

  GlyphPlugin pluginOf(String id) => builtIn.singleWhere((p) => p.manifest.id == id);

  /// Every plugin that ships, all of them added.
  Registry everyOn() {
    final registry = createRegistry(builtIn, store: MemorySwitches(), localOnly: () => false);
    for (final plugin in builtIn) {
      registry.setEnabled(plugin.manifest.id, true);
    }
    return registry;
  }

  void install(Registry registry) {
    final before = plugins;
    addTearDown(() => usePlugins(before));
    usePlugins(registry);
  }

  group('which plugins wear a mark', () {
    test('every plugin that ships is a company’s with its mark, a company’s without one, or the app’s own, and only one', () {
      final ids = [for (final p in builtIn) p.manifest.id];
      final kinds = [pluginBrands.keys.toSet(), pluginsWithoutMark.keys.toSet(), ownPlugins];
      expect(kinds.expand((k) => k).toList()..sort(), [...ids]..sort());
      expect(kinds.fold<int>(0, (n, k) => n + k.length), ids.length, reason: 'a plugin in two of them');
    });

    test('the companies’ plugins named for it wear their marks, each one an asset that is there', () {
      expect(pluginBrands, {
        'notion': 'notion',
        'github': 'github',
        'claude': 'claude',
        'calendar': 'googlecalendar',
        'todoist': 'todoist',
        'things': 'things',
        'lovart': 'lovart',
        'discord': 'discord',
        'google-meet': 'googlemeet',
        'zoom': 'zoom',
        'elevenlabs': 'elevenlabs',
        'gemini': 'googlegemini',
      });
      for (final MapEntry(key: id, value: slug) in pluginBrands.entries) {
        expect(brandOf(pluginOf(id))?.slug, slug, reason: id);
        expect(brandMarkData[slug], isNotNull, reason: slug);
      }
      expect(pluginsWithoutMark.keys.toSet(), {'slack', 'openai', 'aster'});
    });

    testWidgets('a company’s plugin is drawn as its mark; the app’s own, and one without a mark, keep their glyphs', (tester) async {
      for (final plugin in builtIn) {
        final icon = pluginIcon(plugin, 20);
        final id = plugin.manifest.id;
        if (pluginBrands.containsKey(id)) {
          expect((icon as BrandMarkIcon).mark.slug, pluginBrands[id], reason: id);
        } else {
          expect((icon as AppIcon).icon, Lucide.all[plugin.icon], reason: id);
        }
      }
    });
  });

  for (final theme in ['light', 'dark']) {
    group('in $theme', () {
      testWidgets('a plugin’s row in Settings wears its mark in the row’s ink', (tester) async {
        install(createRegistry(builtIn, store: MemorySwitches(), localOnly: () => false));
        await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: const Size(390, 1600), prefs: Preferences(theme: theme));
        final row = find.byKey(const ValueKey('row plugin:github'), skipOffstage: false);
        final mark = find.descendant(of: row, matching: find.byType(BrandMarkIcon), skipOffstage: false);
        expect(tester.widget<BrandMarkIcon>(mark).mark.slug, 'github');
        // No colour of its own: the ink an icon there takes, never GitHub's near-black.
        expect(tester.widget<BrandMarkIcon>(mark).color, isNull);
        final ink = IconTheme.of(tester.element(mark)).color;
        expect(ink, isNotNull);
        expect(ink, isNot(brandMarkData['github']!.colour));
        await endSettings(tester);
      });

      testWidgets('a plugin’s card in the Market wears its mark on a badge in its brand’s colour, or the ink where that would not show', (tester) async {
        await pumpSettings(tester, MarketScreen(onBack: () {}, registry: everyOn(), shelf: MarketShelf.plugins, offerSetup: false), size: const Size(390, 5000), prefs: Preferences(theme: theme));
        Color? colourOn(String id, String slug) {
          final card = find.byKey(ValueKey('market-plugin-$id'), skipOffstage: false);
          final badge = find.descendant(of: card, matching: find.byKey(ValueKey('plugin-badge-$slug')), skipOffstage: false);
          expect(badge, findsOneWidget, reason: id);
          return tester.widget<BrandMarkIcon>(find.descendant(of: badge, matching: find.byType(BrandMarkIcon), skipOffstage: false)).color;
        }

        final t = GlacierTheme.of(tester.element(find.byType(MarketScreen)));
        expect(colourOn('todoist', 'todoist'), brandMarkData['todoist']!.colour);
        expect(colourOn('zoom', 'zoom'), brandMarkData['zoom']!.colour);
        expect(colourOn('github', 'github'), theme == 'light' ? brandMarkData['github']!.colour : t.color('app-ink'));
        expect(colourOn('lovart', 'lovart'), t.color('app-ink'), reason: 'no colour of its own');
        // A plugin of the app's own keeps its tile in its colour, and no badge.
        expect(find.descendant(of: find.byKey(const ValueKey('market-plugin-webhooks'), skipOffstage: false), matching: find.byType(BrandMarkIcon), skipOffstage: false), findsNothing);
        await endSettings(tester);
      });
    });
  }

  group('a store-shot build (GHOST_STORE_NEUTRAL)', () {
    setUp(() => debugStoreShots = true);

    test('no plugin wears a mark', () {
      for (final plugin in builtIn) {
        expect(brandOf(plugin), isNull, reason: plugin.manifest.id);
        expect(pluginIcon(plugin, 20), isA<AppIcon>(), reason: plugin.manifest.id);
      }
    });

    for (final (size, where) in [(const Size(390, 5000), 'a phone'), (const Size(1280, 4000), 'the Mac')]) {
      testWidgets('the Market draws no brand’s mark, on $where, its front, its plugins or a plugin’s page', (tester) async {
        for (final (shelf, plugin) in [(null, null), (MarketShelf.plugins, null), (null, 'todoist')]) {
          await pumpSettings(tester, MarketScreen(onBack: () {}, registry: everyOn(), shelf: shelf, plugin: plugin, offerSetup: false), size: size);
          expect(find.byType(BrandMarkIcon, skipOffstage: false), findsNothing, reason: '$shelf $plugin');
          expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('plugin-badge-'), skipOffstage: false), findsNothing);
          await endSettings(tester);
        }
      });
    }

    testWidgets('Settings’ list draws no brand’s mark', (tester) async {
      install(everyOn());
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: const Size(390, 2600), prefs: const Preferences(experience: 'advanced', experienceChosen: true));
      expect(find.byKey(const ValueKey('row plugin:todoist'), skipOffstage: false), findsOneWidget);
      expect(find.byType(BrandMarkIcon, skipOffstage: false), findsNothing);
      await endSettings(tester);
    });

    testWidgets('the setups, the actions’ icons, Lovart’s and ElevenLabs’ marks fall back to the app’s own drawings', (tester) async {
      for (final plugin in builtIn) {
        if (plugin.setup == null) continue;
        final setup = plugin.setup!();
        if (pluginBrands.containsKey(setup.id)) expect(setupMarkOf(setup), isNull, reason: setup.id);
      }
      await pumpSettings(
        tester,
        Builder(
          builder: (context) => Column(
            children: [
              brandedIcon('notion', (context, size) => NotionMark(size: size))(context, 20),
              const LovartMark(size: 20),
              const ElevenLabsMark(size: 20),
            ],
          ),
        ),
      );
      expect(find.byType(BrandMarkIcon), findsNothing);
      expect(find.byType(NotionMark), findsOneWidget);
      expect(find.descendant(of: find.byType(LovartMark), matching: find.byType(AppIcon)), findsOneWidget);
      await endSettings(tester);
    });
  });

  testWidgets('in the app, the setups wear the company’s mark, and the actions too', (tester) async {
    for (final plugin in builtIn) {
      if (plugin.setup == null) continue;
      final setup = plugin.setup!();
      expect(setupMarkOf(setup) != null, pluginBrands.containsKey(setup.id) || setup.mark != null, reason: setup.id);
    }
    await pumpSettings(tester, Builder(builder: (context) => Column(children: [brandedIcon('notion', (context, size) => NotionMark(size: size))(context, 20), const ElevenLabsMark(size: 20)])));
    expect([for (final mark in tester.widgetList<BrandMarkIcon>(find.byType(BrandMarkIcon))) mark.mark.slug], ['notion', 'elevenlabs']);
    await endSettings(tester);
  });
}
