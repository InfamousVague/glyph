import { beforeEach, describe, expect, it } from 'vitest';
import { applyPreferences, DEFAULT_PREFERENCES, facesOf, isAccent, isRounding, preferences, reloadPreferences, setPreferences, type Preferences } from './preferences.ts';

/**
 * What the page is stamped with, and what survives a store written by another build. The look itself is CSS
 * (app/ink.css): these are the attributes it hangs on, which is the part that can silently stop working.
 */
describe('how the app is drawn', () => {
  beforeEach(() => {
    localStorage.clear();
    setPreferences({ ...DEFAULT_PREFERENCES });
  });

  const root = () => document.documentElement;

  it('stamps nothing while everything is the app’s own', () => {
    applyPreferences({ ...DEFAULT_PREFERENCES });
    expect(root().hasAttribute('data-accent')).toBe(false);
    expect(root().hasAttribute('data-rounding')).toBe(false);
    expect(root().hasAttribute('data-density')).toBe(false);
    // The theme is the exception: Glyph's own default is dark, not the phone's, so it is always stamped.
    expect(root().getAttribute('data-theme')).toBe(DEFAULT_PREFERENCES.theme);
  });

  it('stamps the accent and the rounding once they are chosen, and clears them again', () => {
    setPreferences({ accent: 'teal', rounding: 'square', density: 'compact' });
    expect(root().getAttribute('data-accent')).toBe('teal');
    expect(root().getAttribute('data-rounding')).toBe('square');
    expect(root().getAttribute('data-density')).toBe('compact');
    setPreferences({ accent: 'ink', rounding: 'round', density: 'comfortable' });
    expect(root().hasAttribute('data-accent')).toBe(false);
    expect(root().hasAttribute('data-rounding')).toBe(false);
    expect(root().hasAttribute('data-density')).toBe(false);
  });

  it('knows its own names, and no others', () => {
    expect(isAccent('purple')).toBe(true);
    expect(isAccent('ink')).toBe(true);
    // The accent used to be a colour the app never drew with; a store from that build must not stamp it.
    expect(isAccent('blue')).toBe(false);
    expect(isRounding('rounder')).toBe(true);
    expect(isRounding('squircle')).toBe(false);
  });

  it('takes an accent or a rounding it does not know as the app’s own', () => {
    localStorage.setItem('glyph-preferences', JSON.stringify({ ...DEFAULT_PREFERENCES, accent: 'blue', rounding: 'squircle' }));
    // A fresh read of the store is what a launch does. (setPreferences({}) is not one: it writes what is in memory.)
    reloadPreferences();
    // Cast, because these are names the types no longer admit - which is the point: they can only arrive from a store.
    expect((preferences().accent as string) === 'blue').toBe(false);
    expect((preferences().rounding as string) === 'squircle').toBe(false);
    applyPreferences();
    expect(root().hasAttribute('data-accent')).toBe(false);
    expect(root().hasAttribute('data-rounding')).toBe(false);
  });

  it('draws notes in Maple Mono and the interface in Inter by default, and stamps both', () => {
    expect(facesOf(DEFAULT_PREFERENCES)).toEqual({ ui: 'inter', note: 'maple' });
    applyPreferences({ ...DEFAULT_PREFERENCES });
    // The interface's own default stamps nothing, as the kit expects; the note's face is always stamped.
    expect(root().hasAttribute('data-font')).toBe(false);
    expect(root().getAttribute('data-note-font')).toBe('maple');
    setPreferences({ noteFace: 'inter', typeface: 'plex' });
    expect(root().getAttribute('data-note-font')).toBe('inter');
    expect(root().getAttribute('data-font')).toBe('plex');
  });

  it('reads one face for everything, from a store or another device, as a pair', () => {
    // A coding face chosen for the whole app, before there were two: the note's now, and the interface its default.
    const legacy = (typeface: string, noteFace?: string) => facesOf({ typeface, noteFace } as unknown as Pick<Preferences, 'typeface' | 'noteFace'>);
    expect(legacy('maple')).toEqual({ ui: 'inter', note: 'maple' });
    expect(legacy('fira')).toEqual({ ui: 'inter', note: 'fira' });
    // A sans chosen then keeps the interface in it, and the note takes the default.
    expect(legacy('plex')).toEqual({ ui: 'plex', note: 'maple' });
    // Names from a newer build are the defaults here.
    expect(legacy('comic', 'wingdings')).toEqual({ ui: 'inter', note: 'maple' });
    // A note face said outright wins over an old coding face in the interface's place.
    expect(legacy('maple', 'noto')).toEqual({ ui: 'inter', note: 'noto' });
    setPreferences({ typeface: 'fira' as unknown as Preferences['typeface'], noteFace: undefined as unknown as Preferences['noteFace'] });
    expect(root().hasAttribute('data-font')).toBe(false);
    expect(root().getAttribute('data-note-font')).toBe('fira');
  });
});

