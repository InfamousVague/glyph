import { useEffect, useRef } from 'react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { isDarkNow, preferences, setPreferences } from '../core/preferences.ts';

/**
 * The lights flickering on the guide's "Light or dark?" page (Guide.tsx
 * `Theme`): nothing drawn, only the page going light and dark a few times.
 *
 * Matt asked for a ghost at a light switch, then a gloved hand, then Noto's
 * pointing hand, and last "remove the iconography on the light / dark page
 * just add the flickering between a few times". So this is the flicker
 * alone: one flick a second in, one back, a pause, then a quick double, four
 * in all, ending on the theme the page opened with. Every flick really
 * changes the theme, so the whole guide changes colour and the choice rows
 * follow. A tap on a choice stops it at once (`settled`), and the caller puts
 * the theme back if the person leaves without choosing. With reduced motion
 * nothing happens.
 */

interface GloveSwitchProps {
  /** The person has chosen: the flickering stops. */
  settled: boolean;
}

/** The routine: each flick's wait after the one before. */
const ROUTINE: readonly number[] = [1100, 900, 1700, 170];

function flickTheme(): void {
  setPreferences({ theme: isDarkNow(preferences().theme) ? 'light' : 'dark' });
  fireNativeHaptic('selection');
}

export function GloveSwitch({ settled }: GloveSwitchProps) {
  const timer = useRef(0);
  useEffect(() => {
    if (settled || (typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches)) return undefined;
    let step = 0;
    const next = () => {
      const wait = ROUTINE[step];
      if (wait === undefined) return;
      timer.current = window.setTimeout(() => {
        // Nothing moves while the page is hidden; that beat is skipped.
        if (document.visibilityState === 'visible') flickTheme();
        step += 1;
        next();
      }, wait);
    };
    next();
    return () => window.clearTimeout(timer.current);
  }, [settled]);
  return null;
}
