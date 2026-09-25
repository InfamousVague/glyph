import type { TabGroups } from '../notes/tabGroups.ts';
import { isCodeThemeDark, isCodeThemeLight, type CodeThemeDark, type CodeThemeLight } from '../editor/codeThemes.ts';
import { MOST_TABS } from '../notes/openTabs.ts';
import { isNoteView, type NoteView } from '../editor/viewMode.ts';
import { externalStore } from './externalStore.ts';
import { prefersStill } from './motion.ts';
import { readStored, writeStored } from './stored.ts';

/**
 * The look-and-feel knobs, and how they reach the tokens.
 *
 * Glacier ships no ThemeProvider: an app stamps `data-*` attributes on
 * `<html>` and the generated token CSS keys off them. The one rule that is
 * easy to get wrong is that a value equal to its default must REMOVE the
 * attribute rather than write it, because the `:root` block holds the defaults
 * and an explicit `data-accent='blue'` matches no selector at all.
 */

export type ThemePref = 'system' | 'light' | 'dark' | ThemePreset;

/** Tab groups as stored, kept to their shape: a group with a name and a known colour, and tabs that point at one. */
function readTabGroups(raw: unknown): TabGroups {
  const none: TabGroups = { list: [], of: {} };
  if (!raw || typeof raw !== 'object') return none;
  const { list, of } = raw as { list?: unknown; of?: unknown };
  if (!Array.isArray(list) || !of || typeof of !== 'object') return none;
  const groups = list.filter(
    (g): g is TabGroups['list'][number] =>
      // The colour is only checked for being a word, not against the list of colours: that list lives in
      // core/workspaces.ts, which imports this file, and this runs while this file is still loading - importing it back
      // would read the list before it exists. A colour this build doesn't know draws as ink (ink.css `[data-hue]`).
      !!g && typeof g === 'object' && typeof (g as { id?: unknown }).id === 'string' && typeof (g as { name?: unknown }).name === 'string' && typeof (g as { hue?: unknown }).hue === 'string',
  );
  const known = new Set(groups.map((g) => g.id));
  const members = Object.fromEntries(Object.entries(of as Record<string, unknown>).filter((entry): entry is [string, string] => typeof entry[1] === 'string' && known.has(entry[1])));
  return { list: groups, of: members };
}

/*
 * The kit's named themes (vendor/@glacier/tokens `theme-presets.ts`), brought over from AttackFM as Matt asked: "port
 * Attack.FM's set". Each is one side of the page, light or dark, with its own tinted greys, and comes with an accent.
 * They were already in the vendored kit - `:root[data-theme-preset]` in tokens.css - and nothing in Glyph ever set it.
 */
export type ThemePreset = 'dawn' | 'boreal' | 'ember';
export const THEME_PRESETS: Record<ThemePreset, { scheme: 'light' | 'dark'; accent: Accent }> = {
  dawn: { scheme: 'light', accent: 'red' },
  boreal: { scheme: 'dark', accent: 'green' },
  ember: { scheme: 'dark', accent: 'amber' },
};
export const THEMES: readonly ThemePref[] = ['system', 'light', 'dark', 'dawn', 'boreal', 'ember'];

/*
 * Interface size: every part of the app scaled together, buttons and bars and tabs as well as words (Matt, for the
 * AttackFM port: "Yes, scale everything"). AttackFM's own steps, and its way of doing it - the root's font size -
 * which works because the kit sizes everything in rem, so one number carries all of it. Separate from Text size,
 * which scales only what is read and keeps the taps where they are, and from Spacing, which is the kit's density:
 * the three stack.
 */
export const UI_SCALES = [0.85, 0.925, 1, 1.1, 1.25] as const;
export type UiScale = (typeof UI_SCALES)[number];

export function isUiScale(scale: unknown): scale is UiScale {
  return typeof scale === 'number' && (UI_SCALES as readonly number[]).includes(scale);
}

/**
 * How the notes sidebar opens from its icon in the top bar, on a window wide enough for two panes. A popover by
 * default, on every screen (Matt: "Sidebar should open and close in a popover not a full sidebar even on desktop"):
 * the card a phone has, hung from the icon. Docked, chosen in Settings, is a column beside the note that the icon
 * shows and hides. A narrow window always uses the popover: there is no room to dock.
 *
 * Kept under a new name, `sidebarStyle`. The build before this one had `sidebar`, defaulting to docked, and wrote that
 * default into every device's store; read under the old name, a window would stay docked without anyone choosing it.
 */
export type SidebarStyle = 'popover' | 'docked';

