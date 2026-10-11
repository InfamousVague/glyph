import { History, X } from '@glacier/icons';
import { useLiveNote } from '../core/versions/live.ts';
import { setKeepsVersions, useKeepsVersions } from '../core/versions/record.ts';
import { VersionHistory } from '../editor/VersionHistory.tsx';
import styles from './Aside.module.css';

/**
 * The open note's version history in the desktop's aside (Matt: "make a sidebar that can be expanded on desktop to see
 * the version history"): the More sheet's timeline (editor/VersionHistory.tsx), beside the note rather than over it,
 * so a version can be read against the words while they are still on screen. It compares with the editor's words and
 * restores through the editor (core/versions/live.ts), so a restore here is one change to undo, as it is there. A
 * note that keeps no history says so, with the way to start one.
 */
export function AsideHistory({ noteId, title, onClose }: { noteId: string; title: string; onClose?: () => void }) {
  const keeps = useKeepsVersions(noteId);
  const live = useLiveNote(noteId);
  return (
    <div className={styles.history}>
      <div className={styles.head}>
        <span className={styles.headButton}>
          <History size={15} aria-hidden="true" />
          <span className={styles.headTitle}>Version history</span>
        </span>
        {onClose ? (
          <button type="button" className={styles.close} onClick={onClose} aria-label="Close">
            <X size={16} aria-hidden="true" />
          </button>
        ) : null}
      </div>
      {!keeps ? (
        <div className={styles.historyOff}>
          <p className={styles.empty}>This note keeps no version history.</p>
          <button type="button" className={styles.historyOn} onClick={() => setKeepsVersions(noteId, true)}>
            Keep version history
          </button>
          <p className={styles.historyWhy}>A version is saved as you write, to go back to like git. It is kept beside the note as a .versions file.</p>
        </div>
      ) : live ? (
        <VersionHistory noteId={noteId} title={title} current={live.current} onRestore={live.restore} />
      ) : (
        <p className={styles.empty}>Reading the note…</p>
      )}
    </div>
  );
}
