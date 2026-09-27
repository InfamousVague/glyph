import { useEffect, useState } from 'react';
import { SegmentedControl, Slider, Switch } from '@glacier/react';
import { defaultHeight, saveHeight, savedHeight, useSideKeySpot } from '../capture/sideKey.ts';
import { SideKeyWaves } from '../capture/SideKeyWaves.tsx';
import { isAndroid } from '../core/platform.ts';
import { setPreferences, usePreferences, type Summaries } from '../core/preferences.ts';
import { PaneSection, RowAction, SettingRow } from './kit/settingsKit.tsx';

/**
 * Recording: how a take ends, what happens to the words afterwards, and - on Android, where there is a side key -
 * where that key is. Listed on Android and on the Mac (SettingsSheet.tsx): the
 * Mac records through Speak, runs the better words and the summaries, and its rows had no home there before
 * (docs/DESIGN.md §127 section 2). The side key's own section is Android's alone.
 */

/** Which recordings are summarised on their own (core/preferences.ts `Summaries`), in the choice's order. */
const SUMMARY_CHOICES: { value: Summaries; label: string }[] = [
  { value: 'meetings', label: 'Meetings' },
  { value: 'long', label: 'Meetings and long voice notes' },
  { value: 'off', label: 'Off' },
];

export function RecordingPane() {
  const prefs = usePreferences();
  return (
    <>
      <PaneSection title={isAndroid ? 'The side key' : 'While recording'}>
        <SettingRow
          label="Stop when I go quiet"
          hint="Saves the recording after four seconds of quiet, once you've started talking. You can still press the side key or tap Done."
          control={<Switch aria-label="Stop when I go quiet" checked={prefs.quietStop} onCheckedChange={(quietStop) => setPreferences({ quietStop })} />}
        />
        <SettingRow
          label="Review after recording"
          hint="When you stop, a slower speech model listens again and the language model thinks the note through out loud, then shows what it would fix for you to keep or commit. For recordings under three minutes."
          control={<Switch aria-label="Review after recording" checked={prefs.review} onCheckedChange={(review) => setPreferences({ review })} />}
        />
      </PaneSection>
      {isAndroid ? <SideKeyPlace /> : null}
      <PaneSection title="After recording">
        <SettingRow
          label="Better words"
          hint="After you finish, a larger model goes over the recording and fixes the words. A few seconds of the phone per minute of speech."
          control={<Switch aria-label="Better words after recording" checked={prefs.refine} onCheckedChange={(refine) => setPreferences({ refine })} />}
        />
        <SettingRow
          label="Summaries"
          hint="The language model on the phone writes a summary under the title. What was said, what was decided, and your to-dos. A long voice note is one over three minutes. A few minutes of the phone for a long recording."
          layout="stacked"
          control={
            <SegmentedControl aria-label="Summaries" fullWidth size="sm" options={SUMMARY_CHOICES} value={prefs.summaries} onValueChange={(value) => setPreferences({ summaries: value as Summaries })} />
          }
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
          label="Use Ghost.md's guess"
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
