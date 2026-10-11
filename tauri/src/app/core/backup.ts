import { answerHost } from './host.ts';
import { listenTo } from './events.ts';
import { hasNativeGeneration } from './nativeGeneration.ts';
import { isAndroid, isIOS, isMacApp } from './platform.ts';
import { invoke, isTauri } from './tauri.ts';

/**
 * Backup: every note, onto a removable drive, as plain files under a `Ghost.md` folder on its root (docs/DESIGN.md
 * §204; Matt: "add a section to the settings called "Backup" it should prompt the user to plugin a removable drive to
 * backup all the notes in the app to workspace folders and such under a Ghost.md folder on the root of the drive").
 *
 * The drives are the Mac's under `/Volumes` (src-tauri/src/backup_commands.rs `backup_drives`) or Android's removable
 * volumes (files/BackupDrives.kt), asked again every two seconds while Settings › Backup is open, so a drive plugged in
 * shows up by itself. On Android a drive is allowed once, through the system's own picker opened on its root, and is
 * remembered. The writing is Rust's (src-tauri/src/backup.rs): the notes by their workspace folders, each note's
 * versions file beside it, the pictures, films and recordings under Attachments/, and a second backup to the same drive
 * writes only what changed.
 */

/** The native generation with the backup's commands and Android's drives. */
export const BACKUP_GENERATION = 26;

/**
 * Where a backup can go from here: the Mac's drives, Windows' (its removable drive letters, with no Eject of the
 * app's own), Android's, an app to update first, or nowhere (a browser, an iPhone).
 */
export type BackupWay = 'mac' | 'windows' | 'android' | 'update' | 'none';

export async function backupWay(): Promise<BackupWay> {
  if (!isTauri() || isIOS) return 'none';
  if (!(await hasNativeGeneration(BACKUP_GENERATION))) return 'update';
  if (isAndroid) return typeof window.GlyphHost?.backupDrives === 'function' ? 'android' : 'update';
  return isMacApp ? 'mac' : 'windows';
}

/** The last backup a drive holds. */
export interface LastBackup {
  backedUpAt: string;
  notes: number;
}

/** A drive plugged in now. */
export interface BackupDrive {
  /** The Mac's path under /Volumes, or Android's volume id. */
  id: string;
  name: string;
  free: number | null;
  total: number | null;
  /** Android: the drive's tree Ghost.md may write, once the person has allowed it; never on the Mac. */
  tree: string | null;
  last: LastBackup | null;
}

export interface BackupProgress {
  done: number;
  total: number;
  files: number;
  of: number;
}

export interface Backed {
  notes: number;
  files: number;
  written: number;
  unchanged: number;
  removed: number;
  bytes: number;
}

const num = (value: unknown): number | null => (typeof value === 'number' && Number.isFinite(value) ? value : null);

function lastOf(value: unknown): LastBackup | null {
  if (!value || typeof value !== 'object') return null;
  const said = value as Record<string, unknown>;
  return typeof said.backedUpAt === 'string' && said.backedUpAt ? { backedUpAt: said.backedUpAt, notes: num(said.notes) ?? 0 } : null;
}

/** Android's drives as the activity says them (BackupDrives.kt `drives`): nothing readable is no drives. */
export function readAndroidDrives(json: string): BackupDrive[] {
  let said: unknown;
  try {
    said = JSON.parse(json);
  } catch {
    return [];
  }
  if (!Array.isArray(said)) return [];
  return said.flatMap((value): BackupDrive[] => {
    if (!value || typeof value !== 'object') return [];
    const drive = value as Record<string, unknown>;
    if (typeof drive.id !== 'string' || !drive.id) return [];
    return [
      {
        id: drive.id,
        name: typeof drive.name === 'string' && drive.name ? drive.name : drive.id,
        free: num(drive.free),
        total: num(drive.total),
        tree: typeof drive.tree === 'string' && drive.tree ? drive.tree : null,
        last: null,
      },
    ];
  });
}

