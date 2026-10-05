import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * A backup onto a removable drive (core/backup.ts; docs/DESIGN.md §204): where one can go, the drives as the Mac and
 * Android say them, Android's one-time allow, the backup's request and its words after. The apps, their generation and
 * their events are stood in for; the activity's own words are read out of its Kotlin, since the bridge is typed twice.
 */

const device = vi.hoisted(() => ({
  tauri: true,
  android: false,
  ios: false,
  generation: 26,
  commands: [] as { command: string; args: unknown }[],
  answers: {} as Record<string, unknown>,
  progress: null as ((payload: unknown) => void) | null,
}));
vi.mock('./tauri.ts', () => ({
  isTauri: () => device.tauri,
  invoke: async (command: string, args: unknown) => {
    device.commands.push({ command, args });
    const answer = device.answers[command];
    if (answer instanceof Error) throw answer.message;
    return answer;
  },
}));
vi.mock('./events.ts', () => ({
  listenTo: async (_event: string, handler: (payload: unknown) => void) => {
    device.progress = handler;
    return () => {
      device.progress = null;
    };
  },
}));
vi.mock('./nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => device.generation >= wanted }));
vi.mock('./platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./platform.ts')>()),
  get isAndroid() {
    return device.android;
  },
  get isIOS() {
    return device.ios;
  },
}));

const { BACKUP_GENERATION, allowDrive, backedSaid, backupReadme, backupWay, lastSaid, listDrives, readAndroidDrives, readDriveAnswer, runBackup } = await import('./backup.ts');

const DRIVE = { id: '/Volumes/KINGSTON', name: 'KINGSTON', free: 30_000_000_000, total: 32_000_000_000, tree: null, last: null };

beforeEach(() => {
  device.tauri = true;
  device.android = false;
  device.ios = false;
  device.generation = BACKUP_GENERATION;
  device.commands = [];
  device.answers = {};
});

afterEach(() => {
  delete window.GlyphHost;
  delete window.__glyph;
});

describe('where a backup can go', () => {
  it('is the Mac’s drives, Android’s, an app to update, or nowhere', async () => {
    expect(await backupWay()).toBe('mac');
    device.generation = BACKUP_GENERATION - 1;
    expect(await backupWay()).toBe('update');
    device.generation = BACKUP_GENERATION;
    device.android = true;
    // An APK whose activity has no drives is one to update, whatever it says of its generation.
    expect(await backupWay()).toBe('update');
    window.GlyphHost = { backupDrives: () => '[]' } as unknown as Window['GlyphHost'];
    expect(await backupWay()).toBe('android');
    device.ios = true;
    expect(await backupWay()).toBe('none');
    device.ios = false;
    device.tauri = false;
    expect(await backupWay()).toBe('none');
  });
});

describe('the drives', () => {
  it('are the Mac’s as Rust lists them, with the last backup each holds', async () => {
    device.answers.backup_drives = [{ ...DRIVE, last: { backedUpAt: '2026-10-05T18:52:00Z', notes: 312 } }, { id: '/Volumes/SD', name: 'SD', free: null, total: null }];
    expect(await listDrives('mac')).toEqual([
      { ...DRIVE, last: { backedUpAt: '2026-10-05T18:52:00Z', notes: 312 } },
      { id: '/Volumes/SD', name: 'SD', free: null, total: null, tree: null, last: null },
    ]);
  });

  it('are Android’s as the activity says them, and the last backup asked of each it may write', async () => {
    device.android = true;
    window.GlyphHost = {
      backupDrives: () => JSON.stringify([{ id: '1A2B-3C4D', name: 'SanDisk USB', tree: 'content://tree/1A2B', free: 5, total: 9 }, { id: 'SD-1', name: '' }, { name: 'no id' }]),
    } as unknown as Window['GlyphHost'];
    device.answers.backup_last = { backedUpAt: '2026-10-04T10:00:00Z', notes: 3 };
    const drives = await listDrives('android');
    expect(drives).toEqual([
      { id: '1A2B-3C4D', name: 'SanDisk USB', free: 5, total: 9, tree: 'content://tree/1A2B', last: { backedUpAt: '2026-10-04T10:00:00Z', notes: 3 } },
      { id: 'SD-1', name: 'SD-1', free: null, total: null, tree: null, last: null },
    ]);
    // Only the drive it may write is asked of: the other has no tree to read.
    expect(device.commands).toEqual([{ command: 'backup_last', args: { tree: 'content://tree/1A2B' } }]);
  });

  it('read nothing unreadable as no drives', () => {
    expect(readAndroidDrives('not json')).toEqual([]);
    expect(readAndroidDrives('{"id":"x"}')).toEqual([]);
  });
});

