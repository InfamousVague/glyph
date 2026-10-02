import { useEffect, useRef } from 'react';
import { followAppLinks, readNoteLink, readPlaceLink } from '../share/appLinks.ts';
import { readShareLink } from '../share/share.ts';

/**
 * A link that opened the app, followed once the notes are read. Two kinds arrive, from three roads:
 *
 * - A share link, saved as a copy and opened (share/share.ts, docs/SHARING.md). The reader page's "Save it in
 *   Ghost.md" opens the web app at `#fork=<link>` (src/read/Reader.tsx), and the link comes out of the address bar as
 *   it is taken, so a reload does not save it twice; "Open in the Ghost.md app" opens `ghostmd://` on a phone or a
 *   Mac, which the native side keeps until asked (share/appLinks.ts), and again whenever one arrives while it runs.
 * - A note link, `ghostmd://note/<id>`: the tap on the notification that a meeting was written up (docs/DESIGN.md
 *   §127 section 5). Opened where the note was left, its summary applied first when one is waiting (App.tsx).
 * - A place link, `ghostmd://notifications` or `ghostmd://org/<id>` (docs/TEAMS.md): the Notifications page, or an
 *   organization's screen, for whatever the phone will one day raise about them.
 *
 * All wait for the notes to be read, so a copy lands in a library that is there and a note opened is one the list
 * has. `fork`, `openNote` and `openPlace` are read when a link arrives rather than when the listener was set up.
 */
export function useAppLinks(
  loading: boolean,
  { fork, openNote, openPlace }: { fork: (link: string) => Promise<void>; openNote: (id: string) => Promise<void>; openPlace?: (place: NonNullable<ReturnType<typeof readPlaceLink>>) => void },
): void {
  const latest = useRef({ fork, openNote, openPlace });
  latest.current = { fork, openNote, openPlace };
  const forking = useRef(false);

  useEffect(() => {
    if (loading || forking.current || typeof location === 'undefined' || !location.hash.startsWith('#fork=')) return;
    forking.current = true;
    const link = location.hash.slice('#fork='.length);
    history.replaceState(null, '', location.pathname + location.search);
    void latest.current.fork(link).catch(warn);
  }, [loading]);

  useEffect(() => {
    if (loading) return undefined;
    return followAppLinks((link) => {
      const note = readNoteLink(link);
      const place = readPlaceLink(link);
      if (note) void latest.current.openNote(note).catch(warnNote);
      else if (place) latest.current.openPlace?.(place);
      else if (readShareLink(link)) void latest.current.fork(link).catch(warn);
    });
  }, [loading]);
}

function warn(failure: unknown): void {
  console.warn('[glyph] could not save the shared copy:', failure);
}

function warnNote(failure: unknown): void {
  console.warn('[glyph] could not open the note the link named:', failure);
}
