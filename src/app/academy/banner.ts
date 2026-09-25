import { storedFlag } from '../core/stored.ts';
import { readProgress } from './lessons.ts';

/**
 * Whether the home page offers Glyph Academy (notes/Notices.tsx), the way
 * it offers an update (Matt: "the academy page should show up on the home
 * screen kinda like the update banner for new users as a call to action
 * banner").
 *
 * It is for someone who has not started: the moment a lesson is passed
 * (academy/lessons.ts keeps that), the banner has done its job and goes. A
 * person who would rather not can put it away, which is remembered; the
 * Academy stays in Settings either way.
 */

/** Nowhere to remember it: better to offer once more than never again. */
const dismissed = storedFlag('glyph-academy-banner', { value: 'done' });

export const academyBannerDismissed = dismissed.is;

/** Not kept: put away for this run at least; App.tsx holds that. */
export const dismissAcademyBanner = dismissed.mark;

/** True while the Academy is worth offering: nothing passed yet, and not put away. */
export function academyBannerDue(): boolean {
  return readProgress().size === 0 && !academyBannerDismissed();
}
