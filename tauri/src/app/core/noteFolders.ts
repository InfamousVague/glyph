import { isOrgWorkspace } from './orgs/types.ts';
import { applyNote, getNote, announceNotesChanged } from './store.ts';
import { isTauri } from './tauri.ts';
import { workspacePath } from './workspaceTree.ts';
import type { Workspace } from './workspaces.ts';

/**
 * A note's workspace decides which folder holds its file.
 *
 * Matt: "Setting a workspace should dictate the folder the note is saved in on disk
 * (workspaces/<workspace_name>/<note>.md)". The library is a folder of plain Markdown (docs/LIBRARY.md): a new note
 * is written into `Inbox/`, and the file is named after the note's title. Filing a note in a workspace now moves that
 * file into `workspaces/<the workspace>/`, and taking it out of one moves it back to `Inbox/`, so the folders a
 * person sees in Obsidian or a file manager say the same thing the pills in the app say.
 *
 * The move is the library's own: `store_apply` takes a note carrying the path it should have, and the Rust side
 * renames the file and re-indexes it (library/mod.rs `apply_note`). So this asks for a path and nothing here touches
 * the disk. Where there is no library - the browser, or a phone whose binary is older than the path field - a note
 * has no path and nothing happens.
 *
 * The workspace's name becomes a folder name, so it is cleaned the way a file name is: the characters a folder
 * cannot hold go, and a name that cleans away to nothing leaves the note where it is rather than making a folder
 * called nothing.
 *
 * An organization's workspace (core/orgs/types.ts) files under `orgs/<the organization>/` instead: its name is
 * another account's choice, and a personal workspace may be called the same (docs/TEAMS.md, D5). The folder is
 * decided from the workspace, not from a name, so no caller can file an organization's note under `workspaces/`.
 */

/** Where notes with no workspace live: the library's own landing folder (library/mod.rs `INBOX`). */
const INBOX = 'Inbox';
/** The folder the workspaces' folders sit in, as Matt asked for it. */
const WORKSPACES = 'workspaces';
/** The folder the organizations' workspaces' folders sit in. */
const ORGS = 'orgs';

/**
 * The workspace a note is filed in, as far as its folder cares: the id says whose it is, the name what it is called,
 * and the parent, for a folder inside another, whose folder it sits in.
 */
export type Filed = Pick<Workspace, 'id' | 'name' | 'parent'>;

/** A workspace's name as a folder name: what a file name may not hold is dropped, and the ends are trimmed. */
export function folderName(name: string): string {
  return name
    .replace(/[/\\:*?"<>|]/g, '')
    .replace(/\s+/g, ' ')
    .replace(/^[.\s]+|[.\s]+$/g, '')
    .slice(0, 60)
    .trim();
}

/**
 * The folder a note belongs in: its workspace's, or the inbox with no workspace. Null when the name is unusable.
 *
 * A workspace inside another (`parent`) is a folder inside its parent's, as deep as they go, as the Flutter app
 * lays them out (lib/core/note_folders.dart `folderFor`): `workspaces/Work/Clients/`, or under an organization's,
 * `orgs/Ghost.md/Clients/`. The path matters beyond this disk: a team note's row carries it, and every member's
 * device files the note by the folders it names, so a folder under an organization has to be written where the
 * phone would write it. `all` is every workspace, for the parents' names; without it, or where a parent's name
 * cleans away to nothing, the folder is at the top, as before folders were nested.
 */
export function folderFor(workspace: Filed | null, all: readonly Filed[] = []): string | null {
  if (workspace === null) return INBOX;
  const folder = folderName(workspace.name);
  if (!folder) return null;
  if (isOrgWorkspace(workspace)) return `${ORGS}/${folder}`;
  const path = all.length === 0 || !workspace.parent ? [workspace] : workspacePath(all, workspace.id);
  const steps = path.length ? path : [workspace];
  const names = steps.map((each) => folderName(each.name));
  if (names.some((name) => !name)) return `${WORKSPACES}/${folder}`;
  return `${isOrgWorkspace(steps[0]!) ? ORGS : WORKSPACES}/${names.join('/')}`;
}

/** The file's own name, without the folders: `workspaces/Home/Weekend trip.md` is `Weekend trip.md`. */
function fileName(path: string): string {
  const at = path.lastIndexOf('/');
  return at < 0 ? path : path.slice(at + 1);
}

/**
 * Moves one note's file into the folder its workspace names, if it is not there already.
 *
 * Quiet about everything it cannot do: a note with no file yet (a draft, or a browser), a name that cleans away to
 * nothing, or a library that refuses the move because something is already called that. The note's words are never
 * touched - only where the file sits.
 */
export async function fileNoteInFolder(noteId: string, workspace: Filed | null, all: readonly Filed[] = []): Promise<void> {
  const folder = folderFor(workspace, all);
  if (folder !== null) await fileNoteAt(noteId, folder);
}

/** Moves one note's file into `folder`, whatever names it. */
async function fileNoteAt(noteId: string, folder: string): Promise<void> {
  if (!isTauri()) return;
  try {
    const note = await getNote(noteId);
    if (!note?.path) return;
    const path = `${folder}/${fileName(note.path)}`;
    if (path === note.path) return;
    await applyNote({ ...note, path });
    announceNotesChanged();
  } catch (failure) {
    console.warn('[glyph] the note stayed where it was:', failure);
  }
}

/** The same for several notes at once: a workspace renamed, or taken away. */
export async function fileNotesInFolder(noteIds: readonly string[], workspace: Filed | null, all: readonly Filed[] = []): Promise<void> {
  for (const id of noteIds) await fileNoteInFolder(id, workspace, all);
}
