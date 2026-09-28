import { useLayoutEffect, useState, type RefObject } from 'react';
import { flushSync } from 'react-dom';
import { tierOf, type Tier } from './tiers.ts';

/**
 * Which tier the home page's column is in (home/tiers.ts), answered again whenever the column changes width: the Fold
 * opened out or closed, the window resized, the sidebar docked or hidden, Settings' interface size changed, which
 * moves the gutters and so the column. The container queries in HomeScreen.module.css answer the same question for
 * the page's layout; this answers it for the counts, which are the page's code and not its stylesheet's.
 *
 * A layout effect, so the first answer is in before the first paint: a desk would otherwise paint the phone's four
 * Recent cards and five to-dos for a frame, then grow two cards and three rows under the scroller. After that a size
 * observer on the same element, read by its content box: `.page` has no padding and no border, so that box is exactly
 * the width its container queries measure, and the two cannot disagree about which side of a line the page is on.
 * The observer's answer is committed at once (`flushSync`), inside the frame the observer reports in: an update from
 * outside React waits for a later task, so crossing the desk's line (a rotation, a window resized, the sidebar
 * toggled) painted one frame of the desk's layout with the phone's counts, measured by a second observer on the
 * column, before the two cards and three rows came in on the next.
 *
 * It starts as the stack, the phone's tier, which is also the first answer on a phone, so nothing renders twice there.
 */
export function useColumnTier(page: RefObject<HTMLElement | null>): Tier {
  const [tier, setTier] = useState<Tier>('stack');
  useLayoutEffect(() => {
    const el = page.current;
    if (!el) return;
    // The root's rem, which is what a container query's rem is too; read at each answer, since Settings can move it.
    const rem = () => parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
    setTier(tierOf(el.getBoundingClientRect().width, rem()));
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(([entry]) => {
      if (entry) flushSync(() => setTier(tierOf(entry.contentRect.width, rem())));
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, [page]);
  return tier;
}
