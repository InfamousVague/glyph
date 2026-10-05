import { createPortal } from 'react-dom';
import { Archive, ArchiveRestore, ExternalLink, Pin, PinOff, Trash2 } from '@glacier/icons';
import { MenuItem, MenuSeparator } from '@glacier/react';
import { noteTitle, type Note } from '../core/store.ts';
import { PopMenu } from '../editor/PopMenu.tsx';
import { closeNoteMenu, noteMenuNow, useNoteMenu } from './noteMenu.ts';
import styles from './NoteMenu.module.css';

/**
 * The note's menu at the pointer (notes/noteMenu.ts; docs/DESIGN.md §172): Open, Pin or Unpin, Archive or Unarchive,
 * and Delete in the danger tone. Each does what the card's swipe does (notes/swipe.ts) through the same actions, so a
 * deleted note goes to the Trash with an Undo (notes/useNoteActions.ts) and a right-click is never a way to lose one.
 *
 * Drawn from the kit's Menu through editor/PopMenu.tsx, as the tab row's menus are (notes/TabMenus.tsx), hung from a
 * point of no size where the pointer was, at the body so nothing the page is drawn inside can move it (Matt: "Allow the
 * header to be overlapped by the popup menus use the glacierUI context menus"). PopMenu closes it on the back gesture
 * and Escape, on a press anywhere else heard before a card can keep it to itself, and holds it to half the window's
 * height, so a right-click near the foot turns it upward whole.
 */

interface NoteMenuHostProps {
  /** Every note a list may show, the archived among them: the menu finds the one it was opened on here. */
  notes: readonly Note[];
  onOpen: (note: Note) => void;
  onPin: (note: Note) => void;
  onArchive: (note: Note, archived: boolean) => void;
  onDelete: (note: Note) => void;
}

export function NoteMenuHost({ notes, onOpen, onPin, onArchive, onDelete }: NoteMenuHostProps) {
  const at = useNoteMenu();
  const note = at ? notes.find((each) => each.id === at.id) : undefined;
  if (!at || !note || typeof document === 'undefined') return null;
  const archived = !!note.archivedAt;
  const title = noteTitle(note.body) || 'Untitled';
  return createPortal(
    <PopMenu
      // A fresh menu for each right-click, so a second one somewhere else opens there.
      key={`${at.id}:${at.x}:${at.y}`}
      at={at}
      // Told a microtask after it closes: a right-click elsewhere has opened the next one by then, which stays.
      onDismiss={() => {
        if (noteMenuNow() === at) closeNoteMenu();
      }}
      placement="bottom-start"
      aria-label={`${title}, note`}
    >
      <MenuItem icon={<ExternalLink size={16} aria-hidden="true" />} onSelect={() => onOpen(note)}>
        Open
      </MenuItem>
      <MenuItem icon={note.starred ? <PinOff size={16} aria-hidden="true" /> : <Pin size={16} aria-hidden="true" />} onSelect={() => onPin(note)}>
        {note.starred ? 'Unpin' : 'Pin'}
      </MenuItem>
      <MenuItem icon={archived ? <ArchiveRestore size={16} aria-hidden="true" /> : <Archive size={16} aria-hidden="true" />} onSelect={() => onArchive(note, !archived)}>
        {archived ? 'Unarchive' : 'Archive'}
      </MenuItem>
      <MenuSeparator />
      <MenuItem danger className={styles.danger} icon={<Trash2 size={16} aria-hidden="true" />} onSelect={() => onDelete(note)}>
        Delete
      </MenuItem>
    </PopMenu>,
    document.body,
  );
}
