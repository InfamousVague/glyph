import { useEffect, useState, useSyncExternalStore } from 'react';
import { accountState } from '../account/account.ts';
import { onPreferences, preferences, setPreferences } from '../preferences.ts';
import { isOrgWorkspace, onWorkspaces, workspaceOf } from '../workspaces.ts';
import { readFile, withVersion, type Version } from './file.ts';
import { readVersionsFile, VERSIONS_CHANGED, writeVersionsFile } from './store.ts';

/**
 * A note's version history (Matt: "add edit history timelines to notes that are in organizations by default and allow
 * versioning on personal notes by enabling it under the more menu. We should be able to revert back to previous
 * versions like git kinda").
 *
 * Which notes keep one: a note filed in an organization's workspace does, unless it is switched off; a note of the
 * person's own does once it is switched on from its More sheet (editor/NoteSettings.tsx). Both are the `versions`
 * preference, so the choice travels with the person.
 *
 * When a version is kept: after a pause in the writing (`PAUSE_MS`), when the note is left, and by hand with a name
 * (editor/useVersionKeeping.ts) - never one of no change. Going back to a version keeps a new one with that version's
 * words, as `git revert` does, so the history only ever grows and a step back can itself be undone.
 */

/** How long the writing rests before what it wrote is kept as a version. */
export const PAUSE_MS = 2 * 60_000;

/** Whether note `id` keeps a version history, as the preferences and its workspace say now. */
export function keepsVersions(id: string): boolean {
  const said = preferences().versions[id];
  const space = workspaceOf(id);
  if (space && isOrgWorkspace(space)) return said !== false;
  return said === true;
}

/** Whether note `id` is an organization's, whose history is kept unless switched off. */
export function versionsByDefault(id: string): boolean {
  const space = workspaceOf(id);
  return Boolean(space && isOrgWorkspace(space));
}

function subscribe(listener: () => void): () => void {
  const a = onPreferences(listener);
  const b = onWorkspaces(listener);
  return () => {
    a();
    b();
  };
}

/** `keepsVersions`, kept up to date. */
export function useKeepsVersions(id: string): boolean {
  return useSyncExternalStore(subscribe, () => keepsVersions(id), () => keepsVersions(id));
}

/** Switches note `id`'s history on or off. Its versions file stays either way: switched on again, it carries on. */
export function setKeepsVersions(id: string, on: boolean): void {
  const versions = { ...preferences().versions };
  // A choice that is what the note would do anyway is not kept: an organization's note on, a note of one's own off.
  if (on === versionsByDefault(id)) delete versions[id];
  else versions[id] = on;
  setPreferences({ versions });
}

/** Who keeps a version here: the account's handle, or `me` without one. */
function keeper(): string {
  return accountState().session?.handle ?? 'me';
}

/** One write at a time per note, so two versions kept close together do not each read the file before the other wrote it. */
const writing = new Map<string, Promise<unknown>>();

function inTurn<T>(id: string, work: () => Promise<T>): Promise<T> {
  const before = writing.get(id) ?? Promise.resolve();
  const next = before.catch(() => undefined).then(work);
  writing.set(id, next);
  void next.finally(() => {
    if (writing.get(id) === next) writing.delete(id);
  });
  return next;
}

/**
 * Keeps `text` as a version of note `id`, named `label` if given, answering whether one was kept: not when the last
 * version already holds this text and no name is being given.
 */
export function keepVersion(id: string, text: string, { label, now = Date.now() }: { label?: string; now?: number } = {}): Promise<boolean> {
  return inTurn(id, async () => {
    const file = await readVersionsFile(id);
    const next = withVersion(file, id, text, { at: now, by: keeper(), ...(label ? { label } : {}) });
    if (next === null) return false;
    await writeVersionsFile(id, next);
    return true;
  });
}

/** Note `id`'s versions, oldest first, and how many of the file's versions could not be read. */
export async function versionsOf(id: string): Promise<{ versions: Version[]; damaged: number }> {
  const file = await readVersionsFile(id);
  const read = file ? readFile(file) : null;
  return { versions: read?.versions ?? [], damaged: read?.damaged ?? 0 };
}

/** Note `id`'s versions, read again whenever its file changes here. Null while the first read is under way. */
export function useVersions(id: string, open = true): { versions: Version[]; damaged: number } | null {
  const [read, setRead] = useState<{ versions: Version[]; damaged: number } | null>(null);
  useEffect(() => {
    if (!open) return;
    let live = true;
    const load = () =>
      void versionsOf(id)
        .then((next) => {
          if (live) setRead(next);
        })
        .catch(() => {
          if (live) setRead({ versions: [], damaged: 0 });
        });
    load();
    const onChanged = (event: Event) => {
      if ((event as CustomEvent<string>).detail === id) load();
    };
    window.addEventListener(VERSIONS_CHANGED, onChanged);
    return () => {
      live = false;
      window.removeEventListener(VERSIONS_CHANGED, onChanged);
    };
  }, [id, open]);
  return read;
}
