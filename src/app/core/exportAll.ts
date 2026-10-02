import { answerHost } from './host.ts';
import { listenTo } from './events.ts';
import { hasNativeGeneration } from './nativeGeneration.ts';
import { isAndroid, isIOS } from './platform.ts';
import { listNotes, noteTitle, type Note } from './store.ts';
import { invoke, isTauri } from './tauri.ts';
import { webGet, webNames } from './webImages.ts';
import { zipFiles, type ZipFile } from '../share/zip.ts';

/**
 * Everything the app keeps, as one zip on a USB drive or wherever a person chooses (Matt: "Please add a feature that
 * allows me to plug in a USB drive and export the entire app onto a folder or zip file with
 * ghostmarkdown_<datetime>.7z or something"; docs/DESIGN.md §167).
 *
 * A zip rather than a 7z, since every computer and phone opens a zip with nothing installed, named
 * `ghostmarkdown_2026-10-01_21-42-05.zip` on the device's own clock, with one folder of that name inside it. Where it
 * goes is the device's own question:
 *
 * - **The Mac**: the save panel, a plugged-in drive on its side (src-tauri export_commands.rs `export_save`).
 * - **Android**: the system's picker makes the file, a drive plugged in by USB among its places
 *   (files/ExportTarget.kt), and Rust writes the archive straight into it (`export_fd`).
 * - **A browser**: the notes and pictures it keeps, zipped here, and saved where the browser's own save asks.
 *
 * Both apps need native generation 22. An iPhone has no way to it yet.
 */

/** The binary generation with `export_save`, `export_fd`, `export_cancel` and the activity's `chooseExport`. */
export const EXPORT_GENERATION = 22;

/** Where an export can go from here: the Mac's panel, Android's picker, a browser's save, or nowhere yet. */
export type ExportWay = 'mac' | 'android' | 'browser' | 'update' | 'none';

export async function exportWay(): Promise<ExportWay> {
  if (!isTauri()) return 'browser';
  if (isIOS) return 'none';
  if (isAndroid) {
    if (typeof window.GlyphHost?.chooseExport !== 'function') return 'update';
    return (await hasNativeGeneration(EXPORT_GENERATION)) ? 'android' : 'update';
  }
  return (await hasNativeGeneration(EXPORT_GENERATION)) ? 'mac' : 'update';
}

const two = (n: number) => String(n).padStart(2, '0');

/** `ghostmarkdown_2026-10-01_21-42-05.zip`, on the device's clock: no colon, which a USB drive's FAT will not hold. */
export function exportName(at: Date): string {
  const day = `${at.getFullYear()}-${two(at.getMonth() + 1)}-${two(at.getDate())}`;
  const time = `${two(at.getHours())}-${two(at.getMinutes())}-${two(at.getSeconds())}`;
  return `ghostmarkdown_${day}_${time}.zip`;
}

/**
 * The settings carried: how the app looks and behaves, its plugins and the workspaces (core/preferences.ts holds
 * them), and nothing that opens an account or a service. No session, no sync key, no Notion or GitHub token: a drive
 * is easily lost.
 */
export const SETTINGS_KEYS = ['glyph-preferences', 'glyph-plugins', 'glyph-workspace-current', 'glyph-note-bookmarks', 'glyph-book-spots'] as const;

/** The settings as `settings.json`: each key's stored value, read as JSON where it is JSON. */
export function settingsFile(storage: Pick<Storage, 'getItem'> | null = typeof localStorage === 'undefined' ? null : localStorage): string {
  const settings: Record<string, unknown> = {};
  for (const key of SETTINGS_KEYS) {
    let raw: string | null;
    try {
      raw = storage?.getItem(key) ?? null;
    } catch {
      raw = null;
    }
    if (raw === null) continue;
    try {
      settings[key] = JSON.parse(raw) as unknown;
    } catch {
      settings[key] = raw;
    }
  }
  return `${JSON.stringify(settings, null, 2)}\n`;
}

