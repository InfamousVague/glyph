import { useEffect, useState } from 'react';
import { HardDriveDownload } from '@glacier/icons';
import { ProgressBar } from '@glacier/react';
import { cancelExport, doneSaid, exportEverything, exportWay, sizeSaid, type Exported, type ExportProgress, type ExportWay } from '../core/exportAll.ts';
import { PaneSection, RowAction, SettingRow, SettingsCallout } from './kit/settingsKit.tsx';

/**
 * Settings › Export, a section of its own since §205 (Matt: "export should be a setting section"), a card on Account
 * until then (docs/DESIGN.md §167; Matt: "Please add a feature that allows me to plug in
 * a USB drive and export the entire app onto a folder or zip file with ghostmarkdown_<datetime>.7z or something"). One
 * row: everything, as `ghostmarkdown_<date>_<time>.zip`, wherever the device's own save asks, a drive plugged in among
 * its places (core/exportAll.ts). While it runs, how far it has got and a word to stop it; after, what it wrote.
 */

/** What the row says under its name, by where an export can go from here. */
const HINT: Record<ExportWay, string> = {
  mac: 'Every note, picture, film and recording, as one zip. Choose a USB drive or any folder.',
  android: 'Every note, picture, film and recording, as one zip. Plug in a USB drive and choose it, or any folder.',
  browser: 'Every note and picture this browser keeps, as one zip.',
  update: 'Update Ghost.md to export everything.',
  none: 'Exporting isn’t on iPhone yet.',
};

/** A failure as the card says it: Rust answers with a sentence, a page throw with an Error. */
function failureOf(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  return 'The export could not be written.';
}

type State = { phase: 'idle' } | { phase: 'running'; progress: ExportProgress | null } | { phase: 'done'; exported: Exported } | { phase: 'failed'; why: string };

export function ExportCard() {
  const [way, setWay] = useState<ExportWay | null>(null);
  const [state, setState] = useState<State>({ phase: 'idle' });

  useEffect(() => {
    let live = true;
    void exportWay().then((found) => live && setWay(found));
    return () => {
      live = false;
    };
  }, []);

  const start = () => {
    setState({ phase: 'running', progress: null });
    exportEverything((progress) => setState({ phase: 'running', progress })).then(
      (exported) => setState(exported ? { phase: 'done', exported } : { phase: 'idle' }),
      (error: unknown) => setState({ phase: 'failed', why: failureOf(error) }),
    );
  };

  const running = state.phase === 'running';
  const progress = running ? state.progress : null;
  const can = way === 'mac' || way === 'android' || way === 'browser';

  return (
    <>
      {running ? (
        <SettingsCallout icon={<HardDriveDownload size={20} />} action={<RowAction onPress={cancelExport}>Stop</RowAction>}>
          <span>
            {progress && progress.total > 0
              ? `Exporting, ${sizeSaid(progress.done)} of ${sizeSaid(progress.total)}. Keep Ghost.md open, and the drive plugged in.`
              : 'Choose where the export goes.'}
          </span>
          {progress ? <ProgressBar aria-label="Exporting everything" value={progress.done} max={Math.max(progress.total, 1)} size="sm" /> : null}
        </SettingsCallout>
      ) : null}
      {state.phase === 'done' ? (
        <SettingsCallout icon={<HardDriveDownload size={20} />}>
          {doneSaid(state.exported)}
        </SettingsCallout>
      ) : null}
      {state.phase === 'failed' ? <SettingsCallout>{state.why}</SettingsCallout> : null}

      <PaneSection>
        <SettingRow
          icon={<HardDriveDownload size={20} />}
          label="Export everything"
          hint={way ? HINT[way] : HINT.browser}
          onPress={can && !running ? start : undefined}
          disabled={!can || running}
        />
      </PaneSection>
    </>
  );
}
