import { useEffect, useState } from 'react';
import { Gauge, Smartphone, Terminal } from '@glacier/icons';
import { SegmentedControl, Switch } from '@glacier/react';
import { useAnyRunning } from '../ai/runs.ts';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { resetLocalData } from '../core/reset.ts';
import { SceneBench } from '../diag/SceneBench.tsx';
import { WispBench } from '../diag/WispBench.tsx';
import { windowFacts } from '../diag/windowFacts.ts';
import type { SceneScript } from '../scene/scripted.ts';
import { setDeveloperMode, useDeveloperMode } from './developerMode.ts';
import { PaneSection, RowAction, SettingRow } from './kit/settingsKit.tsx';

/**
 * The developer page, present only while developer mode is on (seven presses on the version in About): what the
 * window is, the smoke bench, the scene after Done played from a script, the switch that hides the page, and the two
 * resets.
 *
 * Since docs/DESIGN.md §138 there is no Set-up card: its "Choose your model" was the walkthrough's model page alone,
 * the same choice as Recording's Model card, and its "Welcome guide" exactly About's welcome walkthrough. The scene's
 * three rows, one per set of readings, are one choice of readings and one row that plays it.
 *
 * What the search finds here is DeveloperPane.findable.ts, in this page's order.
 */

/** Which readings the scene plays with (scene/scripted.ts `SceneScript`), in the choice's order. */
const READINGS: { value: SceneScript; label: string }[] = [
  { value: 'heat', label: 'Heat' },
  { value: 'cold', label: 'No heat' },
  { value: 'none', label: 'None' },
];

export function DeveloperPane() {
  const on = useDeveloperMode();
  const [bench, setBench] = useState(false);
  const [readings, setReadings] = useState<SceneScript>('heat');
  const [scene, setScene] = useState<SceneScript | null>(null);
  // The bench's run would queue behind a real one and then play against the real engine: not while the model is on a note.
  const busy = useAnyRunning();
  const busyReason = 'The model is on a note. Try again when it is done.';
  return (
    <>
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
      <PaneSection title="The phone at work" description="The scene after Done, played from a script. The models are pretend, the screen is this one, and the words are the note's.">
        <SettingRow
          label="Readings"
          hint="With a heat reading, without one as on a phone that hides its thermal zones, or with none as on the Mac or a binary before generation 14."
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Readings"
              fullWidth
              size="sm"
              options={READINGS}
              value={readings}
              onValueChange={(value) => setReadings(READINGS.find((choice) => choice.value === value)?.value ?? 'heat')}
            />
          }
        />
        <SettingRow
          icon={<Smartphone size={20} />}
          label="Play the scene"
          hint="Listening again, then the run: loading, reading, thinking, writing, done."
          onPress={() => setScene(readings)}
          disabled={busy}
          disabledReason={busy ? busyReason : undefined}
        />
      </PaneSection>
      <SceneBench script={scene} onClose={() => setScene(null)} />
      <PaneSection title="Developer mode">
        <SettingRow
          icon={<Terminal size={20} />}
          label="Developer settings"
          hint="Turning this off hides the page again. Seven taps on the version in About bring it back."
          control={<Switch aria-label="Developer settings" checked={on} onCheckedChange={setDeveloperMode} />}
        />
      </PaneSection>
      <PaneSection title="Reset" description="Two taps: the first arms it, the second does it. Ghost.md reloads on the welcome walkthrough afterwards.">
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

/** What the window is (diag/windowFacts.ts), read again whenever it changes size. */
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
