import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/bottom_nudge.dart';
import 'package:ghost_md/guide/guide.dart';
import 'package:ghost_md/guide/narrator.dart';
import 'package:ghost_md/guide/pages.dart';

import 'support.dart';

/// Pictures of the tour's pages (2026-10-27), dark and light, on a phone (390 x 844), on an unfolded Fold
/// (884 x 1104, the band beside the words) and in a Mac's window (1280 x 800): test/guide/shots/, looked at. Drawn
/// still (Reduce motion), so a picture is the page at rest and not a moment of its drift, and with the nudge's words
/// picked, not drawn by lot.
void main() {
  setUpAll(loadAppFonts);

  const sizes = {'phone': Size(390, 844), 'fold': Size(884, 1104), 'mac': Size(1280, 800)};

  Future<void> show(WidgetTester tester, String name, {required String theme, required int index, Size size = const Size(390, 844), bool tooSoon = false, bool fine = false}) async {
    final prefs = Preferences(theme: theme);
    final store = ValueNotifier<Preferences>(prefs);
    addTearDown(store.dispose);
    final narrator = Narrator(useDefaultOutput: false);
    addTearDown(narrator.dispose);
    await pumpGuide(
      tester,
      Guide(index: index, onIndex: (_) {}, onClose: () {}, onAcademy: () {}, tooSoon: tooSoon, preferences: store, models: fine ? FakeGuideModels() : null, narrator: narrator, random: PickedNudge(nudges.first)),
      prefs: prefs,
      size: size,
      still: true,
    );
    if (fine) {
      final scroller = tester.state<ScrollableState>(find.byType(Scrollable).first);
      scroller.position.jumpTo(scroller.position.maxScrollExtent);
    }
    await wait(tester, 2000);
    await loadPictures(tester);
    await shot(tester, name);
  }

  for (final theme in ['light', 'dark']) {
    for (final MapEntry(key: where, value: size) in sizes.entries) {
      for (final page in walkthroughPages) {
        testWidgets('${page.name}, $where, $theme', (tester) => show(tester, '${page.name}-$where-$theme', theme: theme, index: page.index, size: size));
      }
    }
    testWidgets('too soon, $theme', (tester) => show(tester, 'too-soon-$theme', theme: theme, index: 0, tooSoon: true));
    testWidgets('the model page’s line about the download, $theme', (tester) => show(tester, 'model-fine-$theme', theme: theme, index: GuidePage.model.index, fine: true));
  }
}
