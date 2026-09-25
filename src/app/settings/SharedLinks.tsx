import { useEffect, useState } from 'react';
import { Link2 } from '@glacier/icons';
import { failureText } from '../core/failure.ts';
import { listNotes, noteTitle, NOTES_CHANGED, NOTE_SAVED } from '../core/store.ts';
import { onShares, sharedLinks, sharesOnServer, stopSharing, takeDownShare } from '../share/share.ts';
import { PaneSection, RowAction, SettingRow } from './kit/settingsKit.tsx';

/** How long a share the list doesn't name must have gone unwritten before it counts as lost track of. */
const ORPHAN_AFTER_S = 600;

/**
 * Everything shared by a link, in one place (Settings › Account): each note or book with its link to copy and a way
 * to stop it, whichever device shared it, since the list travels with the synced settings (share/share.ts). A share
 * the server holds that no device lists any more - two devices changed their settings at once and one list won - has
 * no note to stop it from, so those are counted and can be taken down together.
 */
export function SharedLinks() {
  const [links, setLinks] = useState(sharedLinks);
  const [titles, setTitles] = useState<Record<string, string>>({});
  const [orphans, setOrphans] = useState<string[]>([]);
  const [said, setSaid] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => onShares(() => setLinks(sharedLinks())), []);

  useEffect(() => {
    let gone = false;
    const read = () =>
      void listNotes()
        .then((notes) => {
          if (!gone) setTitles(Object.fromEntries(notes.map((n) => [n.id, noteTitle(n.body) || 'Untitled'])));
        })
        .catch(() => undefined);
    read();
    window.addEventListener(NOTES_CHANGED, read);
    window.addEventListener(NOTE_SAVED, read);
    return () => {
      gone = true;
      window.removeEventListener(NOTES_CHANGED, read);
      window.removeEventListener(NOTE_SAVED, read);
    };
  }, []);

  // What the server holds that the list doesn't: asked once the list is known, and again when it changes.
  useEffect(() => {
    let gone = false;
    const listed = new Set(links.map((l) => l.id));
    sharesOnServer()
      .then((held) => {
        // Written in the last ten minutes, a share another device just made may not be in the synced list yet.
        const settled = Date.now() / 1000 - ORPHAN_AFTER_S;
        if (!gone) setOrphans(held.filter((s) => !listed.has(s.id) && s.updated < settled).map((s) => s.id));
      })
      .catch(() => undefined);
    return () => {
      gone = true;
    };
  }, [links]);

  const copy = async (link: string) => {
    try {
      await navigator.clipboard.writeText(link);
      setSaid('The link is copied.');
    } catch {
      setSaid(link);
    }
  };

  const run = async (work: () => Promise<void>) => {
    setBusy(true);
    setSaid(null);
    try {
      await work();
    } catch (failure) {
      setSaid(failureText(failure));
    } finally {
      setBusy(false);
    }
  };

  if (!links.length && !orphans.length) return null;
  return (
    <PaneSection
      title="Shared links"
      footer={said ?? 'Anyone with a link can read that note or book, and nobody else, the server included. Stopping a link means it reads nothing from then on.'}
    >
      {links.map((share) => (
        <SettingRow
          key={share.id}
          icon={<Link2 size={20} />}
          label={titles[share.noteId] ?? 'A note not on this device'}
          hint={titles[share.noteId] ? 'Read-only link. Your edits follow it.' : 'Shared from another device, or since deleted.'}
          control={
            <>
              <RowAction onPress={() => void copy(share.link)}>Copy</RowAction>
              <RowAction disabled={busy} onPress={() => void run(() => stopSharing(share.noteId))}>
                Stop
              </RowAction>
            </>
          }
        />
      ))}
      {orphans.length ? (
        <SettingRow
          label={orphans.length === 1 ? 'A link no device lists' : `${orphans.length} links no device lists`}
          hint="Still readable by anyone who has them. Taking them down can't be undone."
          control={
            <RowAction
              disabled={busy}
              onPress={() =>
                void run(async () => {
                  for (const id of orphans) await takeDownShare(id);
                  setOrphans([]);
                })
              }
            >
              Take down
            </RowAction>
          }
        />
      ) : null}
    </PaneSection>
  );
}
