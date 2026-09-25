import { useEffect, useRef } from 'react';
import { followAppLinks } from '../share/appLinks.ts';

/**
 * A share link that opened the app, saved as a copy and opened (share/share.ts, docs/SHARING.md). Two ways one
 * arrives, and both wait for the notes to be read, so the copy lands in a library that is there:
 *
 * - The reader page's "Save it in Ghost.md" opens the web app at `#fork=<link>` (src/read/Reader.tsx). The link comes
 *   out of the address bar as it is taken, so a reload does not save it twice.
 * - "Open in the Ghost.md app" opens `ghostmd://` on a phone or a Mac, which the native side keeps until asked
 *   (share/appLinks.ts), and again whenever one arrives while the app runs.
 *
 * `fork` does the saving and the opening, and is read when a link arrives rather than when the listener was set up.
 */
export function useForkLinks(loading: boolean, fork: (link: string) => Promise<void>): void {
  const latest = useRef(fork);
  latest.current = fork;
  const forking = useRef(false);

  useEffect(() => {
    if (loading || forking.current || typeof location === 'undefined' || !location.hash.startsWith('#fork=')) return;
    forking.current = true;
    const link = location.hash.slice('#fork='.length);
    history.replaceState(null, '', location.pathname + location.search);
    void latest.current(link).catch(warn);
  }, [loading]);

  useEffect(() => {
    if (loading) return undefined;
    return followAppLinks((link) => void latest.current(link).catch(warn));
  }, [loading]);
}

function warn(failure: unknown): void {
  console.warn('[glyph] could not save the shared copy:', failure);
}
