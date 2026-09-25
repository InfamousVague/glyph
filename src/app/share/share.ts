import { call } from '../core/account/api.ts';
import { accountState } from '../core/account/account.ts';
import { fromBase64Url, openBytes, sealBytes, toBase64Url, type Bytes } from '../core/sync/crypto.ts';
import { imageBytes, imageNames, keepImage, smallerImage } from '../core/images.ts';
import { withFrontMatterTitle, frontMatterValue } from '../core/frontMatter.ts';
import { listNotes, newNoteId, noteTitle, saveNote, NOTE_SAVED, NOTES_CHANGED, type Note } from '../core/store.ts';
import { onPreferences, preferences, setPreferences } from '../core/preferences.ts';
import { readStored, writeStored } from '../core/stored.ts';
import { chaptersOf, isBookBody } from '../book/book.ts';
import { sameTitle } from '../editor/wikiLinks.ts';
import { zipFiles } from './zip.ts';

/**
 * Sharing a note or a book by its link (docs/SHARING.md).
 *
 * Matt: "share books and notes with people online and allow them to read only the notes and give them areas to fork
 * the note into their own Ghost.md app". His choices: anyone with the link reads it, and the server cannot; what is
 * shared follows the owner's edits; readers open a small page of its own made of the app's parts; and a reader can
 * save a copy into their own Ghost.md or download it as Markdown.
 *
 * So a share is sealed on the device under a key made for that share alone, and the key rides in the link after the
 * `#`, which a browser never sends to a server: the link is the only way in, and the service (server/src/shares.rs)
 * keeps ciphertext it cannot open, as it does a synced note. A book is shared whole - its index and every chapter
 * that has a note - so the reader can turn its pages. This device keeps which of its notes it has shared, with each
 * share's key, and writes a share again a few seconds after any save that changed what it holds.
 */

/** What a share holds, sealed. A note is one page; a book is its index first, then its chapters in order. */
export interface Shared {
  v: 1;
  kind: 'note' | 'book';
  title: string;
  pages: { title: string; body: string }[];
  /** When it was written, in ms. */
  at: number;
  /**
   * The pictures its pages show, by name (`![…](image/<name>)`, core/images.ts). Carried in the share itself: a
   * reader has no account to fetch them from, and the server keeps the share whole or not at all.
   */
  pictures?: Record<string, Bytes>;
}

/** The context a share is sealed in: a synced note's ciphertext cannot be passed off as a share, nor the reverse. */
const CONTEXT = 'glyph/v1/share';

/**
 * Where a reader reads: the small page (read.html), on ghostmarkdown.com (Matt: "The ghost markdown.com page isn't
 * opening my read notes"). The page is the release's own, served there too (scripts/deploy-landing.mjs), so a link from
 * before, on attack.fm/glyph/read.html, opens the same share as well: the id and key after the # are the whole link.
 */
export const READER_URL: string =
  (import.meta.env.VITE_GLYPH_READER as string | undefined)?.replace(/\/+$/, '') || 'https://ghostmarkdown.com/read.html';

// ---- keys, ids and links --------------------------------------------------------------------

function random(bytes: number): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(bytes);
  crypto.getRandomValues(out);
  return out;
}

/** A share's id: 128 random bits, base64url. */
export function newShareId(): string {
  return toBase64Url(random(16));
}

/** A share's key: 256 random bits, base64url, carried in the link and nowhere else but this device. */
export function newShareKey(): string {
  return toBase64Url(random(32));
}

function keyOf(key: string): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', fromBase64Url(key), { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}

/**
 * A share with pictures, sealed: `GSP1`, the length of what follows as four bytes, the share's words as JSON (with
 * each picture's name and size where the pictures were), and then the pictures' bytes one after another. Pictures
 * sealed as base64 inside the JSON would be encoded twice over, since the sealed share goes to the server as base64
 * again, and the server's limit is on that text. A share with no pictures is its JSON alone, as it always was.
 */
const PICTURED = [0x47, 0x53, 0x50, 0x31];
/** The longest share the server keeps (server/src/shares.rs `SHARE_LIMIT`), in the base64url characters it counts. */
export const SHARE_LIMIT = 6_000_000;
/** What a share may hold before it is sealed and encoded: three quarters of the limit, less room for the seal. */
export const SHARE_BYTES = 4_400_000;
/** A picture's name as a note writes it: nothing a share could use to reach outside the picture store. */
const PICTURE_NAME = /^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}$/;

