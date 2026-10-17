import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/reach.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/plugins_pane.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:glacier/glacier.dart';

import '../settings/panes/support.dart';
import 'support.dart';

/// Settings > Plugins (lib/settings/panes/plugins_pane.dart): the cases of `src/app/plugins/PluginsPane.test.tsx`,
/// then the page inside the real sheet (its row, its sub-pages, the search), then the page held to the rects the web
/// page measured.
///
/// The page's own cases are run over stand-ins made from the web's five manifests (support.dart `webBuiltIn`), whose
/// pages are a line of text each, so a case can say which page it opened. The measurements and the pictures are of
/// the five that ship (lib/plugins/built_in.dart `builtIn`, [shippedRegistry]) on a fresh install, as the page was
/// measured: their cards are their own manifests' words.
///
/// The measurements are `test/plugins/fixtures/plugins-pane-390.json`: the web app on its dev server in Chromium at
/// 390 x 844, two device pixels to one, light, 2026-10-08, in three states (as it comes up; Claude's reasons open;
/// Local only on). Across the page (x and width) every rect is held to half a pixel. Down it, the kit sets a line of
/// small text 20 px high where the page has 20.09, and a hero's title 31 where the page has 30.88, so on a page
/// 2100 px long the difference gathers to three pixels by the foot: each thing is held to half a pixel plus that
/// gathering ([_slack]), and to three quarters of a pixel from the top of its own card.

Registry webRegistry([Map<String, bool>? switches]) => createRegistry(webBuiltIn(), store: MemorySwitches(switches), localOnly: () => preferences.value.localOnly);

/// The five that ship, with nothing switched by hand: what the web page was measured over. Webhooks, the port's own
/// sixth (lib/integrations/webhooks/plugin.dart), is not on the page, so not among them: its card is held below.
Registry shippedRegistry() => createRegistry([for (final plugin in builtIn) if (plugin.manifest.id != 'webhooks') plugin], store: MemorySwitches(), localOnly: () => preferences.value.localOnly);

/// Makes [registry] the app's for this test.
Registry install(WidgetTester tester, Registry registry) {
  final before = plugins;
  addTearDown(() => usePlugins(before));
  usePlugins(registry);
  return registry;
}

Finder heroCalled(String name) => find.byWidgetPredicate((w) => w is PaneHero && w.title == name, skipOffstage: false);
Finder cardOf(String name) => find.ancestor(of: heroCalled(name), matching: find.byType(PaneSection, skipOffstage: false)).first;
Finder inCard(String name, Finder what) => find.descendant(of: cardOf(name), matching: what, skipOffstage: false);

/// Every word a card draws, a word that goes somewhere included.
String wordsOf(WidgetTester tester, Finder card) => [
      for (final text in tester.widgetList<Text>(find.descendant(of: card, matching: find.byType(Text, skipOffstage: false), skipOffstage: false)))
        if (text.data != null) text.data! else if (!text.textSpan!.toPlainText().contains('￼')) text.textSpan!.toPlainText(),
    ].join(' | ');

List<String> heroTitles(WidgetTester tester) => [for (final hero in tester.widgetList<PaneHero>(find.byType(PaneHero, skipOffstage: false))) hero.title];
GlacierSwitch switchOf(WidgetTester tester, String name) => tester.widget(inCard(name, find.byType(GlacierSwitch, skipOffstage: false)));
Finder actionIn(String name, String word) => inCard(name, find.widgetWithText(RowAction, word, skipOffstage: false));

/// The page by itself, outside Settings, with somewhere for its rows to go.
Future<List<(String, String?)>> pumpPane(WidgetTester tester, Registry registry, {bool localOnly = false, bool goes = true}) async {
  final opened = <(String, String?)>[];
  await pumpSettings(
    tester,
    SingleChildScrollView(child: PluginsPane(registry: registry, onOpen: goes ? (id, {setting}) => opened.add((id, setting)) : null)),
    prefs: Preferences(theme: 'light', localOnly: localOnly),
  );
  return opened;
}

Map<String, dynamic> _fixture() => (jsonDecode(File('test/plugins/fixtures/plugins-pane-390.json').readAsStringSync()) as Map).cast<String, dynamic>();

