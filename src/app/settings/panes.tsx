import { useEffect, useState } from 'react';
import { BookOpen, Terminal } from '@glacier/icons';
import { SegmentedControl, Slider, Switch, useToast } from '@glacier/react';
import { setPreferences, usePreferences, type TextSize, type ThemePref, type Typeface } from '../core/preferences.ts';
import { hapticsAvailable, setHapticsPref, useHapticsPref, fireNativeHaptic } from '../core/haptics.ts';
import { describeBuild, sourceHost, type Updates } from '../core/ota.ts';
import { isTauri } from '../core/tauri.ts';
import { countKnock, KNOCKS_WANTED, setDeveloperMode, useDeveloperMode } from './developerMode.ts';
import { useUpdateAlerts } from './useUpdateAlerts.ts';
import { resetLocalData } from '../core/reset.ts';
import { GUIDE_MODEL_PAGE } from '../guide/pages.ts';
import { PaneHero, PaneSection, RowAction, SettingRow, SettingsFootnote } from './kit/settingsKit.tsx';
import { SideKeyWaves } from '../capture/SideKeyWaves.tsx';
import { defaultHeight, saveHeight, savedHeight, useSideKeySpot } from '../capture/sideKey.ts';

/**
 * The small panes, one function each: Type, Theme, Recording, Feel, Updates,
 * About and Developer. Formatting has a file of its own. Each is a stack of
 * the kit's cards and nothing else; the words they say are Glyph's.
 */

const TEXT_SIZES: { value: TextSize; label: string }[] = [
  { value: 'large', label: 'Large' },
  { value: 'larger', label: 'Larger' },
  { value: 'largest', label: 'Largest' },
];

const TYPEFACES: { value: Typeface; label: string }[] = [
  { value: 'inter', label: 'Inter' },
  { value: 'noto', label: 'Noto' },
  { value: 'plex', label: 'Plex' },
];

const THEMES: { value: ThemePref; label: string }[] = [
  { value: 'system', label: 'System' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
];

export function TypePane() {
  const prefs = usePreferences();
  return (
    <>
      <p className="settingsScreen__sample" aria-hidden="true">
        Aa
      </p>
      <PaneSection title="Size">
        <SettingRow
          label="Text size"
          hint="The note, the list and the headings all follow it."
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Text size"
              fullWidth
              size="sm"
              options={TEXT_SIZES}
              value={prefs.textSize}
              onValueChange={(value) => setPreferences({ textSize: value as TextSize })}
            />
          }
        />
      </PaneSection>
      <PaneSection title="Typeface">
        <SettingRow
          label="Family"
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Typeface"
              fullWidth
              size="sm"
              options={TYPEFACES}
              value={prefs.typeface}
              onValueChange={(value) => setPreferences({ typeface: value as Typeface })}
            />
          }
        />
      </PaneSection>
    </>
  );
}

export function ThemePane() {
  const prefs = usePreferences();
  return (
    <PaneSection title="Page" description="Ink on paper, or paper on ink. System follows the phone.">
      <SettingRow
        label="Theme"
        layout="stacked"
        control={
          <SegmentedControl
            aria-label="Theme"
            fullWidth
            size="sm"
            options={THEMES}
            value={prefs.theme}
            onValueChange={(value) => setPreferences({ theme: value as ThemePref })}
          />
        }
      />
    </PaneSection>
  );
}

export function RecordingPane() {
  const prefs = usePreferences();
  return (
    <>
      <PaneSection title="The side key">
        <SettingRow
          label="Memo mode"
          hint="Recording adds to your last note until you tap New note."
          control={<Switch aria-label="Memo mode" checked={prefs.memo} onCheckedChange={(memo) => setPreferences({ memo })} />}
        />
        <SettingRow
          label="Stop when I go quiet"
          hint="Saves the recording after four seconds of quiet, once you've started talking. You can still press the side key or tap Done."
          control={<Switch aria-label="Stop when I go quiet" checked={prefs.quietStop} onCheckedChange={(quietStop) => setPreferences({ quietStop })} />}
        />
        <SettingRow
          label="Commands start with “Glyph”"
          hint="Say “Glyph, add buy milk to HelloTrade” and it asks before it does it. Off, a command can be said without it, and still asks."
          control={<Switch aria-label="Commands start with Glyph" checked={prefs.commandWord} onCheckedChange={(commandWord) => setPreferences({ commandWord })} />}
        />
      </PaneSection>
      {isTauri() ? <SideKeyPlace /> : null}
      <PaneSection title="After recording">
        <SettingRow
          label="Better words"
          hint="After you finish, a larger model goes over the recording and fixes the words. A few seconds of the phone per minute of speech."
          control={<Switch aria-label="Better words after recording" checked={prefs.refine} onCheckedChange={(refine) => setPreferences({ refine })} />}
        />
      </PaneSection>
    </>
  );
}