export async function sealShare(shared: Shared, key: string): Promise<string> {
  const { pictures = {}, ...words } = shared;
  const names = Object.keys(pictures);
  if (!names.length) return toBase64Url(await sealBytes(await keyOf(key), new TextEncoder().encode(JSON.stringify(words)), CONTEXT));
  const head = new TextEncoder().encode(JSON.stringify({ ...words, pictures: names.map((name) => [name, pictures[name]!.length]) }));
  const out = new Uint8Array(8 + head.length + names.reduce((sum, name) => sum + pictures[name]!.length, 0));
  out.set(PICTURED, 0);
  new DataView(out.buffer).setUint32(4, head.length);
  out.set(head, 8);
  let at = 8 + head.length;
  for (const name of names) {
    out.set(pictures[name]!, at);
    at += pictures[name]!.length;
  }
  return toBase64Url(await sealBytes(await keyOf(key), out, CONTEXT));
}

export async function openShare(blob: string, key: string): Promise<Shared> {
  const bytes = await openBytes(await keyOf(key), fromBase64Url(blob), CONTEXT);
  let shared: Shared;
  if (PICTURED.every((byte, i) => bytes[i] === byte)) {
    const length = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(4);
    const head = JSON.parse(new TextDecoder().decode(bytes.subarray(8, 8 + length))) as Omit<Shared, 'pictures'> & { pictures?: [string, number][] };
    const pictures: Record<string, Bytes> = {};
    let at = 8 + length;
    for (const [name, size] of Array.isArray(head.pictures) ? head.pictures : []) {
      if (typeof name === 'string' && PICTURE_NAME.test(name) && Number.isInteger(size) && size > 0) pictures[name] = bytes.slice(at, at + size);
      at += Number(size) || 0;
    }
    shared = { ...head, pictures };
  } else {
    shared = JSON.parse(new TextDecoder().decode(bytes)) as Shared;
  }
  if (shared?.v !== 1 || !Array.isArray(shared.pages)) throw new Error('This link was shared by a newer Ghost.md. Update the app to read it.');
  return shared;
}

/**
 * `shared` with the pictures its pages show, read from this device (`read`), as many as the share can hold: as they
 * are kept if they fit, else each drawn smaller (`smaller`), else as many as fit in the order the pages show them. A
 * picture this device does not have is left out, and the reader sees it missing, as the owner's other devices would;
 * those are answered as `lacked`, so the share is sent again when one arrives (`refreshShares`).
 */
export async function withPictures(
  shared: Shared,
  deps: { read: (name: string) => Promise<Bytes | null>; smaller: (bytes: Bytes) => Promise<Bytes> } = {
    read: imageBytes,
    smaller: (bytes) => smallerImage(bytes, 1024, 0.72),
  },
  budget = SHARE_BYTES,
): Promise<{ shared: Shared; lacked: string[] }> {
  const names = [...new Set(shared.pages.flatMap((page) => imageNames(page.body)))];
  if (!names.length) return { shared, lacked: [] };
  let found: [string, Bytes][] = [];
  const lacked: string[] = [];
  for (const name of names) {
    const bytes = await deps.read(name).catch(() => null);
    if (bytes?.length) found.push([name, bytes]);
    else lacked.push(name);
  }
  const room = budget - new TextEncoder().encode(JSON.stringify(shared)).length;
  const size = (list: [string, Bytes][]) => list.reduce((sum, [, bytes]) => sum + bytes.length, 0);
  if (size(found) > room) {
    // Too much to carry as kept: a reading copy of each, smaller.
    const smaller: [string, Bytes][] = [];
    for (const [name, bytes] of found) smaller.push([name, await deps.smaller(bytes).catch(() => bytes)]);
    found = smaller;
  }
  const pictures: Record<string, Bytes> = {};
  let used = 0;
  for (const [name, bytes] of found) {
    if (used + bytes.length > room) continue;
    pictures[name] = bytes;
    used += bytes.length;
  }
  return { shared: Object.keys(pictures).length ? { ...shared, pictures } : shared, lacked };
}

