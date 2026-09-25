import { useEffect, useState } from 'react';
import { Gauge, Terminal } from '@glacier/icons';
import { Switch } from '@glacier/react';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { resetLocalData } from '../core/reset.ts';
import { GUIDE_MODEL_PAGE } from '../guide/pages.ts';
import { setDeveloperMode, useDeveloperMode } from './developerMode.ts';
import { PaneSection, RowAction, SettingRow } from './kit/settingsKit.tsx';
import { WispBench } from './WispBench.tsx';
import { windowFacts } from './windowFacts.ts';

/**
 * The developer page, present only while developer mode is on (seven presses on the version in About): the welcome
 * guide again, what the window is, the smoke bench, the switch that hides the page, and the two resets.
 */
export function DeveloperPane({ onGuide }: { onGuide: (page?: number) => void }) {
  const on = useDeveloperMode();
  const [bench, setBench] = useState(false);
  return (
    <>
      <PaneSection title="Set-up">
        <SettingRow label="Choose your model" hint="The welcome guide's page, on its own." onPress={() => onGuide(GUIDE_MODEL_PAGE)} />
        <SettingRow label="Welcome guide" hint="From the first page." onPress={() => onGuide(0)} />
      </PaneSection>
      <WindowFacts />
      <PaneSection title="Smoke" description="The wisp edge costs the Mac app frames. This is where it is measured, on the screen it is drawn on.">
        <SettingRow
          icon={<Gauge size={20} />}
          label="Smoke bench"
          hint="A page wearing the filter, the mask or nothing, with its frame times in its header and a run that fills a table."
          onPress={() => setBench(true)}
        />
      </PaneSection>
      <WispBench open={bench} onClose={() => setBench(false)} />
      <PaneSection title="Developer mode">
        <SettingRow
          icon={<Terminal size={20} />}
          label="Developer settings"
          hint="Turning this off hides the page again. Seven taps on the version in About bring it back."
          control={<Switch aria-label="Developer settings" checked={on} onCheckedChange={setDeveloperMode} />}
        />
      </PaneSection>
      <PaneSection title="Reset" description="Two taps: the first arms it, the second does it. Ghost.md reloads on the welcome guide afterwards.">
        <ResetRow
          label="Reset local data"
          hint="Notes, recordings, pictures, settings, the guide and the sign-in go. Downloaded models stay, and so does this page."
          models={false}
        />
        <ResetRow label="Reset everything" hint="The same, and the downloaded models too. They come back when asked for." models />
      </PaneSection>
    </>
  );
}

/** What the window is (windowFacts.ts), read again whenever it changes size. */
function WindowFacts() {
  const [facts, setFacts] = useState(windowFacts);
  useEffect(() => {
    const read = () => setFacts(windowFacts());
    read();
    window.addEventListener('resize', read);
    return () => window.removeEventListener('resize', read);
  }, []);
  return (
    <PaneSection title="Window" description="Read off the page: what it is given at its top, its size against the screen, and what draws it.">
      <SettingRow label="Top inset" hint="The status bar's height when the page is drawn under it; 0 when it is not." value={facts.inset} />
      <SettingRow label="Page" hint="Its size, and pixels to the point." value={facts.page} />
      <SettingRow label="Screen" value={facts.screen} />
      <SettingRow label="Engine" value={facts.engine} />
    </PaneSection>
  );
}

/** How long a reset stays armed after its first tap. */
const ARMED_MS = 5000;

/** A reset that has to be tapped twice: armed for five seconds, then done. A reset that fails says why in its hint. */
function ResetRow({ label, hint, models }: { label: string; hint: string; models: boolean }) {
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  useEffect(() => {
    if (!armed) return undefined;
    const id = window.setTimeout(() => setArmed(false), ARMED_MS);
    return () => window.clearTimeout(id);
  }, [armed]);
  const press = async () => {
    if (!armed) {
      setArmed(true);
      fireNativeHaptic('warning');
      return;
    }
    setBusy(true);
    try {
      await resetLocalData({ models });
    } catch (failure) {
      setProblem(failureText(failure));
      setBusy(false);
      setArmed(false);
    }
  };
  return (
    <SettingRow
      label={label}
      hint={problem ?? hint}
      control={
        <RowAction onPress={() => void press()} disabled={busy}>
          {busy ? 'Resetting' : armed ? 'Tap again' : 'Reset'}
        </RowAction>
      }
    />
  );
}