export function isSidebarStyle(style: unknown): style is SidebarStyle {
  return style === 'popover' || style === 'docked';
}

function isThemePreset(theme: unknown): theme is ThemePreset {
  return typeof theme === 'string' && theme in THEME_PRESETS;
}

function isTheme(theme: unknown): theme is ThemePref {
  return typeof theme === 'string' && (THEMES as readonly string[]).includes(theme);
}

/** Which side of the page a theme is: a named theme is always one, and System follows the device. */
export function themeScheme(theme: ThemePref): 'system' | 'light' | 'dark' {
  return isThemePreset(theme) ? THEME_PRESETS[theme].scheme : theme;
}

/**
 * The preferences to set when a theme is chosen: the theme, and the accent that comes with a named one, as AttackFM
 * does. Going back to a plain theme takes the accent back to ink only if it is still the one the named theme put there
 * - an accent chosen on purpose afterwards is left alone, where AttackFM would have reset it.
 */
export function themeChoice(theme: ThemePref, now: { theme: ThemePref; accent: Accent }): { theme: ThemePref; accent?: Accent } {
  if (isThemePreset(theme)) return { theme, accent: THEME_PRESETS[theme].accent };
  if (isThemePreset(now.theme) && now.accent === THEME_PRESETS[now.theme].accent) return { theme, accent: 'ink' };
  return { theme };
}
export type Density = 'extra-compact' | 'compact' | 'comfortable' | 'spacious' | 'more-space';

/** The accents the kit carries, and `ink`: the app's own, which is no accent at all. */
export const ACCENTS = ['ink', 'graphite', 'red', 'amber', 'green', 'teal', 'purple'] as const;
export type Accent = (typeof ACCENTS)[number];

export function isAccent(value: unknown): value is Accent {
  return typeof value === 'string' && (ACCENTS as readonly string[]).includes(value);
}

/**
 * How round a corner is: the kit's radius scale multiplied. `round` is the kit's own 1. Pills and circles are not
 * affected - `--glacier-radius-full` is a flat 9999px - so a square setting squares off cards and fields while the
 * Speak pill stays a pill.
 */
export const ROUNDINGS = ['square', 'soft', 'round', 'rounder'] as const;
export type Rounding = (typeof ROUNDINGS)[number];

export function isRounding(value: unknown): value is Rounding {
  return typeof value === 'string' && (ROUNDINGS as readonly string[]).includes(value);
}
/** The reader's dial on the type scale in app.css; 'large' is already large. */
export type TextSize = 'large' | 'larger' | 'largest';
/**
 * Every face the app can set: two monospace coding faces with ligatures and decorative symbols (typefaces.css), Maple
 * Mono and Fira Code, and the kit's three sans. Two are chosen (Matt: "font pairs, for the note body I want to use the
 * maple mono font and for the interface I want to use inter by default, make both kinds of fonts pickable"): the
 * note's face, any of the five, and the interface's - tabs, lists, Settings, buttons - one of the sans.
 */
export const TYPEFACES = ['maple', 'fira', 'inter', 'noto', 'plex'] as const;
export type Typeface = (typeof TYPEFACES)[number];
/** The faces the interface can be set in: a monospace face's grid is for text to read, not for a row of tabs. */
export const INTERFACE_FACES = ['inter', 'noto', 'plex'] as const;
export type InterfaceFace = (typeof INTERFACE_FACES)[number];

export function isTypeface(value: unknown): value is Typeface {
  return typeof value === 'string' && (TYPEFACES as readonly string[]).includes(value);
}

export function isInterfaceFace(value: unknown): value is InterfaceFace {
  return typeof value === 'string' && (INTERFACE_FACES as readonly string[]).includes(value);
}

/** Whether a face is one of the monospace coding faces, which set the note's code as well as its words. */
export function isCodingFace(face: Typeface): boolean {
  return face === 'maple' || face === 'fira';
}

/**
 * The two faces a set of preferences draws with, whatever the store says: the interface's is one of the sans, and the
 * note's any face. One face for everything was the setting until 2026-09-24, and a coding face chosen then - here, or
 * from another device by sync - is the note's; the interface goes back to its own default.
 */
export function facesOf(prefs: Pick<Preferences, 'typeface' | 'noteFace'>): { ui: InterfaceFace; note: Typeface } {
  const ui = isInterfaceFace(prefs.typeface) ? prefs.typeface : DEFAULT_PREFERENCES.typeface;
  const note = isTypeface(prefs.noteFace) ? prefs.noteFace : isTypeface(prefs.typeface) && isCodingFace(prefs.typeface) ? prefs.typeface : DEFAULT_PREFERENCES.noteFace;
  return { ui, note };
}