/** Sealed for the server, or a refusal a person can read when even the words are more than a share holds. */
async function sealForServer(shared: Shared, key: string): Promise<string> {
  const blob = await sealShare(shared, key);
  if (blob.length > SHARE_LIMIT) throw new Error('That is more than a share can hold, even with its pictures drawn smaller. Share a chapter, or fewer of them.');
  return blob;
}

/** The link a reader opens: the reader page, and after the `#` the share's id and key. */
export function shareLink(id: string, key: string): string {
  return `${READER_URL}#${id}.${key}`;
}

const LINKED = /([A-Za-z0-9_-]{22,64})\.([A-Za-z0-9_-]{43})(?![A-Za-z0-9_-])/;

/** A share's id and key out of a link, or out of what follows its `#`; null when it holds none. */
export function readShareLink(text: string): { id: string; key: string } | null {
  const hash = text.includes('#') ? text.slice(text.indexOf('#') + 1) : text;
  const found = LINKED.exec(hash.trim());
  return found ? { id: found[1]!, key: found[2]! } : null;
}

// ---- what a note or a book shares ---------------------------------------------------------------

/** What `note` shares: itself, or a book's index and every chapter that has a note, found among `notes`. */
export function sharedOf(note: Note, notes: readonly Note[]): Shared {
  const title = noteTitle(note.body) || 'Untitled';
  if (!isBookBody(note.body)) return { v: 1, kind: 'note', title, pages: [{ title, body: note.body }], at: Date.now() };
  const pages = [{ title, body: note.body }];
  for (const chapter of chaptersOf(note.body)) {
    const found = notes.find((n) => n.id !== note.id && sameTitle(noteTitle(n.body), chapter.title));
    if (found && !pages.some((p) => sameTitle(p.title, chapter.title))) pages.push({ title: chapter.title, body: found.body });
  }
  return { v: 1, kind: 'book', title, pages, at: Date.now() };
}

// ---- the account's shares --------------------------------------------------------------------------

/**
 * Where the shares were kept before they were synced: this device's own storage. Read once, folded into the synced
 * settings (core/preferences.ts `shares`), and removed, so a share made on the phone is listed on the Mac too.
 */
const LEGACY_KEY = 'glyph-shares';

export interface Kept {
  id: string;
  key: string;
  /** What was sent last, as a digest, so a save that changed nothing in it sends nothing. */
  sent: string;
  /**
   * Pictures the pages showed that the sending device did not have. A picture that arrives later, by sync, changes no
   * page, so these are looked for on each refresh and the share goes again when one is here.
   */
  lacked?: string[];
}

let migrated = false;
function migrateLegacy(): void {
  if (migrated) return;
  migrated = true;
  // Nothing kept, or unreadable: nothing to bring over, and the key is left as it is.
  const value = readStored<unknown>(LEGACY_KEY, undefined);
  if (value === undefined) return;
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    setPreferences({ shares: { ...(value as Record<string, Kept>), ...preferences().shares } });
  }
  writeStored(LEGACY_KEY, null);
}

function readKept(): Record<string, Kept> {
  migrateLegacy();
  return { ...preferences().shares };
}

function writeKept(kept: Record<string, Kept>): void {
  setPreferences({ shares: kept });
  for (const listener of listeners) listener();
}

const listeners = new Set<() => void>();

/** Told whenever a note starts or stops being shared, here or (by the synced settings) on another device. */
export function onShares(listener: () => void): () => void {
  listeners.add(listener);
  const off = onPreferences(listener);
  return () => {
    listeners.delete(listener);
    off();
  };
}

/** Every note shared by a link, by note id, with its link: the settings' list of shares (settings/SharedLinks.tsx). */
export function sharedLinks(): { noteId: string; link: string; id: string }[] {
  return Object.entries(readKept()).map(([noteId, kept]) => ({ noteId, id: kept.id, link: shareLink(kept.id, kept.key) }));
}

/** Every share the account holds on the server, those no device lists any more included, with when each was written (seconds). */
export async function sharesOnServer(): Promise<{ id: string; updated: number }[]> {
  const answer = await call<{ shares: { id: string; updated: number }[] }>('GET', 'shares', { token: token() });
  return answer.shares;
}

