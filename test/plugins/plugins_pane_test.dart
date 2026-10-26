import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
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

/// Settings › Plugins as a catalogue (lib/settings/panes/plugins_pane.dart; Matt, 2026-10-18: "rework the plugins
/// page to be a marketplace, also move plugin settings to their own page under settings"): the shelves and their
/// cards, the filter and the search, Add, Local only, a plugin's page in the catalogue, and the plugins' own pages
/// as rows of Settings' list, found by the search and landed on by links.
///
/// Every case is over the plugins that ship (lib/plugins/built_in.dart `builtIn`) in a registry of the test's own
/// with nothing switched by hand, which is a fresh install: Claude, GitHub, Notion, Marks and Rich embeds added.
///
/// The page was a port of the web app's Plugins (src/app/plugins/PluginsPane.tsx) until then, held to its measured
/// rects (fixtures/plugins-pane-390.json, fixtures/web/); it is the app's own now, and those are the web's page.

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

Finder heroCalled(String name) => find.byWidgetPredicate((w) => w is PaneHero && w.title == name, skipOffstage: false);
Finder cardOf(String name) => find.ancestor(of: heroCalled(name), matching: find.byType(PluginCard, skipOffstage: false)).first;
Finder inCard(String name, Finder what) => find.descendant(of: cardOf(name), matching: what, skipOffstage: false);
Finder shelfCalled(String title) => find.byWidgetPredicate((w) => w is PluginShelf && w.title == title, skipOffstage: false);
Finder chipCalled(String label) => find.byWidgetPredicate((w) => w is CategoryChip && w.label == label, skipOffstage: false);
Finder rowOf(String sectionId) => find.byKey(ValueKey('row $sectionId'), skipOffstage: false);

/// The names on a shelf's cards, in its order.
List<String> shelf(WidgetTester tester, String title) => [
      for (final card in tester.widgetList<PluginCard>(find.descendant(of: shelfCalled(title), matching: find.byType(PluginCard, skipOffstage: false), skipOffstage: false))) card.plugin.manifest.name,
    ];

List<String> heroTitles(WidgetTester tester) => [for (final hero in tester.widgetList<PaneHero>(find.byType(PaneHero, skipOffstage: false))) hero.title];

/// The words, on the screen, of a sentence with a word that goes somewhere in it.
String said(WidgetTester tester, Finder text) => tester.widget<Text>(text).textSpan!.toPlainText().replaceAll('￼', 'Local only');

/// The catalogue by itself, outside Settings, with somewhere for its cards to go.
Future<List<(String, String?)>> pumpPane(WidgetTester tester, Registry registry, {bool localOnly = false, bool goes = true, Size size = phone}) async {
  final opened = <(String, String?)>[];
  await pumpSettings(
    tester,
    SingleChildScrollView(child: PluginsPane(registry: registry, onOpen: goes ? (id, {setting}) => opened.add((id, setting)) : null)),
    prefs: Preferences(theme: 'light', localOnly: localOnly),
    size: size,
  );
  return opened;
}

/// A plugin's page in the catalogue by itself.
Future<List<(String, String?)>> pumpInfo(WidgetTester tester, Registry registry, String id, {bool localOnly = false}) async {
  final opened = <(String, String?)>[];
  await pumpSettings(
    tester,
    SingleChildScrollView(child: PluginInfoPane(plugin: registry.byId(id)!, registry: registry, onOpen: (id, {setting}) => opened.add((id, setting)))),
    prefs: Preferences(theme: 'light', localOnly: localOnly),
    size: const Size(390, 1400),
  );
  return opened;
}

Future<void> typeIn(WidgetTester tester, String words) async {
  await tester.enterText(find.descendant(of: find.byKey(const ValueKey('plugins-find')), matching: find.byType(EditableText)), words);
  await tester.pump();
  await settleSettings(tester);
}

List<SettingsSection> sectionsOf(WidgetTester tester) => tester.state<SettingsScreenState>(find.byType(SettingsScreen)).widget.sections;

