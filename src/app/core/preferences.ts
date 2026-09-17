import { useSyncExternalStore } from 'react';
import { isCodeThemeDark, isCodeThemeLight, type CodeThemeDark, type CodeThemeLight } from '../editor/codeThemes.ts';
import { isNoteView, type NoteView } from '../editor/viewMode.ts';

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

/** How quickly things move (Settings > Animations; Matt: "add controls to animation speeds"). */
export type MotionSpeed = 'relaxed' | 'normal' | 'brisk';

/** How much longer (above 1) or shorter (below 1) every animation runs at a speed. */
export const MOTION_SCALE: Record<MotionSpeed, number> = { relaxed: 1.6, normal: 1, brisk: 0.6 };

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
   * Memo mode: recording - the Speak button or the side key - writes to a
   * scratch page, sorted into notes when it ends (capture/scratch.ts, sort/;
   * Matt: "not real until the memo is done, then the AI can figure out how to
   * sort"). It used to keep adding to the last spoken note. Off, every
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
  /**
   * After Stop, the review (review/): the slower speech model listens again and
   * the language model, thinking out loud, checks the note; the person keeps
   * or commits what it finds. On by default: Matt asked for it.
   */
  review: boolean;
  /**
   * Nothing leaves the phone and nothing arrives: no update checks, no model
   * downloads, and plugins that use the network are off. Glyph runs from what
   * is on the phone. Matt: "the app can be run totally without a server if desired".
   */
  localOnly: boolean;
  /** Which model formats notes on the phone, by its id in core/ai.ts. */
  formatModel: string;
  /** Colours for code on the light page and on the dark one (editor/codeThemes.ts); 'ink' keeps code in the page's ink. */
  codeLight: CodeThemeLight;
  codeDark: CodeThemeDark;
  /** Whether the code colours were picked in Settings; until they are, they follow the default (Pastel). */
  codeChosen: boolean;
  /** How notes are shown: marks and formatting together, or just the formatted text (editor/viewMode.ts). */
  noteView: NoteView;
  /**
   * The app's movement, three switches under Settings > Animations (Matt: "add animations section to settings").
   * On by default, every one of them: they are what Glyph looks like. A phone asking for less motion is obeyed
   * whatever these say (app.css `prefers-reduced-motion`).
   *
   * `wisp` is the ghostly typing, letters arriving and leaving as smoke (editor/wispArrivals.ts); `wispEdge` the
   * smoke where a page slips under its header (art/wispEdge.ts); `ripples` the rings that answer a voice while
   * recording (capture/LivePage.tsx).
   */
  wisp: boolean;
  wispEdge: boolean;
  ripples: boolean;
  /** The pace of all of it: the typing smoke, and the app's own movement between screens and sheets. */
  motionSpeed: MotionSpeed;
  /**
   * A card under a line that is only a link, with the page's title (editor/linkCards.ts). Reading the title asks
   * the linked site, so it can be switched off.
   */
  linkPreviews: boolean;
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
  review: true,
  localOnly: false,
  formatModel: 'qwen3.5-4b',
  codeLight: 'pastel',
  codeDark: 'pastel',
  codeChosen: false,
  noteView: 'mixed',
  wisp: true,
  wispEdge: true,
  ripples: true,
  motionSpeed: 'normal',
  linkPreviews: true,
};

const STORAGE_KEY = 'glyph-preferences';
const listeners = new Set<() => void>();
let current: Preferences = load();

function load(): Preferences {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_PREFERENCES;
    const loaded = { ...DEFAULT_PREFERENCES, ...(JSON.parse(raw) as Partial<Preferences>) };
    // A theme a later build removed falls back to the default rather than to no colours at all.
    if (!isCodeThemeLight(loaded.codeLight) || !loaded.codeChosen) loaded.codeLight = DEFAULT_PREFERENCES.codeLight;
    if (!isCodeThemeDark(loaded.codeDark) || !loaded.codeChosen) loaded.codeDark = DEFAULT_PREFERENCES.codeDark;
    if (!isNoteView(loaded.noteView)) loaded.noteView = DEFAULT_PREFERENCES.noteView;
    if (!(loaded.motionSpeed in MOTION_SCALE)) loaded.motionSpeed = DEFAULT_PREFERENCES.motionSpeed;
    return loaded;
  } catch {
    return DEFAULT_PREFERENCES;
  }
}

export function preferences(): Preferences {
  return current;
}

/** The chosen pace as a multiplier for a duration: 1 at the normal speed. */
export function motionScale(prefs: Preferences = current): number {
  return MOTION_SCALE[prefs.motionSpeed] ?? 1;
}

/** The kit's duration tokens (Glacier's tokens.css), which its components and app.css move by. */
const DURATIONS: [string, number][] = [
  ['--glacier-duration-instant', 75],
  ['--glacier-duration-fast', 150],
  ['--glacier-duration-normal', 250],
  ['--glacier-duration-slow', 400],
  ['--glacier-duration-slower', 600],
];

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

/** Called after every change, for code outside React that must follow a preference. */
export function onPreferences(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
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
 * The phone's status bar icons, in step with the page: dark on light paper,
 * light on dark. Android picks them from the phone's own dark mode, so a
 * Light setting on a dark phone drew white icons on white paper (Matt: "they
 * don't swap between light and dark mode"). On System the page follows the
 * phone, so it is told again when the phone changes. Native generation 15;
 * a no-op before.
 */
let chromeTheme: ThemePref | null = null;
let chromeWatched = false;

function matchChrome(theme: ThemePref): void {
  chromeTheme = theme;
  const tell = () => {
    try {
      window.GlyphHost?.setLightChrome?.(!isDarkNow(chromeTheme ?? 'system'));
    } catch {
      // An activity from before generation 15 has no such method.
    }
  };
  tell();
  if (!chromeWatched && typeof matchMedia !== 'undefined') {
    chromeWatched = true;
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
      if (chromeTheme === 'system') tell();
    });
  }
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
  matchChrome(prefs.theme);

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

  // Both code themes are stamped; editor/codeThemes.css applies whichever side of the page is showing.
  root.setAttribute('data-code-light', prefs.codeLight);
  root.setAttribute('data-code-dark', prefs.codeDark);
  // The pace: the kit's durations stretched or shortened. Inline, so the kit's own reduced-motion rule, which sets
  // them in a media query, would lose to it: that case is left alone and the page reads the phone's setting instead.
  const scale = motionScale(prefs);
  const still = typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  for (const [name, ms] of DURATIONS) {
    if (scale === 1 || still) root.style.removeProperty(name);
    else root.style.setProperty(name, `${Math.round(ms * scale)}ms`);
  }
  root.style.setProperty('--app-motion-scale', String(still ? 1 : scale));
}
