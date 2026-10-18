/// Whether the home page offers Ghost.md Academy: the Academy card among the home page's notices
/// (lib/notes/notices.dart `AcademyCard`), offered the way an update is (Matt: "the academy page should show up on
/// the home screen kinda like the update banner for new users as a call to action banner", hence the file's name).
/// A port of `src/app/academy/banner.ts`.
///
/// It is for someone who has not started: the moment a lesson is passed (lessons.dart keeps that), the card has done
/// its job and goes. A person who would rather not can put it away, which is remembered; the Academy stays in
/// Settings either way.
///
/// What differs: the flag is asked of `stored` each time, where the page made it once as the module loaded, so a
/// store put in place after this file was first read (`useStored`) is the one that is asked.
///
/// **A week, and then it goes by itself** (GHST-103, simple mode's home): the card is for the first week it is
/// offered, from the day it was first due ([academyBannerSinceKey]); past that, someone who has not started and
/// has not put it away is left in peace. The Academy stays in Settings.
library;

import '../core/stored.dart';
import 'lessons.dart';

/// The key the putting away is kept under; `done` is what it holds.
const String academyBannerKey = 'glyph-academy-banner';

/// The key the day it was first offered is kept under, in UTC.
const String academyBannerSinceKey = 'glyph-academy-banner-since';

/// How long the card is offered for.
const Duration academyBannerFor = Duration(days: 7);

/// Nowhere to remember it: better to offer once more than never again.
StoredFlag get _dismissed => stored.flag(academyBannerKey, value: 'done');

/// Not kept: put away for this run at least; whoever shows the card holds that.
void dismissAcademyBanner() => _dismissed.mark();

/// True while the Academy is worth offering: nothing passed yet, not put away, and within a week of when it was
/// first due. The first ask writes the day down, so the week runs from the first home page that could have shown
/// the card, not from a launch that never reached it. `now` is the test's clock.
bool academyBannerDue({DateTime? now}) {
  if (readProgress().isNotEmpty || _dismissed.isMarked) return false;
  final at = (now ?? DateTime.now()).toUtc();
  final since = DateTime.tryParse(stored.readText(academyBannerSinceKey) ?? '');
  if (since == null) {
    stored.writeText(academyBannerSinceKey, at.toIso8601String());
    return true;
  }
  return at.difference(since) < academyBannerFor;
}
