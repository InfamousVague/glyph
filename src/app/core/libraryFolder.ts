import { answerHost } from './host.ts';
import { hasNativeGeneration } from './nativeGeneration.ts';
import { isAndroid, isIOS } from './platform.ts';
import { announceNotesChanged } from './store.ts';
import { invoke, isTauri } from './tauri.ts';

/** The binary with `library_root`, the folder panel and picker, the move and the way back (src-tauri/src/ota.rs). */
export const FOLDER_GENERATION = 25;

/**
 * Where the library is, and the calls that move it (src-tauri/src/library_commands.rs; docs/DESIGN.md §187), for
 * Settings › Library folder (settings/LibraryFolderPane.tsx). A plugin until §205 (Matt: "library folder should be a
 * setting not a plugin"): where the notes live is the app's own business, not an extension's.
 *
 * A folder is only ever chosen in the system's own panel (the Mac) or picker (Android, files/LibraryTree.kt): the page
 * never sends a path. It is looked into first - how many Markdown files it holds, whether Obsidian keeps it - and the
 * page says what will happen before anything does. Then `moveLibrary` moves the notes in, and the list is read again.
 */

/** Where a folder can be chosen from here: the Mac's panel, Android's picker, or nowhere yet, and why. */
export type FolderWay = 'mac' | 'android' | 'browser' | 'update' | 'none';

export async function folderWay(): Promise<FolderWay> {
  if (!isTauri()) return 'browser';
  if (isIOS) return 'none';
  if (isAndroid && typeof window.GlyphHost?.chooseLibraryFolder !== 'function') return 'update';
  if (!(await hasNativeGeneration(FOLDER_GENERATION))) return 'update';
  return isAndroid ? 'android' : 'mac';
}

/** Where the library is now (library_commands.rs `Status`). */
export interface LibraryStatus {
  kind: 'app' | 'folder' | 'tree';
  path: string | null;
  name: string | null;
  /** False while a chosen folder cannot be reached, and Ghost.md's own folder is open instead. */
  reachable: boolean;
  notes: number;
  own: string | null;
}

/** A folder picked and looked into, nothing written there yet (`Candidate`). */
export interface Candidate {
  kind: 'folder' | 'tree';
  path: string | null;
  name: string;
  markdown: number;
  obsidian: boolean;
  /** The notes that would be moved in from where the library is now. */
  notes: number;
}

/** What a move did (`Moved`). */
export interface Moved {
  notes: number;
  adopted: number;
  renamed: number;
  same: number;
  removed: number;
  status: LibraryStatus;
}

/** A failure as the page says it: Rust answers with a sentence, a page throw with an Error. */
export function failureOf(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  return 'That didn’t work.';
}

export function libraryStatus(): Promise<LibraryStatus> {
  return invoke<LibraryStatus>('library_root');
}

/** What Android's picker answered (files/LibraryTree.kt), as the page reads it. */
export type FolderAnswer = { uri: string; name: string } | { cancelled: true } | { error: string };

export function readFolderAnswer(json: string): FolderAnswer {
  const unread = { error: 'That folder can’t be used.' };
  let said: unknown;
  try {
    said = JSON.parse(json);
  } catch {
    return unread;
  }
  if (!said || typeof said !== 'object') return unread;
  const answer = said as Record<string, unknown>;
  if (answer.cancelled === true) return { cancelled: true };
  if (typeof answer.error === 'string') return { error: answer.error };
  if (typeof answer.uri === 'string' && answer.uri.startsWith('content://')) return { uri: answer.uri, name: typeof answer.name === 'string' ? answer.name : '' };
  return unread;
}

/** The picker's answer, once: the activity says it as a `libraryFolder` event. */
function pickTree(): Promise<FolderAnswer> {
  return new Promise((resolve) => {
    const stop = answerHost('libraryFolder', (json) => {
      stop();
      resolve(readFolderAnswer(json));
    });
    const started = window.GlyphHost?.chooseLibraryFolder?.() ?? 'This phone has no way to choose a folder.';
    if (started !== 'started') {
      stop();
      resolve({ error: started });
    }
  });
}

/** A folder chosen in the system's own panel or picker, and looked into; null when it was closed without one. */
export async function chooseFolder(): Promise<Candidate | null> {
  if (isAndroid) {
    const answer = await pickTree();
    if ('cancelled' in answer) return null;
    if ('error' in answer) throw answer.error;
    return invoke<Candidate>('library_inspect', { uri: answer.uri });
  }
  return invoke<Candidate | null>('library_choose_folder');
}

/** The folder looked into becomes the library; the list is read again from it. */
export async function moveLibrary(): Promise<Moved> {
  const moved = await invoke<Moved>('library_move');
  announceNotesChanged();
  return moved;
}

/** Back to Ghost.md's own folder, with a copy of every note or none. The chosen folder keeps every file. */
export async function backToOwnFolder(copy: boolean): Promise<Moved> {
  const moved = await invoke<Moved>('library_use_app_folder', { copy });
  announceNotesChanged();
  return moved;
}

const notesSaid = (n: number) => (n === 1 ? '1 note' : `${n} notes`);
const filesSaid = (n: number) => (n === 1 ? '1 Markdown file' : `${n} Markdown files`);

/** What will happen, said before it does. `fromOwn` is whether the notes are in Ghost.md's own folder now. */
export function candidateSaid(candidate: Candidate, fromOwn: boolean): string {
  const ours = candidate.notes
    ? `Your ${notesSaid(candidate.notes)} ${fromOwn ? 'move' : 'are copied'} in${candidate.markdown ? ' beside them' : ''}, in the same folders, and a note whose name is taken there gets “2” after it.`
    : 'You have no notes to bring.';
  const after = candidate.notes ? (fromOwn ? ' Once they are in, they leave Ghost.md’s own folder.' : ' The folder they are in now keeps its copy.') : '';
  if (!candidate.markdown) return `${candidate.name} is empty of notes. ${ours}${after}`;
  const vault = candidate.obsidian ? ', and Obsidian keeps it' : '';
  return `${candidate.name} has ${filesSaid(candidate.markdown)}${vault}. Each becomes a note and stays where it is, as it is. ${ours}${after}`;
}

/** What a move did, in a sentence. */
export function movedSaid(moved: Moved): string {
  const parts = [`${notesSaid(moved.notes)} moved in`];
  if (moved.adopted) parts.push(`${notesSaid(moved.adopted)} that were there already`);
  if (moved.renamed) parts.push(`${moved.renamed} renamed with a number`);
  if (moved.same) parts.push(`${moved.same} already there word for word`);
  return `${parts.join(', ')}.`;
}
