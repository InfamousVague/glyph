import { allowLocationWhere, type canLocate, type LocateFailure } from '../core/location.ts';

/**
 * What a journal's "With where you are" says under its switch (book/TemplatePicker.tsx; docs/DESIGN.md §142): what
 * keeping a place means on this device, or why entries made here keep none. A fixed sentence for each state, never a
 * name pasted into a frame (docs/DESIGN.md §21). The journal's switch is the choice and travels in its file; these are
 * this device's reasons, which stay here.
 */

/** Why entries made here keep no place, where the device itself cannot say. */
const CANNOT: Partial<Record<LocateFailure, string>> = {
  'local-only': 'Local only is on, so entries made here keep no place.',
  mac: 'This Mac can’t say where it is. Entries made on the phone keep theirs.',
  unavailable: 'Update Ghost.md to keep where entries were written.',
  none: 'This browser can’t say where you are.',
};

export function entryPlaceHint({ can, refused, asksName }: { can: ReturnType<typeof canLocate>; refused: LocateFailure | null; asksName: boolean }): string {
  if (!can.ok && CANNOT[can.why]) return CANNOT[can.why]!;
  if (refused === 'refused' || refused === 'blocked') return `Ghost.md wasn’t allowed to know where you are. ${allowLocationWhere()}, then turn this on again.`;
  return asksName ? 'Each entry keeps where you are. Its name is asked of OpenStreetMap once.' : 'Each entry keeps where you are.';
}
