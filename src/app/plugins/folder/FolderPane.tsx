import { useCallback, useEffect, useState } from 'react';
import { Folder, FolderOpen, HardDrive, Info, TriangleAlert } from '@glacier/icons';
import { PaneHero, PaneSection, RowAction, SettingRow, SettingsCallout, SettingsEmpty, SettingsFootnote } from '../../settings/kit/settingsKit.tsx';
import { backToOwnFolder, candidateSaid, chooseFolder, failureOf, folderWay, libraryStatus, moveLibrary, movedSaid, type Candidate, type FolderWay, type LibraryStatus, type Moved } from './folder.ts';

/**
 * Settings › Plugins › Library folder (docs/DESIGN.md §187). Matt: "include #6 as a plugin", #6 being "An Obsidian
 * vault, iCloud Drive or Dropbox. Notes are already plain Markdown files. Letting you choose where the library folder
 * lives would make Obsidian, backups and other editors work for free."
 *
 * Where the notes are now; Choose a folder…, which opens the system's own panel or picker and then says, before
 * anything moves, what is in the folder and what will happen to the notes; Use Ghost.md's own folder, with a copy of
 * the notes or none; and what is good to know, by device. Nothing here deletes a file in a folder of the person's, and
 * the page says so where it matters.
 */

/** Why the page cannot choose a folder here, when it cannot. */
const UNAVAILABLE: Record<Exclude<FolderWay, 'mac' | 'android'>, { title: string; body: string }> = {
  browser: { title: 'Only in the app', body: 'In a browser the notes are kept by the browser itself. The Mac and Android apps keep them as Markdown files, in a folder you can choose here.' },
  update: { title: 'Needs the app’s next update', body: 'This version of Ghost.md keeps the notes in its own folder only. Update it to choose another.' },
  none: { title: 'Not on iPhone yet', body: 'On an iPhone the notes stay in Ghost.md’s own folder for now.' },
};

/** What the page is doing: nothing, a folder looked into and waiting for a yes, the way home being asked, or a move under way. */
type Step = { kind: 'idle' } | { kind: 'confirm'; candidate: Candidate } | { kind: 'home' } | { kind: 'moving' };

function whereSaid(status: LibraryStatus): { label: string; hint: string } {
  const count = status.notes === 1 ? '1 note' : `${status.notes} notes`;
  if (status.kind === 'app') return { label: 'Ghost.md’s own folder', hint: `${count}. ${status.own ?? 'Inside the app’s storage.'}` };
  if (status.kind === 'folder') return { label: status.name ?? 'A folder of yours', hint: `${count}. ${status.path ?? ''}`.trim() };
  return { label: status.name || 'A folder of yours', hint: `${count}. Chosen on this phone.` };
}

