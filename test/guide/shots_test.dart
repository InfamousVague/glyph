import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/guide.dart';

import 'support.dart';

/// Pictures of the walkthrough's pages, dark and light, at 390 x 844 (test/guide/shots/), looked at beside
/// Chromium's of the web app's own Guide (test/guide/fixtures/web/, the same names).
void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    // The page's pictures were taken with the theme as the chosen one, so that row is the one printed in reverse.
    // The mode page (GHST-103) has no web picture beside it: it is new with the Flutter app.
    for (final (index, name) in ['welcome', 'theme', 'mode', 'model', 'start'].indexed) {
      testWidgets('$name, $theme', (tester) async {
        final prefs = Preferences(theme: theme);
        final store = ValueNotifier<Preferences>(prefs);
        addTearDown(store.dispose);
        await pumpGuide(tester, Guide(index: index, onIndex: (_) {}, onClose: () {}, onAcademy: () {}, preferences: store), prefs: prefs);
        await wait(tester, 2000);
        await shot(tester, '$name-$theme');
      });
    }

    testWidgets('too soon, $theme', (tester) async {
      final prefs = Preferences(theme: theme);
      await pumpGuide(tester, Guide(index: 0, onIndex: (_) {}, onClose: () {}, onAcademy: () {}, tooSoon: true), prefs: prefs);
      await wait(tester, 2000);
      await shot(tester, 'too-soon-$theme');
    });

    testWidgets('the model page’s line about the download, $theme', (tester) async {
      final prefs = Preferences(theme: theme);
      final store = ValueNotifier<Preferences>(prefs);
      addTearDown(store.dispose);
      await pumpGuide(tester, Guide(index: 3, onIndex: (_) {}, onClose: () {}, onAcademy: () {}, preferences: store, models: FakeGuideModels()), prefs: prefs);
      final scroller = tester.state<ScrollableState>(find.byType(Scrollable).first);
      scroller.position.jumpTo(scroller.position.maxScrollExtent);
      await wait(tester, 2000);
      await shot(tester, 'model-fine-$theme');
    });
  }
}
