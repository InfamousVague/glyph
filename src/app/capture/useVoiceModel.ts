import { useCallback, useEffect, useRef, useState } from 'react';
import { isTauri } from '../core/tauri.ts';
import { ensureModel } from './engine.ts';

/**
 * Whether the voice model is on the phone, and getting it there if not.
 *
 * The model is about 60 MB and the first press of the side key should never
 * wait for it, so it is fetched as soon as the app opens. That fetch used to be
 * fire-and-forget with its error swallowed, and on the Fold it failed without
 * a trace: the app was installed, the phone locked a minute later, Android
 * froze the backgrounded process mid-download, and the partial file was
 * cleaned up - leaving an empty `models/` folder and nothing on screen to say
 * so. A voice feature whose first use silently cannot work is worse than one
 * that says it is not ready.
 *
 * So the state is visible, the failure is logged with its real message, and
 * the fetch is retried every time the app comes back to the screen until it
 * succeeds. The retry-on-return is the part that fixes the freeze: a download
 * killed by the phone locking resumes the next time Glyph is looked at.
 */

export type VoiceModelState =
  | { kind: 'unsupported' }
  | { kind: 'checking' }
  | { kind: 'downloading'; received: number; total: number }
  | { kind: 'ready' }
  | { kind: 'failed'; message: string };

export function useVoiceModel(): { state: VoiceModelState; retry: () => void } {
  const [state, setState] = useState<VoiceModelState>(() => (isTauri() ? { kind: 'checking' } : { kind: 'unsupported' }));
  const running = useRef(false);
  const ready = useRef(false);

  const fetchModel = useCallback(async () => {
    if (!isTauri() || running.current || ready.current) return;
    running.current = true;
    try {
      await ensureModel((received, total) => setState({ kind: 'downloading', received, total }));
      ready.current = true;
      setState({ kind: 'ready' });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      // Logged so it reaches logcat through the WebView console; the screen
      // shows a short version and a retry.
      console.warn('[glyph] voice model download failed:', message);
      setState({ kind: 'failed', message });
    } finally {
      running.current = false;
    }
  }, []);

  useEffect(() => {
    void fetchModel();
    const onVisible = () => {
      if (document.visibilityState === 'visible') void fetchModel();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [fetchModel]);

  return { state, retry: () => void fetchModel() };
}
