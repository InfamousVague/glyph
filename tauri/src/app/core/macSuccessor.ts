import { useEffect, useState } from 'react';
import { isMacApp } from './platform.ts';

/*
 * The Mac app that comes after this one (Matt, 2026-10-12: "offer the new app in 1.15.0"). From 2.0 the Mac app is
 * another program under the same name: this one cannot become it by reloading its page, so it says there is one and
 * hands over the download. It reads the site's own note of the Mac download (desktop.json, which the download page
 * reads too), and speaks only when that says a version 2 or later: until the new app is published, nothing shows.
 */

/** Where the site says what the Mac download is, and the download itself. */
export const MAC_NOTE = 'https://ghostmarkdown.com/desktop.json';
export const MAC_DOWNLOAD = 'https://ghostmarkdown.com/glyph.dmg';

/** The version a desktop.json offers, when it is the next app's: 2.0.0 or later. Null for anything else. */
export function successorIn(note: unknown): string | null {
  const version = typeof note === 'object' && note !== null ? (note as { version?: unknown }).version : null;
  if (typeof version !== 'string') return null;
  const parts = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
  return parts && Number(parts[1]) >= 2 ? version : null;
}

/** The next Mac app's version once the site offers one, in the Mac app only; null until then and everywhere else. */
export function useMacSuccessor(): string | null {
  const [version, setVersion] = useState<string | null>(null);
  useEffect(() => {
    if (!isMacApp) return;
    let gone = false;
    // After the app has started, and once: a look that fails says nothing, and the next start looks again.
    const timer = window.setTimeout(() => {
      fetch(MAC_NOTE, { cache: 'no-store' })
        .then((answer) => (answer.ok ? answer.json() : null))
        .then((note) => {
          if (!gone) setVersion(successorIn(note));
        })
        .catch(() => undefined);
    }, 6000);
    return () => {
      gone = true;
      window.clearTimeout(timer);
    };
  }, []);
  return version;
}
