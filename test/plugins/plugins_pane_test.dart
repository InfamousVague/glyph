import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/claude/claude_mark.dart' show ClaudeMark;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/catalogue.dart';
import 'package:ghost_md/plugins/reach.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/plugins_pane.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/settings/settings_search.dart' show searchSettings;
import 'package:ghost_md/settings/settings_sheet.dart';

import '../settings/panes/support.dart';
import 'support.dart';

/// The plugins' catalogue and what Settings keeps of them. The catalogue was Settings › Plugins from 2026-10-18
/// (Matt: "rework the plugins page to be a marketplace, also move plugin settings to their own page under
/// settings") and is the Market since 2026-10-26 (Matt: "move the plugins section out of the settings (leaving plugin
/// specific settings to own their settings) add the plugins setting to the market page"; lib/market, its own tests in
/// test/market). Here: the catalogue's order and words, which the Market lists by, and Settings' side: the Market's
/// row, each added plugin's own page as a row of the list, found by the search and landed on by links, and the old
/// links to Plugins handed to the Market.
///
/// Every case is over the plugins that ship (lib/plugins/built_in.dart `builtIn`) in a registry of the test's own
/// with nothing switched by hand, which is a fresh install: Claude, GitHub, Notion, Marks and Rich embeds added.

/// A fresh install's plugins, Local only read from the app's preferences, with [store] for its switches.
Registry shipped([MemorySwitches? store]) => createRegistry(builtIn, store: store ?? MemorySwitches(), localOnly: () => preferences.value.localOnly);

/// Makes [registry] the app's for this test.
Registry install(Registry registry) {
  final before = plugins;
  addTearDown(() => usePlugins(before));
  usePlugins(registry);
  return registry;
}

GlyphPlugin pluginOf(String id) => builtIn.singleWhere((p) => p.manifest.id == id);

Finder rowOf(String sectionId) => find.byKey(ValueKey('row $sectionId'), skipOffstage: false);

List<SettingsSection> sectionsOf(WidgetTester tester) => tester.state<SettingsScreenState>(find.byType(SettingsScreen)).widget.sections;

List<(String, String?)> found(WidgetTester tester, String words) => [for (final hit in searchSettings(sectionsOf(tester), words)) (hit.section.id, hit.setting)];

