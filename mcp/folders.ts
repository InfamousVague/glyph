import { isOrgWorkspace, orgIdOf } from '../tauri/src/app/core/orgs/types.ts';

/**
 * Folders inside folders, as the connector reads and writes them (GHST-108; docs/FEATURES_2_1.md, "Folders inside
 * folders" and "Folders inside an organization's workspace"). A port of the app's rules, kept the same line for line:
 * lib/core/workspaces.dart (`orgOfWorkspace`, `workspaceFamily`, `workspacePath`, `canMove`, `addWorkspace`'s ids),
 * lib/core/note_folders.dart (`folderName`, `folderFor`, `orgFolderNames`) and the library's file names
 * (tauri/src-tauri/src/library/names.rs `file_stem`).
 *
 * A folder is a workspace with a `parent`, another workspace's id, kept in the synced settings beside its name. An
 * organization's own workspace (`org-<orgId>`) may be a parent, never a child, and a folder under it, however deep, is
 * the team's: a team note's folder is its file's path (`orgs/Ghost.md/Clients/Acme/Plan.md`), which rides in the
 * team's row, so every member's device files it the same (lib/team/folders.dart).
 */

/** A workspace as the settings keep it: every field it came with is kept, known here or not. */
export interface Kept {
  id: string;
  name: string;
  hue?: string;
  parent?: string;
  [key: string]: unknown;
}

const INBOX = 'Inbox';
const WORKSPACES = 'workspaces';
const ORGS = 'orgs';

