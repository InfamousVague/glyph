import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../support/render.dart';

/// Pictures of Settings, drawn with the real faces, to lay beside the web app's own (taken over its dev server at
/// the same sizes, 2026-10-07): the section list, the Appearance page and the search, on a phone and on a wide
/// window, light and dark. `flutter test --update-goldens test/settings/settings_shots_test.dart`, then open
/// `test/settings/shots/`. One more picture is the port's own: Appearance as Simple leaves it (GHST-103). Simple or
/// advanced's page, which headed the list from 2026-10-18 and had a picture of its own, is Appearance's first card
/// since Matt, 2026-10-24: "move the simple or advanced toggle under appearance and move appearnce up in the settings
/// to under account".
void main() {
  setUpAll(loadAppFonts);

  /// Settings over an empty page, with no notch: the web's pictures were taken in a browser, which has none.
  Future<void> open(WidgetTester tester, String theme, {Size size = const Size(390, 844), SettingsTarget? toPage, bool simple = false}) async {
    await pumpApp(
      tester,
      size: size,
      prefs: Preferences(theme: theme, experience: simple ? 'simple' : 'advanced', experienceChosen: simple),
      home: BackScope(child: SettingsSheet(open: true, onClose: () {}, toPage: toPage)),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('the section list on a phone, $theme', (tester) async {
      await open(tester, theme);
      await shot(tester, 'settings-list-$theme');
    });

    testWidgets('Appearance on a phone, $theme', (tester) async {
      await open(tester, theme, toPage: const SettingsTarget('theme', nonce: 1));
      await shot(tester, 'settings-appearance-$theme');
    });

    testWidgets('all of Appearance, $theme', (tester) async {
      await open(tester, theme, size: const Size(390, 5330), toPage: const SettingsTarget('theme', nonce: 1));
      await shot(tester, 'settings-appearance-full-$theme');
    });

    testWidgets('Appearance in Simple on a phone, $theme', (tester) async {
      // Tall enough for the whole of it: the mode, the theme cards and the text size.
      await open(tester, theme, size: const Size(390, 1500), simple: true, toPage: const SettingsTarget('theme', nonce: 1));
      await shot(tester, 'settings-appearance-simple-$theme');
    });

    testWidgets('the search on a phone, $theme', (tester) async {
      await open(tester, theme);
      await tester.enterText(find.byType(EditableText), 'smoke');
      await tester.pump();
      await shot(tester, 'settings-search-$theme');
    });

    testWidgets('the split view on a wide window, $theme', (tester) async {
      await open(tester, theme, size: const Size(1280, 800), toPage: const SettingsTarget('theme', nonce: 1));
      await shot(tester, 'settings-wide-$theme');
    });
  }
}
