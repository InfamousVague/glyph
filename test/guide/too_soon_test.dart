import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/guide/guide_state.dart';
import 'package:ghost_md/guide/pages.dart';
import 'package:ghost_md/guide/too_soon.dart';

/// `guide/tooSoon.test.ts` and `shell/useGuide.test.tsx`, case for case, over a memory of the test's own.
void main() {
  late MemoryStored kept;
  setUp(() => useStored(kept = MemoryStored()));
  tearDown(() => useStored(MemoryStored()));

  group('leaving the guide too soon', () {
    test('is not too soon on the very first launch, nor once the guide is finished', () {
      expect(guidePageLeftAt(), -1);
      expect(launchedTooSoon(false), isFalse);
      markGuideStarted();
      expect(launchedTooSoon(true), isFalse);
    });

    test('is too soon when the guide was started and left on a reading page', () {
      markGuideStarted();
      expect(guidePageLeftAt(), 0);
      expect(launchedTooSoon(false), isTrue);
      rememberGuidePage(GuidePage.model.index);
      expect(launchedTooSoon(false), isTrue);
    });

    test('is not too soon on the last page, where the guide has handed over', () {
      markGuideStarted();
      rememberGuidePage(walkthroughPages.length - 1);
      expect(launchedTooSoon(false), isFalse);
      expect(isReadingPage(0), isTrue);
      expect(isReadingPage(GuidePage.model.index), isTrue);
      expect(isReadingPage(walkthroughPages.length - 1), isFalse);
    });

    test('forgets everything when the guide is finished, and shrugs at bad storage', () {
      markGuideStarted();
      rememberGuidePage(2);
      clearGuideProgress();
      expect(guidePageLeftAt(), -1);
      expect(launchedTooSoon(false), isFalse);
      kept.setItem('glyph-guide-started', '1');
      kept.setItem('glyph-guide-page', 'sideways');
      expect(guidePageLeftAt(), 0);
      expect(launchedTooSoon(false), isTrue);
    });
  });

  group('the guide', () {
    test('opens by itself on a first launch, keeping the page it is on', () {
      final guide = GuideController();
      expect(guide.open, isTrue);
      expect(guide.page, 0);
      expect(kept.getItem('glyph-guide-started'), '1');
      guide.turn(2);
      expect(kept.getItem('glyph-guide-page'), '2');
    });

    test('waits on a launch by the side key: the person holding it is mid-sentence', () {
      final guide = GuideController(launchedByKey: true);
      expect(guide.open, isFalse);
      expect(guide.tooSoonAtBoot, isFalse);
    });

    test('comes back with its line on a relaunch that finds it left on a page still to be read', () {
      kept.setItem('glyph-guide-started', '1');
      kept.setItem('glyph-guide-page', '0');
      final guide = GuideController();
      expect(guide.open, isTrue);
      expect(guide.tooSoon, isTrue);
    });

    test('comes back with its line, and holds the recording, when the side key was held on a page still to be read', () {
      kept.setItem('glyph-guide-started', '1');
      kept.setItem('glyph-guide-page', '0');
      final guide = GuideController(launchedByKey: true);
      expect(guide.open, isTrue);
      expect(guide.tooSoon, isTrue);
      expect(guide.tooSoonAtBoot, isTrue);
    });

    test('does not open by itself once seen, and is seen for good when it is closed', () {
      final guide = GuideController();
      guide.close();
      expect(guide.open, isFalse);
      expect(kept.getItem(guideSeenKey), guideSeenValue);
      expect(kept.getItem('glyph-guide-started'), isNull);
      expect(kept.getItem('glyph-guide-page'), isNull);
      expect(GuideController().open, isFalse);
    });

    test('opens once more for someone who saw only the first tour, signed in or not, and is seen again when closed', () {
      kept.setItem(guideSeenKey, '1');
      final guide = GuideController();
      expect(guide.open, isTrue);
      guide.close();
      expect(kept.getItem(guideSeenKey), guideSeenValue);
      expect(GuideController().open, isFalse);
    });

    test('knows a reading page from the page that asks for the side key, and says "not yet" when told', () {
      final guide = GuideController();
      var told = 0;
      guide.addListener(() => told += 1);
      expect(guide.onReadingPage(), isTrue);
      guide.sayTooSoon();
      expect(guide.tooSoon, isTrue);
      // Turning the page is the line read.
      guide.turn(1);
      expect(guide.tooSoon, isFalse);
      guide.hide();
      expect(guide.onReadingPage(), isFalse);
      // Hidden for a recording is not seen: it opens again from Settings, at the page asked for.
      expect(kept.getItem(guideSeenKey), isNull);
      guide.show(3);
      expect(guide.open, isTrue);
      expect(guide.page, 3);
      expect(told, 4);
    });
  });
}
