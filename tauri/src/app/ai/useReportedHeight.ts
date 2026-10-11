import { useEffect, type RefObject } from 'react';

/**
 * How tall a floating piece of the AI is, told to the page as it changes, so the page can make room under it.
 *
 * The strip under a note's header (ai/AiStrip.tsx) floats over the note rather than pushing it, and the note pads
 * itself by its height (editor/NoteScreen.tsx): the height now, again whenever the element resizes, and 0 once it is
 * gone, so the page never keeps room for something that is not there. A webview with no ResizeObserver is told once.
 * (The prompt bar at the note's foot used it too, until the bar was taken out, docs/DESIGN.md §122.)
 *
 * `drawn` is whatever decides whether the element is on the page at all - the strip having something to say - since
 * the element under `host` is a different one, or none, when it changes.
 */
export function useReportedHeight(host: RefObject<HTMLElement | null>, onHeight: ((height: number) => void) | undefined, drawn: boolean): void {
  useEffect(() => {
    if (!onHeight) return undefined;
    const el = host.current;
    if (!el) {
      onHeight(0);
      return undefined;
    }
    const tell = () => onHeight(el.offsetHeight);
    tell();
    if (typeof ResizeObserver === 'undefined') return () => onHeight(0);
    const watched = new ResizeObserver(tell);
    watched.observe(el, { box: 'border-box' });
    return () => {
      watched.disconnect();
      onHeight(0);
    };
  }, [host, onHeight, drawn]);
}
