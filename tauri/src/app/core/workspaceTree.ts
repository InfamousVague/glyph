/**
 * Folders inside folders, as the Flutter app nests them (lib/core/workspaces.dart, GHST-107, 2026-10-19): a
 * workspace may have a `parent`, and an organization's workspace may be a parent, never a child. This page lists
 * workspaces flat, but it has to read the nesting the same way the phone does, because what it decides from the
 * nesting is not cosmetic: a note filed in a folder under an organization's workspace is the team's, and a device
 * that reads it as personal takes it out of the team and deletes its row for every member. That happened on
 * 2026-10-20 (GHST-108): this page's "the team's" was the id's prefix alone, so the folders the connector made
 * under three organizations looked like personal folders here, and 160 team notes were gone within the hour.
 *
 * Pure functions over a list of workspaces, so the store (core/workspaces.ts) and the folders on disk
 * (core/noteFolders.ts) share them without importing each other.
 */
import { orgIdOf } from './orgs/types.ts';

/** What the walk needs of a workspace: its id and, for a folder inside another, its parent's. */
export interface Nested {
  id: string;
  parent?: string;
}

/**
 * The organization a workspace is in, by id: the organization's for its own workspace, the same for a folder under
 * it however deep, and null for a personal workspace, an id the list does not have, or a parent chain that loops.
 */
export function orgOfWorkspace(list: readonly Nested[], id: string): string | null {
  const byId = new Map(list.map((w) => [w.id, w]));
  const seen = new Set<string>();
  let at = byId.get(id);
  while (at && !seen.has(at.id)) {
    seen.add(at.id);
    const org = orgIdOf(at.id);
    if (org !== null) return org;
    at = at.parent ? byId.get(at.parent) : undefined;
  }
  return null;
}

/** The workspaces `id` stands over: itself first, then every folder inside it, however deep. */
export function workspaceFamily(list: readonly Nested[], id: string): string[] {
  const out = [id];
  for (let at = 0; at < out.length; at += 1) {
    for (const w of list) if (w.parent === out[at] && !out.includes(w.id)) out.push(w.id);
  }
  return out;
}

/** The workspaces from the top down to `id`, itself last; empty for an id the list does not have. */
export function workspacePath<T extends Nested>(list: readonly T[], id: string): T[] {
  const byId = new Map(list.map((w) => [w.id, w]));
  const path: T[] = [];
  let at = byId.get(id);
  while (at && !path.includes(at)) {
    path.unshift(at);
    at = at.parent ? byId.get(at.parent) : undefined;
  }
  return path;
}

/**
 * The folders a team note's path names inside its organization's, in order (lib/core/note_folders.dart
 * `orgFolderNames`): `orgs/Ghost.md/Clients/Acme/Plan.md` is `['Clients', 'Acme']`. Empty for a note at the
 * organization's own folder, for one whose path is not under `orgs/` at all, and for no path.
 */
export function orgFolderNames(path: string | null | undefined): string[] {
  if (!path || !path.startsWith('orgs/')) return [];
  const parts = path.split('/');
  // 'orgs', the organization's folder, the folders between, the file.
  return parts.length > 3 ? parts.slice(2, -1).filter((name) => name.length > 0) : [];
}
