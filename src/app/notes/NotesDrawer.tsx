import { useEffect, useRef } from 'react';
import { Plus, X } from '@glacier/icons';
import { noteTitle, notePreview, type Note } from '../core/store.ts';
import { useBack } from '../core/back.ts';
import styles from './NotesDrawer.module.css';

/**
 * Every note, in a card that floats over the one being read (Matt: "add a
 * sidebar that opens as a floating card, add a sidebar icon on the top left of
 * the page"). The icon is at the left of the tab row (NoteTabs.tsx); this is
 * what it opens.
 *
 * The same notes as the list screen, in its order, said shorter: a title and
 * the line under it. A tap opens one, which also gives it a tab, so the card
 * is a way between notes rather than a way out of the one open. It closes on
 * a tap outside, on Escape or the phone's back gesture, and on opening a note.
 */

interface NotesDrawerProps {
  open: boolean;
  notes: Note[];
  activeId: string | null;
  onOpen: (id: string) => void;
  onNew: () => void;
  onClose: () => void;
}

export function NotesDrawer({ open, notes, activeId, onOpen, onNew, onClose }: NotesDrawerProps) {
  const card = useRef<HTMLDivElement>(null);
  // The phone's back gesture and Escape close the card before they leave the note.
  useBack(open, onClose);

  useEffect(() => {
    if (!open) return undefined;
    const outside = (event: PointerEvent) => {
      if (!card.current?.contains(event.target as Node)) onClose();
    };
    // On the next frame: the press that opened it would otherwise close it again.
    const timer = window.setTimeout(() => document.addEventListener('pointerdown', outside), 0);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener('pointerdown', outside);
    };
  }, [open, onClose]);

  if (!open) return null;
  return (
    <div className={styles.over}>
      <div ref={card} className={styles.card} role="dialog" aria-modal="false" aria-label="Your notes">
        <div className={styles.top}>
          <h2 className={styles.title}>Notes</h2>
          <button type="button" className={styles.round} onClick={onNew} aria-label="New note">
            <Plus size={18} strokeWidth={2.2} aria-hidden="true" />
          </button>
          <button type="button" className={styles.round} onClick={onClose} aria-label="Close">
            <X size={18} strokeWidth={2.2} aria-hidden="true" />
          </button>
        </div>
        <ul className={styles.list}>
          {notes.map((note) => {
            const title = noteTitle(note.body);
            const line = notePreview(note.body);
            return (
              <li key={note.id}>
                <button type="button" className={styles.row} data-active={note.id === activeId || undefined} onClick={() => onOpen(note.id)}>
                  <span className={styles.rowTitle}>{title || 'Untitled'}</span>
                  {line ? <span className={styles.rowLine}>{line}</span> : null}
                </button>
              </li>
            );
          })}
          {notes.length ? null : <li className={styles.empty}>No notes yet.</li>}
        </ul>
      </div>
    </div>
  );
}