/// How far a thing at [y] on the page may be from where the page has it: half a pixel, and the kit's whole-pixel
/// lines gathered down to it (three pixels in 2100).
double _slack(num y) => 0.5 + y / 600;

void main() {
  setUpAll(loadAppFonts);

  group('Settings › Plugins', () {
    testWidgets('has a card for every plugin that ships, Claude among them, each with its switch', (tester) async {
      await pumpPane(tester, webRegistry());
      expect(heroTitles(tester), ['Plugins', 'Notion', 'GitHub', 'Marks', 'Claude', 'Slack']);
      expect(switchOf(tester, 'Claude').ariaLabel, 'Claude plugin');
      expect(find.bySemanticsLabel('Claude plugin'), findsOneWidget);
      // Slack is off until switched on: it posts off the phone.
      expect(find.textContaining('4 of 5 on.'), findsOneWidget);
      expect(switchOf(tester, 'Slack').checked, isFalse);
      expect(find.bySemanticsLabel('Library folder plugin'), findsNothing);
      expect(switchOf(tester, 'Claude').checked, isTrue);
      await endSettings(tester);
    });

    testWidgets('says what a plugin may reach in one line, and the reasons a press away', (tester) async {
      expect(reachLine(webNotion), 'Your notes · The internet (api.notion.com, ghostmarkdown.com) · Built-in app commands');
      expect(reachLine(webClaude), 'Your notes · The internet (ghostmarkdown.com)');
      await pumpPane(tester, webRegistry());
      final card = cardOf('Claude');
      expect(wordsOf(tester, card), contains(reachLine(webClaude)));
      expect(wordsOf(tester, card), isNot(contains(webClaude.permissions[0].why)));
      await tapOn(tester, actionIn('Claude', 'Why'));
      expect(wordsOf(tester, card), contains(webClaude.permissions[0].why));
      expect(actionIn('Claude', 'Less'), findsOneWidget);
      // A row a permission, in Settings' words, under the line; and only on the card that was pressed.
      expect([for (final row in tester.widgetList<SettingRow>(inCard('Claude', find.byType(SettingRow, skipOffstage: false)))) row.label], ['Read and write your notes from Claude', 'What it may reach', 'Your notes', 'The internet']);
      expect(actionIn('Notion', 'Why'), findsOneWidget);
      await tapOn(tester, actionIn('Claude', 'Less'));
      expect(wordsOf(tester, card), isNot(contains(webClaude.permissions[0].why)));
      await endSettings(tester);
    });

    testWidgets('opens a plugin’s own page from its card', (tester) async {
      final opened = await pumpPane(tester, webRegistry());
      await tapOn(tester, inCard('Claude', rowCalled('Read and write your notes from Claude')));
      expect(opened, [('plugin:claude', null)]);
      await endSettings(tester);
    });

    // Changed on purpose on the page (docs/DESIGN.md §138): "Local only" is a word that goes to its switch.
    testWidgets('holds every plugin that uses the internet off under Local only, and its words open the switch', (tester) async {
      final opened = await pumpPane(tester, webRegistry(), localOnly: true);
      final callout = find.byType(SettingsCallout);
      final said = tester.widget<Text>(find.descendant(of: callout, matching: find.byWidgetPredicate((w) => w is Text && w.textSpan != null)));
      expect(said.textSpan!.toPlainText().replaceAll('\uFFFC', 'Local only'), 'Local only is on, so plugins that use the internet are held off until it is off.');
      await tapOn(tester, find.descendant(of: callout, matching: find.byType(GoWord)));
      final notion = switchOf(tester, 'Notion');
      expect((notion.disabled, notion.checked), (true, false));
      expect(inCard('Notion', rowCalled('Off while Local only is on')), findsOneWidget);
      final hint = tester.widget<Text>(inCard('Notion', find.byWidgetPredicate((w) => w is Text && (w.textSpan?.toPlainText().startsWith('It uses the internet. Switch ') ?? false), skipOffstage: false)));
      expect(hint.textSpan!.toPlainText().replaceAll('￼', 'Local only'), 'It uses the internet. Switch Local only off to use it.');
      await tapOn(tester, inCard('Notion', find.byType(GoWord, skipOffstage: false)));
      // Both land on Account, at the Privacy card, lit.
      expect(opened, [('account', 'Privacy'), ('account', 'Privacy')]);
      // Marks reaches nothing past the phone, so it is not held.
      expect(inCard('Marks', rowCalled('Off while Local only is on')), findsNothing);
      expect(switchOf(tester, 'Marks').disabled, isFalse);
      expect(find.textContaining('1 of 5 on.'), findsOneWidget);
      // A plugin that is held has no page to go to, whatever its switch says.
      expect(inCard('Claude', rowCalled('Read and write your notes from Claude')), findsNothing);
      await endSettings(tester);
    });

    test('says the internet plainly for a plugin that names no hosts', () {
      expect(reachLine(manifestOf('notion', permissions: [Permission.notes, Permission.network, Permission.native])), 'Your notes · The internet · Built-in app commands');
    });
  });

  group('a plugin’s card', () {
    testWidgets('switches its plugin, which is kept, and has its page only while it is on', (tester) async {
      final store = MemorySwitches();
      final registry = createRegistry(webBuiltIn(), store: store, localOnly: () => false);
      await pumpPane(tester, registry);
      expect(inCard('Slack', rowCalled('Channels to post to')), findsNothing);
      await tapOn(tester, inCard('Slack', find.byType(GlacierSwitch, skipOffstage: false)));
      expect(store.held, {'slack': true});
      expect(find.textContaining('5 of 5 on.', skipOffstage: false), findsOneWidget);
      expect(inCard('Slack', rowCalled('Channels to post to')), findsOneWidget);
      await tapOn(tester, inCard('Claude', find.byType(GlacierSwitch, skipOffstage: false)));
      expect(store.held, {'slack': true, 'claude': false});
      expect(registry.isEnabled('claude'), isFalse);
      expect(inCard('Claude', rowCalled('Read and write your notes from Claude')), findsNothing);
      expect(switchOf(tester, 'Claude').checked, isFalse);
      await endSettings(tester);
    });

    testWidgets('says where it comes from under it: Ghost.md’s own, or its author, and its version', (tester) async {
      final third = GlyphPlugin(manifest: const PluginManifest(id: 'third', name: 'Third', description: 'From somebody else.', version: '2.3.0', author: 'Somebody', standard: false, permissions: [], storage: []), icon: 'no-such-icon');
      await pumpPane(tester, createRegistry([...webBuiltIn(), third], store: MemorySwitches(), localOnly: () => false));
      expect(inCard('Notion', find.text('Ships with Ghost.md · version 1.0.0', skipOffstage: false)), findsOneWidget);
      // Slack is Ghost.md's too, and is not standard: the page says its author, as the web's does.
      expect(inCard('Slack', find.text('Ghost.md · version 1.0.0', skipOffstage: false)), findsOneWidget);
      expect(inCard('Third', find.text('Somebody · version 2.3.0', skipOffstage: false)), findsOneWidget);
      // An icon the kit does not draw is the puzzle piece.
      expect(tester.widget<AppIcon>(inCard('Third', find.byType(AppIcon, skipOffstage: false))).icon, Lucide.puzzle);
      expect(tester.widget<AppIcon>(inCard('Notion', find.byType(AppIcon, skipOffstage: false)).first).icon, Lucide.squareKanban);
      // A plugin with no page and nothing it may reach has the one row, with no line under it.
      expect(tester.widget<SettingRow>(inCard('Marks', find.byType(SettingRow, skipOffstage: false))).hint, isNull);
      await endSettings(tester);
    });

    testWidgets('has no row to its page, and its words go nowhere, where the page is drawn outside Settings', (tester) async {
      await pumpPane(tester, webRegistry(), goes: false);
      expect(inCard('Claude', rowCalled('Read and write your notes from Claude')), findsNothing);
      expect(tester.widget<SettingRow>(inCard('Claude', rowCalled('What it may reach'))).onPress, isNull);
      await endSettings(tester);
    });
  });

  group('Plugins in Settings', () {
    testWidgets('says how many are on in the list, and is found by every plugin’s name and what it does', (tester) async {
      install(tester, webRegistry());
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}), size: const Size(390, 1200));
      expect(tester.widget<Text>(find.descendant(of: find.ancestor(of: find.text('Plugins'), matching: find.byType(GlacierPressable)).first, matching: find.byKey(const ValueKey('settings-row-summary')))).data, '4 of 5 on');
      final sections = tester.state<SettingsScreenState>(find.byType(SettingsScreen)).widget.sections;
      final own = sections.firstWhere((s) => s.id == 'plugins');
      expect([for (final setting in own.settings) (setting.name, setting.words)], [for (final plugin in webBuiltIn()) (plugin.manifest.name, plugin.manifest.description)]);
      // Each switched-on plugin's own page follows, off the list, behind Plugins, in its own colour, with its own words.
      // (Calendar, the port's own, is behind Plugins too, and is no plugin's.)
      expect([for (final s in sections) if (s.parent == 'plugins' && s.id != 'calendar') (s.id, s.label, s.listed, s.hue, s.summary)], [
        ('plugin:notion', 'Notion', false, 'graphite', 'Boards for your lists'),
        ('plugin:github', 'GitHub', false, 'graphite', 'Repos, issues and context'),
        ('plugin:claude', 'Claude', false, 'coral', 'Read and write your notes from Claude'),
      ]);
      final claude = sections.firstWhere((s) => s.id == 'plugin:claude');
      expect(claude.words, webClaude.description);
      expect([for (final setting in claude.settings) setting.name], ['Connect', 'What Claude can do', 'Your key']);
      expect(sections.indexOf(claude), sections.indexWhere((s) => s.id == 'plugins') + 3);
      await endSettings(tester);
    });

    testWidgets('opens a plugin’s own page behind its card, and back from it comes to Plugins', (tester) async {
      install(tester, webRegistry());
      await openPane(tester, 'plugins');
      expect(display(tester), 'Plugins');
      expect(find.text('Not ported yet'), findsNothing);
      await tapOn(tester, inCard('Claude', rowCalled('Read and write your notes from Claude')));
      expect(display(tester), 'Claude');
      expect(find.byKey(const ValueKey('page-of-Claude')), findsOneWidget);
      // The head says where back goes.
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('settings-head-word')), matching: find.byType(Text))).textSpan!.toPlainText(), contains('Plugins'));
      testBack.goBack();
      await tester.pump();
      await settleSettings(tester);
      expect(display(tester), 'Plugins');
      await endSettings(tester);
    });

    testWidgets('gives a plugin switched on here its page at once, and takes “Local only” to Account’s Privacy card', (tester) async {
      install(tester, webRegistry());
      await openPane(tester, 'plugins', prefs: const Preferences(theme: 'light'));
      await tapOn(tester, inCard('Slack', find.byType(GlacierSwitch, skipOffstage: false)));
      await tapOn(tester, inCard('Slack', rowCalled('Channels to post to')));
      expect(display(tester), 'Slack');
      expect(find.byKey(const ValueKey('page-of-Slack')), findsOneWidget);
      await endSettings(tester);

      install(tester, webRegistry());
      await openPane(tester, 'plugins', prefs: const Preferences(theme: 'light', localOnly: true));
      await tapOn(tester, find.descendant(of: find.byType(SettingsCallout), matching: find.byType(GoWord)));
      expect(display(tester), 'Account');
      await endSettings(tester);
    });

    testWidgets('reads “0 of 0 on” before any plugin is put in place, which is the app until built_in.dart installs them', (tester) async {
      install(tester, createRegistry(const [], store: MemorySwitches()));
      await openPane(tester, 'plugins');
      expect(heroTitles(tester), ['Plugins']);
      expect(find.textContaining('0 of 0 on.'), findsOneWidget);
      expect(pluginPageSections(), isEmpty);
      // Only Calendar, which is the app's own and no plugin's.
      expect([for (final spec in settingsSections) if (spec.parent == 'plugins') spec.id], ['calendar']);
      await endSettings(tester);
    });

    test('lists the pages of the plugins that are on, each a sub-page of Plugins, straight after it', () {
      final before = plugins;
      addTearDown(() => usePlugins(before));
      final registry = webRegistry();
      usePlugins(registry);
      expect([for (final spec in pluginPageSections()) spec.id], ['plugin:notion', 'plugin:github', 'plugin:claude']);
      final ids = [for (final spec in settingsSections) spec.id];
      expect(ids.sublist(ids.indexOf('plugins'), ids.indexOf('about') + 1), ['plugins', 'plugin:notion', 'plugin:github', 'plugin:claude', 'calendar', 'about']);
      registry.setEnabled('slack', true);
      registry.setEnabled('notion', false);
      expect([for (final spec in pluginPageSections()) (spec.id, spec.parent, spec.listed, spec.group)], [('plugin:github', 'plugins', false, 2), ('plugin:claude', 'plugins', false, 2), ('plugin:slack', 'plugins', false, 2)]);
      expect(pluginsSummary(registry), '4 of 5 on');
      expect(pluginPageId('notion'), 'plugin:notion');
    });
  });

  group('the page, against the web’s', () {
    late Map<String, dynamic> web;
    setUpAll(() => web = _fixture());

    /// Holds what is drawn to one state of the fixture: every card, hero, switch, row, label, word and footer.
    void hold(WidgetTester tester, String state, {required List<String> cards}) {
      final at = (web['states'] as Map)[state] as Map;
      List<Map> of(String name) => [for (final thing in at[name] as List) thing as Map];
      // The page had scrolled where a press brought a row into view: every y is taken from its first card's.
      final scrolled = (of('cards').first['y'] as num) - 122.73;
      double y(Map thing) => (thing['y'] as num) - scrolled;

      final sections = find.byType(PaneSection, skipOffstage: false);
      // And here, where the same press scrolled this page: every rect is read from the first card's top too.
      final moved = tester.getRect(surfaceOf(sections.at(0))).top - 122.73;
      Rect rectOf(Finder finder) => tester.getRect(finder).shift(Offset(0, -moved));
      final tops = <double>[];
      final webTops = <double>[];
      void near(String what, Rect got, Map want, {double? cardTop, double? webCardTop, bool size = true, bool wide = true}) {
        final wy = y(want);
        expect(got.left, closeTo(want['x'] as num, 0.5), reason: '$state: $what, x');
        expect(got.top, closeTo(wy, _slack(wy)), reason: '$state: $what, y');
        if (cardTop != null) expect(got.top - cardTop, closeTo(wy - webCardTop!, 0.75), reason: '$state: $what, from its card’s top');
        if (wide) expect(got.width, closeTo(want['w'] as num, 0.5), reason: '$state: $what, width');
        // A height of text is the page's lines of 20.09 against the kit's of 20.
        if (size) expect(got.height, closeTo(want['h'] as num, 0.5 + (want['h'] as num) / 200), reason: '$state: $what, height');
      }

      expect(sections.evaluate().length, cards.length);
      expect(of('cards').length, cards.length);
      for (var i = 0; i < cards.length; i++) {
        final surface = rectOf(surfaceOf(sections.at(i)));
        near('the ${cards[i]} card', surface, of('cards')[i]);
        tops.add(surface.top);
        webTops.add(y(of('cards')[i]));
      }

      // Which card a thing at this y is in, on the page and here.
      int cardAt(double top, List<double> all) => all.lastIndexWhere((t) => t <= top + 0.01);

      final heroes = find.byType(PaneHero, skipOffstage: false);
      for (var i = 0; i < cards.length; i++) {
        final hero = heroes.at(i);
        final texts = find.descendant(of: hero, matching: find.byType(Text, skipOffstage: false), skipOffstage: false);
        expect(tester.widget<Text>(texts.at(0)).data, of('heroTitles')[i]['text']);
        near('${cards[i]}’s title', rectOf(texts.at(0)), of('heroTitles')[i], cardTop: tops[i], webCardTop: webTops[i], wide: false);
        near('${cards[i]}’s line', rectOf(texts.at(1)), of('heroMetas')[i], cardTop: tops[i], webCardTop: webTops[i]);
        final icon = find.descendant(of: hero, matching: find.byType(AppIcon, skipOffstage: false), skipOffstage: false);
        near('${cards[i]}’s icon', rectOf(icon), of('heroIcons')[i], cardTop: tops[i], webCardTop: webTops[i]);
        near('${cards[i]}’s tile', rectOf(find.ancestor(of: icon, matching: find.byType(Container, skipOffstage: false)).first), of('heroGlyphs')[i], cardTop: tops[i], webCardTop: webTops[i]);
        if (i > 0) {
          final track = find.descendant(of: hero, matching: find.byType(GlacierSwitch, skipOffstage: false), skipOffstage: false);
          expect(tester.widget<GlacierSwitch>(track).ariaLabel, of('switches')[i - 1]['text']);
          near('${cards[i]}’s switch', rectOf(track), of('tracks')[i - 1], cardTop: tops[i], webCardTop: webTops[i]);
        }
      }

      final rows = find.byType(SettingRow, skipOffstage: false);
      expect(rows.evaluate().length, of('rows').length, reason: '$state: rows');
      var hint = 0;
      for (var i = 0; i < of('rows').length; i++) {
        final row = rows.at(i);
        final widget = tester.widget<SettingRow>(row);
        final want = Map.of(of('rows')[i]);
        expect(widget.label, of('labels')[i]['text'], reason: '$state: row $i');
        final got = rectOf(row);
        final card = cardAt(got.top, tops);
        expect(card, cardAt(y(want), webTops), reason: '$state: ${widget.label} is in the card the page has it in');
        // The page's row carries the hairline over it where it follows a row; here the card draws that line.
        final ruled = i > 0 && cardAt(y(of('rows')[i - 1]), webTops) == card;
        if (ruled) {
          want['y'] = (want['y'] as num) + 1;
          want['h'] = (want['h'] as num) - 1;
        }
        near('the row ${widget.label}', got, want, cardTop: tops[card], webCardTop: webTops[card]);
        final texts = find.descendant(of: row, matching: find.byType(Text, skipOffstage: false), skipOffstage: false);
        near('the label ${widget.label}', rectOf(texts.at(0)), of('labels')[i], cardTop: tops[card], webCardTop: webTops[card], wide: false);
        if (widget.hint != null) {
          near('the line under ${widget.label}', rectOf(texts.at(1)), of('hints')[hint], cardTop: tops[card], webCardTop: webTops[card], wide: false);
          hint++;
        }
      }
      expect(hint, of('hints').length, reason: '$state: every line under a label was held');

      final chips = find.byWidgetPredicate((w) => w is SettingRow && w.icon != null, skipOffstage: false);
      expect(chips.evaluate().length, of('rowIcons').length);
      for (var i = 0; i < of('rowIcons').length; i++) {
        final chip = find.ancestor(of: find.descendant(of: chips.at(i), matching: find.byType(AppIcon, skipOffstage: false), skipOffstage: false), matching: find.byType(Container, skipOffstage: false)).first;
        near('the chip of a page’s row', rectOf(chip), of('rowIcons')[i]);
      }

      final actions = find.byType(RowAction, skipOffstage: false);
      expect(actions.evaluate().length, of('actions').length);
      for (var i = 0; i < of('actions').length; i++) {
        expect(find.descendant(of: actions.at(i), matching: find.text(of('actions')[i]['text'] as String, skipOffstage: false), skipOffstage: false), findsOneWidget);
        near('the word ${of('actions')[i]['text']}', rectOf(actions.at(i)), of('actions')[i]);
      }

      // The words under a card and at the page's foot stand in from its edge, as a card's title does: their tops.
      final footers = [for (final section in tester.widgetList<PaneSection>(sections)) if (section.footer case final Text footer) footer.data!];
      expect(footers, [for (final footer in of('footers')) footer['text']]);
      for (var i = 0; i < footers.length; i++) {
        final got = rectOf(find.descendant(of: sections.at(i + 1), matching: find.text(footers[i], skipOffstage: false), skipOffstage: false));
        final wy = y(of('footers')[i]);
        expect(got.top, closeTo(wy, _slack(wy)), reason: '$state: the words under ${cards[i + 1]}');
        expect(got.top - tops[i + 1], closeTo(wy - webTops[i + 1], 1.2), reason: '$state: the words under ${cards[i + 1]}, from its card’s top');
        expect(got.left, closeTo((of('footers')[i]['x'] as num) + 8.93, 0.5));
      }
      final foot = rectOf(find.textContaining('Plugins ship inside Ghost.md', skipOffstage: false));
      expect(foot.top, closeTo(y(of('footnote').single), _slack(y(of('footnote').single))), reason: '$state: the footnote');

      final callouts = of('callout');
      expect(find.byType(SettingsCallout, skipOffstage: false).evaluate().length, callouts.length);
      if (callouts.isNotEmpty) {
        near('the callout', rectOf(find.descendant(of: find.byType(SettingsCallout), matching: find.byType(Container)).first), callouts.single, size: false);
        final words = find.byType(GoWord, skipOffstage: false);
        expect(words.evaluate().length, of('goWords').length);
        for (var i = 0; i < of('goWords').length; i++) {
          final wy = y(of('goWords')[i]);
          final got = rectOf(find.descendant(of: words.at(i), matching: find.text('Local only', skipOffstage: false), skipOffstage: false));
          expect(got.left, closeTo(of('goWords')[i]['x'] as num, 0.75), reason: '$state: “Local only” $i, x');
          expect(got.width, closeTo(of('goWords')[i]['w'] as num, 0.75), reason: '$state: “Local only” $i, width');
          expect(got.top, closeTo(wy, _slack(wy) + 0.5), reason: '$state: “Local only” $i, y');
        }
      }
    }

    const cards = ['Plugins', 'Notion', 'GitHub', 'Marks', 'Claude', 'Slack'];

    testWidgets('as it comes up: six cards, their switches, their rows and what each may reach, rect for rect', (tester) async {
      install(tester, shippedRegistry());
      await openPane(tester, 'plugins');
      expect(display(tester), 'Plugins');
      expect(web['listRow'], 'Plugins4 of 5 on');
      hold(tester, 'base', cards: cards);
      // The first card is where the page has it to the half pixel, before anything has gathered.
      expect(tester.getRect(surfaceOf(find.byType(PaneSection, skipOffstage: false).first)), rectNear(22.31, 122.73, 345.38, 160.44));
      expect(tester.getRect(find.descendant(of: heroCalled('Notion'), matching: find.byType(GlacierSwitch))).size, const Size(44, 26));
      await endSettings(tester);
    });

    testWidgets('with Claude’s reasons open: a row a permission under what it may reach', (tester) async {
      install(tester, shippedRegistry());
      await openPane(tester, 'plugins');
      await tapOn(tester, actionIn('Claude', 'Why'));
      hold(tester, 'why', cards: cards);
      await endSettings(tester);
    });

    testWidgets('under Local only: the callout, and “Off while Local only is on” on the four that use the internet', (tester) async {
      install(tester, shippedRegistry());
      await openPane(tester, 'plugins', prefs: const Preferences(theme: 'light', localOnly: true));
      hold(tester, 'localOnly', cards: cards);
      expect([for (final name in cards.skip(1)) switchOf(tester, name).disabled], [true, true, false, true, true]);
      await endSettings(tester);
    });
  });

  // Pictures of the page, drawn with the real faces, to lay beside the web app's own (fixtures/web/, taken over its
  // dev server in Chromium at the same sizes, 2026-10-08): `flutter test --update-goldens`, then open shots/.
  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('Plugins on a phone, $theme', (tester) async {
        install(tester, shippedRegistry());
        await openPane(tester, 'plugins', prefs: Preferences(theme: theme));
        await shot(tester, 'plugins-$theme');
      });

      testWidgets('the whole page on a window tall enough to hold it, $theme', (tester) async {
        install(tester, shippedRegistry());
        await openPane(tester, 'plugins', prefs: Preferences(theme: theme), size: const Size(390, 2700));
        await shot(tester, 'plugins-tall-$theme');
      });
    }

    testWidgets('Plugins under Local only, light', (tester) async {
      install(tester, shippedRegistry());
      await openPane(tester, 'plugins', prefs: const Preferences(theme: 'light', localOnly: true));
      await shot(tester, 'plugins-local-only-light');
    });
  });
}