export function FolderPane() {
  const [way, setWay] = useState<FolderWay | null>(null);
  const [status, setStatus] = useState<LibraryStatus | null>(null);
  const [step, setStep] = useState<Step>({ kind: 'idle' });
  const [said, setSaid] = useState<{ text: string; failed: boolean } | null>(null);

  const read = useCallback(async () => {
    try {
      setStatus(await libraryStatus());
    } catch (error) {
      setSaid({ text: failureOf(error), failed: true });
    }
  }, []);

  useEffect(() => {
    let live = true;
    void folderWay().then((found) => {
      if (!live) return;
      setWay(found);
      if (found === 'mac' || found === 'android') void read();
    });
    return () => {
      live = false;
    };
  }, [read]);

  const choose = async () => {
    setSaid(null);
    try {
      const candidate = await chooseFolder();
      setStep(candidate ? { kind: 'confirm', candidate } : { kind: 'idle' });
    } catch (error) {
      setSaid({ text: failureOf(error), failed: true });
    }
  };

  const run = async (move: () => Promise<Moved>, done: (text: string) => string) => {
    setStep({ kind: 'moving' });
    try {
      const moved = await move();
      setStatus(moved.status);
      setSaid({ text: done(movedSaid(moved)), failed: false });
    } catch (error) {
      setSaid({ text: failureOf(error), failed: true });
    }
    setStep({ kind: 'idle' });
  };

  if (way && way !== 'mac' && way !== 'android') {
    const why = UNAVAILABLE[way];
    return (
      <>
        <Hero />
        <SettingsEmpty icon={<Folder size={22} />} title={why.title} body={why.body} />
      </>
    );
  }

  const where = status ? whereSaid(status) : null;
  const own = status?.kind === 'app' || status?.reachable === false;
  const moving = step.kind === 'moving';

  return (
    <>
      <Hero />

      {status && !status.reachable ? (
        <SettingsCallout icon={<TriangleAlert size={18} />}>
          {status.name ?? 'Your folder'} can’t be reached: a drive unplugged, a folder moved, or the phone’s permission taken back. Ghost.md is using its own folder until it is back, and the notes in yours are
          untouched. Open Ghost.md again once it is back, or choose it again.
        </SettingsCallout>
      ) : null}
      {said ? <SettingsCallout icon={said.failed ? <TriangleAlert size={18} /> : <Info size={18} />}>{said.text}</SettingsCallout> : null}

      <PaneSection title="Where your notes are" description="Each note is a Markdown file, in a folder for its workspace, so any app that opens a folder of Markdown opens these.">
        <SettingRow icon={<FolderOpen size={16} />} label={where?.label ?? 'Reading…'} hint={where?.hint} />
        <SettingRow icon={<Folder size={16} />} label="Choose a folder…" hint={way === 'android' ? 'In the phone’s folder picker.' : 'In the Mac’s folder panel.'} onPress={moving ? undefined : () => void choose()} disabled={moving} />
        {status && status.kind !== 'app' ? (
          <SettingRow icon={<HardDrive size={16} />} label="Use Ghost.md’s own folder" hint="Your folder keeps every file." onPress={moving ? undefined : () => setStep({ kind: 'home' })} disabled={moving} />
        ) : null}
      </PaneSection>

      {step.kind === 'confirm' ? (
        <PaneSection title={`Use ${step.candidate.name}?`} description={candidateSaid(step.candidate, own)}>
          <SettingRow
            label="Use this folder"
            hint={step.candidate.path ?? undefined}
            control={
              <>
                <RowAction onPress={() => void run(moveLibrary, (text) => `Your notes are in ${step.candidate.name} now. ${text}`)}>Use it</RowAction>
                <RowAction onPress={() => setStep({ kind: 'idle' })}>Cancel</RowAction>
              </>
            }
          />
        </PaneSection>
      ) : null}

      {step.kind === 'home' ? (
        <PaneSection title="Back to Ghost.md’s own folder?" description={`${where?.label ?? 'Your folder'} keeps every file either way: Ghost.md never deletes anything in a folder of yours.`}>
          <SettingRow label="Bring a copy back" hint="Every note in the folder, copied into Ghost.md’s own." control={<RowAction onPress={() => void run(() => backToOwnFolder(true), (text) => `Back in Ghost.md’s own folder. ${text}`)}>Copy</RowAction>} />
          <SettingRow label="Start empty" hint="Ghost.md’s own folder as it is, and nothing copied." control={<RowAction onPress={() => void run(() => backToOwnFolder(false), () => 'Back in Ghost.md’s own folder.')}>Start</RowAction>} />
          <SettingRow label="Stay in the folder" control={<RowAction onPress={() => setStep({ kind: 'idle' })}>Cancel</RowAction>} />
        </PaneSection>
      ) : null}

      {moving ? <SettingsCallout icon={<Folder size={18} />}>Moving your notes. Keep Ghost.md open.</SettingsCallout> : null}

      <PaneSection title="Good to know">
        {way === 'android' ? (
          <>
            <SettingRow label="A folder on the phone is the reliable one" hint="Syncthing keeps one in step with a computer. Dropbox and Google Drive reach Ghost.md through their own apps, which may keep a note online only and open it slowly." />
            <SettingRow label="iCloud Drive" hint="Has no Android app, so it isn’t in the picker. Choose it on the Mac." />
          </>
        ) : (
          <>
            <SettingRow label="iCloud Drive and Dropbox" hint="With storage optimised, a note the Mac has taken off its disk stays in the list, and comes down when it is opened." />
            <SettingRow label="Obsidian" hint="Its notes keep their names and their properties when Ghost.md edits them, so links still find them. .obsidian and its trash are left alone." />
          </>
        )}
        <SettingRow label="Sync" hint="The folder’s own Markdown files become notes, so with an account they go to your other devices too." />
        <SettingRow label="What stays in Ghost.md" hint="Pictures, films and recordings, and the index that makes the list instant: never in your folder, so a sync service never copies half of it." />
      </PaneSection>

      <SettingsFootnote>
        Ghost.md keeps a small .glyph folder in yours for what a note has that isn’t words (a recording’s phrases). A reset in Developer forgets the folder and leaves every file in it.
      </SettingsFootnote>
    </>
  );
}

function Hero() {
  return (
    <PaneSection>
      <PaneHero glyph={<Folder size={22} />} title="Library folder" meta="Keep your notes in a folder of your own: an Obsidian vault, iCloud Drive or Dropbox, a Syncthing folder, a backup drive. They are Markdown files already." />
    </PaneSection>
  );
}
