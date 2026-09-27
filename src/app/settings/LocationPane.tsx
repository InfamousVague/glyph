import { useState } from 'react';
import { Switch } from '@glacier/react';
import { canLocate, forgetRefusal, locate, whyLocateFailed, type LocateFailure } from '../core/location.ts';
import { setPreferences, usePreferences } from '../core/preferences.ts';
import { PaneSection, RowAction, SettingRow, SettingsFootnote } from './kit/settingsKit.tsx';

/**
 * Location: where a note was written, and the three network things it can mean (core/location.ts). The map at the top
 * of a tagged note asks openstreetmap.org for its tiles; the place's name is asked of OpenStreetMap once when a
 * location is added; and every new note made here can start with where the device was (Matt: "Add a setting to
 * geotag notes by default and turn it on"). Each is its own switch, and Local only turns all of them off, since a fix
 * is a network lookup too. A pane of its own because the privacy switches sit beside their features (Local only under
 * Formatting, Link previews under Type), and this is a feature with three.
 *
 * Turning tagging on asks for a fix once, here, so the permission prompt happens in Settings and never over the
 * recorder. A refusal leaves the switch on, as Matt asked: notes are simply not tagged until location is allowed,
 * and the footnote and each note's More sheet say so.
 */

/** Why tagging cannot happen here, under its switch. */
const CANNOT: Partial<Record<LocateFailure, string>> = {
  'local-only': 'Local only is on.',
  mac: 'This Mac can’t say where it is yet.',
  none: 'This browser can’t say where you are.',
  unavailable: 'Update Ghost.md to tag notes.',
};

export function LocationPane() {
  const prefs = usePreferences();
  const [refused, setRefused] = useState<LocateFailure | null>(null);
  const can = canLocate();
  const localOnly = prefs.localOnly ? 'Local only is on.' : undefined;
  const tagWhy = can.ok ? undefined : CANNOT[can.why];
  const openSettings = typeof window !== 'undefined' && typeof window.GlyphHost?.openLocationSettings === 'function' ? () => void window.GlyphHost?.openLocationSettings?.() : null;

  const flipTagging = (on: boolean) => {
    setPreferences({ tagNewNotes: on });
    setRefused(null);
    if (!on) return;
    // The ask, once, here: a fix now means the next new note's comes without a dialog.
    locate().then(
      () => forgetRefusal(),
      (failure: unknown) => {
        const why = whyLocateFailed(failure);
        if (why === 'refused' || why === 'blocked') setRefused(why);
      },
    );
  };

  return (
    <>
      <PaneSection title="On a note" description="A note can say where it was written. The place is kept in the note's own words, so it goes wherever the note does. A link you share leaves it out unless you say so on the note.">
        <SettingRow
          label="Map on a tagged note"
          hint="A small map at the top of the note. Opening a tagged note fetches the tiles from openstreetmap.org, which sees your IP address, as a website would."
          control={<Switch aria-label="Map on a tagged note" checked={prefs.mapTiles} onCheckedChange={(mapTiles) => setPreferences({ mapTiles })} />}
          disabledReason={localOnly}
        />
        <SettingRow
          label="Place names"
          hint="The name of the place, asked of OpenStreetMap once when you add a location, and kept in the note. Never asked again."
          control={<Switch aria-label="Place names" checked={prefs.placeNames} onCheckedChange={(placeNames) => setPreferences({ placeNames })} />}
          disabledReason={localOnly}
        />
      </PaneSection>
      {prefs.localOnly ? <SettingsFootnote>A tagged note shows its coordinates and a pin while Local only is on, and no new location is taken.</SettingsFootnote> : null}

      <PaneSection title="New notes">
        <SettingRow
          label="Tag new notes with my location"
          hint="Every note you make here starts with where you were, typed or spoken. Off, you add a location by hand from More on a note."
          control={<Switch aria-label="Tag new notes with my location" checked={prefs.tagNewNotes} onCheckedChange={flipTagging} />}
          disabledReason={localOnly ?? tagWhy}
        />
      </PaneSection>
      {refused ? (
        <SettingsFootnote>
          {refused === 'blocked' ? 'Location is off for Ghost.md, so new notes are not tagged. ' : 'Ghost.md wasn’t allowed to know where you are, so new notes are not tagged. '}
          Allow location for Ghost.md in the phone’s settings and they will be.
          {refused === 'blocked' && openSettings ? (
            <>
              {' '}
              <RowAction onPress={openSettings}>Open settings</RowAction>
            </>
          ) : null}
        </SettingsFootnote>
      ) : null}
    </>
  );
}
