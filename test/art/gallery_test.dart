
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/art.dart';

import '../support/render.dart';

/// The art gallery drawn to pictures with the app's real faces, for looking at without a phone:
/// `flutter test --update-goldens test/art/gallery_test.dart`, then open `test/art/shots/art-gallery-*.png`. One of the
/// page whole, at rest (nothing is scrolled, so no edge smokes yet), and one with every box scrolled, where each
/// wisp is worn.
void main() {
  setUpAll(loadAppFonts);

  tearDown(() {
    WispSettings.instance.reset();
    WispDrift.instance.debugReset();
  });

  for (final theme in ['dark', 'light']) {
    testWidgets('the art gallery, $theme', (tester) async {
      await tester.runAsync(() async {
        await WispKit.load(seeds: [3, 5, for (var slot = 0; slot < 6; slot++) wispSlotSeed(slot)]);
        await dockSmokeTile();
      });
      await pumpApp(tester, size: const Size(390, 6400), prefs: AppPreferences(theme: theme), ratio: 1.5, home: const ArtGallery());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Every box that scrolls, scrolled: the page's own is the first and stays where it is.
      final scrollers = tester.stateList<ScrollableState>(find.byType(Scrollable)).toList();
      for (final scroller in scrollers.skip(1)) {
        if (scroller.position.maxScrollExtent > 60) scroller.position.jumpTo(60);
      }
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // The pictures are for looking at, and are only written when asked: the words from smoke arrive at a hand's
      // uneven pace, so no two runs draw the same frame. Every run still builds the page, wakes every smoke and
      // takes it all down again.
      if (autoUpdateGoldenFiles) {
        await shot(tester, 'art-gallery-$theme');
      } else {
        expect(tester.takeException(), isNull);
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }
    });
  }
}
