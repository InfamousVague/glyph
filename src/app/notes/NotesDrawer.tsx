import { useEffect, useRef, type ReactNode } from 'react';
import type { Note } from '../core/store.ts';
import { useBack } from '../core/back.ts';
import { NoteTree } from './NoteTree.tsx';
import styles from './NotesDrawer.module.css';

/**
 * Every note, in a card that floats over the one being read (Matt: "add a
 * sidebar that opens as a floating card, add a sidebar icon on the top left of
 * the page"). The icon is at the left of the tab row (NoteTabs.tsx); this is
 * what it opens.
 *
 * The same notes as the list screen, in its order, said shorter: a title and
 * under it the note itself drawn small, the same drawing the desktop sidebar's
 * cards carry (Matt: "the sidebar previews on mobile should match the
 * formatted versions the desktop sidebar uses"). It was one flattened line
 * before, which said what the second line of the note was and nothing about
 * its shape. A tap opens one, which also gives it a tab, so the card is a way
 * between notes rather than a way out of the one open. It closes on a tap
 * outside, on Escape or the phone's back gesture, and on opening a note.
 */

interface NotesDrawerProps {
  open: boolean;
  notes: Note[];
  activeId: string | null;
  onOpen: (id: string) => void;
  onNew: () => void;
  onClose: () => void;
  /**
   * The command palette (commands/), where a phone has no ⌘K to open it with. The drawer is the one surface that is a
   * tap away from every route, so the way in lives here rather than as a fourth button in the tab bar, where it would
   * eat the width the tabs need. Absent until the palette is mounted, and then the drawer's first row.
   */
  onCommands?: () => void;
  onSettings?: () => void;
  onSpeak?: () => void;
  /** An update or a memo waiting, on a wide window where the card stands in for the docked sidebar. */
  notices?: ReactNode;
}

export function NotesDrawer({ open, notes, activeId, onOpen, onNew, onClose, onCommands, onSettings, onSpeak, notices }: NotesDrawerProps) {
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
  // The same tree the desktop sidebar is (notes/NoteTree.tsx), in a card over the note: a close joins its tools.
  return (
    <div className={styles.over}>
      <div ref={card} className={styles.card} role="dialog" aria-modal="false" aria-label="Your notes">
        <NoteTree
          notes={notes}
          activeId={activeId}
          onOpen={onOpen}
          onNew={onNew}
          onClose={onClose}
          onCommands={
            onCommands
              ? () => {
                  onClose();
                  onCommands();
                }
              : undefined
          }
          onSettings={onSettings}
          onSpeak={onSpeak}
          notices={notices}
        />
      </div>
    </div>
  );
}
