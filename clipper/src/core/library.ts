import { isBookBody, isJournalBody, withChapter } from '../../../tauri/src/app/book/book.ts';
import { uniqueTitle } from '../../../tauri/src/app/book/journal.ts';
import { imageNames } from '../../../tauri/src/app/core/imageRefs.ts';
import { noteTitle } from '../../../tauri/src/app/core/noteTitle.ts';
import { isOrgWorkspace } from '../../../tauri/src/app/core/orgs/types.ts';
import { titleKey } from '../../../tauri/src/app/core/titleKey.ts';
import type { Note } from '../../../tauri/src/app/core/store.ts';
import { Conflict, type ClipperAccount } from './account.ts';

/**
 * Where a clip can go, read from the account as the connector reads it (mcp/server.ts): the workspaces from the
 * synced settings (core/preferences.ts `workspaces`), and the notebooks from the account's notes, a notebook being a
 * note whose front matter says `book: true` (book/book.ts). A journal is a notebook too, but its pages are entries
 * named by the minute (book/journal.ts), so it is not offered.
 *
 * Reading the notebooks means reading the account's feed, every note opened with the account key. That is done
 * once, then only what changed since (`cursor`), and what is kept of it is small: each note's title and revision,
 * and a notebook's own words, held in the browser's session memory and never on the disk. An organization's
 * workspace is not offered: a team's notes are written through the team's channel (mcp/team.ts), which the clipper
 * does not carry, and a note filed there by the settings alone would not be the team's.
 */

export interface LibraryCache {
  v: 1;
  account: number;
  cursor: number;
  /** Every note's revision and title, by id: for a title no other note has, which a notebook's links need. */
  notes: Record<string, { rev: number; title: string }>;
  /** The notebooks, with their words: what a clip filed in one is added to. */
  notebooks: Record<string, { rev: number; note: Note; journal: boolean; recording?: string }>;
}

export interface Choices {
  workspaces: { id: string; name: string }[];
  notebooks: { id: string; title: string }[];
}

export function emptyLibrary(account: number): LibraryCache {
  return { v: 1, account, cursor: 0, notes: {}, notebooks: {} };
}

/** The cache brought up to date with everything written since its cursor. */
export async function refreshLibrary(account: ClipperAccount, cache: LibraryCache | null): Promise<LibraryCache> {
  const next = cache && cache.account === account.accountId ? structuredClone(cache) : emptyLibrary(account.accountId);
  for (;;) {
    const page = await account.feed(next.cursor);
    for (const item of page.items) {
      const payload = await account.openNote(item).catch(() => null);
      delete next.notes[item.id];
      delete next.notebooks[item.id];
      if (!payload) continue;
      const note = { ...payload.note, id: item.id };
      next.notes[item.id] = { rev: item.rev, title: noteTitle(note.body) };
      if (isBookBody(note.body)) next.notebooks[item.id] = { rev: item.rev, note, journal: isJournalBody(note.body), ...(payload.recording ? { recording: payload.recording } : {}) };
    }
    next.cursor = Math.max(next.cursor, page.rev);
    if (!page.more) break;
  }
  return next;
}

function workspacesIn(prefs: Record<string, unknown>): { list: { id: string; name: string }[]; notes: Record<string, string> } {
  const held = (prefs.workspaces && typeof prefs.workspaces === 'object' ? prefs.workspaces : {}) as { list?: unknown; notes?: unknown };
  const list = (Array.isArray(held.list) ? held.list : []).filter(
    (w): w is { id: string; name: string } => Boolean(w) && typeof (w as { id?: unknown }).id === 'string' && typeof (w as { name?: unknown }).name === 'string',
  );
  const notes: Record<string, string> = {};
  if (held.notes && typeof held.notes === 'object') for (const [note, id] of Object.entries(held.notes as Record<string, unknown>)) if (typeof id === 'string') notes[note] = id;
  return { list, notes };
}

function trashIn(prefs: Record<string, unknown>): Set<string> {
  const held = prefs.trash;
  return new Set(held && typeof held === 'object' && !Array.isArray(held) ? Object.keys(held) : []);
}

/** The workspaces and notebooks the popup offers: personal workspaces, and notebooks that are not journals, archived, in the trash, or a team's. */
export function choicesOf(cache: LibraryCache, prefs: Record<string, unknown>): Choices {
  const { list, notes: filed } = workspacesIn(prefs);
  const trash = trashIn(prefs);
  const orgs = new Set(list.filter(isOrgWorkspace).map((w) => w.id));
  const workspaces = list.filter((w) => !isOrgWorkspace(w)).map((w) => ({ id: w.id, name: w.name.trim() || 'Workspace' }));
  const notebooks = Object.entries(cache.notebooks)
    .filter(([id, book]) => !book.journal && !book.note.archivedAt && !trash.has(id) && !orgs.has(filed[id] ?? '') && !(filed[id] ?? '').startsWith('org-'))
    .map(([id, book]) => ({ id, title: noteTitle(book.note.body) || 'Notebook' }))
    .sort((a, b) => a.title.localeCompare(b.title));
  return { workspaces, notebooks };
}

/** The settings with note `id` filed under workspace `into`, every other key kept (mcp/server.ts `filedIn`). */
export function filedIn(prefs: Record<string, unknown>, id: string, into: string): Record<string, unknown> {
  const held = (prefs.workspaces && typeof prefs.workspaces === 'object' ? prefs.workspaces : {}) as Record<string, unknown>;
  const { list, notes } = workspacesIn(prefs);
  if (!list.some((w) => w.id === into) || isOrgWorkspace({ id: into })) return prefs;
  return { ...prefs, workspaces: { ...held, notes: { ...notes, [id]: into } } };
}

/** A title no note in the account has yet (by the app's title key), for a page that a notebook links by its title. */
export function freeTitle(cache: LibraryCache, title: string): string {
  return uniqueTitle(title, new Set(Object.values(cache.notes).map((n) => titleKey(n.title))));
}

/**
 * `title` added to notebook `id`'s index, as a page is added in the app (book/book.ts `withChapter`), written from
 * the revision last read. Another device writing the notebook first is read again and added to, once.
 */
export async function addToNotebook(account: ClipperAccount, cache: LibraryCache, id: string, title: string): Promise<LibraryCache> {
  let current = cache;
  for (let attempt = 0; ; attempt += 1) {
    const book = current.notebooks[id];
    if (!book) throw new Error('That notebook is not in the account any more.');
    const body = withChapter(book.note.body, title);
    if (body === book.note.body) return current;
    const note: Note = { ...book.note, body, updatedAt: Math.max(Date.now(), book.note.updatedAt + 1), formatted: null, formattedFor: null, formattedModel: null };
    try {
      const rev = await account.putNote(note, imageNames(note.body), book.rev, book.recording);
      return { ...current, notebooks: { ...current.notebooks, [id]: { ...book, rev, note } }, notes: { ...current.notes, [id]: { rev, title: noteTitle(body) } } };
    } catch (failure) {
      if (!(failure instanceof Conflict) || attempt > 0) throw failure;
      current = await refreshLibrary(account, current);
    }
  }
}
