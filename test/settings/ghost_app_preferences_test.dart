import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/main.dart' show appStyleSheets;
import 'package:ghost_md/settings/settings_css.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// The app dressed by the person's preferences (lib/app/ghost_app.dart), which is `applyPreferences` on the page:
/// their attributes on the theme, the interface size over the window, the pace in the kit's durations, the haptics
/// switch on the motor; and what was kept read before anything is drawn.
void main() {
  setUpAll(loadAppFonts);

  Tokens tokens(WidgetTester tester) => GlacierTheme.of(tester.element(find.byKey(const ValueKey('home'))));
  const home = SizedBox.expand(key: ValueKey('home'));

  testWidgets('reads what was kept before it draws, with no one loading it first', (tester) async {
    SharedPreferences.setMockInitialValues({
      'glyph-preferences': jsonEncode({'theme': 'ember', 'accent': 'amber', 'density': 'compact', 'motionSpeed': 'relaxed'}),
      'glyph-haptics': 'off',
    });
    // The next test starts on a device that has kept nothing.
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    preferences.forget();
    expect(preferences.loaded, isFalse);
    final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
    await tester.pumpWidget(GhostApp(sheet: sheet!, home: home));
    await tester.pump();
    expect(preferences.loaded, isTrue);
    final t = tokens(tester);
    expect(t.attrs, allOf(containsPair('theme', 'dark'), containsPair('theme-preset', 'ember'), containsPair('accent', 'amber'), containsPair('density', 'compact'), containsPair('note-font', 'maple')));
    expect(t.duration('glacier-duration-normal'), const Duration(milliseconds: 400));
    expect(hapticsEnabled(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps the page’s own attributes beside the preferences’, and the names the stand-in had', (tester) async {
    // The stand-in's name is the preferences themselves now.
    const AppPreferences old = AppPreferences(theme: 'light');
    expect(old, isA<Preferences>());
    await pumpApp(tester, prefs: old, home: home);
    final t = tokens(tester);
    expect(t.attrs, {'platform': 'mobile', 'tabs': 'on', 'theme': 'light', 'note-font': 'maple', 'code-light': 'pastel', 'code-dark': 'pastel'});
    expect(t.len('app-motion-scale'), 1);
    preferences.value = preferences.value.copyWith(theme: 'system');
    await tester.pump();
    // System: nothing stamped, and the theme follows the device.
    expect(preferences.value.attrs.containsKey('theme'), isFalse);
    expect(tokens(tester).attrs['theme'], 'light');
    await endSettings(tester);
  });

  testWidgets('leaves the pace to a device that asks for less motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, prefs: const Preferences(theme: 'light', motionSpeed: 'relaxed'), home: home);
    final t = tokens(tester);
    expect(t.attrs.containsKey('pace'), isFalse);
    // The kit's own reduced-motion rule sets the durations then, and the app's scale is 1.
    expect(t.duration('glacier-duration-normal'), lessThan(const Duration(milliseconds: 250)));
    expect(t.len('app-motion-scale'), 1);
    await endSettings(tester);
  });

  testWidgets('draws everything larger or smaller at another interface size, and a touch still lands where it is drawn', (tester) async {
    var closed = 0;
    await pumpSettings(tester, SettingsSheet(open: true, onClose: () => closed++), prefs: const Preferences(theme: 'light', uiScale: 1.25));
    final context = tester.element(find.byType(SettingsSheet));
    expect(MediaQuery.sizeOf(context), const Size(390 / 1.25, 844 / 1.25));
    // A rem is 20 pixels of the screen: the row's chip, 1.85rem, is 37 across.
    expect(tester.getRect(find.byKey(const ValueKey('settings-row-icon')).first).width, closeTo(1.85 * 16 * 1.25, 0.01));
    expect(tester.getRect(find.byType(SettingsSheet)), const Rect.fromLTWH(0, 0, 390, 844));
    // The row is pressed where it is seen.
    await tester.tapAt(tester.getCenter(find.text('Appearance')));
    await tester.pump();
    await settleSettings(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('settings-display'))).data, 'Appearance');
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('settings-head-word'))));
    await tester.pump();
    await settleSettings(tester);
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('settings-head-word'))));
    expect(closed, 1);
    // And smaller: 85%.
    preferences.update((now) => now.copyWith(uiScale: 0.85));
    await tester.pump();
    await settleSettings(tester);
    expect(tester.getRect(find.byKey(const ValueKey('settings-row-icon')).first).width, closeTo(1.85 * 16 * 0.85, 0.01));
    await endSettings(tester);
  });

  testWidgets('lays settings.css over the sheet once, however often the app is built on it', (tester) async {
    final sheet = (await tester.runAsync(() => loadTokenSheet(more: appStyleSheets)))!;
    final bare = sheet.rules.length;
    installSettingsStyles(sheet);
    final dressed = sheet.rules.length;
    expect(dressed, greaterThan(bare));
    installSettingsStyles(sheet);
    expect(sheet.rules.length, dressed);
    // The cascade is still in order: specificity, then the order the rules were written in.
    for (var i = 1; i < sheet.rules.length; i++) {
      final a = sheet.rules[i - 1], b = sheet.rules[i];
      expect(a.specificity < b.specificity || (a.specificity == b.specificity && a.order < b.order), isTrue);
    }
    // And each property resolves by its own name, as on the page.
    final root = Tokens.root(sheet, attrs: const {'theme': 'light'});
    final screen = root.child(classes: const {'settingsScreen'});
    expect(screen.len('settings-find-pill'), 38.4);
    expect(screen.color('sheet-ground'), root.color('glacier-bg'));
    expect(screen.child(attrs: const {'layout': 'split'}).len('settings-side'), 320);
    expect(root.child(attrs: const {'hue': 'mint'}).colorOf('var(--hue)'), root.colorOf('#1f9e8f'));
    final dark = Tokens.root(sheet, attrs: const {'theme': 'dark'});
    expect(dark.child(attrs: const {'hue': 'mint'}).colorOf('var(--hue)'), dark.colorOf('#5fe0cf'));
    expect(root.child(classes: const {'setk__card'}).color('glacier-segment-track'), root.color('app-paper-3'));
  });
}
