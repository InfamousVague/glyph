import { useEffect, useRef } from 'react';
import { readJoinLink } from '../core/orgs/joinLinks.ts';
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
 * - A place link, `ghostmd://notifications` or `ghostmd://org/<id>` (docs/TEAMS.md): the notifications drawer, or an
 *   organization's dashboard, for whatever the phone will one day raise about them.
 * - An invite link (core/orgs/joinLinks.ts, docs/TEAMS.md): the reader page's "Join on the web" opens the web app at
 *   `#join=<code>`, taken out of the address bar as a fork is, and its "Open in the Ghost.md app" is
 *   `ghostmd://join/<code>`. Either is handed to `join`, which asks before anything is joined (notes/JoinSheet.tsx).
 *
 * All wait for the notes to be read, so a copy lands in a library that is there and a note opened is one the list
 * has. `fork`, `openNote` and `openPlace` are read when a link arrives rather than when the listener was set up.
 */
export function useAppLinks(
  loading: boolean,
  {
    fork,
    openNote,
    openPlace,
    join,
  }: { fork: (link: string) => Promise<void>; openNote: (id: string) => Promise<void>; openPlace?: (place: NonNullable<ReturnType<typeof readPlaceLink>>) => void; join?: (code: string) => void },
): void {
  const latest = useRef({ fork, openNote, openPlace, join });
  latest.current = { fork, openNote, openPlace, join };
  const forking = useRef(false);
  const joining = useRef(false);

  useEffect(() => {
    if (loading || joining.current || typeof location === 'undefined' || !location.hash.startsWith('#join=')) return;
    joining.current = true;
    const code = readJoinLink(location.hash);
    history.replaceState(null, '', location.pathname + location.search);
    if (code) latest.current.join?.(code);
  }, [loading]);

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
      const join = link.trim().startsWith('ghostmd://join/') ? readJoinLink(link) : null;
      if (join) latest.current.join?.(join);
      else if (note) void latest.current.openNote(note).catch(warnNote);
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
