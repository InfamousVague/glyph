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
library;

import '../core/stored.dart';
import 'lessons.dart';

/// The key the putting away is kept under; `done` is what it holds.
const String academyBannerKey = 'glyph-academy-banner';

/// Nowhere to remember it: better to offer once more than never again.
StoredFlag get _dismissed => stored.flag(academyBannerKey, value: 'done');

/// Not kept: put away for this run at least; whoever shows the card holds that.
void dismissAcademyBanner() => _dismissed.mark();

/// True while the Academy is worth offering: nothing passed yet, and not put away.
bool academyBannerDue() => readProgress().isEmpty && !_dismissed.isMarked;