/** The drives plugged in now, each with the last backup it holds where that can be read. */
export async function listDrives(way: BackupWay): Promise<BackupDrive[]> {
  if (way === 'mac' || way === 'windows') {
    const drives = await invoke<Array<Omit<BackupDrive, 'tree' | 'last'> & { last?: unknown }>>('backup_drives');
    return drives.map((drive) => ({ id: drive.id, name: drive.name, free: num(drive.free), total: num(drive.total), tree: null, last: lastOf(drive.last) }));
  }
  if (way !== 'android') return [];
  const drives = readAndroidDrives(window.GlyphHost?.backupDrives?.() ?? '[]');
  return Promise.all(
    drives.map(async (drive) => {
      if (!drive.tree) return drive;
      const last = await invoke<unknown>('backup_last', { tree: drive.tree }).catch(() => null);
      return { ...drive, last: lastOf(last) };
    }),
  );
}

export type DriveAnswer = { tree: string } | { cancelled: true } | { error: string };

export function readDriveAnswer(json: string): DriveAnswer {
  const unread = { error: 'That drive can’t be written to.' };
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
  if (typeof answer.tree === 'string' && answer.tree) return { tree: answer.tree };
  return unread;
}

/** Android: the person asked, once, to let Ghost.md write the drive; the picker's answer arrives as a `backupDrive` event. */
export function allowDrive(id: string): Promise<DriveAnswer> {
  return new Promise((resolve) => {
    const stop = answerHost('backupDrive', (json) => {
      stop();
      resolve(readDriveAnswer(json));
    });
    const started = window.GlyphHost?.chooseBackupDrive?.(id) ?? 'This phone has no way to choose a drive.';
    if (started !== 'started') {
      stop();
      resolve(readDriveAnswer(started.startsWith('{') ? started : JSON.stringify({ error: started })));
    }
  });
}

/** What the README on the drive says. */
export function backupReadme(at: Date): string {
  return [
    `Ghost.md, backed up ${at.toLocaleString()}`,
    '',
    'Every note Ghost.md keeps, as Markdown (.md) files you can open in any text editor or in Obsidian.',
    '',
    'Inbox/            Notes in no workspace.',
    'Workspaces/       A folder for each of your workspaces.',
    'Organizations/    A folder for each organization you are in, with its notes.',
    'Attachments/      The pictures, films and recordings the notes show and play.',
    '',
    'A .versions file beside a note is its version history. .ghostmd-backup.json is what the last backup',
    'wrote, so the next backup to this drive only writes what changed. A note deleted in the app is taken',
    'off at the next backup; nothing else in this folder is ever touched.',
    '',
  ].join('\n');
}

/** The backup onto `drive`, telling how far it has got. */
export async function runBackup(way: BackupWay, drive: BackupDrive, onProgress: (progress: BackupProgress) => void, at = new Date()): Promise<Backed> {
  if (way === 'none') throw new Error('Backing up isn’t on this device.');
  if (way === 'update') throw new Error('Update Ghost.md to back up to a drive.');
  const request = {
    ...(way === 'android' ? { tree: drive.tree } : { drive: drive.id }),
    backedUpAt: at.toISOString(),
    readme: backupReadme(at),
  };
  if (way === 'android' && !drive.tree) throw new Error('Allow Ghost.md to use the drive first.');
  const unlisten = await listenTo<BackupProgress>('backup://progress', onProgress);
  try {
    return await invoke<Backed>('backup_run', { request });
  } finally {
    unlisten();
  }
}

/** The native generation with `backup_files`, the list a drive's tree is drawn from. */
export const BACKUP_FILES_GENERATION = 27;

/** One file the drive's Ghost.md folder holds: its path under the folder, and its size. */
export interface HeldFile {
  path: string;
  size: number;
}

/**
 * Every file the last backup left in the drive's Ghost.md folder (src-tauri/src/backup.rs `held`, from the backup's
 * own manifest), for the tree under the drive (Matt: "show a logical file tree of all the files on the USB drive
 * inside the ghost folder specifically"). Null where it cannot be asked: an app from before the command, or an
 * Android drive not yet allowed.
 */
