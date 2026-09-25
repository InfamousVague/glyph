import { useEffect, useState, type RefObject } from 'react';

/**
 * Next waits at the bottom of a guide page: it only shows once the page has been scrolled to its end. Until then,
 * after a moment, a nudge fades in where it will be, and a tap on the nudge takes the reader down (guide/Guide.tsx).
 * A page that fits the screen is already at its bottom. Watched as the page scrolls, resizes, or grows - a headline
 * types itself in out of smoke, and a table of marks fills in as its rows come near the screen.
 */

/**
 * What the nudge says, one picked each time a page opens (Matt: "a 'Down Here' button … put 6 different sassy phrases
 * it could use").
 */
export const NUDGES = ['Down here.', 'Keep scrolling, hon.', 'It’s not up there.', 'Scroll. I’ll wait.', 'The good bit’s lower.', 'Thumb down. Literally.'] as const;

/** How long a page is read before the nudge fades in. */
export const NUDGE_AFTER_MS = 2400;
/** How close to the end counts as the bottom. */
const BOTTOM_SLACK_PX = 24;

export interface BottomNudge {
  /** The page has been read to its end, or fits the screen: Next shows. */
  atBottom: boolean;
  /** The page has been open long enough for the nudge, if it is still wanted. */
  due: boolean;
  /** What the nudge says on this page. */
  words: string;
}

/** Follows `pageRef`'s scroller, starting afresh whenever `page` changes. */
export function useBottomNudge(pageRef: RefObject<HTMLElement | null>, page: unknown): BottomNudge {
  const [atBottom, setAtBottom] = useState(true);
  const [due, setDue] = useState(false);
  const [words, setWords] = useState<string>(NUDGES[0]);
  useEffect(() => {
    const el = pageRef.current;
    if (!el) return undefined;
    setDue(false);
    setWords(NUDGES[Math.floor(Math.random() * NUDGES.length)] ?? NUDGES[0]);
    const check = () => setAtBottom(el.scrollHeight - el.clientHeight - el.scrollTop <= BOTTOM_SLACK_PX);
    check();
    el.addEventListener('scroll', check, { passive: true });
    const resized = new ResizeObserver(check);
    resized.observe(el);
    const grown = new MutationObserver(check);
    grown.observe(el, { childList: true, subtree: true });
    const timer = window.setTimeout(() => setDue(true), NUDGE_AFTER_MS);
    return () => {
      el.removeEventListener('scroll', check);
      resized.disconnect();
      grown.disconnect();
      window.clearTimeout(timer);
    };
  }, [pageRef, page]);
  return { atBottom, due, words };
}
