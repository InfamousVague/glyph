import { useCallback, useEffect, useRef } from 'react';
import { keepVersion, PAUSE_MS, useKeepsVersions } from '../core/versions/record.ts';

/**
 * When the open note keeps a version (core/versions/record.ts): after the writing rests for `PAUSE_MS`, when the note
 * is left (closed, or the app put away), and once as the history begins - the note as it was when it was switched on
 * or opened, so the first change has something to go back to. A version of no change is never kept (versions/file.ts
 * `withVersion`), so the pauses and the leavings of a note nobody typed in cost nothing.
 *
 * `body` is the live words (editor/useNoteSaving.ts); `changed` is called with each change the editor makes.
 */
export function useVersionKeeping(noteId: string, body: { readonly current: string }): { keeps: boolean; changed: () => void } {
  const keeps = useKeepsVersions(noteId);
  const on = useRef(keeps);
  on.current = keeps;
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  /** Whether there are words since the last version kept, so a leaving with none reads nothing. */
  const dirty = useRef(false);

  const keepNow = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
    if (!on.current || !dirty.current) return;
    dirty.current = false;
    void keepVersion(noteId, body.current).catch(() => undefined);
  }, [noteId, body]);

  // Begun, or opened with a history: the words as they are now are the version the first change goes back from.
  useEffect(() => {
    if (!keeps) return;
    void keepVersion(noteId, body.current).catch(() => undefined);
  }, [keeps, noteId, body]);

  // Left: the closing of the note, the app put away, the page gone.
  useEffect(() => {
    const onHide = () => {
      if (document.visibilityState === 'hidden') keepNow();
    };
    document.addEventListener('visibilitychange', onHide);
    window.addEventListener('pagehide', keepNow);
    return () => {
      document.removeEventListener('visibilitychange', onHide);
      window.removeEventListener('pagehide', keepNow);
      keepNow();
    };
  }, [keepNow]);

  const changed = useCallback(() => {
    if (!on.current) return;
    dirty.current = true;
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(keepNow, PAUSE_MS);
  }, [keepNow]);

  return { keeps, changed };
}
