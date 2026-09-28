import { useEffect, useState, useSyncExternalStore } from 'react';
import { Copy, Link2, MapPinned, Share2, X } from '@glacier/icons';
import { Locate } from '../art/Icons.tsx';
import { useAccount } from '../core/account/account.ts';
import { failureText } from '../core/failure.ts';
import { listNotes } from '../core/store.ts';
import { linkFor, onShares, shareNote, sharesPlace, sharesPlaces, shareWithPlace, shareWithPlaces, sharingPlace, sharingPlaces, stopSharing } from './share.ts';
import styles from '../editor/NoteSettings.module.css';

/**
 * What the link carries of where its pages were written and of the places in their words, in one sentence for what
 * the pages hold: nothing where they hold neither, so a note with only a tag reads as it always did.
 */
function linkCarries({ tag, places, withTag, withPlaces }: { tag: boolean; places: boolean; withTag: boolean; withPlaces: boolean }): string {
  if (tag && places) {
    if (withTag && withPlaces) return 'The link carries where it was written and the places in it.';
    if (withPlaces) return 'The link carries the places in it. Where it was written stays out.';
    if (withTag) return 'The link carries where it was written. The places in it stay out.';
    return 'Where it was written and the places in it stay out of the link.';
  }
  if (tag) return withTag ? 'The link carries where it was written.' : 'Where it was written stays out of the link.';
  if (places) return withPlaces ? 'The link carries the places in it.' : 'The places in it stay out of the link.';
  return '';
}

/**
 * A note's sharing, in its cog (editor/NoteSettings.tsx): share it by a read-only link, copy or send the link, stop
 * sharing (share/share.ts). Signed out, the one line says where to sign in, since a share is kept with an account.
 *
 * A shared note that says where it was written (or a book with such a chapter) gets one more row, "Share where it was
 * written", with the kit's tick: the link leaves the location out until it is ticked (share.ts's header says why). One
 * whose words hold a place (the + beside the line's A place) gets its own, "Share the places in it", ticked apart, so
 * a tick given for the one never carries the other.
 */
export function ShareRows({ noteId }: { noteId: string }) {
  const { session } = useAccount();
  const link = useSyncExternalStore(onShares, () => linkFor(noteId), () => null);
  const withPlace = useSyncExternalStore(onShares, () => sharingPlace(noteId), () => false);
  const withPlaces = useSyncExternalStore(onShares, () => sharingPlaces(noteId), () => false);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  useEffect(() => setSaid(null), [noteId]);
  // Whether the pages have a tag, and places in their words, to share: read once the note is shared, from the library
  // as the share reads it.
  const [held, setHeld] = useState({ tag: false, places: false });
  useEffect(() => {
    if (!link) return undefined;
    let live = true;
    void listNotes()
      .then((notes) => {
        const note = notes.find((n) => n.id === noteId);
        if (live) setHeld({ tag: Boolean(note) && sharesPlace(note!, notes), places: Boolean(note) && sharesPlaces(note!, notes) });
      })
      .catch(() => undefined);
    return () => {
      live = false;
    };
  }, [noteId, link]);
  const placed = held.tag;
  const carries = linkCarries({ tag: held.tag, places: held.places, withTag: withPlace, withPlaces });

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

  const copy = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setSaid('The link is copied.');
    } catch {
      setSaid(text);
    }
  };

  const share = () =>
    run(async () => {
      const notes = await listNotes();
      const note = notes.find((n) => n.id === noteId);
      if (!note) throw new Error('Save the note first: there is nothing to share yet.');
      await copy(await shareNote(note, notes));
    });

  const canSend = typeof navigator !== 'undefined' && typeof navigator.share === 'function';

  return (
    <>
      <p className={styles.heading}>Sharing</p>
      <div className={styles.group}>
        {!session ? (
          <div className={styles.row} aria-disabled>
            <span className={styles.icon} aria-hidden="true">
              <Link2 size={18} strokeWidth={2.2} />
            </span>
            <span className={styles.label}>
              Share a read-only link
              <span className={styles.hint}>Sign in under Settings › Account first: a share is kept with your account.</span>
            </span>
          </div>
        ) : !link ? (
          <button type="button" className={styles.row} disabled={busy} onClick={() => void share()}>
            <span className={styles.icon} aria-hidden="true">
              <Link2 size={18} strokeWidth={2.2} />
            </span>
            <span className={styles.label}>
              {busy ? 'Sharing…' : 'Share a read-only link'}
              <span className={styles.hint}>Anyone with the link can read it, and your edits follow. The server can’t read it.</span>
            </span>
          </button>
        ) : (
          <>
            <button type="button" className={styles.row} onClick={() => void copy(link)}>
              <span className={styles.icon} aria-hidden="true">
                <Copy size={18} strokeWidth={2.2} />
              </span>
              <span className={styles.label}>
                Copy the link
                <span className={styles.hint}>
                  Shared, read-only. Your edits reach readers a few seconds after you save.{carries ? ` ${carries}` : ''}
                </span>
              </span>
            </button>
            {placed ? (
              <button type="button" className={styles.row} disabled={busy} aria-pressed={withPlace} onClick={() => void run(() => shareWithPlace(noteId, !withPlace))}>
                <span className={styles.icon} aria-hidden="true">
                  <Locate />
                </span>
                <span className={styles.label}>
                  Share where it was written
                  <span className={styles.hint}>The place and the map, on the shared page.</span>
                </span>
                {withPlace ? <span className={styles.tick} aria-hidden="true" /> : null}
              </button>
            ) : null}
            {held.places ? (
              <button type="button" className={styles.row} disabled={busy} aria-pressed={withPlaces} onClick={() => void run(() => shareWithPlaces(noteId, !withPlaces))}>
                <span className={styles.icon} aria-hidden="true">
                  <MapPinned size={18} strokeWidth={2.2} />
                </span>
                <span className={styles.label}>
                  Share the places in it
                  <span className={styles.hint}>The places written in it, and their maps.</span>
                </span>
                {withPlaces ? <span className={styles.tick} aria-hidden="true" /> : null}
              </button>
            ) : null}
            {canSend ? (
              <button type="button" className={styles.row} onClick={() => void navigator.share({ url: link }).catch(() => undefined)}>
                <span className={styles.icon} aria-hidden="true">
                  <Share2 size={18} strokeWidth={2.2} />
                </span>
                <span className={styles.label}>Send the link</span>
              </button>
            ) : null}
            <button type="button" className={styles.row} disabled={busy} onClick={() => void run(() => stopSharing(noteId))}>
              <span className={styles.icon} aria-hidden="true">
                <X size={18} strokeWidth={2.2} />
              </span>
              <span className={styles.label}>
                {busy ? 'Stopping…' : 'Stop sharing'}
                <span className={styles.hint}>The link reads nothing from then on.</span>
              </span>
            </button>
          </>
        )}
        {said ? (
          <p className={styles.hint} role="status" style={{ padding: 'var(--glacier-space-2) var(--glacier-space-4)', margin: 0 }}>
            {said}
          </p>
        ) : null}
      </div>
    </>
  );
}
