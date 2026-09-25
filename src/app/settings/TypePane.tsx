import { SegmentedControl, Switch } from '@glacier/react';
import { facesOf, INTERFACE_FACES, setPreferences, TYPEFACES, usePreferences, type TextSize } from '../core/preferences.ts';
import { PaneSection, SettingRow } from './kit/settingsKit.tsx';
import { TypefaceCards } from './TypefaceCards.tsx';
import { optionsOf, SIZE_WORDS } from './words.ts';

/**
 * Type: how big the words are, which faces they are set in - the note's and the interface's - and whether a line
 * that is only a link grows a card with the page's title.
 */

const TEXT_SIZES = optionsOf(SIZE_WORDS);

export function TypePane() {
  const prefs = usePreferences();
  const faces = facesOf(prefs);
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
        {/* Two faces (Matt: "font pairs ... make both kinds of fonts pickable"): the note's, and the interface's. */}
        <SettingRow
          label="Note font"
          hint="The words of a note and its code. Maple Mono and Fira Code join pairs like -> and != into one sign."
          layout="stacked"
          control={<TypefaceCards label="Note font" kind="note" faces={TYPEFACES} value={faces.note} onValueChange={(noteFace) => setPreferences({ noteFace })} />}
        />
        <SettingRow
          label="Interface font"
          hint="Tabs, lists, Settings and buttons."
          layout="stacked"
          control={<TypefaceCards label="Interface font" kind="interface" faces={INTERFACE_FACES} value={faces.ui} onValueChange={(typeface) => setPreferences({ typeface })} />}
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
