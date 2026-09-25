import { SegmentedControl, Switch } from '@glacier/react';
import { setPreferences, usePreferences, type MotionSpeed } from '../core/preferences.ts';
import { PaneSection, SettingRow, SettingsFootnote } from './kit/settingsKit.tsx';
import { optionsOf, SPEED_WORDS } from './words.ts';

/**
 * Animations (Matt: "add animations section to settings"): the three pieces of movement Glyph has, each its own
 * switch. On by default, because they are what the app looks like; a phone set to reduce motion is obeyed whatever
 * is chosen here, and switching one off leaves the thing itself working, only still.
 */

const SPEEDS = optionsOf(SPEED_WORDS);

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
      <SettingsFootnote>Your phone's own “reduce motion” setting comes first: with it on, Ghost.md holds still whatever is switched on here.</SettingsFootnote>
    </>
  );
}
