import { useReducer } from 'react';

/**
 * A render on demand, for a component that shows something React does not
 * hold.
 *
 * Some components draw from a truth that lives elsewhere - CodeMirror's state
 * (the find bar's match count, the styles the context menu shows lit), a
 * module's cache (a mark's details from its plugin, a browser picture arriving
 * from storage, a gist the runner just wrote, a card's drawing just kept) -
 * and are only told that it moved.
 * Copying that truth into React state would give it two owners that can
 * disagree; the component reads the real one on every render instead, and all
 * it needs is a way to ask for the next render. So the state is a counter
 * nobody reads, and what this answers is the one thing that matters about it:
 * calling it renders the component again.
 *
 * The answer is React's own dispatch, so it is the same function on every
 * render and safe in an effect's dependencies.
 */
export function useRedraw(): () => void {
  const [, redraw] = useReducer((n: number) => n + 1, 0);
  return redraw;
}