void main() {
  setUpAll(loadAppFonts);

  group('the catalogue’s order and words', () {
    test('lists the plugins by category, then by name, and has the categories they are in', () {
      expect([for (final p in catalogueOrder(builtIn)) p.manifest.name], ['Claude', 'ElevenLabs', 'Lovart', 'Calendar', 'Contacts', 'Place reminders', 'Things', 'Todoist', 'Discord', 'GitHub', 'Google Meet', 'Notion', 'Slack', 'Webhooks', 'Zoom', 'Marks', 'Rich embeds']);
      expect([for (final c in categoriesOf(builtIn)) c.label], ['AI', 'Calendar & tasks', 'Import', 'Connections', 'Editor']);
      // Every plugin that ships has a category, a line of its own and what it adds.
      for (final plugin in builtIn) {
        expect(plugin.manifest.category, isNotNull, reason: plugin.manifest.id);
        expect(plugin.manifest.tagline, isNotNull, reason: plugin.manifest.id);
        expect(plugin.manifest.tagline!.length, lessThan(50), reason: '${plugin.manifest.id}’s line fits a card');
        expect(plugin.manifest.adds, isNotEmpty, reason: plugin.manifest.id);
      }
      // A plugin with no category is last, and its line is what it does.
      final third = GlyphPlugin(manifest: manifestOf('aaa', name: 'Aardvark'), icon: 'puzzle');
      expect(catalogueOrder([third, ...builtIn]).last, third);
      expect(third.manifest.line, third.manifest.description);
    });

    test('says what a plugin uses in plain words', () {
      expect(usesLine(pluginOf('notion').manifest), 'Uses your notes, the internet and your phone');
      expect(usesLine(pluginOf('github').manifest), 'Uses your notes, the internet and the model on your phone');
      expect(usesLine(pluginOf('rich-embeds').manifest), 'Uses the internet');
      expect(usesLine(pluginOf('marks').manifest), 'Uses nothing past the note you are in');
      expect(joinAnd(['a', 'b', 'c']), 'a, b and c');
      // The web's card's words stay as they were, for what still reads them.
      expect(reachLine(manifestOf('notion', permissions: [Permission.notes, Permission.network, Permission.native])), 'Your notes · The internet · Built-in app commands');
    });

    test('finds a plugin by its name, its line, what it does, what it adds or its category', () {
      List<String> left(String query, [PluginCategory? category]) => [
            for (final p in catalogueOrder(builtIn))
              if (inCatalogue(p, query: query, category: category)) p.manifest.name,
          ];
      expect(left('spotify'), ['Rich embeds']);
      expect(left('google'), ['Calendar', 'Google Meet']);
      expect(left('zoom'), ['Zoom']);
      expect(left('zapier'), ['Webhooks']);
      expect(left('', PluginCategory.imports), ['Things', 'Todoist']);
      expect(left('cal', PluginCategory.calendar), ['Calendar', 'Contacts', 'Place reminders']);
      expect(left('spotify', PluginCategory.ai), isEmpty);
    });

    test('a switch as set, whatever Local only says', () {
      var localOnly = false;
      final registry = createRegistry(builtIn, store: MemorySwitches(), localOnly: () => localOnly);
      expect((registry.switchedOn('notion'), registry.switchedOn('slack'), registry.switchedOn('nothing')), (true, false, false));
      localOnly = true;
      expect((registry.isEnabled('notion'), registry.switchedOn('notion')), (false, true));
    });
  });

  group('the plugins in Settings', () {
    testWidgets('the Market heads a card of its own on the list, a row after it for each added plugin’s page', (tester) async {
      install(shipped());
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: const Size(390, 1600));
      final listed = [for (final s in sectionsOf(tester)) if (s.listed) s.id];
      expect(listed.sublist(listed.indexOf('ai'), listed.indexOf('about') + 1), ['ai', 'market', 'plugin:claude', 'plugin:github', 'plugin:notion', 'about']);
      final card = find.byKey(const ValueKey('cluster market'));
      expect([for (final id in ['market', 'plugin:claude', 'plugin:github', 'plugin:notion']) find.descendant(of: card, matching: rowOf(id)).evaluate().length], [1, 1, 1, 1]);
      expect(find.descendant(of: card, matching: rowOf('about')), findsNothing);
      expect(tester.widget<Text>(find.descendant(of: rowOf('market'), matching: find.byKey(const ValueKey('settings-row-summary')))).data, '7 of 16 plugins added');
      expect(tester.widget<AppIcon>(find.descendant(of: rowOf('market'), matching: find.byType(AppIcon)).first).icon, Lucide.store);
      expect(tester.widget<Text>(find.descendant(of: rowOf('plugin:claude'), matching: find.byKey(const ValueKey('settings-row-summary')))).data, pluginOf('claude').settings!.summary());
      // Each in its own icon, Claude's its own mark as an icon (Matt, 2026-10-26: "iconize the lovart logo so we can use
      // their logo in the settings, same with the Claude logo"), in its coral.
      expect(find.descendant(of: rowOf('plugin:claude'), matching: find.byType(ClaudeMark)), findsOneWidget);
      expect(find.descendant(of: rowOf('plugin:github'), matching: find.byType(ClaudeMark)), findsNothing);
      final claude = sectionsOf(tester).singleWhere((s) => s.id == 'plugin:claude');
      expect((claude.hue, claude.parent, claude.listed, claude.words), ('coral', null, true, pluginOf('claude').manifest.description));
      // The catalogue is not Settings' any more: no Plugins page, and no page a plugin for it.
      expect([for (final s in sectionsOf(tester)) if (s.id == 'plugins' || s.id.startsWith('plugins/') || s.parent == 'plugins') s.id], isEmpty);
      await endSettings(tester);
    });

    testWidgets('the Market’s row shuts Settings for the Market, and its search finds it by the plugins', (tester) async {
      install(shipped());
      final market = <String?>[];
      await openPane(tester, 'account', onMarket: ({plugin}) => market.add(plugin));
      expect(found(tester, 'plugins'), contains(('market', null)));
      expect(found(tester, 'themes'), contains(('market', null)));
      await endSettings(tester);
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}, onMarket: ({plugin}) => market.add(plugin)), size: const Size(390, 1600));
      await tapOn(tester, rowOf('market'));
      expect(market, [null]);
      // It is not entered: the list is still what shows.
      expect(display(tester), isNull);
      await endSettings(tester);
    });

    testWidgets('a link to what was Plugins, or a plugin’s page in it, is handed to the Market', (tester) async {
      install(shipped());
      final market = <String?>[];
      await openPane(tester, 'plugins/notion', onMarket: ({plugin}) => market.add(plugin));
      await endSettings(tester);
      await openPane(tester, 'plugins', onMarket: ({plugin}) => market.add(plugin));
      expect(market, ['notion', null]);
      await endSettings(tester);
      // With nowhere to hand it, Settings lands on the Market's row, whose page has the way there.
      expect(settingsLanding(const SettingsTarget('plugins/slack', nonce: 1)).id, 'market');
      expect(settingsLanding(const SettingsTarget('experience', nonce: 1)).setting, 'Mode');
      await openPane(tester, 'plugins');
      expect(display(tester), 'Market');
      expect(find.byType(MarketPane), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('a plugin’s row comes as it is added and goes as it is removed or held by Local only', (tester) async {
      final registry = install(shipped());
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: const Size(390, 1800));
      expect(rowOf('plugin:calendar'), findsNothing);
      registry.setEnabled('calendar', true);
      await tester.pump();
      await settleSettings(tester);
      expect(rowOf('plugin:calendar'), findsOneWidget);
      final listed = [for (final s in sectionsOf(tester)) if (s.listed) s.id];
      expect(listed.sublist(listed.indexOf('market'), listed.indexOf('about')), ['market', 'plugin:claude', 'plugin:calendar', 'plugin:github', 'plugin:notion']);
      registry.setEnabled('calendar', false);
      await tester.pump();
      await settleSettings(tester);
      expect(rowOf('plugin:calendar'), findsNothing);
      preferences.update((now) => now.copyWith(localOnly: true));
      // What the app's root does when the preferences change (lib/plugins/registry.dart).
      registry.preferencesChanged();
      await tester.pump();
      await settleSettings(tester);
      expect([for (final id in ['plugin:claude', 'plugin:github', 'plugin:notion']) rowOf(id).evaluate().length], [0, 0, 0]);
      await endSettings(tester);
    });

    // Matt, 2026-10-17: Ask Claude and its key were Settings › Ask Claude's; they are on Claude's page, a row of
    // Settings of its own since 2026-10-18.
    testWidgets('the search lands on each added plugin’s settings on its own page', (tester) async {
      final registry = install(shipped());
      await openPane(tester, 'market', size: const Size(390, 1200));
      expect(found(tester, 'ask claude'), contains(('plugin:claude', 'Ask Claude')));
      expect(found(tester, 'api key'), contains(('plugin:claude', 'API key')));
      expect(found(tester, 'anthropic'), contains(('plugin:claude', 'API key')));
      // Matt, 2026-10-17: "add the setting back in to be able to bind ghost as the agent on the phone".
      expect(found(tester, 'assistant'), contains(('plugin:claude', 'Phone assistant')));
      expect(found(tester, 'digital assistant'), contains(('plugin:claude', 'Phone assistant')));
      expect(found(tester, 'claude'), contains(('plugin:claude', null)));
      // Calendar is not added: Settings has no page of it to find.
      expect(found(tester, 'calendar').map((hit) => hit.$1), isNot(contains('plugin:calendar')));
      await endSettings(tester);

      registry.setEnabled('calendar', true);
      await openPane(tester, 'market');
      expect(found(tester, 'calendar'), contains(('plugin:calendar', null)));
      expect(found(tester, 'calendar addresses'), contains(('plugin:calendar', 'Calendar addresses')));
      expect(found(tester, 'google'), contains(('plugin:calendar', null)));
      await endSettings(tester);
    });

    testWidgets('a plugin’s row opens its page straight from the list, and back goes to the list', (tester) async {
      install(shipped());
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: const Size(390, 1600));
      await tapOn(tester, rowOf('plugin:claude'));
      expect(display(tester), 'Claude');
      expect(find.byType(PluginSettingsPage), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('settings-head-word')), matching: find.byType(Text))).textSpan!.toPlainText(), contains('Settings'));
      testBack.goBack();
      await tester.pump();
      await settleSettings(tester);
      expect(display(tester), isNull);
      await endSettings(tester);
    });

    testWidgets('a plugin page’s foot opens the plugin in the Market', (tester) async {
      install(shipped());
      final market = <String?>[];
      await openPane(tester, 'plugin:notion', size: const Size(390, 1600), onMarket: ({plugin}) => market.add(plugin));
      expect(find.byType(PluginSettingsPage), findsOneWidget);
      final foot = find.byKey(const ValueKey('plugin-page-foot'));
      expect(tester.widget<Text>(find.descendant(of: foot, matching: find.byType(Text)).first).textSpan!.toPlainText(), contains('are on'));
      await tapOn(tester, find.descendant(of: foot, matching: find.byType(GoWord)));
      expect(market, ['notion']);
      await endSettings(tester);
    });

    testWidgets('links into Settings still land on a plugin’s page: Claude’s “Add an API key”, Todoist’s while it is added', (tester) async {
      final registry = install(shipped());
      await openPane(tester, 'plugin:claude', setting: 'API key');
      expect(display(tester), 'Claude');
      await endSettings(tester);
      registry.setEnabled('todoist', true);
      await openPane(tester, 'plugin:todoist');
      expect(display(tester), 'Todoist');
      expect(rowLabels(tester).take(2), ['Completed tasks too', 'Todoist CSV export (.csv)']);
      await endSettings(tester);
    });

    testWidgets('finds only names the pages draw: every setting listed for the plugins’ pages is on that page', (tester) async {
      final registry = install(shipped());
      for (final plugin in builtIn) {
        if (plugin.manifest.id != 'contacts') registry.setEnabled(plugin.manifest.id, true);
      }
      // The meeting plugins' pages are listed only for an account with Ghost in meetings, which this sheet has not:
      // test/meet/meet_card_test.dart holds their pages to what they list.
      final ids = [
        for (final spec in settingsSections)
          if ((spec.id == 'market' || spec.id.startsWith('plugin:')) && spec.id != 'plugin:google-meet' && spec.id != 'plugin:zoom') spec.id,
      ];
      expect(ids, containsAll(['market', 'plugin:claude', 'plugin:calendar']));
      final missing = <String>[];
      for (final id in ids) {
        await openPane(tester, id, size: const Size(390, 4000));
        final section = sectionsOf(tester).firstWhere((s) => s.id == id);
        expect(display(tester), section.label);
        for (final setting in section.settings) {
          final named = find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name != null && w.name!.toLowerCase().replaceAll('’', "'") == setting.name.toLowerCase().replaceAll('’', "'"), skipOffstage: false);
          if (named.evaluate().isEmpty) missing.add('$id: ${setting.name}');
        }
        await endSettings(tester);
      }
      // Drawn only once signed in, as their pages' own tests hold.
      expect(missing, ['plugin:notion: Boards']);
    });

    testWidgets('reads “0 of 0 plugins added” before any plugin is put in place, which is the app until built_in.dart installs them', (tester) async {
      install(createRegistry(const [], store: MemorySwitches()));
      await openPane(tester, 'market');
      expect(find.textContaining('0 of 0 plugins added'), findsOneWidget);
      expect(pluginPageSections(), isEmpty);
      await endSettings(tester);
    });
  });
}
