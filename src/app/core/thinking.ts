import { useEffect, useSyncExternalStore } from 'react';

/**
 * Whether the model is thinking where the person is waiting on it: the robot's
 * views writing a note over, the review after a recording, sorting a memo. The
 * thinking gears (art/ThinkingGears.tsx) play over the whole screen while it
 * is.
 *
 * Counted, not a flag, so two screens thinking at once (or one screen
 * re-rendering while it thinks) never turn it off early. Background work - the
 * formatting queue after a recording, the gist under a title, a project's
 * briefing - doesn't count: nobody is watching it, and the gears over the
 * notes list would be in the way.
 */

let count = 0;
const listeners = new Set<() => void>();

const tell = () => listeners.forEach((listener) => listener());

/** Starts thinking; answers the way to stop, which does nothing the second time. */
export function beginThinking(): () => void {
  count += 1;
  if (count === 1) tell();
  let ended = false;
  return () => {
    if (ended) return;
    ended = true;
    count -= 1;
    if (count === 0) tell();
  };
}

export function isThinking(): boolean {
  return count > 0;
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** Whether anything is thinking now, kept current. */
export function useThinking(): boolean {
  return useSyncExternalStore(subscribe, isThinking, isThinking);
}

/** Thinks for as long as `active` is true and the component is mounted. */
export function useThinkingWhile(active: boolean): void {
  useEffect(() => (active ? beginThinking() : undefined), [active]);
}
