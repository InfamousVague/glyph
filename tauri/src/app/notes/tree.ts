import { readStored, readStoredText, writeStored, writeStoredText } from '../core/stored.ts';
import { archiveOrder, listOrder, type Note } from '../core/store.ts';
import type { Workspace } from '../core/workspaces.ts';

/**
 * The notes as the sidebar shows them: a folder for each workspace, then the notes filed in none, then the archive
 * (notes/NoteTree.tsx). Matt: "Make the sidebar on desktop the same sidebar that shows up in the pop-up sidebar. Make
 * it more similar to the obsidian sidebar", and asked, workspaces as folders in the tree.
 *
 * Pure, so the rules of what goes where are tests rather than something to click through. The order inside each
 * group is the list's own (pinned first, then the most recently touched), so a note sits in the same order in the
 * tree as it does on the phone's home screen.
 */

export interface TreeFolder {
  id: string;
  name: string;
  hue?: string;
  notes: Note[];
}

export interface Tree {
  folders: TreeFolder[];
  /** Notes filed in no workspace, or in one that has since gone. */
  loose: Note[];
  archived: Note[];
}

export function noteTree(notes: readonly Note[], spaces: { list: readonly Workspace[]; of: Record<string, string> }): Tree {
  const live = listOrder(notes);
  const known = new Set(spaces.list.map((space) => space.id));
  const folders = spaces.list.map((space) => ({
    id: space.id,
    name: space.name,
    ...(space.hue ? { hue: space.hue } : {}),
    notes: live.filter((note) => spaces.of[note.id] === space.id),
  }));
  const loose = live.filter((note) => !known.has(spaces.of[note.id] ?? ''));
  return { folders, loose, archived: archiveOrder(notes) };
}

/** The archive's place among the folders, for remembering whether it is open. */
export const ARCHIVE_FOLDER = 'archive';

/**
 * Which folders are closed, per device: how a sidebar is left is a matter of the screen it is on, not something to
 * carry to another device. The archive starts closed, everything else open.
 */
const KEY = 'glyph-tree-closed';

export function readClosed(): Set<string> {
  return new Set(readStored<string[]>(KEY, [ARCHIVE_FOLDER], (parsed) => (Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === 'string') : null)));
}

/** In private mode, the sidebar just opens as it was for this run. */
export function writeClosed(closed: ReadonlySet<string>): void {
  writeStored(KEY, [...closed]);
}

/**
 * Whether the trash's folder is open, per device, and shut until it is opened. Kept apart from the folders' own list:
 * that list stores which are shut, and a device that stored it before there was a trash would show the trash open.
 */
const TRASH_KEY = 'glyph-tree-trash-open';

export function readTrashOpen(): boolean {
  return readStoredText(TRASH_KEY) === '1';
}

/** In private mode, it opens shut next time. */
export function writeTrashOpen(open: boolean): void {
  writeStoredText(TRASH_KEY, open ? '1' : '0');
}

/** Whether the sidebar lists names only (notes/NoteTree.tsx), per device, and not until asked. */
const COMPACT_KEY = 'glyph-tree-compact';

export function readCompact(): boolean {
  return readStoredText(COMPACT_KEY) === '1';
}

/** In private mode, names only for this run. */
export function writeCompact(on: boolean): void {
  writeStoredText(COMPACT_KEY, on ? '1' : '0');
}