/** Takes down a share by its id alone: one the settings lost track of, so it has no note to stop it from. */
export async function takeDownShare(id: string): Promise<void> {
  await call('DELETE', `shares/${id}`, { token: token() });
}

/** The link for a shared note, or null. */
export function linkFor(noteId: string): string | null {
  const kept = readKept()[noteId];
  return kept ? shareLink(kept.id, kept.key) : null;
}

/** A short digest of what a share holds, pages only: when it was written does not make it different. */
function digest(shared: Shared): string {
  // "p2": pictures travel with a share, and a share remembers which it lacked. A share sent before either reads as
  // changed, so it is sent again, with them and with that list.
  const text = JSON.stringify(['p2', shared.kind, shared.title, shared.pages]);
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return `${text.length}:${(h >>> 0).toString(36)}`;
}

function token(): string {
  const session = accountState().session;
  if (!session) throw new Error('Sign in under Settings > Account to share: a share is kept with your account.');
  return session.token;
}

/** Shares `note` (and, for a book, its chapters among `notes`), or writes its share again; answers the link. */
export async function shareNote(note: Note, notes: readonly Note[]): Promise<string> {
  const auth = token();
  const all = readKept();
  const kept = all[note.id] ?? { id: newShareId(), key: newShareKey(), sent: '' };
  const shared = sharedOf(note, notes);
  const carried = await withPictures(shared);
  await call('PUT', `shares/${kept.id}`, { token: auth, body: { blob: await sealForServer(carried.shared, kept.key) } });
  all[note.id] = { ...kept, sent: digest(shared), lacked: carried.lacked };
  writeKept(all);
  return shareLink(kept.id, kept.key);
}

/** Whether a picture a share lacked when it was sent is on this device now. Only those names are looked for. */
async function lackedArrived(kept: Kept): Promise<boolean> {
  for (const name of kept.lacked ?? []) if ((await imageBytes(name).catch(() => null))?.length) return true;
  return false;
}

/** Stops sharing `noteId`: the share is taken down and its link reads nothing from then on. */
export async function stopSharing(noteId: string): Promise<void> {
  const all = readKept();
  const kept = all[noteId];
  if (!kept) return;
  await call('DELETE', `shares/${kept.id}`, { token: token() });
  delete all[noteId];
  writeKept(all);
}

/** Writes again every share whose note, or whose book's chapters, changed since it was last sent. */
export async function refreshShares(): Promise<number> {
  const all = readKept();
  const ids = Object.keys(all);
  if (!ids.length || !accountState().session) return 0;
  const notes = await listNotes();
  let sent = 0;
  for (const id of ids) {
    const note = notes.find((n) => n.id === id);
    const kept = all[id];
    if (!note || !kept) continue;
    const shared = sharedOf(note, notes);
    // The pages as they were, and every picture they show either sent or still not here: nothing to send.
    if (digest(shared) === kept.sent && !(await lackedArrived(kept))) continue;
    try {
      const carried = await withPictures(shared);
      await call('PUT', `shares/${kept.id}`, { token: token(), body: { blob: await sealForServer(carried.shared, kept.key) } });
      all[id] = { ...kept, sent: digest(shared), lacked: carried.lacked };
      sent += 1;
    } catch {
      // Offline, or signed out: the next save tries again.
    }
  }
  if (sent) writeKept(all);
  return sent;
}

/** After a save, the shares follow: a few seconds' quiet, then every share that changed is written again. */
const FOLLOW_MS = 3000;
let following = false;

export function followShares(): void {
  if (following || typeof window === 'undefined') return;
  following = true;
  let timer = 0;
  const soon = () => {
    if (!Object.keys(readKept()).length) return;
    window.clearTimeout(timer);
    timer = window.setTimeout(() => void refreshShares(), FOLLOW_MS);
  };
  // A save here, or notes changed by sync: a chapter edited on the Mac reaches a book's share from the phone too.
  window.addEventListener(NOTE_SAVED, soon);
  window.addEventListener(NOTES_CHANGED, soon);
  // And once at launch, once the app has settled: a share whose notes changed on another device, or that was sent by
  // an older app, goes out as it is now.
  if (Object.keys(readKept()).length) timer = window.setTimeout(() => void refreshShares(), FOLLOW_MS * 4);
}

