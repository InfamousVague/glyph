import { DensitySelector, SegmentedControl } from '@glacier/react';
import { isSidebarStyle, setPreferences, themeChoice, usePreferences, type Rounding, type SidebarStyle } from '../core/preferences.ts';
import { CODE_THEMES_DARK, CODE_THEMES_LIGHT, type CodeThemeDark, type CodeThemeLight } from '../editor/codeThemes.ts';
import { AccentSwatch } from './AccentSwatch.tsx';
import { PaneSection, SettingRow } from './kit/settingsKit.tsx';
import { ScaleCards } from './ScaleCards.tsx';
import { ThemeCards } from './ThemeCards.tsx';
import { DENSITY_WORDS, optionsOf, ROUNDING_WORDS } from './words.ts';

/**
 * Appearance: everything about how the app is drawn (Matt: "Change theme to be appearance settings and add the
 * density controller, the accent color picker and the rounding control in there as well as the other existing theme
 * options"). The page first, then its one colour, then how much air it gives itself and how round its corners are,
 * then the colours of code.
 *
 * Spacing is the kit's own density stops, which Glyph always stamped on the root and never offered (Matt: "Bring over
 * preferences from Attack.FM including themes, density options and more, since we use the same UI kit the settings
 * should port straight over"): nothing to port but the row, since the preference, the attribute and the tokens were
 * already here.
 */

const ROUNDINGS = optionsOf(ROUNDING_WORDS);

const SIDEBAR_MODES: { value: SidebarStyle; label: string }[] = [
  { value: 'popover', label: 'Popover' },
  { value: 'docked', label: 'Docked' },
];

export function AppearancePane() {
  const prefs = usePreferences();
  return (
    <>
      <PaneSection title="Page" description="Ink on paper, paper on ink, or one of three tinted themes: Dawn is light, Boreal and Ember are dark, and each brings its own accent. System follows the phone.">
        {/* The kit's theme cards (ThemeCards.tsx): each is the page painted small in that theme, System split light and dark. */}
        <div className="setk-row">
          <ThemeCards value={prefs.theme} onValueChange={(value) => setPreferences(themeChoice(value, prefs))} />
        </div>
      </PaneSection>
      <PaneSection title="Accent" description="Ghost.md is ink on paper. An accent colours the few things that mark a choice: a focus ring, a chosen segment. Ink is the app's own.">
        <AccentSwatch accent={prefs.accent} onAccent={(accent) => setPreferences({ accent })} />
      </PaneSection>
      <PaneSection title="Spacing" description="The padding and gaps of everything the app draws. The words keep their own size.">
        {/* The kit's own density picker: a card per step, each showing how tightly it packs, in Glyph's words. */}
        <div className="setk-row">
          <DensitySelector aria-label="Spacing" value={prefs.density} onValueChange={(value) => setPreferences({ density: value })} labels={DENSITY_WORDS} />
        </div>
      </PaneSection>
      <PaneSection title="Size" description="Everything the app draws, larger or smaller together: buttons, bars and tabs as well as words. Text size, under Type, changes only the words.">
        {/* A card per step, each the same row of the app drawn at that size (ScaleCards.tsx). */}
        <div className="setk-row">
          <ScaleCards value={prefs.uiScale} onValueChange={(uiScale) => setPreferences({ uiScale })} />
        </div>
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
              options={ROUNDINGS}
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