/** What the archive is, in its own README. */
export function readme(name: string, at: Date): string {
  const root = name.replace(/\.zip$/, '');
  return [
    `Ghost.md, exported ${at.toLocaleString()}`,
    '',
    `Everything in ${root}/ is what Ghost.md kept on the device it was exported from.`,
    '',
    'Library/      Every note, as a Markdown (.md) file, in its folders. Open the folder in Obsidian or any',
    '              text editor. Library/.glyph/ holds what a note has that is not text: a recording\'s',
    '              phrases and their times.',
    'images/       The pictures notes show. A note links one as image/<name>.',
    'video/        The films notes play. A note links one as video/<name>.',
    'recordings/   The recordings voice notes and meetings kept, as WAV, named by the note\'s id.',
    'settings.json How the app looked and behaved, its plugins and workspaces. No account, password or key.',
    'manifest.json When it was exported, from which version, and how many notes and files.',
    '',
    'Not here: the AI and voice models (downloaded again in Settings), the search index (rebuilt from',
    'the files), and anything that signs in to an account.',
    '',
  ].join('\n');
}

/** How far an export has got (src-tauri export.rs `Progress`): bytes read of all, files of all. */
export interface ExportProgress {
  done: number;
  total: number;
  files: number;
  of: number;
}

/** What an export wrote (export.rs `Exported`). */
export interface Exported {
  name: string;
  notes: number;
  files: number;
  bytes: number;
  written: number;
}

/** The request Rust takes (export_commands.rs `ExportRequest`). */
function request(name: string, at: Date) {
  return {
    name,
    // A zip's times are the wall clock's; getTimezoneOffset is minutes WEST of UTC.
    offsetMinutes: -at.getTimezoneOffset(),
    page: window.__glyphBoot?.build ?? 'bundled',
    exportedAt: at.toISOString(),
    files: [
      { name: 'README.txt', text: readme(name, at) },
      { name: 'settings.json', text: settingsFile() },
    ],
  };
}

/** What the picker answered (files/ExportTarget.kt), as the page reads it. */
export type TargetAnswer = { fd: number; name: string } | { cancelled: true } | { error: string };

export function readTargetAnswer(json: string): TargetAnswer {
  const unread = { error: 'That place can’t be written to.' };
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
  if (typeof answer.fd === 'number' && Number.isInteger(answer.fd) && answer.fd > 2) return { fd: answer.fd, name: typeof answer.name === 'string' ? answer.name : '' };
  return unread;
}

/** The picker's answer, once: the activity says it as an `exportTarget` event. */
function chooseTarget(name: string): Promise<TargetAnswer> {
  return new Promise((resolve) => {
    const stop = answerHost('exportTarget', (json) => {
      stop();
      resolve(readTargetAnswer(json));
    });
    const started = window.GlyphHost?.chooseExport?.(name) ?? 'This phone has no way to choose where to save.';
    if (started !== 'started') {
      stop();
      resolve({ error: started });
    }
  });
}

/** The one export under way, for `cancelExport`. */
let browserStop: AbortController | null = null;

/** Stops the export under way. */
export function cancelExport(): void {
  browserStop?.abort();
  if (isTauri()) void invoke('export_cancel').catch(() => undefined);
}