/** How quickly things move (Settings > Animations; Matt: "add controls to animation speeds"). */
export type MotionSpeed = 'relaxed' | 'normal' | 'brisk';

/** How much longer (above 1) or shorter (below 1) every animation runs at a speed. */
const MOTION_SCALE: Record<MotionSpeed, number> = { relaxed: 1.6, normal: 1, brisk: 0.6 };

export interface Preferences {
  theme: ThemePref;
  /** Every part of the app scaled together (`UI_SCALES`); 1 is the kit's own size. Kept to this device. */
  uiScale: UiScale;
  /** A popover or docked (`SidebarStyle`). Kept to this device, since it is about this window's width. */
  sidebarStyle: SidebarStyle;
  /**
   * The one colour a person can choose (Matt: "add ... the accent color picker"). `ink` is the app's own answer and
   * the default: Glyph is grey on purpose (app/ink.css), and with ink chosen nothing is stamped and every accent
   * token stays mapped onto the grey scale. Any other name stamps `data-accent`, and the kit's ramp for that colour
   * shows through instead - in the places an accent is actually used: a focus ring, a chosen segment, a swatch.
   */
  accent: Accent;
  density: Density;
  /** How round the app's corners are: the kit's radius scale, multiplied (`--glacier-radius-scale`). */
  rounding: Rounding;
  /** Prose input aids in the editor: autocorrect, autocapitalisation, spellcheck. */
  assist: boolean;
  textSize: TextSize;
  /** The interface's face: tabs, lists, Settings, buttons (`facesOf`). */
  typeface: InterfaceFace;
  /** The note's face: its words and its code (`facesOf`). */
  noteFace: Typeface;
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
   * Whether the AI bar (ai/PromptBar.tsx) stands at the foot of a note. Off until asked for (Matt: "Hide the AI bar
   * on the note by default, put it behind a toggle button"): the note's ✨ button shows and hides it, and the choice
   * is the person's, so it travels with their settings. Asking over a selection opens it for that note either way.
   */
  aiBar: boolean;
  /**
   * The notes left open as tabs, oldest first, and kept so they come back on a reload and on another device
   * (Matt: "Persist tabs across devices and reloads"). State rather than a setting, but it belongs to the person
   * and not to the phone, so it travels the way their settings do (core/sync/prefs.ts).
   */
  openNotes: string[];
  /** Chrome-style groups over the open tabs (notes/tabGroups.ts): named, coloured, folding runs of tabs. */
  tabGroups: TabGroups;
  /**
   * The workspaces and which note is filed in each (core/workspaces.ts).
   *
   * Kept here because this is what travels between a person's devices: a workspace made on the phone is one the
   * desktop knows about (Matt: "I'm not seeing the workspaces being in sync"). Which workspace the list is FILTERED
   * by stays on the device, since that is where you are looking rather than what you have.
   *
   * Written structurally rather than as core/workspaces.ts's own types, so the preferences do not depend on it.
   */
  workspaces: { list: { id: string; name: string; hue?: string }[]; notes: Record<string, string> };
  /**
   * The notes in the trash, by id, and when each went in (core/trash.ts). Here for the reason the workspaces are: it
   * travels with the person, so a note thrown away on the phone is in the trash on the Mac, and it ships over the air
   * rather than as a column in the native store.
   */
  trash: Record<string, number>;
  /**
   * The notes shared by a read-only link (share/share.ts), by note id: each share's id, its key, and what was last
   * sent. Synced, so every device lists every share, keeps it up to date and can stop it. The key is end-to-end
   * encrypted with the rest of the settings: the server that holds the share never sees it.
   */
  shares: Record<string, { id: string; key: string; sent: string; lacked?: string[] }>;
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
  uiScale: 1,
  sidebarStyle: 'popover',
  accent: 'ink',
  density: 'comfortable',
  rounding: 'round',
  assist: true,
  textSize: 'large',
  typeface: 'inter',
  noteFace: 'maple',
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
  aiBar: false,
  openNotes: [],
  tabGroups: { list: [], of: {} },
  workspaces: { list: [], notes: {} },
  trash: {},
  shares: {},
  wisp: true,
  wispEdge: true,
  ripples: true,
  motionSpeed: 'normal',
  linkPreviews: true,
};

const STORAGE_KEY = 'glyph-preferences';
const chosen = externalStore<Preferences>(load(), { server: () => DEFAULT_PREFERENCES });

/** What is kept, or the defaults: nothing kept, or nothing that reads as JSON, is a device that chose nothing yet. */
function load(): Preferences {
  return readStored(STORAGE_KEY, DEFAULT_PREFERENCES, settle);
}

/** A stored set of preferences made whole, whatever build or half-written store it came from. */
function settle(raw: unknown): Preferences {
  const loaded = { ...DEFAULT_PREFERENCES, ...(raw as Partial<Preferences>) };
  // A theme a later build removed falls back to the default rather than to no colours at all.
  if (!isCodeThemeLight(loaded.codeLight) || !loaded.codeChosen) loaded.codeLight = DEFAULT_PREFERENCES.codeLight;
  if (!isCodeThemeDark(loaded.codeDark) || !loaded.codeChosen) loaded.codeDark = DEFAULT_PREFERENCES.codeDark;
  if (!isNoteView(loaded.noteView)) loaded.noteView = DEFAULT_PREFERENCES.noteView;
  // A theme from a later build, or from a device with one this build lacks, reads as the default.
  if (!isTheme(loaded.theme)) loaded.theme = DEFAULT_PREFERENCES.theme;
  // A size that is not one of the steps - another build's, or a half-written store - is the kit's own.
  if (!isUiScale(loaded.uiScale)) loaded.uiScale = DEFAULT_PREFERENCES.uiScale;
  if (!isSidebarStyle(loaded.sidebarStyle)) loaded.sidebarStyle = DEFAULT_PREFERENCES.sidebarStyle;
  // Tabs from another build, or a half-written store: anything but a list of ids is no tabs at all.
  loaded.openNotes = Array.isArray(loaded.openNotes) ? loaded.openNotes.filter((id): id is string => typeof id === 'string').slice(-MOST_TABS) : [];
  // Tab groups from another build, or a half-written store: only well-formed groups, and tabs pointing at them.
  loaded.tabGroups = readTabGroups(loaded.tabGroups);
  // Workspaces from another build, or a half-written store: anything but the shape below is no workspaces at all.
  const spaces = loaded.workspaces as Partial<Preferences['workspaces']> | undefined;
  const list = Array.isArray(spaces?.list) ? spaces.list.filter((w) => w && typeof w.id === 'string' && typeof w.name === 'string') : [];
  const ids = new Set(list.map((w) => w.id));
  const notes: Record<string, string> = {};
  if (spaces?.notes && typeof spaces.notes === 'object') {
    for (const [note, id] of Object.entries(spaces.notes)) if (typeof id === 'string' && ids.has(id)) notes[note] = id;
  }
  loaded.workspaces = { list, notes };
  // The trash from another build, or a half-written store: only ids with a time.
  const thrown: Record<string, number> = {};
  if (loaded.trash && typeof loaded.trash === 'object') {
    for (const [id, at] of Object.entries(loaded.trash)) if (typeof at === 'number' && Number.isFinite(at)) thrown[id] = at;
  }
  loaded.trash = thrown;
  // Shares from another build, or a half-written store: only entries with an id and a key a link can carry.
  const shares: Preferences['shares'] = {};
  const LINK_PART = /^[A-Za-z0-9_-]{16,64}$/;
  if (loaded.shares && typeof loaded.shares === 'object') {
    for (const [note, kept] of Object.entries(loaded.shares as Record<string, unknown>)) {
      const k = kept as { id?: unknown; key?: unknown; sent?: unknown; lacked?: unknown } | null;
      if (!k || typeof k.id !== 'string' || typeof k.key !== 'string' || !LINK_PART.test(k.id) || !LINK_PART.test(k.key)) continue;
      const lacked = Array.isArray(k.lacked) ? k.lacked.filter((n): n is string => typeof n === 'string') : undefined;
      shares[note] = { id: k.id, key: k.key, sent: typeof k.sent === 'string' ? k.sent : '', ...(lacked?.length ? { lacked } : {}) };
    }
  }
  loaded.shares = shares;
  if (!(loaded.motionSpeed in MOTION_SCALE)) loaded.motionSpeed = DEFAULT_PREFERENCES.motionSpeed;
  // An accent or a rounding this build does not have - one from an older store, where the accent was a colour the
  // app never used, or from a newer phone - is the app's own rather than a name nothing can draw.
  if (!isAccent(loaded.accent)) loaded.accent = DEFAULT_PREFERENCES.accent;
  if (!isRounding(loaded.rounding)) loaded.rounding = DEFAULT_PREFERENCES.rounding;
  // The two faces, settled: one face for everything, as a store from before the pair has it, is read as a pair.
  const faces = facesOf(loaded);
  loaded.typeface = faces.ui;
  loaded.noteFace = faces.note;
  return loaded;
}

export const preferences = chosen.get;

/** Reads the stored preferences again: after a reset, and in tests. */
export function reloadPreferences(): void {
  chosen.set(load());
}

/** The chosen pace as a multiplier for a duration: 1 at the normal speed. */
export function motionScale(prefs: Preferences = chosen.get()): number {
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

/** Kept, applied to the page, and then told to everyone following; not kept, the choice still applies for this run. */
export function setPreferences(next: Partial<Preferences>): void {
  const merged = { ...chosen.get(), ...next };
  writeStored(STORAGE_KEY, merged);
  applyPreferences(merged);
  chosen.set(merged);
}

/** Called after every change, for code outside React that must follow a preference. */
export const onPreferences = chosen.subscribe;

export const usePreferences = chosen.use;

/** Whether the editor should be built with CodeMirror's dark base rules. */
export function isDarkNow(theme: ThemePref): boolean {
  const scheme = themeScheme(theme);
  if (scheme === 'dark') return true;
  if (scheme === 'light') return false;
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
export function applyPreferences(prefs: Preferences = chosen.get()): void {
  const root = document.documentElement;

  // A named theme is stamped twice: its side of the page as `data-theme`, so every light-or-dark rule reads it as
  // that side, and its name as `data-theme-preset`, which the kit's tinted greys and ink.css answer to.
  const scheme = themeScheme(prefs.theme);
  if (scheme === 'system') root.removeAttribute('data-theme');
  else root.setAttribute('data-theme', scheme);
  if (isThemePreset(prefs.theme)) root.setAttribute('data-theme-preset', prefs.theme);
  else root.removeAttribute('data-theme-preset');
  matchChrome(prefs.theme);

  // The root's own size, which every rem in the kit and the app is measured from. Inline, so nothing in a stylesheet
  // outranks it; taken off entirely at the kit's own size rather than written as 100%.
  const size = isUiScale(prefs.uiScale) ? prefs.uiScale : 1;
  if (size === 1) root.style.removeProperty('font-size');
  else root.style.setProperty('font-size', `${(size * 100).toFixed(1)}%`);

  if (prefs.density === DEFAULT_PREFERENCES.density) root.removeAttribute('data-density');
  else root.setAttribute('data-density', prefs.density);

  // Ink is no accent at all: nothing is stamped, and ink.css keeps every accent token on the grey scale. Any other
  // is the kit's own ramp, which ink.css steps aside for (`:not([data-accent])`).
  if (!isAccent(prefs.accent) || prefs.accent === 'ink') root.removeAttribute('data-accent');
  else root.setAttribute('data-accent', prefs.accent);

  if (!isRounding(prefs.rounding) || prefs.rounding === DEFAULT_PREFERENCES.rounding) root.removeAttribute('data-rounding');
  else root.setAttribute('data-rounding', prefs.rounding);

  if (prefs.textSize === DEFAULT_PREFERENCES.textSize) root.removeAttribute('data-text-size');
  else root.setAttribute('data-text-size', prefs.textSize);

  // `data-font` is the token layer's own attribute (tokens.css), so the kit's
  // components change face along with the editor.
  // The two faces (`facesOf`, which also reads a face from another build as the default here). The interface's is the
  // token layer's own attribute, so the kit's components change with it; the note's is always stamped, and
  // typefaces.css sets the note's words and code from it.
  const faces = facesOf(prefs);
  if (faces.ui === DEFAULT_PREFERENCES.typeface) root.removeAttribute('data-font');
  else root.setAttribute('data-font', faces.ui);
  root.setAttribute('data-note-font', faces.note);

  // Both code themes are stamped; editor/codeThemes.css applies whichever side of the page is showing.
  root.setAttribute('data-code-light', prefs.codeLight);
  root.setAttribute('data-code-dark', prefs.codeDark);
  // The pace: the kit's durations stretched or shortened. Inline, so the kit's own reduced-motion rule, which sets
  // them in a media query, would lose to it: that case is left alone and the page reads the phone's setting instead.
  const scale = motionScale(prefs);
  const still = prefersStill();
  for (const [name, ms] of DURATIONS) {
    if (scale === 1 || still) root.style.removeProperty(name);
    else root.style.setProperty(name, `${Math.round(ms * scale)}ms`);
  }
  root.style.setProperty('--app-motion-scale', String(still ? 1 : scale));
}