export async function listBackupFiles(way: BackupWay, drive: BackupDrive): Promise<HeldFile[] | null> {
  if (way !== 'mac' && way !== 'windows' && way !== 'android') return null;
  if (way === 'android' && !drive.tree) return null;
  if (!(await hasNativeGeneration(BACKUP_FILES_GENERATION))) return null;
  const said = await invoke<unknown>('backup_files', way === 'android' ? { tree: drive.tree } : { drive: drive.id });
  if (!Array.isArray(said)) return [];
  return said.flatMap((value): HeldFile[] => {
    if (!value || typeof value !== 'object') return [];
    const file = value as Record<string, unknown>;
    return typeof file.path === 'string' && file.path ? [{ path: file.path, size: num(file.size) ?? 0 }] : [];
  });
}

/** A folder of the tree: its folders first, then its files, each by name; `files` and `size` count everything under it. */
export interface TreeFolder {
  name: string;
  /** The path under Ghost.md, with no slash at either end; '' for the folder itself. */
  path: string;
  folders: TreeFolder[];
  leaves: { name: string; path: string; size: number }[];
  files: number;
  size: number;
}

/** The files as the folders they are in, under one root named for the folder on the drive. */
export function backupTree(files: readonly HeldFile[], root = 'Ghost.md'): TreeFolder {
  const top: TreeFolder = { name: root, path: '', folders: [], leaves: [], files: 0, size: 0 };
  for (const file of files) {
    const parts = file.path.split('/').filter(Boolean);
    const name = parts.pop();
    if (!name) continue;
    let folder = top;
    folder.files += 1;
    folder.size += file.size;
    for (const part of parts) {
      let next = folder.folders.find((each) => each.name === part);
      if (!next) {
        next = { name: part, path: folder.path ? `${folder.path}/${part}` : part, folders: [], leaves: [], files: 0, size: 0 };
        folder.folders.push(next);
      }
      next.files += 1;
      next.size += file.size;
      folder = next;
    }
    folder.leaves.push({ name, path: file.path, size: file.size });
  }
  const byName = (a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: 'base' });
  const sort = (folder: TreeFolder) => {
    folder.folders.sort(byName);
    folder.leaves.sort(byName);
    folder.folders.forEach(sort);
  };
  sort(top);
  return top;
}

/** Stops the backup under way, between files. */
export function cancelBackup(): void {
  if (isTauri()) void invoke('backup_cancel').catch(() => undefined);
}

/** The Mac: the drive put away, so it can be pulled out. */
export function ejectDrive(drive: BackupDrive): Promise<void> {
  return invoke('backup_eject', { drive: drive.id });
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

/** When a drive was last backed up to, as its row says: "Last backed up 5 Oct, 18:52 · 312 notes". */
export function lastSaid(last: LastBackup | null, now = new Date()): string {
  if (!last) return 'No backup on it yet';
  const at = new Date(last.backedUpAt);
  if (Number.isNaN(at.getTime())) return 'Backed up before';
  const sameDay = at.toDateString() === now.toDateString();
  const day = sameDay ? 'today' : at.toLocaleDateString(undefined, { day: 'numeric', month: 'short', ...(at.getFullYear() === now.getFullYear() ? {} : { year: 'numeric' }) });
  const time = at.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  const notes = last.notes === 1 ? 'one note' : `${last.notes} notes`;
  return `Last backed up ${day}, ${time} · ${notes}`;
}

/** What a backup did, as Settings says it: "Backed up 312 notes to KINGSTON: 14 files written, 298 already there." */
export function backedSaid(backed: Backed, drive: string): string {
  const notes = backed.notes === 1 ? 'one note' : `${backed.notes} notes`;
  const parts = [`${backed.written === 1 ? 'one file' : `${backed.written} files`} written`];
  if (backed.unchanged) parts.push(`${backed.unchanged} already there`);
  if (backed.removed) parts.push(`${backed.removed} taken off`);
  return `Backed up ${notes} to ${drive}: ${parts.join(', ')}.`;
}
