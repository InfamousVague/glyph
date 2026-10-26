import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_items.dart';
import 'package:ghost_md/market/market_looks.dart';
import 'package:ghost_md/market/market_plugins.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/theme_cards.dart' show ThemeOption, ThemePalette;
import 'package:ghost_md/market/market_cards.dart';

import '../settings/panes/support.dart' hide tapOn;

/// The Market (lib/market/market_screen.dart; Matt, 2026-10-26: "Make the plugins a dedicated "Market" section in
/// the app, include some more themes, fonts an of course all our plugins with vivid iconography and imagery where
/// possible include mobile and desktop support"): its shelves, the search across them, Add and Remove through the
/// registry, a plugin's page and its way to its Settings, Local only, and a theme, an accent and a face applied.
///
/// Over the plugins that ship, in a registry of the test's own with nothing switched by hand: a fresh install, with
/// Claude, GitHub, Notion, Marks and Rich embeds added.
void main() {
  setUpAll(loadAppFonts);

  Registry shipped([MemorySwitches? store]) => createRegistry(builtIn, store: store ?? MemorySwitches(), localOnly: () => preferences.value.localOnly);

  Finder card(String id) => find.byKey(ValueKey('market-plugin-$id'), skipOffstage: false);
  Finder shelfOf(String name) => find.byKey(ValueKey('shelf $name'), skipOffstage: false);

  /// The plugins on a shelf (`added`, `discover`), by id, in its order.
  List<String> onShelf(WidgetTester tester, String name) => [
        for (final each in tester.widgetList<MarketPluginCard>(find.descendant(of: shelfOf(name), matching: find.byType(MarketPluginCard, skipOffstage: false), skipOffstage: false))) each.plugin.manifest.id,
      ];

  Future<({List<String> settings, List<String> localOnly})> pumpMarket(
    WidgetTester tester, {
    Registry? registry,
    MarketShelf? shelf,
    String? plugin,
    Size size = const Size(390, 3000),
    Preferences prefs = const Preferences(theme: 'light'),
  }) async {
    final settings = <String>[], localOnly = <String>[];
    await pumpSettings(
      tester,
      MarketScreen(onBack: () {}, registry: registry ?? shipped(), shelf: shelf, plugin: plugin, onPluginSettings: settings.add, onLocalOnly: () => localOnly.add('privacy')),
      size: size,
      prefs: prefs,
    );
    return (settings: settings, localOnly: localOnly);
  }

  /// Brings [finder] to the middle of its scroller, clear of the bar over the page, and presses it.
  Future<void> tapOn(WidgetTester tester, Finder finder) async {
    final at = finder.first;
    unawaited(Scrollable.ensureVisible(tester.element(at), alignment: 0.5));
    await tester.pump();
    await tester.tap(at);
    await tester.pump();
    await settleSettings(tester);
  }

  Future<void> search(WidgetTester tester, String words) async {
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('market-find')), matching: find.byType(EditableText)), words);
    await tester.pump();
    await settleSettings(tester);
  }

  group('what it reads', () {
    test('says where each plugin works, from the code', () {
      String reach(String id) => reachOf(builtIn.singleWhere((p) => p.manifest.id == id)).line;
      expect(reach('claude'), 'Mobile · Desktop');
      expect(reach('notion'), 'Android · Desktop');
      expect(reach('slack'), 'Android · Desktop');
      expect(reach('place-reminders'), 'Android only');
      expect(reach('todoist'), 'Android · Desktop');
      expect(reach('lovart'), 'Mobile · Desktop');
      // Off an iPhone as Slack is (lib/core/iphone_app.dart; Matt, 2026-10-26).
      expect(reach('discord'), 'Android · Desktop');
    });

    test('gives every plugin a hue it can draw, its Settings page’s where it has one', () {
      for (final plugin in builtIn) {
        expect(marketHues, contains(pluginHue(plugin)), reason: plugin.manifest.id);
        if (plugin.settings?.hue case final hue?) expect(pluginHue(plugin), hue, reason: plugin.manifest.id);
      }
    });

    test('sends an old link to Plugins to the Market', () {
      expect(marketLanding('plugins'), (plugin: null));
      expect(marketLanding('market'), (plugin: null));
      expect(marketLanding('plugins/notion'), (plugin: 'notion'));
      expect(marketLanding('plugin:notion'), isNull);
      expect(marketLanding('account'), isNull);
    });

    test('finds themes and faces by their names and what they are', () {
      const dawn = ThemeOption(value: 'dawn', label: 'Dawn', description: 'Light, with red', palette: _palette);
      expect((themeFound(dawn, 'dawn'), themeFound(dawn, 'red'), themeFound(dawn, 'theme'), themeFound(dawn, 'mono')), (true, true, true, false));
      expect((faceFound('maple', 'maple'), faceFound('maple', 'coding'), faceFound('inter', 'interface'), faceFound('inter', 'coding')), (true, true, true, false));
    });
  });

  group('the shelves', () {
    testWidgets('All has the featured plugins, the themes, the fonts and every plugin, Added and Discover', (tester) async {
      // Wide enough that the themes and the fonts stand across rather than scroll.
      await pumpMarket(tester, size: const Size(1000, 3000));
      expect(find.byKey(const ValueKey('market-band')), findsOneWidget);
      expect(find.byKey(const ValueKey('market-featured-claude'), skipOffstage: false), findsOneWidget);
      expect(find.byType(MarketThemeCard, skipOffstage: false), findsNWidgets(themes.length));
      expect(find.byType(MarketFontCard, skipOffstage: false), findsNWidgets(typefaces.length));
      expect(onShelf(tester, 'added'), ['claude', 'github', 'notion', 'marks', 'rich-embeds']);
      expect(onShelf(tester, 'discover'), ['lovart', 'calendar', 'contacts', 'place-reminders', 'things', 'todoist', 'discord', 'slack', 'webhooks']);
      expect(find.text('5 of ${builtIn.length} added', skipOffstage: false), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('each other shelf is its kind alone', (tester) async {
      await pumpMarket(tester, shelf: MarketShelf.themes);
      expect(find.byType(MarketPluginCard, skipOffstage: false), findsNothing);
      expect(find.byType(MarketFontCard, skipOffstage: false), findsNothing);
      expect(find.byKey(const ValueKey('market-accents'), skipOffstage: false), findsOneWidget);
      await endSettings(tester);

      await pumpMarket(tester, shelf: MarketShelf.fonts);
      expect(find.byType(MarketThemeCard, skipOffstage: false), findsNothing);
      // A note's faces, then the interface's.
      expect(find.byType(MarketFontCard, skipOffstage: false), findsNWidgets(typefaces.length + interfaceFaces.length));
      await endSettings(tester);

      await pumpMarket(tester, shelf: MarketShelf.plugins);
      expect(find.byType(MarketThemeCard, skipOffstage: false), findsNothing);
      expect(find.byType(MarketPluginCard, skipOffstage: false), findsNWidgets(builtIn.length));
      // Its categories filter it.
      await tapOn(tester, find.widgetWithText(MarketChip, 'Import'));
      expect([...onShelf(tester, 'added'), ...onShelf(tester, 'discover')], ['things', 'todoist']);
      await endSettings(tester);
    });

    testWidgets('the control between the shelves moves between them', (tester) async {
      await pumpMarket(tester);
      await tapOn(tester, find.descendant(of: find.byKey(const ValueKey('market-shelves')), matching: find.text('Fonts')));
      expect(find.byType(MarketPluginCard, skipOffstage: false), findsNothing);
      expect(find.byType(MarketFontCard, skipOffstage: false), findsWidgets);
      await endSettings(tester);
    });

    testWidgets('the search filters every shelf at once, and a search that leaves nothing has the way back', (tester) async {
      await pumpMarket(tester);
      await search(tester, 'google');
      expect(find.byType(MarketPluginCard, skipOffstage: false), findsOneWidget);
      expect(card('calendar'), findsOneWidget);
      expect(find.byType(MarketThemeCard, skipOffstage: false), findsNothing);
      await search(tester, 'dark');
      expect([for (final each in tester.widgetList<MarketThemeCard>(find.byType(MarketThemeCard, skipOffstage: false))) each.option.value], containsAll(['dark', 'boreal', 'ember']));
      await search(tester, 'coding');
      expect([for (final each in tester.widgetList<MarketFontCard>(find.byType(MarketFontCard, skipOffstage: false))) each.face], [for (final face in typefaces) if (isCodingFace(face)) face]);
      expect(find.byType(MarketPluginCard, skipOffstage: false), findsNothing);
      await search(tester, 'zzzz');
      expect(find.byKey(const ValueKey('market-nothing')), findsOneWidget);
      await tapOn(tester, find.byKey(const ValueKey('market-everything')));
      expect(find.byType(MarketPluginCard, skipOffstage: false), findsNWidgets(builtIn.length));
      await endSettings(tester);
    });
  });

  testWidgets('lists Discord among the plugins, found by its name, in its colour and the chat bubble, not a brand’s mark', (tester) async {
    final discord = builtIn.singleWhere((p) => p.manifest.id == 'discord');
    expect(hasBrandMark(discord), isFalse);
    expect(pluginHue(discord), 'indigo');
    expect(pluginsFound(builtIn, 'discord').map((p) => p.manifest.id), ['discord']);
    await pumpMarket(tester);
    await search(tester, 'discord');
    expect(find.byType(MarketPluginCard, skipOffstage: false), findsOneWidget);
    expect(card('discord'), findsOneWidget);
    expect(find.descendant(of: card('discord'), matching: find.text('Discord')), findsWidgets);
    expect(find.descendant(of: card('discord'), matching: find.text('Android · Desktop')), findsWidgets);
    await endSettings(tester);
  });

  group('a plugin', () {
    testWidgets('Add on its card switches it on through the registry, kept, and the card moves to Added', (tester) async {
      final store = MemorySwitches();
      final registry = shipped(store);
      await pumpMarket(tester, registry: registry, shelf: MarketShelf.plugins);
      await tapOn(tester, find.descendant(of: card('slack'), matching: find.byKey(const ValueKey('market-add-slack'))));
      expect(store.held, {'slack': true});
      expect(registry.isEnabled('slack'), isTrue);
      expect(onShelf(tester, 'added'), contains('slack'));
      expect(find.text('6 of ${builtIn.length} added', skipOffstage: false), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('its page has what it does, adds and may reach, and Add and Remove switch it', (tester) async {
      final store = MemorySwitches();
      final registry = shipped(store);
      final went = await pumpMarket(tester, registry: registry, shelf: MarketShelf.plugins);
      await tapOn(tester, card('slack'));
      expect(find.byKey(const ValueKey('market-detail-slack')), findsOneWidget);
      expect(find.text('What it may reach'), findsOneWidget);
      expect(find.text('The internet'), findsOneWidget);
      expect(find.byKey(const ValueKey('market-settings-slack')), findsNothing);
      await tapOn(tester, find.byKey(const ValueKey('market-add-slack')).last);
      expect(store.held, {'slack': true});
      // Added, its Settings opens its own page there.
      await tapOn(tester, find.byKey(const ValueKey('market-settings-slack')));
      expect(went.settings, ['slack']);
      await tapOn(tester, find.byKey(const ValueKey('market-remove-slack')));
      expect(store.held, {'slack': false});
      expect(registry.isEnabled('slack'), isFalse);
      // The bar's arrow, and the back gesture, take a phone back to the shelves.
      testBack.goBack();
      await tester.pump();
      await settleSettings(tester);
      expect(find.byKey(const ValueKey('market-detail-slack')), findsNothing);
      await endSettings(tester);
    });

    testWidgets('a plugin with no page of its own has no Settings', (tester) async {
      await pumpMarket(tester, plugin: 'marks');
      expect(find.byKey(const ValueKey('market-detail-marks')), findsOneWidget);
      expect(find.byKey(const ValueKey('market-settings-marks')), findsNothing);
      expect(find.text('Nothing past the note you are in'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('with room, its page opens beside the shelves', (tester) async {
      await pumpMarket(tester, size: const Size(1280, 800), shelf: MarketShelf.plugins);
      await tapOn(tester, card('notion'));
      expect(find.byKey(const ValueKey('market-pane')), findsOneWidget);
      expect(card('github'), findsOneWidget);
      await tapOn(tester, find.byKey(const ValueKey('market-detail-close')));
      expect(find.byKey(const ValueKey('market-pane')), findsNothing);
      await endSettings(tester);
    });

    testWidgets('Local only holds one that uses the internet off, says so, and its word goes to the switch', (tester) async {
      final registry = shipped();
      final went = await pumpMarket(tester, registry: registry, shelf: MarketShelf.plugins, prefs: const Preferences(theme: 'light', localOnly: true));
      expect(find.byKey(const ValueKey('market-local-only')), findsOneWidget);
      expect(find.descendant(of: card('slack'), matching: find.byKey(const ValueKey('market-add-slack'))), findsNothing);
      await tapOn(tester, find.descendant(of: find.byKey(const ValueKey('market-local-only')), matching: find.byType(MarketWord)));
      expect(went.localOnly, ['privacy']);
      // Its page cannot add it.
      await tapOn(tester, card('slack'));
      expect(tester.widget<MarketButton>(find.byKey(const ValueKey('market-add-slack'))).onPress, isNull);
      await endSettings(tester);
    });
  });

  group('looks', () {
    testWidgets('a theme pressed is applied as Appearance applies it, with its accent', (tester) async {
      await pumpMarket(tester, shelf: MarketShelf.themes);
      await tapOn(tester, find.byKey(const ValueKey('market-theme-boreal')));
      expect((preferences.value.theme, preferences.value.accent), ('boreal', themePresets['boreal']!.accent));
      expect(tester.widget<MarketCard>(find.byKey(const ValueKey('market-theme-boreal'))).selected, isTrue);
      await tapOn(tester, find.byKey(const ValueKey('market-theme-light')));
      expect((preferences.value.theme, preferences.value.accent), ('light', 'ink'));
      await endSettings(tester);
    });

    testWidgets('a face pressed is the note’s, or the interface’s, and is marked', (tester) async {
      await pumpMarket(tester, shelf: MarketShelf.fonts);
      await tapOn(tester, find.byKey(const ValueKey('market-face-note-fira')));
      expect(preferences.value.noteFace, 'fira');
      await tapOn(tester, find.byKey(const ValueKey('market-face-interface-plex')));
      expect(preferences.value.typeface, 'plex');
      expect(tester.widget<MarketCard>(find.byKey(const ValueKey('market-face-note-fira'))).selected, isTrue);
      expect(tester.widget<MarketCard>(find.byKey(const ValueKey('market-face-interface-plex'))).selected, isTrue);
      await endSettings(tester);
    });
  });
}

const _palette = ThemePalette(
  background: Color(0xFFFFFFFF),
  sidebar: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  border: Color(0xFFFFFFFF),
  text: Color(0xFF000000),
  muted: Color(0xFF777777),
  accent: Color(0xFFFF0000),
);
