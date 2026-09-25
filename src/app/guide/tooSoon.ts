import { readStoredText, writeStoredText } from '../core/stored.ts';
import { GUIDE_PAGES } from './pages.ts';

/**
 * Whether the reader left the guide early.
 *
 * Matt: "if the app is relaunched we can assume they hit the button on the
 * side too early, so reload with a warning about it being too soon". The
 * guide is shown once, on the first launch, and closed with Skip or from its
 * last page (shell/useGuide.ts). A launch before that, with the guide
 * started and left on a page before the side-key page, is someone who held
 * the key on page one: the app comes up on the guide again with one line at
 * the top of it (Guide.tsx says so in a line of its own) and does not start a recording. From the
 * side-key page on, a press of the key is what the page asks for, and it
 * records as it always did.
 *
 * Two keys next to `glyph-guide-seen`: that the guide has been started, and
 * the page it was last on. Both go when the guide is finished.
 */

// With no storage, a relaunch cannot be told from a first launch, and the guide simply shows.
const STARTED = 'glyph-guide-started';
const PAGE = 'glyph-guide-page';

/** The first page that expects the side key. Pages before it are reading. */
const SIDE_KEY_PAGE = GUIDE_PAGES.indexOf('sidekey');

/** The guide is on screen for the first time. */
export function markGuideStarted(): void {
  writeStoredText(STARTED, '1');
  if (readStoredText(PAGE) === null) writeStoredText(PAGE, '0');
}

/** The page the guide is showing, kept so a relaunch knows how far the reader got. */
export function rememberGuidePage(index: number): void {
  writeStoredText(PAGE, String(Math.max(0, index)));
}

/** The guide was finished (or skipped): nothing left to come back to. */
export function clearGuideProgress(): void {
  writeStoredText(STARTED, null);
  writeStoredText(PAGE, null);
}

/** The page the guide was last on, or -1 when it was never started. */
export function guidePageLeftAt(): number {
  if (readStoredText(STARTED) !== '1') return -1;
  const page = Number(readStoredText(PAGE) ?? '0');
  return Number.isFinite(page) && page >= 0 ? Math.floor(page) : 0;
}

/** Whether a page is one the reader should still be reading: before the side-key page. */
export function isReadingPage(index: number): boolean {
  return index < SIDE_KEY_PAGE;
}

/**
 * A launch that came too soon: the guide has not been finished (`seen` is
 * shell/useGuide.ts's `glyph-guide-seen`), it was started before, and it was left on a
 * reading page. The guide should open again with its line, and a side-key
 * launch should not record.
 */
export function launchedTooSoon(seen: boolean): boolean {
  if (seen) return false;
  const left = guidePageLeftAt();
  return left >= 0 && isReadingPage(left);
}
