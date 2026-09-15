import { useSyncExternalStore } from 'react';

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
