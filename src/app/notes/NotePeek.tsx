import { useEffect, useMemo, useRef, useState } from 'react';
import { Editor } from '../editor/Editor.tsx';
import { isDarkNow, usePreferences } from '../core/preferences.ts';
import { PEEK_LINES, peekMarkdown } from './peek.ts';
import { isCanvasBody } from '../canvas/jsonCanvas.ts';
import styles from './NotePeek.module.css';

/**
 * A note drawn small: the first lines of it, in the note's own editor, set in the formatted view at a fraction of the
 * size. The card's description on the home page and in the sidebar.
 *
 * It was a miniature drawn by hand (notes/peek.ts, still there for the sample note's tests): a heading a heavier
 * line, a to-do a six-pixel box, a bullet a dot. Matt: "the preview for the formatting should use the same formatter
 * that the actual note uses instead of custom rolled small stuff like the checkboxes are weird for example". So it is
 * the same editor the note opens in (editor/Editor.tsx), read-only and in its `peek` mode - nothing that fetches,
 * polls or acts - given the note after its title (`peekMarkdown`) and clipped to a few lines' height. Whatever the
 * note draws, the card draws the same way: a to-do's box is the note's box, a board is a board, a table a table.
 * The card is a button, so nothing here takes a tap.
 *
 * An editor is not free: measured at 25-30 ms each on a Mac in the dev build, and the sidebar's tree has one card
 * per note. So a card holds a blank of about the right height until it is near the screen, then gets its editor -
 * one card at a time, so the page paints first and the previews fill in behind it - and gives it back once it has
 * scrolled well away. A page that cannot watch the screen (a test) draws them all at once.
 *
 * It says nothing to a screen reader: the row already has its name and its date.
 */

export interface NotePeekProps {
  body: string;
  className?: string;
}

/** How far off the screen a card is drawn, or kept drawn, in pixels: a scroll's worth. */
const NEAR_PX = 400;

/**
 * One editor at a time, whichever card asked first, each in a task of its own: ten cards mounting in one go is a
 * quarter of a second in which nothing paints, and the same ten one after another is a page that appears and fills
 * in. A task rather than an animation frame, which a hidden page never gets: a page that comes back to the front
 * finds its cards drawn, and a job that throws does not stop the ones behind it.
 */
const queue: (() => void)[] = [];
let draining = false;
function soon(run: () => void): () => void {
  queue.push(run);
  if (!draining) {
    draining = true;
    const next = () => {
      const job = queue.shift();
      if (!job) {
        draining = false;
        return;
      }
      try {
        job();
      } finally {
        window.setTimeout(next, 0);
      }
    };
    window.setTimeout(next, 0);
  }
  return () => {
    const at = queue.indexOf(run);
    if (at >= 0) queue.splice(at, 1);
  };
}

export function NotePeek({ body, className }: NotePeekProps) {
  const { theme } = usePreferences();
  // A canvas note is JSON, not words: its card shows nothing small until a canvas can be drawn small (docs/CANVAS.md).
  const markdown = useMemo(() => (isCanvasBody(body) ? '' : peekMarkdown(body)), [body]);
  const host = useRef<HTMLSpanElement>(null);
  const [drawn, setDrawn] = useState(() => typeof IntersectionObserver === 'undefined');
  /** How tall the editor was, so the blank that stands in for it once it is gone keeps the card's height. */
  const [stood, setStood] = useState<number | null>(null);
  /** More of the note below the card's edge: the last line fades out, to say so. */
  const [clipped, setClipped] = useState(false);

  useEffect(() => {
    const el = host.current;
    if (!el || !drawn || typeof ResizeObserver === 'undefined') return undefined;
    const check = () => setClipped(el.scrollHeight > el.clientHeight + 1);
    check();
    const watcher = new ResizeObserver(check);
    watcher.observe(el);
    for (const child of el.children) watcher.observe(child);
    return () => watcher.disconnect();
  }, [drawn, markdown]);

  useEffect(() => {
    const el = host.current;
    if (!el || typeof IntersectionObserver === 'undefined') return undefined;
    let cancel: (() => void) | null = null;
    const watcher = new IntersectionObserver(
      ([entry]) => {
        if (!entry) return;
        if (entry.isIntersecting) {
          cancel?.();
          cancel = soon(() => {
            cancel = null;
            setDrawn(true);
          });
        } else {
          cancel?.();
          cancel = null;
          // Gone well off the screen: its editor goes, and a blank its height stands in.
          setDrawn((was) => {
            if (was) setStood(el.offsetHeight);
            return false;
          });
        }
      },
      { rootMargin: `${NEAR_PX}px 0px` },
    );
    watcher.observe(el);
    return () => {
      cancel?.();
      watcher.disconnect();
    };
  }, []);

  if (!markdown) return null;
  // Before the editor: a blank about as tall as the lines it will draw, so the cards do not jump as they fill in.
  const lines = Math.min(PEEK_LINES, markdown.split('\n').filter((line) => line.trim()).length);
  const style = drawn ? undefined : { blockSize: stood !== null ? `${stood}px` : `calc(var(--app-body) * 1.6 * ${lines})` };
  return (
    <span
      ref={host}
      className={className ? `${styles.peek} ${className}` : styles.peek}
      style={style}
      data-clipped={drawn && clipped ? '' : undefined}
      aria-hidden="true"
    >
      {drawn ? <Editor value={markdown} onChange={noop} dark={isDarkNow(theme)} assist={false} readOnly display="formatted" peek grow /> : null}
    </span>
  );
}

function noop(): void {
  // Read-only: nothing typed comes back.
}
