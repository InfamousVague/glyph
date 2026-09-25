import { useCallback, useEffect, type RefObject } from 'react';

/**
 * The room the note's page keeps for the AI's strip (ai/AiStrip.tsx), which floats under the header and over the page,
 * never in the page's smoke, so the note's first lines are not covered while the model works.
 *
 * Two measures, written as custom properties on the screen rather than held as state, since nothing in the screen's
 * render depends on them: where the header ends (`--ai-strip-top`, the header is a pane of glass whose height the
 * app's bar decides), and how tall the strip is (`--ai-strip-room`, zero once it is gone). The page pads itself by
 * them (NoteScreen.module.css).
 *
 * Answers the strip's `onHeight`.
 */
export function useStripRoom(screen: RefObject<HTMLElement | null>, header: RefObject<HTMLElement | null>): (height: number) => void {
  useEffect(() => {
    const pane = header.current;
    const host = screen.current;
    if (!pane || !host) return undefined;
    const fit = () => host.style.setProperty('--ai-strip-top', `${pane.offsetHeight}px`);
    fit();
    if (typeof ResizeObserver === 'undefined') return undefined;
    const watched = new ResizeObserver(fit);
    watched.observe(pane, { box: 'border-box' });
    return () => watched.disconnect();
  }, [screen, header]);
  return useCallback(
    (height: number) => {
      screen.current?.style.setProperty('--ai-strip-room', height ? `${height + 8}px` : '0px');
    },
    [screen],
  );
}
