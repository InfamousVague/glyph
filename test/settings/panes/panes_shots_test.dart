import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import 'support.dart';

/// Pictures of every ported page of Settings, drawn with the real faces, to lay beside the web app's own (taken
/// over its dev server in Chromium at the same sizes, 2026-10-07): on a phone light and dark, and on a wide window.
/// `flutter test --update-goldens test/settings/panes/panes_shots_test.dart`, then open `test/settings/panes/shots/`.
void main() {
  setUpAll(loadAppFonts);

  /// A page with what the web page was measured with: the seeded workspaces, the build About named.
  Future<void> open(WidgetTester tester, String page, String theme, {Size size = phone, bool developer = false, SettingsFeatures features = const SettingsFeatures(), bool spaces = false, bool updates = false}) => openPane(
        tester,
        page,
        size: size,
        prefs: Preferences(theme: theme),
        developer: developer,
        features: features,
        workspaces: spaces ? seededSpaces() : null,
        updates: updates ? measuredUpdates() : null,
      );

  for (final theme in ['light', 'dark']) {
    for (final (name, page) in [
      ('workspaces', 'workspaces'),
      ('notifications', 'notifications'),
      ('about', 'about'),
      ('cheatsheet', 'cheatsheet'),
      ('spec', 'spec'),
      ('examples', 'examples'),
      ('recording', 'recording'),
      ('ai', 'ai'),
      ('account', 'account'),
      ('organizations', 'organizations'),
      ('export', 'export'),
    ]) {
      testWidgets('$name on a phone, $theme', (tester) async {
        await open(tester, page, theme, spaces: name == 'workspaces', updates: name == 'about');
        await loadPictures(tester);
        await shot(tester, 'pane-$name-$theme');
      });
    }

    testWidgets('developer on a phone, $theme', (tester) async {
      await open(tester, 'developer', theme, developer: true);
      await shot(tester, 'pane-developer-$theme');
    });

    testWidgets('test results on a phone, $theme', (tester) async {
      final report = webTestReport();
      // A clock of the picture's own, eight hours after the report was made: "Ran 8 hr ago" whenever this runs.
      final ran = DateTime.parse(report!['generatedAt'] as String);
      await open(tester, 'test-results', theme, developer: true, features: SettingsFeatures(testReport: report, testBuildSource: report['sourceHash'] as String?, testNow: ran.add(const Duration(hours: 8))));
      await shot(tester, 'pane-tests-$theme');
    }, skip: webTestReport() == null);

    testWidgets('test results with no report, $theme', (tester) async {
      await open(tester, 'test-results', theme, developer: true);
      await shot(tester, 'pane-tests-none-$theme');
    });
  }

  for (final (name, page) in [('workspaces', 'workspaces'), ('about', 'about'), ('cheatsheet', 'cheatsheet'), ('spec', 'spec'), ('recording', 'recording')]) {
    testWidgets('$name on a wide window', (tester) async {
      await open(tester, page, 'light', size: wideWindow, spaces: name == 'workspaces', updates: name == 'about');
      await shot(tester, 'pane-$name-wide-light');
    });
  }
}
