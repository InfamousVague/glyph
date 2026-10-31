import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { canvasOf, type Canvas } from '../../src/app/canvas/jsonCanvas.ts';
import { isBookBody } from '../../src/app/book/book.ts';
import { noteTitle } from '../../src/app/core/noteTitle.ts';
import { isTicket, ticketIdOf } from '../../src/app/core/properties.ts';
import { titleKey } from '../../src/app/core/titleKey.ts';
import { slugOf } from '../../src/read/slugs.ts';
import type { PublishConfig } from './config.ts';
import { isOn, listOf, pageText, readFrontMatter, type FrontMatter } from './frontMatter.ts';
import { transcriptOf } from './meeting.ts';

/**
 * A Library folder read as a site's pages (docs/MARKDOWN_FIRST.md §6, the target layout): every `.md` not under a dot
 * folder or `.trash/` is a page at `<folder>/<slug>.html`, its folders the sidebar, its front matter (frontMatter.ts)
 * its properties; `image/`, `file/`, `video/` and `recordings/` beside the notes are where its pictures, files, films
 * and tapes are. What a page IS - words, a ticket, a canvas, a meeting, a notebook - is decided here once, from the
 * app's own readers (canvas/jsonCanvas.ts, core/properties.ts, book/book.ts), so every later step asks the page.
 *
 * `README.md` at the root is the git plugin's note to whoever opens the repository, not a page (§12, the critic's
 * medium finding), and is left out.
 */

export type PageKind = 'note' | 'ticket' | 'canvas' | 'meeting' | 'notebook';

export interface Page {
  /** The file, from the library's root, with `/` between folders. */
  file: string;
  /** Its folders, from the root: `['workspaces', 'Work']`; `[]` for a note at the root. */
  folder: string[];
  title: string;
  /** Its address on the site, from the site's root: `workspaces/work/the-plan.html`. */
  href: string;
  kind: PageKind;
  front: FrontMatter;
  /** The note's text without the library's block: what the app's readers are given. */
  text: string;
  /** The words after every block: what is drawn. */
  body: string;
  pinned: boolean;
  /** Other names a `[[link]]` may use (`aliases:`). */
  aliases: string[];
  /** A ticket's key, `GHO-12`. */
  issue: string | null;
  /** When it was last changed: `updated:` where the library wrote one, the file's time otherwise. */
  updatedAt: number;
  createdAt: number;
  /** A canvas: the `.canvas` sidecar beside the note where there is one, else the JSON the note holds. */
  canvas: Canvas | null;
  /** A meeting's transcript, read from its words (meeting.ts). */
  transcript: ReturnType<typeof transcriptOf> | null;
  /** The library's id, for its tape at `recordings/<id>.wav`. */
  id: string | null;
}

export interface Folder {
  name: string;
  path: string[];
  pages: Page[];
  folders: Folder[];
}

export interface Library {
  root: string;
  pages: Page[];
  /** The folder tree: the root's pages, and its folders in the sidebar's order. */
  tree: Folder;
  /** Files the notes link, `image/<name>` and the like, that are there: path from the root to its bytes' path. */
  files: Map<string, string>;
}

const PUBLISHED_KINDS = ['image', 'file', 'video', 'recordings'] as const;

/** A folder the walk goes into: not a dot folder, and `.trash/` never. */
function published(name: string): boolean {
  return !name.startsWith('.');
}

function* walk(root: string, dir: string): Generator<string> {
  for (const name of readdirSync(dir).sort()) {
    const path = join(dir, name);
    const stat = statSync(path);
    if (stat.isDirectory()) {
      if (published(name) && !(PUBLISHED_KINDS as readonly string[]).includes(relative(root, path).split(sep)[0]!)) yield* walk(root, path);
    } else if (stat.isFile() && name.endsWith('.md') && !name.startsWith('.')) yield path;
  }
}

/** Whether a folder path is one the config publishes. */
export function publishes(folder: readonly string[], config: PublishConfig): boolean {
  if (folder[0] === 'orgs') {
    if (config.orgs === false) return false;
    if (Array.isArray(config.orgs)) return folder.length > 1 && config.orgs.includes(folder[1]!);
    return true;
  }
  if (!config.folders) return true;
  const path = folder.join('/');
  return config.folders.some((allowed) => allowed === '' || path === allowed || path.startsWith(`${allowed}/`) || (folder.length === 0 && allowed === '.'));
}

function timeOf(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const at = Date.parse(value);
  return Number.isFinite(at) ? at : fallback;
}

