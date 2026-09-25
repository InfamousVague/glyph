import { useCallback, useEffect, useRef, useState } from 'react';
import { backFrom, canGoBack, canGoOn, FIRST, noteIdOf, onFrom, placeAt, went, type Place, type Trail } from '../notes/visited.ts';

/**
 * Where he has been, and the arrows that walk it (notes/visited.ts is the trail's rules; this is the React half, drawn
 * in the tab bar and offered in the palette). Matt: "Add the back and forward arrows in the top bar to the right of
 * the button used to toggle the sidebar and make sure we have full forward and backwards support".
 *
 * The trail records arriving somewhere rather than every way of getting there, so it does not matter which of the
 * many paths into a note was taken - a tab, a link in the words, the floating list, a swipe back. The arrows only say
 * where to go (`back`, `on`); the Shell does the going, as it does for every other way of moving.
 *
 * `jumped` is how the arrows say "this move was me": without it, going back would itself be recorded as somewhere new
 * and forward would never mean anything.
 */

export interface TrailWalk {
  /** The trail itself, for whatever must follow it changing (the palette's doings). */
  trail: Trail;
  /** A place worth landing on: the list and the grid always, a note only while it can still be seen. */
  stillThere: (spot: Place) => boolean;
  canBack: boolean;
  canOn: boolean;
  /** One step back: answers the place to go to, or null when there is nowhere. */
  back: () => Place | null;
  /** One step forward again: answers the place to go to, or null when there is nowhere. */
  on: () => Place | null;
}

/** `place` is where the screen is now (shell/screen.ts `placeOf`); `live` the ids of the notes that can still be seen. */
export function useTrail(place: Place | null, live: ReadonlySet<string>): TrailWalk {
  const [trail, setTrail] = useState(FIRST);
  const jumped = useRef(false);
  useEffect(() => {
    if (!place) return;
    if (jumped.current) {
      jumped.current = false;
      return;
    }
    setTrail((was) => went(was, place));
  }, [place]);
  const stillThere = useCallback(
    (spot: Place) => {
      const id = noteIdOf(spot);
      return id === null ? true : live.has(id);
    },
    [live],
  );
  const step = (next: Trail | null): Place | null => {
    const spot = next && placeAt(next);
    if (!next || !spot) return null;
    setTrail(next);
    jumped.current = true;
    return spot;
  };
  return {
    trail,
    stillThere,
    canBack: canGoBack(trail, stillThere),
    canOn: canGoOn(trail, stillThere),
    back: () => step(backFrom(trail, stillThere)),
    on: () => step(onFrom(trail, stillThere)),
  };
}
