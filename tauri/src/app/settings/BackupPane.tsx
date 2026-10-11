import { useEffect, useMemo, useRef, useState } from 'react';
import { CircleCheck, HardDrive, HardDriveUpload, Usb } from '@glacier/icons';
import { ProgressBar } from '@glacier/react';
import {
  BACKUP_FILES_GENERATION,
  allowDrive,
  backedSaid,
  backupTree,
  backupWay,
  cancelBackup,
  ejectDrive,
  lastSaid,
  listBackupFiles,
  listDrives,
  runBackup,
  sizeSaid,
  type Backed,
  type BackupDrive,
  type BackupProgress,
  type BackupWay,
  type HeldFile,
} from '../core/backup.ts';
import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { BackupTree } from './BackupTree.tsx';
import { PaneSection, RowAction, SettingRow, SettingsCallout, SettingsEmpty, SettingsFootnote } from './kit/settingsKit.tsx';

/**
 * Settings › Backup (docs/DESIGN.md §204; Matt: "add a section to the settings called "Backup" it should prompt the
 * user to plugin a removable drive to backup all the notes in the app to workspace folders and such under a Ghost.md
 * folder on the root of the drive").
 *
 * With no drive in, the page asks for one, and looks again every two seconds while it is open, so a drive plugged in
 * shows up by itself. Each drive is a row: its name, its room, and the last backup it holds; Back up writes every note
 * into `Ghost.md/` on its root (core/backup.ts). On Android the first backup to a drive opens the system's picker on
 * its root to allow it, once. While a backup runs, how far it has got and Stop; after, what it wrote, and on the Mac a
 * word to eject the drive.
 *
 * Under the drives, each one that holds a backup has its Ghost.md folder as a tree (BackupTree.tsx; docs/DESIGN.md
 * §213): read once for a drive and again when its last backup's time changes, not at every look. An app from before
 * the list (native generation 27) says to update instead.
 */

/** How often the drives are looked for while the page is open. */
export const LOOK_EVERY_MS = 2_000;

type State =
  | { phase: 'idle' }
  | { phase: 'allowing'; drive: BackupDrive }
  | { phase: 'running'; drive: BackupDrive; progress: BackupProgress | null }
  | { phase: 'done'; drive: BackupDrive; backed: Backed }
  | { phase: 'ejected'; name: string }
  | { phase: 'failed'; why: string };

/** A failure as the page says it: Rust answers with a sentence, a page throw with an Error. */
function failureOf(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  return 'The backup could not be written.';
}

/** What a drive's files were read for: the drive, the way in to it, and the backup it held then. */
const heldKey = (drive: BackupDrive) => `${drive.id}|${drive.tree ?? ''}|${drive.last?.backedUpAt ?? ''}`;

/** One drive's tree, built once for the files it was read with. */
function DriveTree({ drive, files }: { drive: BackupDrive; files: HeldFile[] }) {
  const tree = useMemo(() => backupTree(files), [files]);
  return (
    <PaneSection title={`On ${drive.name}`}>
      <BackupTree tree={tree} />
    </PaneSection>
  );
}

/** A drive's row's hint: its room, and the last backup it holds. */
function hintOf(drive: BackupDrive): string {
  const room = drive.free !== null ? `${sizeSaid(drive.free)} free` : null;
  return [room, lastSaid(drive.last)].filter(Boolean).join(' · ');
}