/** A page's address: each folder's slug, then the title's, unique among the pages of its folder. */
function hrefOf(folder: readonly string[], title: string, taken: Set<string>): string {
  const dir = folder.map((name) => slugOf(name) || 'folder').join('/');
  const base = slugOf(title) || 'page';
  let slug = base;
  for (let n = 2; taken.has(`${dir}/${slug}`); n += 1) slug = `${base}-${n}`;
  taken.add(`${dir}/${slug}`);
  return dir ? `${dir}/${slug}.html` : `${slug}.html`;
}

/** The library at `root`, read whole. */
export function readLibrary(root: string, config: PublishConfig): Library {
  const pages: Page[] = [];
  const taken = new Set<string>();
  for (const path of walk(root, root)) {
    const file = relative(root, path).split(sep).join('/');
    const folder = file.split('/').slice(0, -1);
    if (folder.length === 0 && file === 'README.md') continue;
    if (!publishes(folder, config)) continue;
    const raw = readFileSync(path, 'utf8');
    const front = readFrontMatter(raw);
    // `private: true` keeps a note off the site, whichever folder it is in (config.ts).
    if (isOn(front.page.private)) continue;
    const text = pageText(raw);
    const title = noteTitle(text) || file.split('/').pop()!.replace(/\.md$/, '');
    const stat = statSync(path);
    const sidecar = path.replace(/\.md$/, '.canvas');
    let canvas: Canvas | null = null;
    if (existsSync(sidecar)) canvas = canvasOf(readFileSync(sidecar, 'utf8'));
    if (!canvas) canvas = canvasOf(text);
    const transcript = canvas ? null : transcriptOf(front.body, front.page);
    const kind: PageKind = canvas ? 'canvas' : transcript ? 'meeting' : isTicket(text) ? 'ticket' : isBookBody(text) ? 'notebook' : 'note';
    pages.push({
      file,
      folder,
      title,
      href: hrefOf(folder, title, taken),
      kind,
      front,
      text,
      body: front.body,
      pinned: isOn(front.managed.pinned) || isOn(front.page.pinned),
      aliases: listOf(front.page.aliases),
      issue: front.page.issue ?? (isTicket(text) ? ticketIdOf(text) : null),
      updatedAt: timeOf(front.managed.updated ?? front.page.updated, stat.mtimeMs),
      createdAt: timeOf(front.managed.created ?? front.page.created, stat.birthtimeMs || stat.mtimeMs),
      canvas,
      transcript,
      id: front.managed.id ?? null,
    });
  }
  const files = new Map<string, string>();
  for (const kind of PUBLISHED_KINDS) {
    const dir = join(root, kind);
    if (!existsSync(dir) || !statSync(dir).isDirectory()) continue;
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isFile() && !name.startsWith('.')) files.set(`${kind}/${name}`, path);
    }
  }
  return { root, pages, tree: treeOf(pages), files };
}

/** The sidebar's order of the root's folders: Inbox, then the workspaces, then organizations, then anything else. */
const ROOT_ORDER = ['Inbox', 'workspaces', 'orgs'];

function rank(name: string): number {
  const at = ROOT_ORDER.indexOf(name);
  return at >= 0 ? at : ROOT_ORDER.length;
}

/** Pinned first, then by title, as the sidebar lists a folder's pages. */
export function byPinnedThenTitle(a: Page, b: Page): number {
  return Number(b.pinned) - Number(a.pinned) || a.title.localeCompare(b.title, undefined, { sensitivity: 'base' }) || a.file.localeCompare(b.file);
}

function treeOf(pages: readonly Page[]): Folder {
  const root: Folder = { name: '', path: [], pages: [], folders: [] };
  for (const page of pages) {
    let at = root;
    for (const name of page.folder) {
      let next = at.folders.find((f) => f.name === name);
      if (!next) {
        next = { name, path: [...at.path, name], pages: [], folders: [] };
        at.folders.push(next);
      }
      at = next;
    }
    at.pages.push(page);
  }
  const sort = (folder: Folder, top: boolean) => {
    folder.pages.sort(byPinnedThenTitle);
    folder.folders.sort((a, b) => (top ? rank(a.name) - rank(b.name) : 0) || a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
    for (const child of folder.folders) sort(child, false);
  };
  sort(root, true);
  return root;
}

/** The pages by every name a `[[link]]` may use: the title's key, each alias's, and a ticket's key. */
export function namesOf(pages: readonly Page[]): Map<string, Page[]> {
  const out = new Map<string, Page[]>();
  const add = (name: string, page: Page) => {
    const key = titleKey(name);
    if (!key) return;
    const list = out.get(key) ?? [];
    if (!list.includes(page)) list.push(page);
    out.set(key, list);
  };
  for (const page of pages) {
    add(page.title, page);
    for (const alias of page.aliases) add(alias, page);
    if (page.issue) add(page.issue, page);
  }
  return out;
}
