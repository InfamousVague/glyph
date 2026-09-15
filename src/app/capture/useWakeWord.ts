import { useEffect, useRef } from 'react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { isTauri } from '../core/tauri.ts';
import { listenForWakeWord, type WakeListener } from './wakeWord.ts';

/** How long the app can be behind something before the microphone is let go. */
const HIDDEN_MS = 2500;

/**
 * Listens for "Glyph" while `on` (App.tsx: the list or a note on screen, no
 * sheet or guide over it, the keyword and "Listen while Glyph is open" both
 * switched on), and while the app is in front. Hearing it buzzes and calls
 * `onWake`, which opens the recorder with the hand-over (capture/wakeWord.ts).
 *
 * Going behind another app lets the microphone go, but not at once: asking
 * for the microphone puts Android's (invisible, instant) permission screen
 * over the app for a moment, which hides the page, and stopping on that and
 * starting again on its return asked again, round and round, on the emulator.
 * A start that fails (no model, no microphone) isn't tried again until `on`
 * changes.
 */
export function useWakeWord(on: boolean, onWake: () => void): void {
  const wakeRef = useRef(onWake);
  wakeRef.current = onWake;

  useEffect(() => {
    if (!on || !isTauri()) return undefined;
    let listener: WakeListener | null = null;
    let alive = true;
    let starting = false;
    let failed = false;
    let hideTimer = 0;

    const begin = async () => {
      if (listener || starting || failed || document.visibilityState !== 'visible') return;
      starting = true;
      const started = await listenForWakeWord(() => {
        listener = null;
        fireNativeHaptic('medium');
        wakeRef.current();
      });
      starting = false;
      if (!started) {
        failed = true;
        return;
      }
      if (!alive) started.stop();
      else listener = started;
    };
    const end = () => {
      listener?.stop();
      listener = null;
    };
    const onVisible = () => {
      window.clearTimeout(hideTimer);
      if (document.visibilityState === 'visible') void begin();
      else hideTimer = window.setTimeout(end, HIDDEN_MS);
    };
    document.addEventListener('visibilitychange', onVisible);
    void begin();
    return () => {
      alive = false;
      window.clearTimeout(hideTimer);
      document.removeEventListener('visibilitychange', onVisible);
      end();
    };
  }, [on]);
}
