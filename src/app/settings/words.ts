import type { Accent, Density, MotionSpeed, Rounding, TextSize, ThemePref, Typeface } from '../core/preferences.ts';

/**
 * What Settings calls each value of a preference, in one place for both of the places that say it: the pane's own
 * control (a segment, a card, a swatch) and the section's reading in the list (SettingsSheet.tsx). They were two maps
 * each, one beside the control and one beside the reading, and a named theme had reached the pane without reaching
 * the list, which read "dawn" under Appearance while the card said Dawn.
 *
 * Typed by the preference's own union, so a value added to core/preferences.ts fails to compile here until it has a
 * word. Each map is written in the order its control shows the values, which is the order `optionsOf` hands them on.
 */

export const SIZE_WORDS: Record<TextSize, string> = { large: 'Large', larger: 'Larger', largest: 'Largest' };

export const FACE_WORDS: Record<Typeface, string> = { maple: 'Maple Mono', fira: 'Fira Code', inter: 'Inter', noto: 'Noto', plex: 'Plex' };

/**
 * How much air the app gives itself: the kit's own density stops, in Glyph's words. Two stops either side of
 * Comfortable, which is the kit's own default and Glyph's.
 */
export const DENSITY_WORDS: Record<Density, string> = {
  'extra-compact': 'Tightest',
  compact: 'Tight',
  comfortable: 'Comfortable',
  spacious: 'Roomy',
  'more-space': 'Roomiest',
};

/** How round the app's corners are drawn (core/preferences.ts `ROUNDINGS`). */
export const ROUNDING_WORDS: Record<Rounding, string> = { square: 'Square', soft: 'Soft', round: 'Round', rounder: 'Roundest' };

export const SPEED_WORDS: Record<MotionSpeed, string> = { relaxed: 'Relaxed', normal: 'Normal', brisk: 'Brisk' };

/** Each accent by name, for the finger that cannot see the colour as well as for the list's reading. */
export const ACCENT_WORDS: Record<Accent, string> = {
  ink: 'Ink',
  graphite: 'Graphite',
  red: 'Red',
  amber: 'Amber',
  green: 'Green',
  teal: 'Teal',
  purple: 'Purple',
};

export const THEME_WORDS: Record<ThemePref, string> = { system: 'System', light: 'Light', dark: 'Dark', dawn: 'Dawn', boreal: 'Boreal', ember: 'Ember' };

/** A map's values as the options a SegmentedControl takes, in the map's own order. */
export function optionsOf<T extends string>(words: Record<T, string>): { value: T; label: string }[] {
  return (Object.keys(words) as T[]).map((value) => ({ value, label: words[value] }));
}
