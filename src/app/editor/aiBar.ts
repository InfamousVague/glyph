import { useCallback, useEffect, useState, type RefObject } from 'react';
import type { RunScope } from '../ai/runs.ts';
import { setPreferences } from '../core/preferences.ts';

/**
 * The AI's bar at the foot of the note and its strip under the header (ai/PromptBar.tsx, ai/AiStrip.tsx): whether the
 * bar shows, what it is asked about, and the room the page keeps for both.
 *
 * The bar is off until asked for (core/preferences.ts `aiBar`; Matt: "Hide the AI bar on the note by default, put it
 * behind a toggle button"). The toggle is a ✨ where the bar lives: a small ring at the foot of the note while it is
 * hidden, and the spark at the start of the bar's own field while it shows. At the foot rather than with the note's
 * tools in the top bar, where a fifth ring pushed the three dots off a phone's bar (measured at 412 px: the More
 * button 14 px past the slot's edge, reachable only by a sideways scroll with no scrollbar).
 *
 * Ask over a selection (editor/ContextMenu.tsx) is asking for the bar, so that opens it for this note whatever the
 * setting: the selected words become the bar's scope, and the bar asks which - this part or the whole note - when a
 * chip is pressed or an instruction sent. Putting the bar away puts that ask away with it - its words and the focus it
 * was owed - so showing the bar again later is a plain bar, not the keyboard coming up on words that may since have
 * moved.
 */

export interface AiBar {
  shown: boolean;
  show: () => void;
  hide: () => void;
  /** Ask about the words from `from` to `to`: the bar opens on them, its field focused. */
  askAbout: (from: number, to: number) => void;
  /** The selection the bar is asking about, or null for the whole note. */
  scope: RunScope | null;
  clearScope: () => void;
  /** Rises each time the bar's field is owed the focus. */
  focusAsk: number;
}

/** The bar, shown when `wanted` (the preference) says so or a selection asked for it. */
export function useAiBar(wanted: boolean): AiBar {
  const [scope, setScope] = useState<RunScope | null>(null);
  const [focusAsk, setFocusAsk] = useState(0);
  const [askedFor, setAskedFor] = useState(false);
  return {
    shown: wanted || askedFor,
    show: () => setPreferences({ aiBar: true }),
    hide: () => {
      setPreferences({ aiBar: false });
      setAskedFor(false);
      setScope(null);
      setFocusAsk(0);
    },
    askAbout: (from, to) => {
      setAskedFor(true);
      setScope({ from, to });
      setFocusAsk((n) => n + 1);
    },
    scope,
    clearScope: () => setScope(null),
    focusAsk,
  };
}

/**
 * The room the page keeps for the strip and the bar, written as custom properties on the screen rather than held as
 * state, since nothing in the screen's render depends on them: where the header ends (`--ai-strip-top`, the header is a
 * pane of glass whose height the app's bar decides), how tall the strip is (`--ai-strip-room`, zero once it is gone),
 * and how tall the bar is, or the ✨ ring while the bar is away (`--ai-bar-room`). The page pads itself by them
 * (NoteScreen.module.css), so the note's first and last lines are never under either.
 */
export function useAiRoom(screen: RefObject<HTMLElement | null>, header: RefObject<HTMLElement | null>, { barShown, ringShown }: { barShown: boolean; ringShown: boolean }) {
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
  const onStripHeight = useCallback(
    (height: number) => {
      screen.current?.style.setProperty('--ai-strip-room', height ? `${height + 8}px` : '0px');
    },
    [screen],
  );
  const onBarHeight = useCallback(
    (height: number) => {
      screen.current?.style.setProperty('--ai-bar-room', height ? `${height + 12}px` : '0px');
    },
    [screen],
  );
  // The ring's room while the bar is away: the bar tells its own height as it mounts, and 0 as it goes, so this runs
  // after that and has the last word.
  useEffect(() => {
    if (!barShown) screen.current?.style.setProperty('--ai-bar-room', ringShown ? '52px' : '0px');
  }, [screen, barShown, ringShown]);
  return { onStripHeight, onBarHeight };
}
