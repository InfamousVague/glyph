import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Settings › Backup (settings/BackupPane.tsx; docs/DESIGN.md §204): the drive asked for with none in, the drive
 * found by looking again, a backup run on a row's Back up, what it did, and Eject on the Mac. The drives and the
 * backup are core/backup.ts's, stood in for here.
 */

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const drive = vi.hoisted(() => ({
  way: 'mac' as 'mac' | 'android' | 'update' | 'none',
  drives: [] as Array<{ id: string; name: string; free: number | null; total: number | null; tree: string | null; last: { backedUpAt: string; notes: number } | null }>,
  runs: [] as string[],
  ejected: [] as string[],
}));
vi.mock('../core/backup.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/backup.ts')>()),
  backupWay: async () => drive.way,
  listDrives: async () => drive.drives,
  runBackup: async (_way: string, chosen: { name: string }, onProgress: (progress: { done: number; total: number; files: number; of: number }) => void) => {
    drive.runs.push(chosen.name);
    onProgress({ done: 5, total: 10, files: 1, of: 2 });
    return { notes: 312, files: 340, written: 14, unchanged: 326, removed: 0, bytes: 10 };
  },
  ejectDrive: async (chosen: { name: string }) => {
    drive.ejected.push(chosen.name);
  },
}));

// The kit reads matchMedia as it loads (test/stubs.ts): in before the dynamic import.
const { stubMatchMedia } = await import('../../test/stubs.ts');
stubMatchMedia();
const { BackupPane, LOOK_EVERY_MS } = await import('./BackupPane.tsx');

let root: Root | null = null;
let host: HTMLElement | null = null;

beforeEach(() => {
  vi.useFakeTimers({ shouldAdvanceTime: true });
  drive.way = 'mac';
  drive.drives = [];
  drive.runs = [];
  drive.ejected = [];
});

afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  root = null;
  host = null;
  vi.useRealTimers();
});

async function open() {
  host = document.createElement('div');
  document.body.append(host);
  root = createRoot(host);
  await act(async () => root!.render(<BackupPane />));
  await act(async () => undefined);
  return host;
}

const button = (page: HTMLElement, words: string) => [...page.querySelectorAll('button')].find((b) => b.textContent?.trim() === words);

describe('Settings › Backup', () => {
  it('asks for a drive with none in, and finds one plugged in by looking again', async () => {
    const page = await open();
    expect(page.textContent).toContain('Plug in a drive');
    drive.drives = [{ id: '/Volumes/KINGSTON', name: 'KINGSTON', free: 30_000_000_000, total: 32_000_000_000, tree: null, last: null }];
    await act(async () => {
      vi.advanceTimersByTime(LOOK_EVERY_MS);
    });
    await act(async () => undefined);
    expect(page.textContent).toContain('KINGSTON');
    expect(page.textContent).toContain('30 GB free · No backup on it yet');
    expect(page.textContent).not.toContain('Plug in a drive');
  });

  it('backs up to a drive from its row, says what it did, and ejects it on the Mac', async () => {
    drive.drives = [{ id: '/Volumes/KINGSTON', name: 'KINGSTON', free: null, total: null, tree: null, last: { backedUpAt: '2026-10-05T18:52:00Z', notes: 300 } }];
    const page = await open();
    await act(async () => button(page, 'Back up')!.click());
    await act(async () => undefined);
    expect(drive.runs).toEqual(['KINGSTON']);
    expect(page.textContent).toContain('Backed up 312 notes to KINGSTON: 14 files written, 326 already there.');
    await act(async () => button(page, 'Eject')!.click());
    await act(async () => undefined);
    expect(drive.ejected).toEqual(['KINGSTON']);
    expect(page.textContent).toContain('KINGSTON can be unplugged now.');
  });

  it('says to update an app too old to write a drive, and that a browser cannot', async () => {
    drive.way = 'update';
    expect((await open()).textContent).toContain('Update Ghost.md to back up');
    act(() => root?.unmount());
    host?.remove();
    drive.way = 'none';
    expect((await open()).textContent).toContain('Backups need the app');
  });
});