/** A file name from a note's title for a browser's archive, never empty, made unique among `taken`. */
export function noteFileName(title: string, taken: Set<string>): string {
  const base = title.replace(/[\\/:*?"<>|#^[\]\n]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80) || 'Untitled';
  let name = `${base}.md`;
  for (let n = 2; taken.has(name.toLowerCase()); n += 1) name = `${base} ${n}.md`;
  taken.add(name.toLowerCase());
  return name;
}

/** A browser's library as files: each note in Library/, its pictures in images/. */
export async function browserFiles(notes: readonly Note[], name: string, at: Date, signal?: AbortSignal): Promise<ZipFile[]> {
  const root = name.replace(/\.zip$/, '');
  const encoder = new TextEncoder();
  const taken = new Set<string>();
  const files: ZipFile[] = [
    { name: `${root}/README.txt`, bytes: encoder.encode(readme(name, at)) },
    { name: `${root}/settings.json`, bytes: encoder.encode(settingsFile()) },
  ];
  for (const note of notes) files.push({ name: `${root}/Library/${noteFileName(noteTitle(note.body), taken)}`, bytes: encoder.encode(note.body) });
  for (const picture of await webNames()) {
    if (signal?.aborted) throw new Error('The export was stopped.');
    const blob = await webGet(picture);
    if (blob) files.push({ name: `${root}/images/${picture}`, bytes: new Uint8Array(await blob.arrayBuffer()) });
  }
  const manifest = { app: 'Ghost.md', exported: at.toISOString(), page: 'browser', notes: notes.length, files: files.length - 2 };
  files.splice(2, 0, { name: `${root}/manifest.json`, bytes: encoder.encode(`${JSON.stringify(manifest, null, 2)}\n`) });
  return files;
}

interface SavePicker {
  showSaveFilePicker?: (options: { suggestedName: string; types: { description: string; accept: Record<string, string[]> }[] }) => Promise<{
    createWritable: () => Promise<{ write: (data: Blob) => Promise<void>; close: () => Promise<void> }>;
  }>;
}

/** Saves a browser's archive: where the person picks, where the browser can ask; else as a download. Null when closed. */
async function saveInBrowser(blob: Blob, name: string): Promise<boolean> {
  const picker = (window as unknown as SavePicker).showSaveFilePicker;
  if (picker) {
    try {
      const handle = await picker({ suggestedName: name, types: [{ description: 'Zip archive', accept: { 'application/zip': ['.zip'] } }] });
      const writable = await handle.createWritable();
      await writable.write(blob);
      await writable.close();
      return true;
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return false;
      throw error;
    }
  }
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
  return true;
}

/**
 * Exports everything the way this device can: the archive written where the person chose, or null when they closed
 * the panel or the picker without choosing. `onProgress` hears how far it has got.
 */
export async function exportEverything(onProgress: (progress: ExportProgress) => void, at = new Date()): Promise<Exported | null> {
  const name = exportName(at);
  const way = await exportWay();
  if (way === 'none') throw new Error('Exporting isn’t on iPhone yet.');
  if (way === 'update') throw new Error('Update Ghost.md to export everything.');

  if (way === 'browser') {
    browserStop = new AbortController();
    try {
      const notes = await listNotes();
      onProgress({ done: 0, total: notes.length, files: 0, of: notes.length });
      const files = await browserFiles(notes, name, at, browserStop.signal);
      const zip = zipFiles(files, at);
      const bytes = files.reduce((sum, file) => sum + file.bytes.length, 0);
      onProgress({ done: notes.length, total: notes.length, files: files.length, of: files.length });
      const saved = await saveInBrowser(new Blob([zip], { type: 'application/zip' }), name);
      return saved ? { name, notes: notes.length, files: files.length - 3, bytes, written: zip.length } : null;
    } finally {
      browserStop = null;
    }
  }

  const unlisten = await listenTo<ExportProgress>('export://progress', onProgress);
  try {
    if (way === 'mac') return await invoke<Exported | null>('export_save', { request: request(name, at) });
    const target = await chooseTarget(name);
    if ('cancelled' in target) return null;
    if ('error' in target) throw new Error(target.error);
    try {
      const done = await invoke<Exported>('export_fd', { request: request(name, at), fd: target.fd });
      window.GlyphHost?.exportDone?.();
      return { ...done, name: target.name || done.name };
    } catch (error) {
      // Half an archive is no archive: the picker's file goes, so the drive holds only what opens.
      window.GlyphHost?.discardExport?.();
      throw error;
    }
  } finally {
    unlisten();
  }
}

/** What an export wrote, as Settings' Export card says it (settings/ExportCard.tsx): "Exported 312 notes and 48 other files, 1.2 GB, as ghostmarkdown_….zip." */
export function doneSaid(exported: Exported): string {
  const count = (n: number, one: string, many: string) => (n === 1 ? `one ${one}` : `${n} ${many}`);
  const others = Math.max(0, exported.files - exported.notes);
  const what = others ? `${count(exported.notes, 'note', 'notes')} and ${count(others, 'other file', 'other files')}` : count(exported.notes, 'note', 'notes');
  return `Exported ${what}, ${sizeSaid(exported.written)}, as ${exported.name}.`;
}

/** A size as a person reads it: "820 KB", "1.4 GB". */
export function sizeSaid(bytes: number): string {
  if (bytes < 1000) return `${bytes} bytes`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1000;
  let unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit += 1;
  }
  return `${value >= 10 || unit === 0 ? Math.round(value) : value.toFixed(1)} ${units[unit]}`;
}