/**
 * Where the side key is, for the rings the recorder sends from it. Android
 * does not say where a phone's buttons are, so Glyph guesses from the model
 * and this lets the guess be moved: drag until the glow sits beside the key.
 */
function SideKeyPlace() {
  const [height, setHeight] = useState<number | null>(() => savedHeight());
  const [fallback, setFallback] = useState(0.4);
  useEffect(() => {
    let live = true;
    void defaultHeight().then((value) => {
      if (live) setFallback(value);
    });
    return () => {
      live = false;
    };
  }, []);
  const shown = height ?? fallback;
  const spot = useSideKeySpot(shown);
  return (
    <PaneSection
      title="Where the side key is"
      description="The recorder sends rings from the side key while you talk. If the glow isn't beside your key, slide it there."
    >
      {/* A phone's outline, upright, with the rings coming from its key. Inline so settings.css stays the kit's. */}
      <div
        style={{
          position: 'relative',
          inlineSize: '6.5rem',
          blockSize: '12rem',
          margin: 'var(--glacier-space-2) auto var(--glacier-space-3)',
          border: '2px solid var(--app-ink-3, var(--glacier-border-strong))',
          borderRadius: '1.1rem',
          overflow: 'hidden',
        }}
      >
        <SideKeyWaves spot={spot} contained />
      </div>
      <SettingRow
        label="Height"
        layout="stacked"
        control={
          <Slider
            aria-label="Side key height"
            min={0}
            max={100}
            step={1}
            value={Math.round(shown * 100)}
            onValueChange={(value) => {
              setHeight(value / 100);
              saveHeight(value / 100);
            }}
          />
        }
      />
      {height !== null ? (
        <SettingRow
          label="Use Glyph's guess"
          control={
            <RowAction
              onPress={() => {
                setHeight(null);
                saveHeight(null);
              }}
            >
              Reset
            </RowAction>
          }
        />
      ) : null}
    </PaneSection>
  );
}

export function FeelPane() {
  const haptics = useHapticsPref();
  return (
    <PaneSection title="Touch">
      <SettingRow
        label="Haptics"
        hint="A small tap when a style or a cue kicks in."
        control={<Switch aria-label="Haptics" checked={haptics} onCheckedChange={setHapticsPref} />}
        disabledReason={hapticsAvailable() ? undefined : 'This device has no motor.'}
      />
    </PaneSection>
  );
}

export function UpdatesPane({ updates }: { updates: Updates }) {
  const { ready, apk, checking, lastError, lastChecked } = updates;
  const alerts = useUpdateAlerts();

  if (!isTauri()) {
    return (
      <PaneSection title="This build">
        <SettingRow label="You're on the web version" hint="Reload the page to update." />
      </PaneSection>
    );
  }

  let status: string;
  if (checking) status = 'Checking for updates.';
  else if (apk.kind === 'downloading') status = `Downloading Glyph ${apk.info.version}.`;
  else if (apk.kind === 'available') status = `Glyph ${apk.info.version} is ready to install.`;
  else if (ready) status = 'A new version is downloaded.';
  else if (lastError) status = `Couldn't check for updates: ${lastError}`;
  else if (lastChecked) status = 'Up to date.';
  else status = 'Not checked yet.';
  const installable = apk.kind === 'available' || apk.kind === 'failed' || apk.kind === 'needs-permission';

  return (
    <>
      <PaneSection title="Version">
        <SettingRow label={status} />
      </PaneSection>
      <div className="settingsScreen__actions">
        {ready ? <RowAction onPress={updates.reload}>Reload</RowAction> : null}
        {installable ? <RowAction onPress={updates.installApk}>Install {apk.info.version}</RowAction> : null}
        <RowAction onPress={updates.check} disabled={checking}>
          Check for updates
        </RowAction>
      </div>
      {alerts.available ? (
        <PaneSection title="Alerts">
          <SettingRow
            label="Update alerts"
            hint={
              alerts.state === 'blocked'
                ? "It's on, but Android is blocking Glyph's notifications. Allow them in the app's system settings."
                : 'Get a notification when a new version is out, even when Glyph is closed.'
            }
            control={<Switch aria-label="Update alerts" checked={alerts.state !== 'off'} onCheckedChange={alerts.set} />}
          />
        </PaneSection>
      ) : null}
    </>
  );
}

