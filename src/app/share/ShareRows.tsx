import { useEffect, useState, useSyncExternalStore } from 'react';
import { Copy, Link2, Share2, X } from '@glacier/icons';
import { Locate } from '../art/Icons.tsx';
import { useAccount } from '../core/account/account.ts';
import { failureText } from '../core/failure.ts';
import { listNotes } from '../core/store.ts';
import { linkFor, onShares, shareNote, sharesPlace, shareWithPlace, sharingPlace, stopSharing } from './share.ts';
import styles from '../editor/NoteSettings.module.css';

/**
 * A note's sharing, in its cog (editor/NoteSettings.tsx): share it by a read-only link, copy or send the link, stop
 * sharing (share/share.ts). Signed out, the one line says where to sign in, since a share is kept with an account.
 *
 * A shared note that says where it was written (or a book with such a chapter) gets one more row, "Share where it was
 * written", with the kit's tick: the link leaves the location out until it is ticked (share.ts's header says why).
 */
export function ShareRows({ noteId }: { noteId: string }) {
  const { session } = useAccount();
  const link = useSyncExternalStore(onShares, () => linkFor(noteId), () => null);
  const withPlace = useSyncExternalStore(onShares, () => sharingPlace(noteId), () => false);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  useEffect(() => setSaid(null), [noteId]);
  // Whether the pages have a place to share: read once the note is shared, from the library as the share reads it.
  const [placed, setPlaced] = useState(false);
  useEffect(() => {
    if (!link) return undefined;
    let live = true;
    void listNotes()
      .then((notes) => {
        const note = notes.find((n) => n.id === noteId);
        if (live) setPlaced(Boolean(note) && sharesPlace(note!, notes));
      })
      .catch(() => undefined);
    return () => {
      live = false;
    };
  }, [noteId, link]);

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
                  Shared, read-only. Your edits reach readers a few seconds after you save.{placed ? (withPlace ? ' The link carries where it was written.' : ' Where it was written stays out of the link.') : ''}
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
