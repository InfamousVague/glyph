import { useCallback, useEffect, useState } from 'react';
import { answerHost } from '../core/host.ts';

/**
 * Update alerts, as the Settings switch sees them: whether they exist on this
 * build at all, and "off" / "on" / "blocked".
 *
 * The state lives in the activity (SharedPreferences), because the background
 * check that honours it runs without the page. It is read, never cached: after
 * turning alerts on, Android's permission prompt answers later, and the person
 * can also revoke notifications in system settings while Glyph is closed - so
 * the switch re-reads when the activity says the prompt was answered and
 * whenever the app returns to the screen.
 */

export type AlertsState = 'off' | 'on' | 'blocked';

function read(): AlertsState {
  try {
    const answer = window.GlyphHost?.updateAlerts?.();
    return answer === 'on' || answer === 'blocked' ? answer : 'off';
  } catch {
    return 'off';
  }
}

export function useUpdateAlerts(): { available: boolean; state: AlertsState; set: (on: boolean) => void } {
  const available = typeof window !== 'undefined' && typeof window.GlyphHost?.setUpdateAlerts === 'function';
  const [state, setState] = useState<AlertsState>(() => (available ? read() : 'off'));

  useEffect(() => {
    if (!available) return undefined;
    const recheck = () => {
      if (document.visibilityState === 'visible') setState(read());
    };
    document.addEventListener('visibilitychange', recheck);
    const unanswer = answerHost('alerts', () => setState(read()));
    return () => {
      document.removeEventListener('visibilitychange', recheck);
      unanswer();
    };
  }, [available]);

  const set = useCallback((on: boolean) => {
    try {
      const answer = window.GlyphHost?.setUpdateAlerts?.(on);
      setState(answer === 'on' || answer === 'blocked' ? answer : 'off');
    } catch {
      setState(read());
    }
  }, []);

  return { available, state, set };
}
