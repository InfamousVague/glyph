import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/banner.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/core/stored.dart';

/// `academy/banner.test.ts`, case for case. The home page's Academy card (lib/notes/notices.dart) is for someone who
/// has not started. These are the two ways it goes: a lesson passed, or the cross.
void main() {
  group('the Academy card', () {
    setUp(() => useStored(MemoryStored()));

    test('is offered to someone who has not started', () {
      expect(academyBannerDue(), isTrue);
    });

    test('goes once a lesson is passed', () {
      writeProgress({'title'});
      expect(academyBannerDue(), isFalse);
    });

    test('is offered for a week from the first time it was due, then goes by itself (GHST-103)', () {
      final first = DateTime.utc(2026, 10, 18, 9);
      expect(academyBannerDue(now: first), isTrue);
      expect(stored.readText(academyBannerSinceKey), first.toIso8601String());
      expect(academyBannerDue(now: first.add(const Duration(days: 6, hours: 23))), isTrue);
      expect(academyBannerDue(now: first.add(const Duration(days: 7))), isFalse);
      // The day it was first due holds: a later ask does not move it.
      expect(stored.readText(academyBannerSinceKey), first.toIso8601String());
    });

    test('goes when it is put away, and stays gone', () {
      dismissAcademyBanner();
      expect(academyBannerDue(), isFalse);
      // Kept as the page keeps it, so a library moved over from the web app stays put away.
      expect(stored.readText('glyph-academy-banner'), 'done');
    });
  });
}
