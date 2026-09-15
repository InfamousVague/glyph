import { useEffect, useRef, useState, type RefObject } from 'react';
import styles from './ScrollFades.module.css';

/**
 * The top and bottom edges of a scrolling page, blurred and faded into the
 * paper, and only where there is more to scroll to.
 *
 * Matt: "Do a gradient blur and fade at the top of the content on the app page
 * so that it gracefully fades off screen top and bottom as needed, dont show
 * when on top and bottom of scroll." Words scrolling out under the header, or
 * off the bottom, soften and dissolve instead of being cut by an edge. At the
 * very top the top fade is gone, so the first line sits crisp under the
 * header; at the very end the bottom one is.
 *
 * Two bands over the scroller's own box (fixed to where it is on screen, read
 * again when the screen resizes), each a backdrop blur masked by a gradient
 * with a veil of paper over it. They never take a touch. The scroller is
 * watched with a passive scroll listener, and the bands' visibility is two
 * attributes, so scrolling renders nothing.
 */

interface ScrollFadesProps {
  /** The element that scrolls. */
  target: RefObject<HTMLElement | null>;
  top?: boolean;
  bottom?: boolean;
  /** Extra height for the top band, over the scroller's edge: the status bar, where the page starts under it. */
  topInset?: string;
}

/** Within this many pixels of an end counts as at it. */
const AT_END_PX = 4;

export function ScrollFades({ target, top = true, bottom = true, topInset }: ScrollFadesProps) {
  const topBand = useRef<HTMLDivElement>(null);
  const bottomBand = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState<{ top: number; left: number; width: number; height: number } | null>(null);

  useEffect(() => {
    const scroller = target.current;
    if (!scroller) return undefined;
    const place = () => {
      const rect = scroller.getBoundingClientRect();
      setBox((was) =>
        was && was.top === rect.top && was.left === rect.left && was.width === rect.width && was.height === rect.height
          ? was
          : { top: rect.top, left: rect.left, width: rect.width, height: rect.height },
      );
    };
    const edges = () => {
      const more = scroller.scrollHeight - scroller.clientHeight;
      const atTop = scroller.scrollTop <= AT_END_PX;
      const atEnd = scroller.scrollTop >= more - AT_END_PX;
      if (topBand.current) topBand.current.dataset.shown = !atTop && more > 0 ? 'true' : 'false';
      if (bottomBand.current) bottomBand.current.dataset.shown = !atEnd && more > 0 ? 'true' : 'false';
    };
    place();
    edges();
    scroller.addEventListener('scroll', edges, { passive: true });
    const observer = new ResizeObserver(() => {
      place();
      edges();
    });
    observer.observe(scroller);
    // The content growing (a note typed longer) changes what's left to scroll without a scroll.
    for (const child of Array.from(scroller.children)) observer.observe(child);
    window.addEventListener('resize', place);
    return () => {
      scroller.removeEventListener('scroll', edges);
      observer.disconnect();
      window.removeEventListener('resize', place);
    };
  }, [target]);

  if (!box) return null;
  return (
    <>
      {top ? (
        <div
          ref={topBand}
          className={styles.top}
          data-shown="false"
          aria-hidden="true"
          style={{ top: box.top, left: box.left, width: box.width, ...(topInset ? { marginBlockStart: `calc(-1 * ${topInset})`, paddingBlockStart: topInset } : {}) }}
        />
      ) : null}
      {bottom ? (
        <div ref={bottomBand} className={styles.bottom} data-shown="false" aria-hidden="true" style={{ top: box.top + box.height, left: box.left, width: box.width }} />
      ) : null}
    </>
  );
}