/** A workspace's name as a folder name: what a file name may not hold is dropped, and the ends trimmed (`folderName`). */
export function folderName(name: string): string {
  const clean = name
    .replace(/[/\\:*?"<>|]/g, '')
    .replace(/\s+/g, ' ')
    .replace(/^[.\s]+|[.\s]+$/g, '');
  return (clean.length > 60 ? clean.slice(0, 60) : clean).trim();
}

/** A name as the app tidies one before keeping it: spaces collapsed, ends trimmed (workspaces.dart `_tidy`). */
export function tidyName(name: string): string {
  return name.replace(/\s+/g, ' ').trim();
}

const MAX_STEM = 80;

/** A note's title as its file's name, without `.md` (library/names.rs `file_stem`). */
export function fileStem(title: string): string {
  const cleaned = [...title]
    .filter((c) => !'/\\:*?"<>|#^[]'.includes(c) && !/\p{Cc}/u.test(c))
    .join('')
    .replaceAll('**', '')
    .replaceAll('__', '');
  let stem = cleaned.split(/\s+/).filter(Boolean).join(' ');
  const chars = [...stem];
  if (chars.length > MAX_STEM) {
    const cut = chars.slice(0, MAX_STEM).join('');
    const at = cut.lastIndexOf(' ');
    stem = at > MAX_STEM / 2 ? cut.slice(0, at) : cut;
  }
  stem = stem.replace(/[. ]+$/, '').replace(/^\.+/, '').trim();
  return stem || 'Untitled';
}

/**
 * The list as the app reads it (workspaces.dart `_read`): a parent that is gone, a parent on an organization's own
 * workspace, or a loop back to itself is no parent, and the folder is at the top.
 */
export function effective<T extends Kept>(list: readonly T[]): T[] {
  const ids = new Set(list.map((w) => w.id));
  const byId = new Map(list.map((w) => [w.id, w]));
  const loops = (w: T): boolean => {
    const seen = new Set([w.id]);
    let at = w.parent ? byId.get(w.parent) : undefined;
    while (at) {
      if (seen.has(at.id)) return true;
      seen.add(at.id);
      at = at.parent ? byId.get(at.parent) : undefined;
    }
    return false;
  };
  return list.map((w) => {
    if (typeof w.parent !== 'string' || !w.parent) {
      if (w.parent === undefined) return w;
      const { parent: _gone, ...rest } = w;
      return rest as T;
    }
    if (!ids.has(w.parent) || isOrgWorkspace(w) || loops(w)) {
      const { parent: _gone, ...rest } = w;
      return rest as T;
    }
    return w;
  });
}

/** The organization a workspace is in, walking its parents up to an organization's own workspace (`orgOfWorkspace`). */
export function orgOf(list: readonly Kept[], id: string): string | null {
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

/** The workspaces `id` stands over, itself first, then every folder inside it however deep (`workspaceFamily`). */
export function workspaceFamily(list: readonly Kept[], id: string): string[] {
  const out = [id];
  for (let at = 0; at < out.length; at += 1) {
    for (const w of list) if (w.parent === out[at] && !out.includes(w.id)) out.push(w.id);
  }
  return out;
}

/** The workspaces from the top down to `id`, itself last; empty for an id the list does not have (`workspacePath`). */
export function workspacePath<T extends Kept>(list: readonly T[], id: string): T[] {
  const byId = new Map(list.map((w) => [w.id, w]));
  const path: T[] = [];
  let at = byId.get(id);
  while (at && !path.includes(at)) {
    path.unshift(at);
    at = at.parent ? byId.get(at.parent) : undefined;
  }
  return path;
}

/** "Ghost.md › Clients › Acme": a workspace's name with its parents' before it (`workspacePathName`). */
export function pathName(list: readonly Kept[], id: string): string {
  return workspacePath(list, id)
    .map((w) => w.name)
    .join(' › ');
}

/**
 * The folder a note in `workspace` belongs in on disk, or the inbox for none; null when its name is unusable
 * (note_folders.dart `folderFor`): `workspaces/Work/Clients`, or `orgs/Ghost.md/Clients/Acme` under an organization's.
 */
export function folderFor(workspace: Kept | null, all: readonly Kept[] = []): string | null {
  if (!workspace) return INBOX;
  const folder = folderName(workspace.name);
  if (!folder) return null;
  if (isOrgWorkspace(workspace)) return `${ORGS}/${folder}`;
  const path = all.length === 0 || !workspace.parent ? [workspace] : workspacePath(all, workspace.id);
  const chain = path.length ? path : [workspace];
  const names = chain.map((each) => folderName(each.name));
  if (names.some((name) => !name)) return `${WORKSPACES}/${folder}`;
  return `${isOrgWorkspace(chain[0]!) ? ORGS : WORKSPACES}/${names.join('/')}`;
}

/** The folders a team note's path names inside its organization's (`orgFolderNames`): `['Clients', 'Acme']`. */
export function orgFolderNames(path: string | null | undefined): string[] {
  if (!path) return [];
  const parts = path.split('/');
  if (parts.length < 4 || parts[0] !== ORGS) return [];
  return parts.slice(2, parts.length - 1).filter(Boolean);
}

/** The file's own name, without the folders; for a note with no path yet, the one the library would give it. */
export function fileNameOf(path: string | null | undefined, title: string): string {
  if (path) {
    const at = path.lastIndexOf('/');
    const name = at < 0 ? path : path.slice(at + 1);
    if (name) return name;
  }
  return `${fileStem(title)}.md`;
}

/**
 * The folder workspace a team note's path files it in, as a member's device finds it (lib/team/folders.dart
 * `_find`): each name, under the organization's workspace and then under each in turn, matched by its folder's name,
 * then ignoring case. As deep as the names are found; the organization's workspace itself for none.
 */
export function folderAtPath(list: readonly Kept[], root: string, names: readonly string[]): string {
  let at = root;
  for (const name of names) {
    const inside = list.filter((w) => w.parent === at);
    const found = inside.find((w) => folderName(w.name) === name) ?? inside.find((w) => folderName(w.name).toLowerCase() === name.toLowerCase());
    if (!found) break;
    at = found.id;
  }
  return at;
}

/**
 * Whether `id` may be put inside `parent` (null, the top), as the app allows (`canMove`): never an organization's own
 * workspace; never into itself or a folder inside it; and in the same organization as it is now, or in none.
 */
export function canMove(list: readonly Kept[], id: string, parent: string | null): boolean {
  if (orgIdOf(id) !== null) return false;
  if (!list.some((w) => w.id === id)) return false;
  const org = orgOf(list, id);
  if (parent === null) return org === null;
  if (!list.some((w) => w.id === parent) || orgOf(list, parent) !== org) return false;
  return !workspaceFamily(list, id).includes(parent);
}

/** A fresh workspace id in the app's shape (`_freshId`): `w-` and six letters or digits, none the list has. */
export function freshId(list: readonly Kept[], random: () => number = Math.random): string {
  const letters = '0123456789abcdefghijklmnopqrstuvwxyz';
  for (;;) {
    let id = 'w-';
    for (let i = 0; i < 6; i += 1) id += letters[Math.floor(random() * letters.length)];
    if (!list.some((w) => w.id === id)) return id;
  }
}
