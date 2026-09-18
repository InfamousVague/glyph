import { useEffect, useState } from 'react';
import { BookOpen, FileText, GraduationCap, LayoutGrid, ListChecks, Terminal } from '@glacier/icons';
import { SegmentedControl, Slider, Switch, useToast } from '@glacier/react';
import { isSidebarStyle, isUiScale, setPreferences, themeChoice, usePreferences, type Density, type MotionSpeed, type Rounding, type TextSize, type ThemePref, type Typeface } from '../core/preferences.ts';
import { AccentSwatch } from './AccentSwatch.tsx';
import { CODE_THEMES_DARK, CODE_THEMES_LIGHT, type CodeThemeDark, type CodeThemeLight } from '../editor/codeThemes.ts';
import { hapticsAvailable, setHapticsPref, useHapticsPref, fireNativeHaptic } from '../core/haptics.ts';
import { describeBuild, sourceHost, STAGING, type Updates } from '../core/ota.ts';
import { fetchReleases, keptReleases, releaseWhen, type Release } from '../core/changelog.ts';
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

/**
 * How much air the app gives itself: the kit's own density stops, which Glyph has always stamped on the root and
 * never offered (Matt: "Bring over preferences from Attack.FM including themes, density options and more, since we
 * use the same UI kit the settings should port straight over"). Nothing to port but the row: the preference, the
 * attribute and the tokens were already here. Two stops either side of Comfortable, which is the kit's own default
 * and Glyph's.
 */
const DENSITIES: { value: Density; label: string }[] = [
  { value: 'extra-compact', label: 'Tightest' },
  { value: 'compact', label: 'Tight' },
  { value: 'comfortable', label: 'Comfortable' },
  { value: 'spacious', label: 'Roomy' },
  { value: 'more-space', label: 'Roomiest' },
];

/** How round the app's corners are drawn (core/preferences.ts `ROUNDINGS`). */
const ROUNDING_WORDS: { value: Rounding; label: string }[] = [
  { value: 'square', label: 'Square' },
  { value: 'soft', label: 'Soft' },
  { value: 'round', label: 'Round' },
  { value: 'rounder', label: 'Roundest' },
];

const TYPEFACES: { value: Typeface; label: string }[] = [
  { value: 'inter', label: 'Inter' },
  { value: 'noto', label: 'Noto' },
  { value: 'plex', label: 'Plex' },
];

/** Interface size, in AttackFM's own words and steps (core/preferences.ts `UI_SCALES`). */
const UI_SIZES: { value: string; label: string }[] = [
  { value: '0.85', label: '85%' },
  { value: '0.925', label: '93%' },
  { value: '1', label: 'Default' },
  { value: '1.1', label: '110%' },
  { value: '1.25', label: '125%' },
];

const SIDEBAR_MODES: { value: string; label: string }[] = [
  { value: 'popover', label: 'Popover' },
  { value: 'docked', label: 'Docked' },
];

const SPEEDS: { value: MotionSpeed; label: string }[] = [
  { value: 'relaxed', label: 'Relaxed' },
  { value: 'normal', label: 'Normal' },
  { value: 'brisk', label: 'Brisk' },
];

/*
 * The kit's named themes alongside the plain three (Matt: "port Attack.FM's set"): Dawn is light, Boreal and Ember
 * are dark, each with its own tinted greys and an accent that comes with it (core/preferences.ts THEME_PRESETS).
 */
const THEMES: { value: ThemePref; label: string }[] = [
  { value: 'system', label: 'System' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'dawn', label: 'Dawn' },
  { value: 'boreal', label: 'Boreal' },
  { value: 'ember', label: 'Ember' },
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
      <PaneSection title="Links">
        <SettingRow
          label="Link previews"
          hint="A card with the page's title under a line that is only a link. The title is read from the linked site."
          control={<Switch aria-label="Link previews" checked={prefs.linkPreviews} onCheckedChange={(linkPreviews) => setPreferences({ linkPreviews })} />}
        />
      </PaneSection>
    </>
  );
}

/**
 * Appearance: everything about how the app is drawn (Matt: "Change theme to be appearance settings and add the
 * density controller, the accent color picker and the rounding control in there as well as the other existing theme
 * options"). The page first, then its one colour, then how much air it gives itself and how round its corners are,
 * then the colours of code.
 */
