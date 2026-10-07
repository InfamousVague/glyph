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
/// `test/settings/shots/`.
void main() {
  setUpAll(loadAppFonts);

  /// Settings over an empty page, with no notch: the web's pictures were taken in a browser, which has none.
  Future<void> open(WidgetTester tester, String theme, {Size size = const Size(390, 844), SettingsTarget? toPage}) async {
    await pumpApp(
      tester,
      size: size,
      prefs: Preferences(theme: theme),
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
      await open(tester, theme, size: const Size(390, 4935), toPage: const SettingsTarget('theme', nonce: 1));
      await shot(tester, 'settings-appearance-full-$theme');
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
