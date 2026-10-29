// Settings and the plugins found from the command search, in the app put together (Matt, 2026-10-29: "Add the ability
// to search settings and plugins from the command search"; lib/commands/settings_places.dart): the header toolbar's
// search pill (Command centre and Grouped command) opens the palette, what is typed finds a setting under Settings and
// a plugin under Plugins after the notes and commands, and choosing one opens Settings at its page with the row lit, a
// More of Simple's opened for it, or the Market at a plugin not added. On a phone and on a desktop's window.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/style_sheets.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const phone = Size(390, 844), desktop = Size(1280, 800);

  Future<void> pump(WidgetTester tester, [int times = 6]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The app launched with [version]'s bar kept on the device and [experience] chosen, the plugins the built-in ones
  /// with Keyboard modes added.
  Future<void> launch(WidgetTester tester, {required Size size, required HeaderToolbarVersion version, String experience = 'advanced'}) async {
    SharedPreferences.setMockInitialValues({
      PreferencesStore.storageKey: jsonEncode({'theme': 'light', 'experience': experience, 'experienceChosen': true}),
      'glyph-header-toolbar': version.id,
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    preferences.forget();
    final before = plugins;
    usePlugins(createRegistry(builtIn, store: MemorySwitches({for (final plugin in builtIn) plugin.manifest.id: plugin.manifest.id == 'keyboard-modes'})));
    addTearDown(() => usePlugins(before));
    debugDisableShadows = false;
    const ratio = 2.0;
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    tester.view.padding = const FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
    tester.view.viewPadding = const FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
    addTearDown(tester.view.reset);
    final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
    await tester.pumpWidget(
      GhostApp(
        sheet: sheet!,
        home: GhostRoot(launch: false, library: SampleLibrary.seeded(), stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
      ),
    );
    await pump(tester, 12);
  }

  Future<void> close(WidgetTester tester) async {
    headerToolbarChoice.set(HeaderToolbarVersion.today.id);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  /// The pill pressed, [query] typed into the palette it opens. Simple's bar has no pill: there the palette is
  /// opened as its dock's search opens it.
  Future<void> search(WidgetTester tester, String query, {bool pill = true}) async {
    if (pill) {
      await tester.tap(find.byKey(HeaderAct.keyOf('search')));
    } else {
      expect(find.byKey(HeaderAct.keyOf('search')), findsNothing);
      tester.state<CommandBarState>(find.byType(CommandBar)).show();
    }
    await pump(tester);
    expect(tester.state<CommandBarState>(find.byType(CommandBar)).isOpen, isTrue, reason: 'the pill opens the palette');
    await tester.enterText(find.descendant(of: find.byType(GlacierCommandPalette), matching: find.byType(EditableText)), query);
    await pump(tester);
  }

  /// The headings of the palette's list, top to bottom.
  List<String> headings(WidgetTester tester) => [
        for (final text in tester.widgetList<Text>(find.descendant(of: find.byType(GlacierCommandPalette), matching: find.byType(Text))))
          if (text.data != null && text.data == text.data!.toUpperCase() && text.data!.trim().isNotEmpty && RegExp('[A-Z]').hasMatch(text.data!)) text.data!,
      ];

  /// The palette's row that says [label].
  Finder row(String label) => find.descendant(of: find.byType(GlacierCommandPalette), matching: find.text(label, findRichText: true));

  bool lit(WidgetTester tester, String name) => tester
      .widgetList(find.descendant(
        of: find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name == name, skipOffstage: false),
        matching: find.byKey(SettingsFindableMark.lightKey, skipOffstage: false),
        skipOffstage: false,
      ))
      .any(SettingsFindableMark.isLit);

  String? shownPage(WidgetTester tester) => tester.state<SettingsScreenState>(find.byType(SettingsScreen)).activeId;

  for (final size in [phone, desktop]) {
    final at = size == phone ? 'phone' : 'desktop';
    for (final version in [HeaderToolbarVersion.command, HeaderToolbarVersion.groupedCommand]) {
      testWidgets('${version.label} on a $at: a setting found by the pill’s search opens Settings at it, lit', (tester) async {
        await launch(tester, size: size, version: version);
        await search(tester, 'font size');
        // The commands first, then Settings.
        expect(headings(tester), contains('SETTINGS'));
        expect(find.descendant(of: find.byType(GlacierCommandPalette), matching: find.text('Appearance')), findsWidgets, reason: 'where it is, beside its name');
        await tester.tap(row('Text size').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.state<CommandBarState>(find.byType(CommandBar)).isOpen, isFalse);
        expect(shownPage(tester), 'theme');
        expect(lit(tester, 'Text size'), isTrue);
        await pump(tester, 20);
        await close(tester);
      });
    }

    testWidgets('on a $at: a plugin not added opens in the Market; an added one’s setting on its page; both under Plugins after Settings', (tester) async {
      await launch(tester, size: size, version: HeaderToolbarVersion.command);
      await search(tester, 'keyboard');
      expect(headings(tester).last, 'PLUGINS');
      expect(find.descendant(of: find.byType(GlacierCommandPalette), matching: find.text('Added')), findsOneWidget, reason: 'Keyboard modes is added');
      tester.state<CommandBarState>(find.byType(CommandBar)).close();
      await pump(tester);
      await search(tester, 'jk');
      expect(headings(tester), ['PLUGINS']);
      await tester.tap(row('jk to leave Insert').last);
      await pump(tester, 2);
      expect(shownPage(tester), 'plugin:keyboard-modes');
      await pump(tester, 20);
      // Settings put away, the Market from a plugin not added.
      tester.state<SettingsScreenState>(find.byType(SettingsScreen)).widget.onClose();
      await pump(tester);
      await search(tester, 'notion');
      expect(find.descendant(of: find.byType(GlacierCommandPalette), matching: find.text('Not added')), findsWidgets);
      await tester.tap(row('Notion').last);
      await pump(tester, 10);
      expect(find.byType(MarketScreen), findsOneWidget);
      expect(tester.widget<MarketScreen>(find.byType(MarketScreen)).plugin, 'notion');
      await close(tester);
    });

    testWidgets('in Simple on a $at: a row behind More is found, and More opens in place for it', (tester) async {
      await launch(tester, size: size, version: HeaderToolbarVersion.groupedCommand, experience: 'simple');
      await search(tester, 'typewriter', pill: false);
      expect(row('Typewriter scroll'), findsWidgets);
      await tester.tap(row('Typewriter scroll').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(shownPage(tester), 'theme');
      expect(find.byWidgetPredicate((w) => w is SettingRow && w.label == 'Typewriter scroll', skipOffstage: false), findsOneWidget);
      expect(lit(tester, 'Typewriter scroll'), isTrue);
      await pump(tester, 20);
      tester.state<SettingsScreenState>(find.byType(SettingsScreen)).widget.onClose();
      await pump(tester);
      // No Market in Simple: no plugin offered there.
      await search(tester, 'notion', pill: false);
      expect(headings(tester), isNot(contains('PLUGINS')));
      await close(tester);
    });
  }
}
