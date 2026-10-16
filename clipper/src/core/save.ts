import { randomId } from '../../../tauri/src/app/core/ids.ts';
import { imageNames } from '../../../tauri/src/app/core/imageRefs.ts';
import type { Note } from '../../../tauri/src/app/core/store.ts';
import type { ClipperAccount } from './account.ts';
import { addToNotebook, filedIn, freeTitle, refreshLibrary, type LibraryCache } from './library.ts';
import { cleanTitle, contentOf, noteBody, type Draft } from './note.ts';
import { placePictures, resolvePictures, type LinkReason, type PictureFetcher, type Shrinker } from './pictures.ts';

/**
 * A clip saved: its pictures stored, the note written, filed in its workspace and added to its notebook, in that
 * order. The pictures go first so that no device ever meets the note with its pictures missing; a picture whose note
 * never came is a sealed file no note names, which costs the account a few kilobytes and nothing else.
 */

export interface Saved {
  id: string;
  title: string;
  stored: number;
  linked: { url: string; why: LinkReason }[];
  workspace: string | null;
  notebook: string | null;
  library: LibraryCache | null;
}

export interface SaveDeps {
  fetchers: readonly PictureFetcher[];
  shrink: Shrinker;
  now?: () => Date;
  /** The notebooks as last read, kept by the caller between clips. */
  library?: LibraryCache | null;
}

export async function saveClip(account: ClipperAccount, draft: Draft, { fetchers, shrink, now = () => new Date(), library = null }: SaveDeps): Promise<Saved> {
  const at = now();
  const placed = await resolvePictures(draft.pictures, { fetchers, shrink });
  for (const picture of placed.stored) await account.putPicture(picture.name, picture.bytes);

  // A notebook lists its pages by title: a clip going into one takes a title no other note has.
  let cache = library;
  let title = cleanTitle(draft.title, draft.url);
  if (draft.notebook) {
    cache = await refreshLibrary(account, cache);
    title = freeTitle(cache, title);
  }
  const body = noteBody({ title, url: draft.url, clipped: at, tags: draft.tags, comment: draft.comment, content: placePictures(contentOf(draft), draft.pictures, placed) });
  const ms = at.getTime();
  const note: Note = { id: randomId(), body, createdAt: ms, updatedAt: ms, source: 'editor', starred: false, archivedAt: null };
  const rev = await account.putNote(note, imageNames(body), 0);
  if (cache) cache = { ...cache, notes: { ...cache.notes, [note.id]: { rev, title } } };

  let workspace: string | null = null;
  if (draft.workspace) {
    const into = draft.workspace;
    await account.changePrefs((prefs) => filedIn(prefs, note.id, into));
    workspace = into;
  }
  let notebook: string | null = null;
  if (draft.notebook && cache) {
    cache = await addToNotebook(account, cache, draft.notebook, title);
    notebook = draft.notebook;
  }
  return { id: note.id, title, stored: placed.stored.length, linked: placed.linked.map(({ url, why }) => ({ url, why })), workspace, notebook, library: cache };
}