describe('a store written by another build, or half written', () => {
  const KEY = 'glyph-preferences';

  /** The preferences as a launch reads `stored`. */
  function launchWith(stored: Record<string, unknown>): Preferences {
    localStorage.setItem(KEY, JSON.stringify({ ...DEFAULT_PREFERENCES, ...stored }));
    reloadPreferences();
    return preferences();
  }

  beforeEach(() => {
    localStorage.clear();
    reloadPreferences();
  });

  it('reads a Write up or a Sync meeting recordings it does not know as the default', () => {
    expect(launchWith({ writeUp: 'now', syncMeetingRecordings: true })).toMatchObject({ writeUp: 'now', syncMeetingRecordings: true });
    expect(launchWith({ writeUp: 'overnight', syncMeetingRecordings: 'yes' })).toMatchObject({ writeUp: 'charging', syncMeetingRecordings: false });
  });

  it('reads a meeting\u2019s own sound as off unless written on, and off by default', () => {
    expect(DEFAULT_PREFERENCES.meetingSound).toBe(false);
    expect(launchWith({ meetingSound: true })).toMatchObject({ meetingSound: true });
    expect(launchWith({ meetingSound: 'yes' })).toMatchObject({ meetingSound: false });
  });

  it('reads as the defaults when there is nothing, or nothing that is JSON', () => {
    expect(preferences()).toEqual(DEFAULT_PREFERENCES);
    localStorage.setItem(KEY, '{half');
    reloadPreferences();
    expect(preferences()).toEqual(DEFAULT_PREFERENCES);
  });

  it('keeps only the tabs that are ids, the last eight of them', () => {
    const ids = Array.from({ length: 10 }, (_, i) => `n${i}`);
    expect(launchWith({ openNotes: [...ids.slice(0, 2), 7, null, ...ids.slice(2)] }).openNotes).toEqual(ids.slice(2));
    expect(launchWith({ openNotes: 'n1' }).openNotes).toEqual([]);
  });

  it('keeps tab groups that are whole, and only tabs that point at one of them', () => {
    const tabGroups = {
      list: [{ id: 'g1', name: 'Work', hue: 'teal' }, { id: 'g2', name: 'No colour' }, 'rubbish', { id: 3, name: 'Bad id', hue: 'red' }],
      of: { a: 'g1', b: 'g2', c: 'gone', d: 4 },
    };
    expect(launchWith({ tabGroups }).tabGroups).toEqual({ list: [{ id: 'g1', name: 'Work', hue: 'teal' }], of: { a: 'g1' } });
    expect(launchWith({ tabGroups: { list: 'no' } }).tabGroups).toEqual({ list: [], of: {} });
  });

  it('keeps workspaces with an id and a name, and filings that point at one of them', () => {
    const workspaces = { list: [{ id: 'w1', name: 'Home' }, { id: 'w2' }, null], notes: { a: 'w1', b: 'w2', c: 5 } };
    expect(launchWith({ workspaces }).workspaces).toEqual({ list: [{ id: 'w1', name: 'Home' }], notes: { a: 'w1' } });
    expect(launchWith({ workspaces: 'none' }).workspaces).toEqual({ list: [], notes: {} });
  });

  it('reads the notification switches as on unless written off, and mutes only ids', () => {
    expect(launchWith({ notifications: { team: false, mutedOrgs: ['o1', 7, null] } }).notifications).toEqual({ team: false, claude: true, summaries: true, conflicts: true, mutedOrgs: ['o1'] });
    expect(launchWith({ notifications: 'all' }).notifications).toEqual(DEFAULT_PREFERENCES.notifications);
    expect(launchWith({}).notifications).toEqual({ team: true, claude: true, summaries: true, conflicts: true, mutedOrgs: [] });
  });

  it('keeps the trash only as ids with a time', () => {
    expect(launchWith({ trash: { a: 10, b: 'yesterday', c: null } }).trash).toEqual({ a: 10 });
    expect(launchWith({ trash: 'none' }).trash).toEqual({});
  });

  it('keeps the meetings only as note ids with the time each started', () => {
    expect(launchWith({ meetings: { a: 10, b: 'yesterday', c: null } }).meetings).toEqual({ a: 10 });
    expect(launchWith({ meetings: 'none' }).meetings).toEqual({});
    expect(launchWith({}).meetings).toEqual({});
  });

  it('keeps a share only when its id and key are ones a link could carry', () => {
    const id = 'A'.repeat(22);
    const key = 'b_'.repeat(20);
    const shares = {
      good: { id, key, sent: 'p2:9', lacked: ['x.jpg', 4] },
      unsent: { id, key },
      short: { id: 'abc', key },
      spaced: { id, key: 'not a key at all, not at all' },
      none: null,
    };
    expect(launchWith({ shares }).shares).toEqual({ good: { id, key, sent: 'p2:9', lacked: ['x.jpg'] }, unsent: { id, key, sent: '' } });
  });

  it('keeps whether a share carries where its note was written, only as true', () => {
    const id = 'A'.repeat(22);
    const key = 'b_'.repeat(20);
    const shares = { placed: { id, key, sent: 'p2:9', place: true }, said: { id, key, sent: '', place: false }, odd: { id, key, sent: '', place: 'yes' } };
    expect(launchWith({ shares }).shares).toEqual({ placed: { id, key, sent: 'p2:9', place: true }, said: { id, key, sent: '' }, odd: { id, key, sent: '' } });
  });

  it('reads a pace, a theme, a size or a sidebar this build does not have as its own', () => {
    const read = launchWith({ motionSpeed: 'ludicrous', theme: 'neon', uiScale: 3, sidebarStyle: 'floating', noteView: 'hologram' });
    expect(read).toMatchObject({
      motionSpeed: DEFAULT_PREFERENCES.motionSpeed,
      theme: DEFAULT_PREFERENCES.theme,
      uiScale: DEFAULT_PREFERENCES.uiScale,
      sidebarStyle: DEFAULT_PREFERENCES.sidebarStyle,
      noteView: DEFAULT_PREFERENCES.noteView,
    });
  });

  it('keeps code colours only once they have been chosen', () => {
    expect(launchWith({ codeLight: 'ink', codeDark: 'ink', codeChosen: false })).toMatchObject({ codeLight: DEFAULT_PREFERENCES.codeLight, codeDark: DEFAULT_PREFERENCES.codeDark });
    expect(launchWith({ codeLight: 'ink', codeDark: 'ink', codeChosen: true })).toMatchObject({ codeLight: 'ink', codeDark: 'ink' });
  });

  it('opens the home page on Spotlight until a layout is picked, the Cards every device stored before it included', () => {
    expect(DEFAULT_PREFERENCES.homeLayout).toBe('spotlight');
    expect(launchWith({ homeLayout: 'cards' })).toMatchObject({ homeLayout: 'spotlight' });
    expect(launchWith({ homeLayout: 'cards', homeLayoutChosen: true })).toMatchObject({ homeLayout: 'cards' });
    expect(launchWith({ homeLayout: 'sideways', homeLayoutChosen: true })).toMatchObject({ homeLayout: 'spotlight' });
  });

  it('reads a top bar cut from the choices, the Strip or Thumb, as Classic, and keeps the four', () => {
    expect(DEFAULT_PREFERENCES.topBar).toBe('classic');
    for (const gone of ['strip', 'thumb']) expect(launchWith({ topBar: gone })).toMatchObject({ topBar: 'classic' });
    for (const kept of ['ledger', 'masthead', 'islands']) expect(launchWith({ topBar: kept })).toMatchObject({ topBar: kept });
  });
});