// ---- reading and forking ----------------------------------------------------------------------------

/** What a link shares, read and opened: anyone with the link can, with no account. */
export async function readShared(link: string, fetcher: typeof fetch = fetch): Promise<Shared> {
  const found = readShareLink(link);
  if (!found) throw new Error('That is not a Ghost.md share link.');
  const answer = await call<{ blob: string }>('GET', `shares/${found.id}`, { fetcher });
  return openShare(answer.blob, found.key);
}

/** A page's body under a new title: its front matter's title if it has one, else its first heading. */
function retitled(body: string, from: string, to: string): string {
  if (frontMatterValue(body, 'title') !== null) return withFrontMatterTitle(body, to);
  const lines = body.split('\n');
  const at = lines.findIndex((line) => /^#\s/.test(line));
  if (at >= 0 && sameTitle(lines[at]!.replace(/^#\s+/, ''), from)) lines[at] = `# ${to}`;
  else lines.unshift(`# ${to}`, '');
  return lines.join('\n');
}

/**
 * Saves a copy of what was shared into this library, as the reader's own notes: a note, or a book with its chapters.
 * A page whose title a note here already has is saved as "Title (shared)", and a book's index points at the copies,
 * so a fork never mixes with what the reader already wrote. Answers the note to open: the note, or the book.
 */
export async function forkShared(
  shared: Shared,
  deps: { notes: () => Promise<Note[]>; save: (body: string) => Promise<Note>; keep?: (name: string, bytes: Bytes) => Promise<void> } = {
    notes: listNotes,
    save: (body) => saveNote(newNoteId(), body, 'editor'),
  },
): Promise<Note> {
  // The pictures first, under their own names, so the pages draw them as they open; sync sends them on from here.
  const keep = deps.keep ?? keepImage;
  for (const [name, bytes] of Object.entries(shared.pictures ?? {})) {
    await keep(name, bytes).catch((failure: unknown) => console.warn('[glyph] a shared picture was not kept:', failure));
  }
  const have = (await deps.notes()).map((n) => noteTitle(n.body));
  const taken = (t: string) => have.some((h) => sameTitle(h, t));
  const names = new Map<string, string>();
  for (const page of shared.pages) {
    let name = page.title;
    for (let n = 1; taken(name) || [...names.values()].some((v) => sameTitle(v, name)); n++) name = n === 1 ? `${page.title} (shared)` : `${page.title} (shared ${n})`;
    names.set(page.title, name);
  }
  let first: Note | null = null;
  for (const [i, page] of shared.pages.entries()) {
    let body = page.body;
    const name = names.get(page.title)!;
    if (name !== page.title) body = retitled(body, page.title, name);
    // The book's index points at the copies it was saved with.
    if (shared.kind === 'book' && i === 0) {
      for (const [from, to] of names) if (from !== to && from !== page.title) body = body.split(`[[${from}]]`).join(`[[${to}]]`);
    }
    const saved = await deps.save(body);
    first ??= saved;
  }
  if (!first) throw new Error('That share holds nothing to save.');
  return first;
}

/** A file name from a title: what a file system takes, never empty. */
function fileName(title: string): string {
  return title.replace(/[\\/:*?"<>|\n]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 120) || 'Untitled';
}

/** What was shared, as files for any Markdown app: one `.md` for a note, a `.zip` of every page for a book. */
export function sharedAsFile(shared: Shared): { name: string; blob: Blob } {
  // The pictures beside the pages in an `image/` folder, which is where the pages' `image/<name>` links point.
  const pictures = Object.entries(shared.pictures ?? {}).map(([name, bytes]) => ({ name: `image/${name}`, bytes }));
  if ((shared.kind === 'note' || shared.pages.length === 1) && !pictures.length) {
    const page = shared.pages[0]!;
    return { name: `${fileName(page.title)}.md`, blob: new Blob([page.body], { type: 'text/markdown' }) };
  }
  const encoder = new TextEncoder();
  const files = [...shared.pages.map((page) => ({ name: `${fileName(page.title)}.md`, bytes: encoder.encode(page.body) })), ...pictures];
  return { name: `${fileName(shared.title)}.zip`, blob: new Blob([zipFiles(files)], { type: 'application/zip' }) };
}
