import styles from './NoNoteOpen.module.css';

/**
 * The note pane with no note in it, beside the desktop sidebar (App.tsx): on
 * launch, and after a note is closed, archived or deleted. It says where the
 * notes are and offers the two ways to start one, typed or said, the same two
 * the list's dock offers.
 */

interface NoNoteOpenProps {
  onNew: () => void;
  onCapture: () => void;
}

export function NoNoteOpen({ onNew, onCapture }: NoNoteOpenProps) {
  return (
    <div className={styles.pane}>
      <div className={styles.inner}>
        <p className={styles.lead}>No note open</p>
        <p className={styles.hint}>Pick one from the list, or start a new one.</p>
        <div className={styles.actions}>
          <button type="button" className="app-pill" onClick={onCapture}>
            Speak
          </button>
          <button type="button" className={`app-word ${styles.write}`} onClick={onNew}>
            New note
          </button>
        </div>
      </div>
    </div>
  );
}
