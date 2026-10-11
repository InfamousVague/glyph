/// Whether the reader left the walkthrough early. A port of `src/app/guide/tooSoon.ts`.
///
/// Matt: "if the app is relaunched we can assume they hit the button on the side too early, so reload with a warning
/// about it being too soon". The guide is shown once, on the first launch, and closed with Skip or from its last page
/// (guide_state.dart). A launch before that, with the guide started and left on a page before the last, is someone
/// who held the key on page one: the app comes up on the guide again with one line at the top of it and does not
/// start a recording. On the last page the guide has handed over, and a press of the key records as it always did.
///
/// Two keys next to `glyph-guide-seen`: that the guide has been started, and the page it was last on. Both go when
/// the guide is finished. With no storage, a relaunch cannot be told from a first launch, and the guide simply shows.
///
/// What differs: nothing but the storage being lib/core/stored.dart's [stored], which a test replaces.
library;

import '../core/stored.dart';
import 'pages.dart';

const String _started = 'glyph-guide-started';
const String _page = 'glyph-guide-page';

/// The page that hands over. Pages before it are reading.
final int _lastPage = GuidePage.values.length - 1;

/// The guide is on screen for the first time (`markGuideStarted`).
void markGuideStarted() {
  stored.writeText(_started, '1');
  if (stored.readText(_page) == null) stored.writeText(_page, '0');
}

/// The page the guide is showing, kept so a relaunch knows how far the reader got (`rememberGuidePage`).
void rememberGuidePage(int index) => stored.writeText(_page, '${index < 0 ? 0 : index}');

/// The guide was finished (or skipped): nothing left to come back to (`clearGuideProgress`).
void clearGuideProgress() {
  stored.writeText(_started, null);
  stored.writeText(_page, null);
}

/// The page the guide was last on, or -1 when it was never started (`guidePageLeftAt`). A page that does not read
/// as a number is the first: JavaScript's `Number` of it is not finite.
int guidePageLeftAt() {
  if (stored.readText(_started) != '1') return -1;
  final text = (stored.readText(_page) ?? '0').trim();
  final page = text.isEmpty ? 0.0 : double.tryParse(text);
  return page != null && page.isFinite && page >= 0 ? page.floor() : 0;
}

/// Whether a page is one the reader should still be reading: before the last (`isReadingPage`).
bool isReadingPage(int index) => index < _lastPage;

/// A launch that came too soon (`launchedTooSoon`): the guide has not been finished ([seen] is `glyph-guide-seen`),
/// it was started before, and it was left on a reading page. The guide should open again with its line, and a
/// side-key launch should not record.
bool launchedTooSoon(bool seen) {
  if (seen) return false;
  final left = guidePageLeftAt();
  return left >= 0 && isReadingPage(left);
}