describe('Android’s allow, once a drive', () => {
  it('waits for the picker’s answer and gives back the drive’s tree', async () => {
    let asked = '';
    window.GlyphHost = {
      chooseBackupDrive: (id: string) => {
        asked = id;
        queueMicrotask(() => window.__glyph?.backupDrive?.(JSON.stringify({ id, tree: 'content://tree/1A2B' })));
        return 'started';
      },
    } as unknown as Window['GlyphHost'];
    expect(await allowDrive('1A2B-3C4D')).toEqual({ tree: 'content://tree/1A2B' });
    expect(asked).toBe('1A2B-3C4D');
    // And lets go of the event once answered.
    expect(window.__glyph?.backupDrive).toBeUndefined();
  });

  it('says why where the picker would not open', async () => {
    window.GlyphHost = { chooseBackupDrive: () => JSON.stringify({ error: 'That drive isn’t plugged in any more.' }) } as unknown as Window['GlyphHost'];
    expect(await allowDrive('gone')).toEqual({ error: 'That drive isn’t plugged in any more.' });
  });

  it('reads a cancel, a refusal and nonsense', () => {
    expect(readDriveAnswer('{"cancelled":true}')).toEqual({ cancelled: true });
    expect(readDriveAnswer('{"error":"Choose the drive itself"}')).toEqual({ error: 'Choose the drive itself' });
    expect(readDriveAnswer('{}')).toEqual({ error: 'That drive can’t be written to.' });
  });

  it('is the words the activity says, so the two sides cannot drift', () => {
    const kotlin = readFileSync(join(process.cwd(), 'src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/files/BackupDrives.kt'), 'utf8');
    expect(kotlin).toContain('put("tree", uri.toString())');
    expect(kotlin).toContain('put("cancelled", true)');
    const activity = readFileSync(join(process.cwd(), 'src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/MainActivity.kt'), 'utf8');
    expect(activity).toContain('fun backupDrives(): String');
    expect(activity).toContain('fun chooseBackupDrive(id: String): String');
    expect(activity).toContain('window.__glyph.backupDrive(');
  });
});

describe('the backup', () => {
  it('asks Rust to write the Mac’s drive, with the README, and tells how far it has got', async () => {
    const backed = { notes: 2, files: 3, written: 3, unchanged: 0, removed: 0, bytes: 9 };
    device.answers.backup_run = backed;
    const seen: unknown[] = [];
    const at = new Date('2026-10-05T20:00:00Z');
    expect(await runBackup('mac', DRIVE, (progress) => seen.push(progress), at)).toEqual(backed);
    expect(device.commands).toEqual([{ command: 'backup_run', args: { request: { drive: '/Volumes/KINGSTON', backedUpAt: '2026-10-05T20:00:00.000Z', readme: backupReadme(at) } } }]);
  });

  it('writes Android’s drive by its tree, and refuses one not yet allowed', async () => {
    device.answers.backup_run = { notes: 0, files: 0, written: 0, unchanged: 0, removed: 0, bytes: 0 };
    await runBackup('android', { ...DRIVE, id: '1A2B', tree: 'content://tree/1A2B' }, () => {});
    expect((device.commands[0]!.args as { request: { tree: string } }).request.tree).toBe('content://tree/1A2B');
    await expect(runBackup('android', { ...DRIVE, id: '1A2B' }, () => {})).rejects.toThrow('Allow Ghost.md to use the drive first.');
  });

  it('says what it did, and when a drive was last backed up', () => {
    expect(backedSaid({ notes: 312, files: 340, written: 14, unchanged: 326, removed: 2, bytes: 10 }, 'KINGSTON')).toBe('Backed up 312 notes to KINGSTON: 14 files written, 326 already there, 2 taken off.');
    expect(backedSaid({ notes: 1, files: 1, written: 1, unchanged: 0, removed: 0, bytes: 1 }, 'SD')).toBe('Backed up one note to SD: one file written.');
    expect(lastSaid(null)).toBe('No backup on it yet');
    const now = new Date('2026-10-05T21:00:00');
    expect(lastSaid({ backedUpAt: new Date('2026-10-05T18:52:00').toISOString(), notes: 312 }, now)).toMatch(/^Last backed up today, .+ · 312 notes$/);
  });

  it('leaves a README that says what each folder is', () => {
    const readme = backupReadme(new Date('2026-10-05T20:00:00Z'));
    for (const folder of ['Inbox/', 'Workspaces/', 'Organizations/', 'Attachments/']) expect(readme).toContain(folder);
  });
});
