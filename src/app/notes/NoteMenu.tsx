import { createPortal } from 'react-dom';
import { Archive, ArchiveRestore, ExternalLink, MessageSquarePlus, Pin, PinOff, Trash2 } from '@glacier/icons';
import { Menu, MenuItem, MenuSeparator } from '@glacier/react';
import { noteTitle, type Note } from '../core/store.ts';
import { closeNoteMenu, useNoteMenu } from './noteMenu.ts';
import styles from './NoteMenu.module.css';

/**
 * The note's menu at the pointer (notes/noteMenu.ts; docs/DESIGN.md §172): Open, Add a comment, Pin or Unpin, Archive or
 * Unarchive, and Delete in the danger tone. Add a comment opens the note with a comment started on its first line
 * (core/comments/ask.ts; Matt: "add them to the context menu for a note ... so we can quickly click to add comments"). Each does what the card's swipe does (notes/swipe.ts) through the same actions, so a
 * deleted note goes to the Trash with an Undo (notes/useNoteActions.ts) and a right-click is never a way to lose one.
 *
 * Drawn from the kit's Menu, the tab row's menus' (notes/TabMenus.tsx), hung from a point of no size where the pointer
 * was, in a layer of its own on the body so nothing the page is drawn inside can move it.
 */

interface NoteMenuHostProps {
  /** Every note a list may show, the archived among them: the menu finds the one it was opened on here. */
  notes: readonly Note[];
  onOpen: (note: Note) => void;
  /** Opens the note and starts a comment on its first line; absent, the row is not shown. */
  onComment?: (note: Note) => void;
  onPin: (note: Note) => void;
  onArchive: (note: Note, archived: boolean) => void;
  onDelete: (note: Note) => void;
}

export function NoteMenuHost({ notes, onOpen, onComment, onPin, onArchive, onDelete }: NoteMenuHostProps) {
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
      {onComment ? (
        <MenuItem icon={<MessageSquarePlus size={16} aria-hidden="true" />} onSelect={() => onComment(note)}>
          Add a comment
        </MenuItem>
      ) : null}
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
