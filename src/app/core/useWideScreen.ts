import { useSyncExternalStore } from 'react';
import { isMobile } from './platform.ts';

/**
 * Whether the screen is wide enough for more in a header: a tablet, or a folding phone opened out. Answers again as
 * the phone folds and unfolds.
 */
const WIDE = '(min-width: 600px)';

function subscribe(listener: () => void): () => void {
  if (typeof matchMedia === 'undefined') return () => undefined;
  const query = matchMedia(WIDE);
  query.addEventListener('change', listener);
  return () => query.removeEventListener('change', listener);
}

export function useWideScreen(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => typeof matchMedia !== 'undefined' && matchMedia(WIDE).matches,
    () => false,
  );
}

/**
 * Whether the notes sit in a sidebar beside the open note: a desktop window
 * (not a phone or tablet, however wide) at least 900px across, which leaves the
 * note more room than a phone's screen beside the list (Matt: "on widescreen
 * desktop I would like to see a sidebar with all notes in them"). Answers again
 * as the window is resized.
 */
const SIDEBAR = '(min-width: 900px)';

function subscribeSidebar(listener: () => void): () => void {
  if (typeof matchMedia === 'undefined') return () => undefined;
  const query = matchMedia(SIDEBAR);
  query.addEventListener('change', listener);
  return () => query.removeEventListener('change', listener);
}

export function useSidebar(): boolean {
  return useSyncExternalStore(
    subscribeSidebar,
    () => !isMobile && typeof matchMedia !== 'undefined' && matchMedia(SIDEBAR).matches,
    () => false,
  );
}