List<(String, String?)> found(WidgetTester tester, String words) => [for (final hit in searchSettings(sectionsOf(tester), words)) (hit.section.id, hit.setting)];

void main() {
  setUpAll(loadAppFonts);

  group('the catalogue’s order and words', () {
    test('lists the plugins by category, then by name, and has the categories they are in', () {
      expect([for (final p in catalogueOrder(builtIn)) p.manifest.name], ['Claude', 'Lovart', 'Calendar', 'Contacts', 'Place reminders', 'Things', 'Todoist', 'GitHub', 'Notion', 'Slack', 'Webhooks', 'Marks', 'Rich embeds']);
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
      expect(left('google'), ['Calendar']);
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

  group('Settings › Plugins', () {
    testWidgets('has every plugin on two shelves, Added and Discover, in the catalogue’s order', (tester) async {
      await pumpPane(tester, shipped());
      expect(heroTitles(tester).first, 'Plugins');
      expect(find.textContaining('5 of 13 added.', skipOffstage: false), findsOneWidget);
      expect(shelf(tester, 'Added'), ['Claude', 'GitHub', 'Notion', 'Marks', 'Rich embeds']);
      expect(shelf(tester, 'Discover'), ['Lovart', 'Calendar', 'Contacts', 'Place reminders', 'Things', 'Todoist', 'Slack', 'Webhooks']);
      // The search finds the shelves by their captions.
      expect(find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name == 'Discover', skipOffstage: false), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('a card says what the plugin is and what it uses, and Add, or that it is added', (tester) async {
      await pumpPane(tester, shipped());
      expect(inCard('Notion', find.text('List items as tasks on your Notion boards', skipOffstage: false)), findsOneWidget);
      expect(inCard('Notion', find.text('Uses your notes, the internet and your phone', skipOffstage: false)), findsOneWidget);
      expect(inCard('Marks', find.text('Uses nothing past the note you are in', skipOffstage: false)), findsOneWidget);
      expect(inCard('Claude', find.text('Added', skipOffstage: false)), findsOneWidget);
      expect(inCard('Claude', find.byType(RowAction, skipOffstage: false)), findsNothing);
      expect(inCard('Slack', find.widgetWithText(RowAction, 'Add', skipOffstage: false)), findsOneWidget);
      // Each in its own icon; one the kit does not draw is the puzzle piece.
      expect(tester.widget<AppIcon>(inCard('Notion', find.byType(AppIcon, skipOffstage: false)).first).icon, Lucide.squareKanban);
      await endSettings(tester);

      final third = GlyphPlugin(manifest: manifestOf('third', name: 'Third', standard: false), icon: 'no-such-icon');
      await pumpPane(tester, createRegistry([third], store: MemorySwitches()));
      expect(tester.widget<AppIcon>(inCard('Third', find.byType(AppIcon, skipOffstage: false)).first).icon, Lucide.puzzle);
      await endSettings(tester);
    });

    testWidgets('Add switches the plugin on, kept, and the card moves to Added', (tester) async {
      final store = MemorySwitches();
      final registry = shipped(store);
      await pumpPane(tester, registry);
      await tapOn(tester, inCard('Slack', find.byType(RowAction, skipOffstage: false)));
      expect(store.held, {'slack': true});
      expect(registry.isEnabled('slack'), isTrue);
      expect(shelf(tester, 'Added'), ['Claude', 'GitHub', 'Notion', 'Slack', 'Marks', 'Rich embeds']);
      expect(shelf(tester, 'Discover'), isNot(contains('Slack')));
      expect(find.textContaining('6 of 13 added.', skipOffstage: false), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('filters by category, All bringing them back, with the search inside the category chosen', (tester) async {
      await pumpPane(tester, shipped());
      expect([for (final chip in tester.widgetList<CategoryChip>(find.byType(CategoryChip, skipOffstage: false))) chip.label], ['All', 'AI', 'Calendar & tasks', 'Import', 'Connections', 'Editor']);
      expect(tester.widget<CategoryChip>(chipCalled('All')).chosen, isTrue);
      await tapOn(tester, chipCalled('Import'));
      expect(heroTitles(tester), ['Plugins', 'Things', 'Todoist']);
      expect(shelfCalled('Added'), findsNothing);
      expect(tester.widget<CategoryChip>(chipCalled('Import')).chosen, isTrue);
      await tapOn(tester, chipCalled('AI'));
      expect(heroTitles(tester), ['Plugins', 'Claude', 'Lovart']);
      await typeIn(tester, 'spotify');
      expect(heroTitles(tester), ['Plugins']);
      expect(find.text('No plugin matches'), findsOneWidget);
      expect(find.text('Nothing in AI matches “spotify”.'), findsOneWidget);
      await tapOn(tester, find.text('Show every plugin'));
      expect(heroTitles(tester).length, 14);
      expect(tester.widget<CategoryChip>(chipCalled('All')).chosen, isTrue);
      await endSettings(tester);
    });

    testWidgets('the search leaves the plugins it finds, on their shelves', (tester) async {
      await pumpPane(tester, shipped());
      await typeIn(tester, 'notes from claude');
      expect(heroTitles(tester), ['Plugins', 'Claude']);
      await typeIn(tester, 'google');
      expect(shelf(tester, 'Discover'), ['Calendar']);
      expect(shelfCalled('Added'), findsNothing);
      await typeIn(tester, '');
      expect(heroTitles(tester).length, 14);
      await endSettings(tester);
    });

    // Changed on purpose on the page (docs/DESIGN.md §138): "Local only" is a word that goes to its switch.
    testWidgets('holds every plugin that uses the internet off under Local only, says so on its card, and its words open the switch', (tester) async {
      final opened = await pumpPane(tester, shipped(), localOnly: true);
      final callout = find.byType(SettingsCallout);
      expect(said(tester, find.descendant(of: callout, matching: find.byWidgetPredicate((w) => w is Text && w.textSpan != null))), 'Local only is on, so plugins that use the internet are held off until it is off.');
      await tapOn(tester, find.descendant(of: callout, matching: find.byType(GoWord)));
      // Slack is held: it says so, and cannot be added.
      expect(tester.widget<RowAction>(inCard('Slack', find.byType(RowAction, skipOffstage: false))).disabled, isTrue);
      expect(said(tester, inCard('Slack', find.byWidgetPredicate((w) => w is Text && (w.textSpan?.toPlainText().startsWith('Off while') ?? false), skipOffstage: false))), 'Off while Local only is on: it uses the internet.');
      await tapOn(tester, inCard('Slack', find.byType(GoWord, skipOffstage: false)));
      expect(opened, [('account', 'Privacy'), ('account', 'Privacy')]);
      // Notion was added, and is still on Added, held; Marks reaches nothing past the phone and is not.
      expect(shelf(tester, 'Added'), contains('Notion'));
      expect(inCard('Notion', find.byType(GoWord, skipOffstage: false)), findsOneWidget);
      expect(inCard('Marks', find.byType(GoWord, skipOffstage: false)), findsNothing);
      expect(inCard('Place reminders', find.byType(GoWord, skipOffstage: false)), findsNothing);
      await endSettings(tester);
    });

    testWidgets('a card opens its plugin’s page in the catalogue', (tester) async {
      final opened = await pumpPane(tester, shipped());
      await tapOn(tester, heroCalled('Notion'));
      await tapOn(tester, heroCalled('Slack'));
      expect(opened, [('plugins/notion', null), ('plugins/slack', null)]);
      await endSettings(tester);
    });

    testWidgets('stands its cards one to a row on a phone, and two or three across where there is room', (tester) async {
      expect([for (final width in [350.0, 540.0, 820.0, 1200.0]) PluginShelf.across(width, 12)], [1, 2, 3, 3]);
      await pumpPane(tester, shipped());
      final claude = tester.getRect(cardOf('Claude')), github = tester.getRect(cardOf('GitHub'));
      expect((github.top > claude.bottom, claude.width), (true, github.width));
      await endSettings(tester);

      await pumpPane(tester, shipped(), size: const Size(900, 1600));
      final tops = [for (final name in ['Claude', 'GitHub', 'Notion', 'Marks']) tester.getRect(cardOf(name)).top];
      expect(tops.sublist(0, 3).toSet(), hasLength(1), reason: 'three across');
      expect(tops[3], greaterThan(tops[0]));
      // The cards of a line are as tall as its tallest.
      expect({for (final name in ['Claude', 'GitHub', 'Notion']) tester.getRect(cardOf(name)).height}, hasLength(1));
      await endSettings(tester);
    });

    testWidgets('reads “0 of 0 added” before any plugin is put in place, which is the app until built_in.dart installs them', (tester) async {
      install(createRegistry(const [], store: MemorySwitches()));
      await openPane(tester, 'plugins');
      expect(heroTitles(tester), ['Plugins']);
      expect(find.textContaining('0 of 0 added.'), findsOneWidget);
      expect(find.text('There is no plugin in this build.', skipOffstage: false), findsOneWidget);
      expect(pluginPageSections(), isEmpty);
      expect(pluginInfoSections(), isEmpty);
      await endSettings(tester);
    });
  });

  group('a plugin’s page in the catalogue', () {
    testWidgets('says what it does, what it adds and what it may reach, in plain words', (tester) async {
      await pumpInfo(tester, shipped(), 'notion');
      expect(cardTitles(tester), [null, 'What it does', 'What it adds', 'What it may reach']);
      expect(find.text(pluginOf('notion').manifest.description, skipOffstage: false), findsOneWidget);
      expect(rowLabels(tester, 'What it adds'), [...pluginOf('notion').manifest.adds, 'A page of its own in Settings']);
      expect(rowLabels(tester, 'What it may reach'), ['Your notes', 'The internet', 'Your phone']);
      final internet = tester.widget<SettingRow>(rowCalled('The internet')).hint! as Text;
      expect(internet.data, endsWith('Only the items you send go. It talks to api.notion.com and ghostmarkdown.com and nowhere else.'));
      expect(find.text('Connections · Ghost.md · version 1.0.0', skipOffstage: false), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('Add and Remove switch it, and once it is added its Settings row opens its own page', (tester) async {
      final store = MemorySwitches();
      final registry = shipped(store);
      final opened = await pumpInfo(tester, registry, 'slack');
      expect(tester.widget<PaneHero>(heroCalled('Slack')).status!.text, 'Not added');
      expect(rowCalled('Settings'), findsNothing);
      await tapOn(tester, inRow('Not added', find.widgetWithText(RowAction, 'Add')));
      expect(store.held, {'slack': true});
      expect(registry.isEnabled('slack'), isTrue);
      expect(tester.widget<PaneHero>(heroCalled('Slack')).status!.text, 'Added');
      await tapOn(tester, rowCalled('Settings'));
      expect(opened, [('plugin:slack', null)]);
      await tapOn(tester, inRow('Added to Ghost.md', find.widgetWithText(RowAction, 'Remove')));
      expect(store.held, {'slack': false});
      expect(registry.isEnabled('slack'), isFalse);
      expect(rowCalled('Settings'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('Marks asks for nothing, and says so; it has no page of its own to go to', (tester) async {
      await pumpInfo(tester, shipped(), 'marks');
      expect(rowLabels(tester, 'What it may reach'), ['Nothing past the note you are in']);
      expect(rowCalled('A page of its own in Settings'), findsNothing);
      expect(rowCalled('Settings'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('under Local only, one that uses the internet says so and cannot be added or removed', (tester) async {
      final opened = await pumpInfo(tester, shipped(), 'slack', localOnly: true);
      expect(tester.widget<PaneHero>(heroCalled('Slack')).status!.text, 'Held off by Local only');
      expect(tester.widget<RowAction>(inRow('Not added', find.byType(RowAction))).disabled, isTrue);
      await tapOn(tester, inRow('Off while Local only is on', find.byType(GoWord)));
      expect(opened, [('account', 'Privacy')]);
      await endSettings(tester);
    });
  });

  group('the plugins in Settings', () {
    testWidgets('Plugins heads a card of its own on the list, a row after it for each added plugin’s page', (tester) async {
      install(shipped());
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: const Size(390, 1600));
      final listed = [for (final s in sectionsOf(tester)) if (s.listed) s.id];
      expect(listed.sublist(listed.indexOf('ai'), listed.indexOf('about') + 1), ['ai', 'plugins', 'plugin:claude', 'plugin:github', 'plugin:notion', 'about']);
      final card = find.byKey(const ValueKey('cluster plugins'));
      expect([for (final id in ['plugins', 'plugin:claude', 'plugin:github', 'plugin:notion']) find.descendant(of: card, matching: rowOf(id)).evaluate().length], [1, 1, 1, 1]);
      expect(find.descendant(of: card, matching: rowOf('about')), findsNothing);
      expect(tester.widget<Text>(find.descendant(of: rowOf('plugins'), matching: find.byKey(const ValueKey('settings-row-summary')))).data, '5 of 13 added');
      expect(tester.widget<Text>(find.descendant(of: rowOf('plugin:claude'), matching: find.byKey(const ValueKey('settings-row-summary')))).data, pluginOf('claude').settings!.summary());
      // Each in its own icon, and Claude in its coral.
      expect(tester.widget<AppIcon>(find.descendant(of: rowOf('plugin:claude'), matching: find.byType(AppIcon)).first).icon, Lucide.bot);
      final claude = sectionsOf(tester).singleWhere((s) => s.id == 'plugin:claude');
      expect((claude.hue, claude.parent, claude.listed, claude.words), ('coral', null, true, pluginOf('claude').manifest.description));
      // Every plugin's page in the catalogue is a sub-page of Plugins, in its green.
      expect([for (final s in sectionsOf(tester)) if (s.parent == 'plugins') s.id], [for (final p in catalogueOrder(builtIn)) 'plugins/${p.manifest.id}']);
      expect(sectionsOf(tester).singleWhere((s) => s.id == 'plugins/slack').hue, 'green');
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
      expect(listed.sublist(listed.indexOf('plugins'), listed.indexOf('about')), ['plugins', 'plugin:claude', 'plugin:calendar', 'plugin:github', 'plugin:notion']);
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
    testWidgets('the search lands on each plugin’s settings on its own page, and on its page in the catalogue while it is not added', (tester) async {
      final registry = install(shipped());
      await openPane(tester, 'plugins', size: const Size(390, 1200));
      expect(found(tester, 'ask claude'), contains(('plugin:claude', 'Ask Claude')));
      expect(found(tester, 'api key'), contains(('plugin:claude', 'API key')));
      expect(found(tester, 'anthropic'), contains(('plugin:claude', 'API key')));
      // Matt, 2026-10-17: "add the setting back in to be able to bind ghost as the agent on the phone".
      expect(found(tester, 'assistant'), contains(('plugin:claude', 'Phone assistant')));
      expect(found(tester, 'digital assistant'), contains(('plugin:claude', 'Phone assistant')));
      // Claude has its own page, so its name finds that and not its page in the catalogue.
      expect(found(tester, 'claude'), contains(('plugin:claude', null)));
      expect(found(tester, 'claude').map((hit) => hit.$1), isNot(contains('plugins/claude')));
      // Calendar is not added: its name finds its page in the catalogue, where it can be.
      expect(found(tester, 'calendar'), contains(('plugins/calendar', null)));
      expect(found(tester, 'calendar').map((hit) => hit.$1), isNot(contains('plugin:calendar')));
      expect(found(tester, 'discover'), contains(('plugins', 'Discover')));
      // Marks has no page but its page in the catalogue, added or not.
      expect(found(tester, 'marks'), contains(('plugins/marks', null)));
      await endSettings(tester);

      registry.setEnabled('calendar', true);
      await openPane(tester, 'plugins');
      expect(found(tester, 'calendar'), contains(('plugin:calendar', null)));
      expect(found(tester, 'calendar').map((hit) => hit.$1), isNot(contains('plugins/calendar')));
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

    testWidgets('a card opens its page in the catalogue, back from it is Plugins, and its Settings row and the page’s foot go between them', (tester) async {
      install(shipped());
      await openPane(tester, 'plugins');
      await tapOn(tester, heroCalled('Notion'));
      expect(display(tester), 'Notion');
      expect(find.byType(PluginInfoPane), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('settings-head-word')), matching: find.byType(Text))).textSpan!.toPlainText(), contains('Plugins'));
      await tapOn(tester, rowCalled('Settings'));
      expect(display(tester), 'Notion');
      expect(find.byType(PluginSettingsPage), findsOneWidget);
      await tapOn(tester, find.descendant(of: find.byKey(const ValueKey('plugin-page-foot')), matching: find.byType(GoWord)));
      expect(find.byType(PluginInfoPane), findsOneWidget);
      testBack.goBack();
      await tester.pump();
      await settleSettings(tester);
      expect(display(tester), 'Plugins');
      await endSettings(tester);
    });

    testWidgets('a plugin added from its page in the catalogue has its row on the list at once', (tester) async {
      install(shipped());
      await openPane(tester, 'plugins/slack', prefs: const Preferences(theme: 'light'));
      expect(display(tester), 'Slack');
      await tapOn(tester, inRow('Not added', find.byType(RowAction)));
      await tapOn(tester, rowCalled('Settings'));
      expect(display(tester), 'Slack');
      expect(find.byType(PluginSettingsPage), findsOneWidget);
      testBack.goBack();
      await tester.pump();
      await settleSettings(tester);
      expect(rowOf('plugin:slack'), findsOneWidget);
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
      await openPane(tester, 'plugins/todoist');
      expect(display(tester), 'Todoist');
      expect(find.byType(PluginInfoPane), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('finds only names the pages draw: every setting listed for Plugins and its plugins’ pages is on that page', (tester) async {
      final registry = install(shipped());
      for (final plugin in builtIn) {
        if (plugin.manifest.id != 'contacts') registry.setEnabled(plugin.manifest.id, true);
      }
      final ids = [for (final spec in settingsSections) if (spec.id == 'plugins' || spec.id.startsWith('plugin:') || spec.id.startsWith('plugins/')) spec.id];
      expect(ids, containsAll(['plugins', 'plugin:claude', 'plugin:calendar', 'plugins/marks']));
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
  });

  // Pictures of the page, drawn with the real faces: `flutter test --update-goldens`, then open shots/.
  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('Plugins on a phone, $theme', (tester) async {
        install(shipped());
        await openPane(tester, 'plugins', prefs: Preferences(theme: theme));
        await shot(tester, 'plugins-$theme');
      });

      testWidgets('the whole catalogue on a window tall enough to hold it, $theme', (tester) async {
        install(shipped());
        await openPane(tester, 'plugins', prefs: Preferences(theme: theme), size: const Size(390, 2900));
        await shot(tester, 'plugins-tall-$theme');
      });
    }

    testWidgets('Plugins under Local only, light', (tester) async {
      install(shipped());
      await openPane(tester, 'plugins', prefs: const Preferences(theme: 'light', localOnly: true));
      await shot(tester, 'plugins-local-only-light');
    });

    testWidgets('Plugins on a wide window, three across, light', (tester) async {
      install(shipped());
      await openPane(tester, 'plugins', size: wideWindow);
      await shot(tester, 'plugins-wide-light');
    });

    testWidgets('Notion’s page in the catalogue, light', (tester) async {
      install(shipped());
      await openPane(tester, 'plugins/notion', size: const Size(390, 1400));
      await shot(tester, 'plugin-info-notion-light');
    });

    testWidgets('Settings’ list with the Plugins card, light', (tester) async {
      install(shipped());
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: const Size(390, 1400));
      await shot(tester, 'settings-list-plugins-light');
    });
  });
}