export function BackupPane() {
  const [way, setWay] = useState<BackupWay | null>(null);
  const [drives, setDrives] = useState<BackupDrive[] | null>(null);
  const [state, setState] = useState<State>({ phase: 'idle' });
  // Read by the look for drives, which must not change the page under a backup that is running.
  const busy = useRef(false);
  busy.current = state.phase === 'running' || state.phase === 'allowing';

  useEffect(() => {
    let live = true;
    void backupWay().then((found) => live && setWay(found));
    return () => {
      live = false;
    };
  }, []);

  useEffect(() => {
    if (way !== 'mac' && way !== 'windows' && way !== 'android') return undefined;
    let live = true;
    const look = () => {
      if (busy.current) return;
      void listDrives(way).then(
        (found) => live && setDrives(found),
        () => live && setDrives([]),
      );
    };
    look();
    const timer = window.setInterval(look, LOOK_EVERY_MS);
    return () => {
      live = false;
      window.clearInterval(timer);
    };
  }, [way]);

  // The files each drive's Ghost.md folder holds, by `heldKey`: asked once for a drive and the backup on it.
  const [held, setHeld] = useState<Record<string, HeldFile[] | null>>({});
  const asked = useRef(new Set<string>());
  const [canList, setCanList] = useState(true);
  useEffect(() => {
    let live = true;
    void hasNativeGeneration(BACKUP_FILES_GENERATION).then((can) => live && setCanList(can));
    return () => {
      live = false;
    };
  }, []);
  useEffect(() => {
    if (!way || !drives) return;
    for (const drive of drives) {
      if (!drive.last) continue;
      const key = heldKey(drive);
      if (asked.current.has(key)) continue;
      asked.current.add(key);
      void listBackupFiles(way, drive).then(
        (files) => setHeld((was) => ({ ...was, [key]: files })),
        () => setHeld((was) => ({ ...was, [key]: null })),
      );
    }
  }, [way, drives]);

  const backUp = async (given: BackupDrive) => {
    if (!way) return;
    let drive = given;
    if (way === 'android' && !drive.tree) {
      setState({ phase: 'allowing', drive });
      const answer = await allowDrive(drive.id);
      if ('cancelled' in answer) {
        setState({ phase: 'idle' });
        return;
      }
      if ('error' in answer) {
        setState({ phase: 'failed', why: answer.error });
        return;
      }
      drive = { ...drive, tree: answer.tree };
    }
    setState({ phase: 'running', drive, progress: null });
    try {
      const backed = await runBackup(way, drive, (progress) => setState({ phase: 'running', drive, progress }));
      setState({ phase: 'done', drive, backed });
      void listDrives(way).then(setDrives, () => undefined);
    } catch (error) {
      setState({ phase: 'failed', why: failureOf(error) });
    }
  };

  const eject = (drive: BackupDrive) => {
    ejectDrive(drive).then(
      () => setState({ phase: 'ejected', name: drive.name }),
      (error: unknown) => setState({ phase: 'failed', why: failureOf(error) }),
    );
  };

  if (way === 'none') {
    return <SettingsEmpty icon={<HardDrive size={28} />} title="Backups need the app" body="Back up to a USB drive or an SD card from Ghost.md on a Mac or an Android phone." />;
  }
  if (way === 'update') {
    return <SettingsEmpty icon={<HardDrive size={28} />} title="Update Ghost.md to back up" body="This version of the app can’t write to a drive yet. Settings › About has the update." />;
  }

  const running = state.phase === 'running' ? state : null;
  const progress = running?.progress ?? null;
  const working = state.phase === 'running' || state.phase === 'allowing';

  return (
    <>
      {running ? (
        <SettingsCallout icon={<HardDriveUpload size={20} />} action={<RowAction onPress={cancelBackup}>Stop</RowAction>}>
          <span>
            {progress && progress.total > 0
              ? `Backing up to ${running.drive.name}, ${sizeSaid(progress.done)} of ${sizeSaid(progress.total)}. Keep the drive plugged in.`
              : `Backing up to ${running.drive.name}…`}
          </span>
          {progress ? <ProgressBar aria-label="Backing up" value={progress.done} max={Math.max(progress.total, 1)} size="sm" /> : null}
        </SettingsCallout>
      ) : null}
      {state.phase === 'allowing' ? <SettingsCallout icon={<Usb size={20} />}>Allow Ghost.md to use {state.drive.name}, at the top of the drive.</SettingsCallout> : null}
      {state.phase === 'done' ? (
        <SettingsCallout icon={<CircleCheck size={20} />} action={way === 'mac' ? <RowAction onPress={() => eject(state.drive)}>Eject</RowAction> : undefined}>
          {backedSaid(state.backed, state.drive.name)}
        </SettingsCallout>
      ) : null}
      {state.phase === 'ejected' ? <SettingsCallout icon={<CircleCheck size={20} />}>{state.name} can be unplugged now.</SettingsCallout> : null}
      {state.phase === 'failed' ? <SettingsCallout>{state.why}</SettingsCallout> : null}

      {drives === null ? null : drives.length === 0 ? (
        <SettingsEmpty
          icon={<Usb size={28} />}
          title="Plug in a drive"
          body={`Plug in a USB drive${way === 'android' ? ', or put in an SD card,' : ' or an SD card'} to back up every note onto it. Ghost.md is looking for one now.`}
        />
      ) : (
        <PaneSection title="Back up to">
          {drives.map((drive) => (
            <SettingRow
              key={drive.id}
              icon={<HardDrive size={20} />}
              label={drive.name}
              hint={hintOf(drive)}
              control={
                <RowAction onPress={() => void backUp(drive)} disabled={working}>
                  Back up
                </RowAction>
              }
            />
          ))}
        </PaneSection>
      )}
      {(drives ?? []).map((drive) => {
        const files = drive.last ? held[heldKey(drive)] : null;
        return files && files.length > 0 ? <DriveTree key={drive.id} drive={drive} files={files} /> : null;
      })}
      {!canList && (drives ?? []).some((drive) => drive.last) ? <SettingsFootnote>Update Ghost.md to see the files a drive holds here.</SettingsFootnote> : null}
      <SettingsFootnote>
        Every note goes into a Ghost.md folder at the top of the drive, in your workspaces’ folders, with its version history and its pictures, films and
        recordings. The next backup to the same drive only writes what changed. Nothing leaves this device but onto the drive.
      </SettingsFootnote>
    </>
  );
}
