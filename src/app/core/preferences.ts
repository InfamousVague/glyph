import { useSyncExternalStore } from 'react';

/**
 * The look-and-feel knobs, and how they reach the tokens.
 *
 * Glacier ships no ThemeProvider: an app stamps `data-*` attributes on
 * `<html>` and the generated token CSS keys off them. The one rule that is
 * easy to get wrong is that a value equal to its default must REMOVE the
 * attribute rather than write it, because the `:root` block holds the defaults
 * and an explicit `data-accent='blue'` matches no selector at all.
 */

export type ThemePref = 'system' | 'light' | 'dark';
export type Density = 'extra-compact' | 'compact' | 'comfortable' | 'spacious' | 'more-space';
/** The reader's dial on the type scale in app.css; 'large' is already large. */
export type TextSize = 'large' | 'larger' | 'largest';
/** The kit's three sans families. 'inter' is the token default. */
export type Typeface = 'inter' | 'noto' | 'plex';

export interface Preferences {
  theme: ThemePref;
  /**
   * Kept only so preferences saved by an older build still load. Glyph is ink
   * (app/ink.css): there is no accent to choose, and none is ever stamped.
   */
  accent: string;
  density: Density;
  /** Prose input aids in the editor: autocorrect, autocapitalisation, spellcheck. */
  assist: boolean;
  textSize: TextSize;
  typeface: Typeface;
  /**
   * Memo mode: recording - the Speak button or the side key - keeps adding to
   * the last spoken note until New note is tapped on the recorder. Off, every
   * recording is a new note.
   */
  memo: boolean;
  /**
   * Better words after recording: a larger, slower model goes over the kept
   * recording in the background and replaces the live words (capture/refine.ts).
   */
  refine: boolean;
  /**
   * Stop when I go quiet: a recording that has heard words saves itself after
   * a few seconds of quiet (capture/quiet.ts). Off by default: a pause to
   * think should not end a note unless someone asked for that.
   */
  quietStop: boolean;
  /**
   * Commands while recording ("add buy milk to HelloTrade") only count after
   * "Glyph" is said (capture/command.ts). On by default: Matt, after a command
   * became a note, "not do anything until it hears the keyword". Every command
   * asks before it acts, either way.
   */
  commandWord: boolean;
  /** Which model formats notes on the phone, by its id in core/ai.ts. */
  formatModel: string;
}

export const DEFAULT_PREFERENCES: Preferences = {
  theme: 'dark',
  accent: 'blue',
  density: 'comfortable',
  assist: true,
  textSize: 'large',
  typeface: 'inter',
  memo: true,
  refine: true,
  quietStop: false,
  commandWord: true,
  formatModel: 'qwen3.5-4b',
};

const STORAGE_KEY = 'glyph-preferences';
const listeners = new Set<() => void>();
let current: Preferences = load();

function load(): Preferences {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_PREFERENCES;
    return { ...DEFAULT_PREFERENCES, ...(JSON.parse(raw) as Partial<Preferences>) };
  } catch {
    return DEFAULT_PREFERENCES;
  }
}

export function preferences(): Preferences {
  return current;
}

export function setPreferences(next: Partial<Preferences>): void {
  current = { ...current, ...next };
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(current));
  } catch {
    // The choice still applies for this run.
  }
  applyPreferences(current);
  for (const l of listeners) l();
}

export function usePreferences(): Preferences {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    preferences,
    () => DEFAULT_PREFERENCES,
  );
}

/** Whether the editor should be built with CodeMirror's dark base rules. */
export function isDarkNow(theme: ThemePref): boolean {
  if (theme === 'dark') return true;
  if (theme === 'light') return false;
  return typeof matchMedia !== 'undefined' && matchMedia('(prefers-color-scheme: dark)').matches;
}

/**
 * Reflect the preferences onto the document element. Each value equal to its
 * default clears its attribute so the token `:root` defaults win, which is how
 * the Glacier docs app and AttackFM both drive their theming.
 */
export function applyPreferences(prefs: Preferences = current): void {
  const root = document.documentElement;

  if (prefs.theme === 'system') root.removeAttribute('data-theme');
  else root.setAttribute('data-theme', prefs.theme);

  if (prefs.density === DEFAULT_PREFERENCES.density) root.removeAttribute('data-density');
  else root.setAttribute('data-density', prefs.density);

  // Never an accent: ink.css maps the accent to ink, and a stale attribute from
  // an older build would only re-tint the kit's ramps underneath it.
  root.removeAttribute('data-accent');

  if (prefs.textSize === DEFAULT_PREFERENCES.textSize) root.removeAttribute('data-text-size');
  else root.setAttribute('data-text-size', prefs.textSize);

  // `data-font` is the token layer's own attribute (tokens.css), so the kit's
  // components change face along with the editor.
  if (prefs.typeface === DEFAULT_PREFERENCES.typeface) root.removeAttribute('data-font');
  else root.setAttribute('data-font', prefs.typeface);
}