export function AppearancePane() {
  const prefs = usePreferences();
  return (
    <>
      <PaneSection title="Page" description="Ink on paper, paper on ink, or one of three tinted themes: Dawn is light, Boreal and Ember are dark, and each brings its own accent. System follows the phone.">
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
              onValueChange={(value) => setPreferences(themeChoice(value as ThemePref, prefs))}
            />
          }
        />
      </PaneSection>
      <PaneSection title="Accent" description="Glyph is ink on paper. An accent colours the few things that mark a choice: a focus ring, a chosen segment. Ink is the app's own.">
        <AccentSwatch accent={prefs.accent} onAccent={(accent) => setPreferences({ accent })} />
      </PaneSection>
      <PaneSection title="Spacing" description="The padding and gaps of everything the app draws. The words keep their own size.">
        <SettingRow
          label="How much air"
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Spacing"
              fullWidth
              size="sm"
              options={DENSITIES}
              value={prefs.density}
              onValueChange={(value) => setPreferences({ density: value as Density })}
            />
          }
        />
      </PaneSection>
      <PaneSection title="Size" description="Everything the app draws, larger or smaller together: buttons, bars and tabs as well as words. Text size, under Type, changes only the words.">
        <SettingRow
          label="Interface size"
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Interface size"
              fullWidth
              size="sm"
              options={UI_SIZES}
              value={String(prefs.uiScale)}
              onValueChange={(value) => {
                const next = Number(value);
                if (isUiScale(next)) setPreferences({ uiScale: next });
              }}
            />
          }
        />
      </PaneSection>
      <PaneSection title="Sidebar" description="The sidebar icon in the top bar opens your notes in a popover over the note. On a wide window it can dock them as a column beside the note instead.">
        <SettingRow
          label="Sidebar"
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Sidebar"
              fullWidth
              size="sm"
              options={SIDEBAR_MODES}
              value={prefs.sidebarStyle}
              onValueChange={(value) => {
                if (isSidebarStyle(value)) setPreferences({ sidebarStyle: value });
              }}
            />
          }
        />
      </PaneSection>
      <PaneSection title="Corners" description="How round a card, a field or a card's corner is drawn. Pills stay pills at every setting.">
        <SettingRow
          label="Rounding"
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Rounding"
              fullWidth
              size="sm"
              options={ROUNDING_WORDS}
              value={prefs.rounding}
              onValueChange={(value) => setPreferences({ rounding: value as Rounding })}
            />
          }
        />
      </PaneSection>
      <PaneSection
        title="Code"
        description="The colours of code in a code block, one set for the light page and one for the dark. Ink keeps code in the page's own ink."
      >
        <SettingRow
          label="On the light page"
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Code colours on the light page"
              fullWidth
              size="sm"
              options={CODE_THEMES_LIGHT}
              value={prefs.codeLight}
              onValueChange={(value) => setPreferences({ codeLight: value as CodeThemeLight, codeChosen: true })}
            />
          }
        />
        <SettingRow
          label="On the dark page"
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Code colours on the dark page"
              fullWidth
              size="sm"
              options={CODE_THEMES_DARK}
              value={prefs.codeDark}
              onValueChange={(value) => setPreferences({ codeDark: value as CodeThemeDark, codeChosen: true })}
            />
          }
        />
      </PaneSection>
    </>
  );
}