function buildLine(updates: Updates): string {
  if (!isTauri()) return describeBuild(updates.build);
  const { status } = updates;
  const overTheAir = Boolean(window.__glyphBoot?.build);
  const host = sourceHost(status?.sources?.[0]);
  return [overTheAir ? 'Updated over the air' : 'Built into the app', describeBuild(updates.build), status ? `app ${status.nativeVersion}` : null, host ? `updates from ${host}` : null]
    .filter(Boolean)
    .join(' · ');
}

/**
 * About: the version, big, which is also the door to the developer tools -
 * seven presses on it, the way Android's own are unlocked, with a countdown
 * from the third press so somebody who knows the gesture knows it is working.
 */
export function AboutPane({ updates, onGuide, onDeveloper }: { updates: Updates; onGuide: () => void; onDeveloper: () => void }) {
  const { toast } = useToast();
  const knock = () => {
    const left = countKnock();
    if (left === 0) {
      setDeveloperMode(true);
      fireNativeHaptic('success');
      toast({ message: 'Developer settings are on.', duration: 1800 });
      onDeveloper();
      return;
    }
    if (left <= KNOCKS_WANTED - 3) {
      toast({ message: `${left} more ${left === 1 ? 'tap' : 'taps'} for developer settings.`, duration: 1000 });
    }
  };
  return (
    <>
      <PaneSection>
        <PaneHero title={updates.version} meta={buildLine(updates)} onPress={knock} />
      </PaneSection>
      <PaneSection title="Help">
        <SettingRow icon={<BookOpen size={20} />} label="How to talk to Glyph" hint="The side key, and the cues that make markdown." onPress={onGuide} />
      </PaneSection>
      <SettingsFootnote>Glyph keeps your notes, recordings and models on the phone. Nothing is sent anywhere.</SettingsFootnote>
    </>
  );
}

/**
 * The developer page, present only while developer mode is on. Projects is
 * parked here: the plan is to bring a git project's code into the context a
 * note is formatted with, and the switch holds the place while the formatter
 * itself is finished.
 */
export function DeveloperPane({ onGuide }: { onGuide: (page?: number) => void }) {
  const on = useDeveloperMode();
  return (
    <>
      <PaneSection title="Set-up">
        <SettingRow label="Choose your model" hint="The welcome guide's page, on its own." onPress={() => onGuide(GUIDE_MODEL_PAGE)} />
        <SettingRow label="Welcome guide" hint="From the first page." onPress={() => onGuide(0)} />
      </PaneSection>
      <PaneSection title="Developer mode">
        <SettingRow
          icon={<Terminal size={20} />}
          label="Developer settings"
          hint="Turning this off hides the page again. Seven taps on the version in About bring it back."
          control={<Switch aria-label="Developer settings" checked={on} onCheckedChange={setDeveloperMode} />}
        />
      </PaneSection>
      <PaneSection title="Reset" description="Two taps: the first arms it, the second does it. Glyph reloads on the welcome guide afterwards.">
        <ResetRow
          label="Reset local data"
          hint="Notes, recordings, pictures, settings and the guide go. Downloaded models stay, and so does this page."
          models={false}
        />
        <ResetRow label="Reset everything" hint="The same, and the downloaded models too. They come back when asked for." models />
      </PaneSection>
    </>
  );
}

/** A reset that has to be tapped twice: armed for five seconds, then done. */
function ResetRow({ label, hint, models }: { label: string; hint: string; models: boolean }) {
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  useEffect(() => {
    if (!armed) return undefined;
    const id = window.setTimeout(() => setArmed(false), 5000);
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
      setProblem(failure instanceof Error ? failure.message : String(failure));
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
