import { hasNativeGeneration } from '../nativeGeneration.ts';
import { readStored, readStoredText, writeStored, writeStoredText } from '../stored.ts';
import { invoke, isTauri } from '../tauri.ts';

/**
 * Where a note's versions file is kept (core/versions/file.ts): `<Title>.versions` beside the note in its library
 * folder, from the binary that has the commands for it (`VERSIONS_GENERATION`, src-tauri/src/library/versions.rs).
 * In a browser, and on a binary from before it, the page keeps the file itself under `glyph-versions-<id>`, and moves it
 * beside its note the first time it is read on a binary that can keep it there - so a history begun over the air is
 * not lost when the app updates.
 *
 * A file written here is owed to the account until sync has sent it (`unsentVersions`), so a version kept by hand,
 * with no change to the note's words, still travels (core/sync/notes.ts).
 */

/** Native generation with `versions_read` and `versions_write`. */
export const VERSIONS_GENERATION = 24;

const UNSENT = 'glyph-versions-unsent';
/** Heard when a note's versions file changes here, by sync or by a version kept: `detail` is the note's id. */
export const VERSIONS_CHANGED = 'glyph:versions-changed';

async function native(): Promise<boolean> {
  return isTauri() && (await hasNativeGeneration(VERSIONS_GENERATION));
}

/** Note `id`'s versions file, or null where it has none. */
export async function readVersionsFile(id: string): Promise<string | null> {
  const local = readStoredText(`glyph-versions-${id}`);
  if (!(await native())) return local;
  const beside = await invoke<string | null>('versions_read', { id });
  if (beside === null && local) {
    // Kept by the page before this binary could keep it beside the note: moved there now, and forgotten here.
    if (await invoke<boolean>('versions_write', { id, text: local })) writeStoredText(`glyph-versions-${id}`, null);
    return local;
  }
  return beside;
}

/** Keeps `text` as note `id`'s versions file. `owed` (the default) marks it for the next sync to send. */
export async function writeVersionsFile(id: string, text: string, { owed = true }: { owed?: boolean } = {}): Promise<void> {
  const beside = (await native()) && (await invoke<boolean>('versions_write', { id, text }));
  // No note file to keep it beside yet (a draft the binary would not write), or no binary that can: the page keeps it.
  if (!beside) writeStoredText(`glyph-versions-${id}`, text);
  if (owed) owe(id);
  window.dispatchEvent(new CustomEvent(VERSIONS_CHANGED, { detail: id }));
}

// --- what sync owes the account ----------------------------------------------------------

function unsent(): string[] {
  return readStored<string[]>(UNSENT, [], (raw) => (Array.isArray(raw) ? raw.filter((id): id is string => typeof id === 'string') : []));
}

function owe(id: string): void {
  const now = unsent();
  if (!now.includes(id)) writeStored(UNSENT, [...now, id]);
}

/** The notes whose versions file changed here since sync last sent it. */
export const unsentVersions = (): string[] => unsent();

/** Note `id`'s versions file is with the account now. */
export function sentVersions(id: string): void {
  const now = unsent();
  if (now.includes(id)) writeStored(UNSENT, now.filter((each) => each !== id));
}