export function RecordingPane() {
  const prefs = usePreferences();
  return (
    <>
      <PaneSection title="The side key">
        <SettingRow
          label="Memo mode"
          hint="What you say is kept on a scratch page, then sorted into your notes when you’re done: you see where each part goes before it’s filed. Off, every recording is a plain new note."
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
          control={
            <Switch aria-label="Commands start with Glyph" checked={prefs.commandWord} onCheckedChange={(commandWord) => setPreferences({ commandWord })} />
          }
        />
        <SettingRow
          label="Review after recording"
          hint="When you stop, a slower speech model listens again and the language model thinks the note through out loud, then shows what it would fix for you to keep or commit."
          control={<Switch aria-label="Review after recording" checked={prefs.review} onCheckedChange={(review) => setPreferences({ review })} />}
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

/**
 * Updates, as a part of the About page: where this build stands, the buttons that move it on, and the alerts switch.
 * Was a page of its own (Matt: "combine about whats new and updates settings pages").
 */
function UpdatesSection({ updates }: { updates: Updates }) {
  const { ready, apk, checking, lastError, lastChecked } = updates;
  const alerts = useUpdateAlerts();

  if (!isTauri()) {
    return (
      <PaneSection title="Updates">
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
      <PaneSection title="Updates">
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
  return [
    overTheAir ? 'Updated over the air' : 'Built into the app',
    describeBuild(updates.build),
    status ? `app ${status.nativeVersion}` : null,
    STAGING ? 'staging build, updates off' : host ? `updates from ${host}` : null,
  ]
    .filter(Boolean)
    .join(' · ');
}

/**
 * What's new, as the foot of the About page: every release published, newest first, with the one running marked
 * (core/changelog.ts). Read from the site each time the page opens, and from what was kept when there is no signal
 * (Matt: "show a changelog with all updates including OTA").
 */
function ReleasesSection({ updates }: { updates: Updates }) {
  const [releases, setReleases] = useState<Release[]>(keptReleases);
  const [reading, setReading] = useState(true);
  const running = window.__glyphBoot?.build ?? updates.build;

  useEffect(() => {
    const stop = new AbortController();
    void fetchReleases(updates.status?.sources, stop.signal).then((found) => {
      setReleases(found);
      setReading(false);
    });
    return () => stop.abort();
  }, [updates.status?.sources]);

  if (!releases.length) {
    return (
      <PaneSection title="What's new">
        <SettingRow
          label={reading ? 'Reading the updates…' : 'No updates to show yet.'}
          hint={reading ? undefined : 'They are read from where Glyph takes its updates.'}
        />
      </PaneSection>
    );
  }

  // One group, a row a release: on the About page the list is the foot of it, not a page of cards of its own.
  return (
    <>
      <PaneSection title="What's new" description="Every update, newest first. A version with an app number needs installing.">
        {releases.map((release) => (
          <SettingRow
            key={release.build}
            label={release.build === running ? `${release.version} · you're on this one` : release.version}
            value={releaseWhen(release)}
            hint={[release.notes, release.apk ? `Installed as Glyph ${release.apk}.` : null].filter(Boolean).join(' ')}
          />
        ))}
      </PaneSection>
    </>
  );
}

/**
 * Animations (Matt: "add animations section to settings"): the three pieces of movement Glyph has, each its own
 * switch. On by default, because they are what the app looks like; a phone set to reduce motion is obeyed whatever
 * is chosen here, and switching one off leaves the thing itself working, only still.
 */
export function AnimationsPane() {
  const prefs = usePreferences();
  return (
    <>
      <PaneSection title="Speed" description="How quickly letters gather and screens and sheets move.">
        <SettingRow
          label="Animation speed"
          layout="stacked"
          control={
            <SegmentedControl
              aria-label="Animation speed"
              fullWidth
              size="sm"
              options={SPEEDS}
              value={prefs.motionSpeed}
              onValueChange={(value) => setPreferences({ motionSpeed: value as MotionSpeed })}
            />
          }
        />
      </PaneSection>
      <PaneSection title="Movement" description="Switch any of it off and what it belongs to still works; it simply holds still.">
        <SettingRow
          label="Ghostly typing"
          hint="Letters arrive as smoke and gather into words as you talk or type, and dissolve where they are deleted."
          control={<Switch aria-label="Ghostly typing" checked={prefs.wisp} onCheckedChange={(wisp) => setPreferences({ wisp })} />}
        />
        <SettingRow
          label="Smoke at the edges"
          hint="A page going under the header or the dock turns to smoke as it passes, rather than sliding under a hard line."
          control={<Switch aria-label="Smoke at the edges" checked={prefs.wispEdge} onCheckedChange={(wispEdge) => setPreferences({ wispEdge })} />}
        />
        <SettingRow
          label="Ripples while recording"
          hint="The newest words move with your voice as the phone hears it."
          control={<Switch aria-label="Ripples while recording" checked={prefs.ripples} onCheckedChange={(ripples) => setPreferences({ ripples })} />}
        />
      </PaneSection>
      <SettingsFootnote>Your phone's own “reduce motion” setting comes first: with it on, Glyph holds still whatever is switched on here.</SettingsFootnote>
    </>
  );
}

/**
 * About, updates and what's new, as one page (Matt: "combine about whats new and updates settings pages"): the
 * version, big, then where this build stands and how to move it on, then help, then every release published.
 *
 * The version is also the door to the developer tools - seven presses on it, the way Android's own are unlocked, with
 * a countdown from the third press so somebody who knows the gesture knows it is working.
 */
export function AboutPane({
  updates,
  onGuide,
  onSample,
  onBoard,
  onAcademy,
  onCheatSheet,
  onDeveloper,
}: {
  updates: Updates;
  onGuide: () => void;
  onSample: () => void;
  onBoard: () => void;
  onAcademy: () => void;
  onCheatSheet: () => void;
  onDeveloper: () => void;
}) {
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
      <UpdatesSection updates={updates} />
      <PaneSection title="Help">
        <SettingRow
          icon={<GraduationCap size={20} />}
          label="Glyph Academy"
          hint="Markdown taught a mark at a time: it shows you one, you type your own, and you watch it format underneath."
          onPress={() => onAcademy()}
        />
        <SettingRow
          icon={<BookOpen size={20} />}
          label="How to talk to Glyph"
          hint="The side key, and the cues that make markdown."
          onPress={() => onGuide()}
        />
        <SettingRow
          icon={<ListChecks size={20} />}
          label="Formatting cheat sheet"
          hint="Every mark you can type, with what it looks like, in one page to look things up in."
          onPress={() => onCheatSheet()}
        />
        <SettingRow
          icon={<LayoutGrid size={20} />}
          label="Add the example board"
          hint="A working board written in markdown: columns, cards, and the items they point at."
          onPress={onBoard}
        />
        <SettingRow
          icon={<FileText size={20} />}
          label="Add the sample note"
          hint="One note with every mark in it: headings, lists, a table, a picture, a secret in smoke."
          onPress={onSample}
        />
      </PaneSection>
      <ReleasesSection updates={updates} />
      <SettingsFootnote>
        Glyph keeps your notes, recordings and models on the phone. Signed in to an account, your notes, recordings and settings are synced, encrypted on the phone first so only your own devices
        can read them. With link previews on, a linked page is asked for its title. Nothing else is sent anywhere.
      </SettingsFootnote>
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
