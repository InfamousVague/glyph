import { createPortal } from 'react-dom';
import { Archive, ArchiveRestore, ExternalLink, Pin, PinOff, Trash2 } from '@glacier/icons';
import { Menu, MenuItem, MenuSeparator } from '@glacier/react';
import { noteTitle, type Note } from '../core/store.ts';
import { closeNoteMenu, useNoteMenu } from './noteMenu.ts';
import styles from './NoteMenu.module.css';

/**
 * The note's menu at the pointer (notes/noteMenu.ts; docs/DESIGN.md §172): Open, Pin or Unpin, Archive or Unarchive,
 * and Delete in the danger tone. Each does what the card's swipe does (notes/swipe.ts) through the same actions, so a
 * deleted note goes to the Trash with an Undo (notes/useNoteActions.ts) and a right-click is never a way to lose one.
 *
 * Drawn from the kit's Menu, the tab row's menus' (notes/TabMenus.tsx), hung from a point of no size where the pointer
 * was, in a layer of its own on the body so nothing the page is drawn inside can move it.
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
    <Menu
      // A fresh menu for each right-click, so a second one somewhere else opens there.
      key={`${at.id}:${at.x}:${at.y}`}
      open
      onOpenChange={(still) => !still && closeNoteMenu()}
      trigger={<span data-note-menu-anchor="" style={{ position: 'fixed', left: at.x, top: at.y, inlineSize: 0, blockSize: 0 }} />}
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
    </Menu>,
    document.body,
  );
}
