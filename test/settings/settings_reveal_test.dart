// A setting looked for by name opens where it is, even out of sight (Matt, 2026-10-29: "Add the ability to search
// settings and plugins from the command search"; lib/commands/settings_places.dart): Settings at its page, the row
// brought into view and lit, a More that keeps it in Simple opened in place for it (settings_kit.dart
// `settingsSought`), and a plugin's Set up opening its setup. Then the drift: every name the index lists for a page
// Simple keeps, and for every plugin's own page, is drawn there and lit when it is looked for, so a list beside a page
// cannot drift from what the page draws without a test failing.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart' show PluginSetupSheet;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart' show GlyphPlugin;
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/plugins_pane.dart' show pluginPageId;
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_search.dart' show fold;
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/sounds/sound_pack.dart' show SoundEvent;

import 'panes/support.dart';

const Preferences _simple = Preferences(theme: 'light', experience: 'simple', experienceChosen: true);
const Preferences _advanced = Preferences(theme: 'light', experience: 'advanced', experienceChosen: true);

/// Settings, sent to a page and a setting on it each time [go] is called.
class _Settings {
  final ValueNotifier<SettingsTarget?> target = ValueNotifier(null);
  int _nonce = 0;

  Future<void> pump(WidgetTester tester, {Preferences prefs = _simple, Size size = const Size(390, 844)}) => pumpSettings(
        tester,
        ValueListenableBuilder<SettingsTarget?>(valueListenable: target, builder: (context, toPage, _) => SettingsSheet(open: true, onClose: () {}, toPage: toPage)),
        size: size,
        prefs: prefs,
      );

  /// Settings at [page], at [setting], and a few frames for the page to be drawn and the setting found.
  Future<void> go(WidgetTester tester, String page, String setting) async {
    target.value = SettingsTarget(page, setting: setting, nonce: ++_nonce);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
}

/// The parts of the page that say [name], as the finder folds it.
Finder _marked(String name) => find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name != null && fold(w.name!).trim() == fold(name).trim(), skipOffstage: false);

bool _lit(WidgetTester tester, String name) => tester
    .widgetList(find.descendant(of: _marked(name), matching: find.byKey(SettingsFindableMark.lightKey, skipOffstage: false), skipOffstage: false))
    .any(SettingsFindableMark.isLit);

/// The built-in plugins, each added.
Registry _everyPlugin() => createRegistry(builtIn, store: MemorySwitches({for (final plugin in builtIn) plugin.manifest.id: true}));

void main() {
  setUpAll(loadAppFonts);

  group('a setting looked for by name', () {
    testWidgets('behind Simple’s More on Appearance: More opens in place, and the row is lit', (tester) async {
      final settings = _Settings();
      await settings.pump(tester);
      await settings.go(tester, 'theme', 'Typewriter scroll');
      expect(display(tester), 'Appearance');
      expect(rowLabels(tester, 'Focus'), ['Focus mode', 'Typewriter scroll'], reason: 'More opened in place');
      expect(_lit(tester, 'Typewriter scroll'), isTrue);
      await settleSettings(tester);
      await endSettings(tester);
    });

    testWidgets('behind Simple’s More on Sounds: the rest of the page is there, and the sound lit', (tester) async {
      final settings = _Settings();
      await settings.pump(tester);
      await settings.go(tester, 'sounds', 'Sounds');
      // The card that is behind More in Simple is not looked for by its rows' names here: one of them is.
      final event = SoundEvent.values.first.label;
      await settings.go(tester, 'sounds', event);
      expect(find.byKey(const ValueKey('sounds-more'), skipOffstage: false), findsNothing);
      expect(_lit(tester, event), isTrue);
      await settleSettings(tester);
      await endSettings(tester);
    });

    testWidgets('a page opened plainly in Simple keeps its More shut', (tester) async {
      final settings = _Settings();
      await settings.pump(tester);
      await settings.go(tester, 'theme', 'Text size');
      expect(rowLabels(tester, 'Focus'), ['Focus mode', 'More']);
      expect(_lit(tester, 'Text size'), isTrue);
      await settleSettings(tester);
      await endSettings(tester);
    });

    testWidgets('a plugin’s Set up opens its setup over its page', (tester) async {
      final before = plugins;
      usePlugins(createRegistry(builtIn, store: MemorySwitches({'lovart': true})));
      addTearDown(() => usePlugins(before));
      final settings = _Settings();
      await settings.pump(tester, prefs: _advanced);
      expect(find.byType(PluginSetupSheet), findsNothing);
      await settings.go(tester, pluginPageId('lovart'), 'Set up Lovart');
      expect(display(tester), 'Lovart');
      expect(find.byType(PluginSetupSheet), findsOneWidget);
      expect(_lit(tester, 'Set up Lovart'), isTrue);
      await settleSettings(tester);
      await endSettings(tester);
    });
  });

  group('the drift', () {
    testWidgets('every setting the index lists on a page Simple keeps is drawn there, and lit, when looked for', (tester) async {
      // Listed and drawn only with what these devices have not: the way in the form already is has no row (as
      // panes_test.dart allows), and the cheat sheet's marks are drawn by its own cards, not the kit's.
      const notDrawn = {
        'account': {'I have an account'},
      };
      final settings = _Settings();
      await settings.pump(tester, size: const Size(390, 3000));
      final facts = SettingsFacts(prefs: _simple, wide: false, haptics: false, android: false, ios: false, developer: false);
      var checked = 0;
      for (final spec in settingsSections) {
        if (!(spec.where?.call(facts) ?? true) || spec.id == 'cheatsheet' || spec.settings == null) continue;
        for (final setting in spec.settings!(facts)) {
          if (notDrawn[spec.id]?.contains(setting.name) ?? false) continue;
          await settings.go(tester, spec.id, setting.name);
          expect(_marked(setting.name), findsWidgets, reason: '${spec.label} lists "${setting.name}" in Simple and does not draw it');
          expect(_lit(tester, setting.name), isTrue, reason: '${spec.label}: "${setting.name}" is drawn and not lit');
          checked++;
        }
      }
      expect(checked, greaterThan(20));
      await settleSettings(tester);
      await endSettings(tester);
    });

    testWidgets('every setting a plugin’s page lists is drawn on it, each plugin added', (tester) async {
      final before = plugins;
      usePlugins(_everyPlugin());
      addTearDown(() => usePlugins(before));
      // Drawn only with what a test has not: Notion's boards once Notion is signed in to.
      const notDrawn = {
        'notion': {'Boards'},
      };
      final settings = _Settings();
      await settings.pump(tester, prefs: _advanced, size: const Size(390, 3000));
      var checked = 0;
      final missing = <String>[];
      for (final GlyphPlugin plugin in plugins.enabled()) {
        final own = plugin.settings;
        if (own == null) continue;
        final page = pluginPageId(plugin.manifest.id);
        for (final setting in own.findable?.call(null) ?? own.settings) {
          if (notDrawn[plugin.manifest.id]?.contains(setting.name) ?? false) continue;
          await settings.go(tester, page, setting.name);
          // A page these facts do not list (a meeting plugin's, without the service) opens nothing to look on.
          if (display(tester) != plugin.manifest.name) continue;
          if (_marked(setting.name).evaluate().isEmpty) missing.add('${plugin.manifest.id}: ${setting.name}');
          checked++;
        }
      }
      expect(missing, isEmpty, reason: 'listed for the search and not drawn on the plugin’s page');
      expect(checked, greaterThan(10));
      await settleSettings(tester);
      await endSettings(tester);
    });
  });
}
