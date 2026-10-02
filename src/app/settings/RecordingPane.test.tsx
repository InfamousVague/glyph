import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { button, buttonSaying, show, unmount, waitUntil } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
// The side key's rings watch their box; jsdom has no observer.
stubResizeObserver();

// On Android, where there is a side key to place, on the Mac, or in a browser, where there is none.
let native = true;
let android = true;
/** The binary: which generation it is, and the audio it was asked to remove. */
const phone = vi.hoisted(() => ({ generation: 0, removed: [] as string[][] }));
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string, args?: Record<string, unknown>) => {
    if (command === 'ota_status') return { nativeGeneration: phone.generation };
    if (command === 'list_notes') return JSON.parse(localStorage.getItem('glyph-notes') ?? '[]');
    if (command === 'recording_delete') {
      const ids = args!.ids as string[];
      phone.removed.push(ids);
      return { removed: ids, freedBytes: ids.length * 100 };
    }
    throw new Error(`no ${command} in a test`);
  },
}));
// The `rec` scheme's URL as the app makes it: what a tape is asked about.
vi.mock('@tauri-apps/api/core', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@tauri-apps/api/core')>()),
  convertFileSrc: (path: string, scheme: string) => `${scheme}://localhost/${path}`,
}));
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isAndroid() {
    return android;
  },
}));

const { RecordingPane } = await import('./RecordingPane.tsx');
const { savedHeight, saveHeight } = await import('../capture/sideKey.ts');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');

/**
 * Recording's page: its switches write the preferences the recorder reads, and in the app the side key can be moved
 * from Ghost.md's guess to where the key really is, and put back. Its cards: While recording, After recording,
 * Summaries as three picks, Meetings, Tapes and the side key, last. The Model moved to its own AI section
 * (settings/AiPane.tsx), so it is no longer here.
 */

const titles = (host: HTMLElement) => [...host.querySelectorAll('.setk__title')].map((title) => title.textContent);

beforeEach(() => {
  native = true;
  android = true;
  phone.generation = 0;
  phone.removed = [];
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
});

describe('the Recording page', () => {
  it('writes each switch to the preference the recorder reads', () => {
    const host = show(<RecordingPane />);
    const quiet = preferences().quietStop;
    act(() => host.querySelector<HTMLElement>('[aria-label="Stop when I go quiet"]')!.click());
    expect(preferences().quietStop).toBe(!quiet);
    const refine = preferences().refine;
    act(() => host.querySelector<HTMLElement>('[aria-label="Better words after recording"]')!.click());
    expect(preferences().refine).toBe(!refine);
  });

  it('holds its cards in order on an Android phone, the side key last', () => {
    expect(titles(show(<RecordingPane />))).toEqual(['While recording', 'After recording', 'Summaries', 'Tapes', 'The side key']);
  });

  it('offers Ghost.md’s guess back only once the side key has been moved, and forgets the move', () => {
    let host = show(<RecordingPane />);
    expect(titles(host)).toContain('The side key');
    expect(host.textContent).not.toContain('Use Ghost.md’s guess');
    saveHeight(0.62);
    host = show(<RecordingPane />);
    // The slider stands where the key was moved to, as a percentage of the edge.
    const slider = host.querySelector<HTMLElement>('[aria-label="Side key height"]')!;
    expect(slider.getAttribute('aria-valuenow') ?? (slider as HTMLInputElement).value).toBe('62');
    act(() => button('Reset', host).click());
    expect(savedHeight()).toBeNull();
    expect(host.textContent).not.toContain('Use Ghost.md’s guess');
  });

  it('has no side key to place in a browser, nor on the Mac, and no tapes in a browser', () => {
    native = false;
    android = false;
    const browser = show(<RecordingPane />);
    expect(titles(browser)).toEqual(['While recording', 'After recording', 'Summaries']);
    native = true;
    const mac = show(<RecordingPane />);
    expect(titles(mac)).toEqual(['While recording', 'After recording', 'Summaries', 'Tapes']);
    // The side key is not the Mac's to press.
    expect(mac.textContent).toContain("Saves after four seconds of quiet, once you've started talking. Done still works.");
    expect(mac.textContent).not.toContain('side key');
  });

  it('says this Mac where the work is done on the Mac, and the phone on a phone', () => {
    native = true;
    android = false;
    const mac = show(<RecordingPane />);
    expect(mac.textContent).toContain('The language model on this Mac writes a summary under the title.');
    expect(mac.textContent).toContain('A few seconds of this Mac per minute of speech.');
    expect(mac.textContent).toContain('A few minutes of this Mac for each.');
    expect(mac.textContent).not.toContain('the phone');
    unmount();
    android = true;
    const phone = show(<RecordingPane />);
    expect(phone.textContent).toContain('The language model on the phone writes a summary under the title.');
    expect(phone.textContent).toContain('A few seconds of the phone per minute of speech.');
    expect(phone.textContent).not.toContain('this Mac');
  });

  it('offers the summaries as three picks, meetings by default, each saying what it means, and writes the choice the queue reads', () => {
    const host = show(<RecordingPane />);
    expect(preferences().summaries).toBe('meetings');
    const pick = (label: string) => host.querySelector<HTMLButtonElement>(`[role="radio"][aria-label="${label}"]`)!;
    expect(pick('Meetings').getAttribute('aria-checked')).toBe('true');
    expect(host.textContent).toContain('Every meeting, once it is done.');
    expect(host.textContent).toContain('A long voice note is one over three minutes. A few minutes of the phone for each.');
    act(() => pick('Meetings and long voice notes').click());
    expect(preferences().summaries).toBe('long');
    act(() => pick('Off').click());
    expect(preferences().summaries).toBe('off');
    expect(pick('Off').getAttribute('aria-checked')).toBe('true');
  });
});

/** The pane and the stores read afresh: the binary's generation is asked once per page and kept, so a test that changes it starts a page. */
async function freshPage() {
  vi.resetModules();
  const { RecordingPane: Pane } = await import('./RecordingPane.tsx');
  const prefs = await import('../core/preferences.ts');
  const recordings = await import('../core/recordings.ts');
  prefs.setPreferences(prefs.DEFAULT_PREFERENCES);
  return { Pane, prefs, recordings };
}

describe('Meetings', () => {
  afterEach(() => {
    delete window.GlyphHost;
  });

  it('is on an Android phone with the service, where Write up straight away is the phone’s choice and Allow asks the meeting’s own prompt', async () => {
    phone.generation = 20;
    const asked = vi.fn(() => 'asked');
    let canNotify = false;
    window.GlyphHost = { requestNotifications: asked, canNotify: () => canNotify } as unknown as Window['GlyphHost'];
    const { Pane, prefs } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(titles(host)).toContain('Meetings'));
    expect(titles(host)).toEqual(['While recording', 'After recording', 'Summaries', 'Meetings', 'Tapes', 'The side key']);
    // Settings' contract with the meetings drawn, the one state SettingsSheet.test.tsx cannot draw (its binary answers no
    // generation): every name the search lists for the page is on it, so a hit lights something.
    const { findable } = await import('./RecordingPane.findable.ts');
    const { findSetting } = await import('./settingsSearch.ts');
    expect(findable({ android: true, app: true }).filter(({ name }) => !findSetting(host, name))).toEqual([]);
    expect(host.textContent).toContain('Off, a meeting is written up when the phone is charging or above half. On, straight away, which uses more of the battery.');
    // One switch over the two values the preference always kept: off is "charging", the default, and on is "now".
    const straight = () => host.querySelector<HTMLInputElement>('[aria-label="Write up straight away"]')!;
    expect(prefs.preferences().writeUp).toBe('charging');
    expect(straight().checked).toBe(false);
    act(() => straight().click());
    expect(prefs.preferences().writeUp).toBe('now');
    act(() => straight().click());
    expect(prefs.preferences().writeUp).toBe('charging');
    expect(host.textContent).toContain('Tell me when a meeting is written up');
    act(() => button('Allow', host).click());
    expect(asked).toHaveBeenCalledTimes(1);
    // Answered yes: the row says so, and the word goes.
    canNotify = true;
    act(() => window.__glyph!.notified!());
    await waitUntil(() => expect(host.textContent).toContain('On'));
    expect(buttonSaying(host, 'Allow')).toBeUndefined();
  });

  it('is not on an older phone, nor on the Mac, which has no service', async () => {
    const { Pane } = await freshPage();
    const older = show(<Pane />);
    await waitUntil(() => expect(older.textContent).toContain('No tapes on this device.'));
    expect(older.textContent).not.toContain('Tell me when a meeting is written up');
    unmount();
    phone.generation = 20;
    android = false;
    const { Pane: Mac } = await freshPage();
    const host = show(<Mac />);
    await waitUntil(() => expect(host.textContent).toContain('No tapes on this device.'));
    expect(host.textContent).not.toContain('Tell me when a meeting is written up');
  });
});

describe('Tapes', () => {
  /** Notes as the page's own store keeps them: an hour's meeting from two months ago, a minute's note from today, and a typed one. */
  const seed = () => {
    const now = Date.now();
    localStorage.setItem(
      'glyph-notes',
      JSON.stringify([
        { id: 'old', body: '# Meeting, 26 Jul 14:05', createdAt: now - 60 * 24 * 60 * 60 * 1000, updatedAt: now, source: 'capture', recordingMs: 3_600_000, revision: 1 },
        { id: 'new', body: '# Today', createdAt: now - 1000, updatedAt: now, source: 'capture', recordingMs: 60_000, revision: 1 },
        { id: 'typed', body: '# Typed', createdAt: now - 90 * 24 * 60 * 60 * 1000, updatedAt: now, source: 'editor', revision: 1 },
      ]),
    );
  };

  /** The Tapes card's footer: the room the tapes take, or what a removal did. */
  const footer = (host: HTMLElement) => [...host.querySelectorAll('section')].find((s) => s.querySelector('.setk__title')?.textContent === 'Tapes')?.querySelector('.setk__footer')?.textContent;

  it('says how much room the tapes take, and on a phone that can, removes the audio of the old ones after a second tap, keeping the words', async () => {
    phone.generation = 20;
    seed();
    const { Pane, recordings } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(footer(host)).toBe('Your tapes take about 117 MB on this device.'));
    expect(host.textContent).toContain('Remove audio older than a month');
    act(() => button('Remove', host).click());
    expect(phone.removed).toEqual([]);
    await act(async () => button('Tap again', host).click());
    await waitUntil(() => expect(footer(host)).toBe('Removed the audio of one tape. The words stay.'));
    expect(phone.removed).toEqual([['old']]);
    expect(recordings.audioRemoved('old')).toBe(true);
    expect(recordings.audioRemoved('new')).toBe(false);
    // The words are still there, and the size no longer counts it.
    expect(JSON.parse(localStorage.getItem('glyph-notes')!)).toHaveLength(3);
  });

  it('counts only the audio that is on this device: not what was removed, nor a synced tape whose audio stayed elsewhere', async () => {
    phone.generation = 20;
    seed();
    // The Tapes row took the hour's audio away on an earlier visit; the minute's tape answers 404, made elsewhere.
    localStorage.setItem('glyph-audio-removed', JSON.stringify(['old']));
    const heads: string[] = [];
    const fetch = vi.spyOn(globalThis, 'fetch').mockImplementation(async (url: RequestInfo | URL, init?: RequestInit) => {
      heads.push(`${init?.method} ${String(url)}`);
      return new Response(null, { status: String(url).includes('new.wav') ? 404 : 200 });
    });
    const { Pane } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(footer(host)).toBe('No tapes on this device.'));
    expect(heads.every((head) => head.startsWith('HEAD '))).toBe(true);
    expect(button('Remove', host).disabled).toBe(true);
    fetch.mockRestore();
  });

  it('says nothing about removing until the binary has said which generation it is', async () => {
    seed();
    const { Pane } = await freshPage();
    const host = show(<Pane />);
    // Drawn before the answer: neither Remove nor the reason it is held.
    expect(host.textContent).toContain('Remove audio older than a month');
    expect(host.textContent).not.toContain('Update Ghost.md to remove audio here.');
    expect(buttonSaying(host, 'Remove')).toBeUndefined();
    await waitUntil(() => expect(host.textContent).toContain('Update Ghost.md to remove audio here.'));
  });

  it('only says the size on an older phone, which cannot remove a file, and says why the row is held', async () => {
    seed();
    const { Pane } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(footer(host)).toBe('Your tapes take about 117 MB on this device.'));
    expect(buttonSaying(host, 'Remove')).toBeUndefined();
    expect(host.textContent).toContain('Update Ghost.md to remove audio here.');
  });

  it('counts in gigabytes past one, and says when there are no tapes', async () => {
    const { oldTapes, tapeBytes, tapeSize } = await import('./tapes.ts');
    expect(tapeSize(2_300_000_000)).toBe('2.3 GB');
    expect(tapeSize(117_120_000)).toBe('117 MB');
    expect(tapeSize(10)).toBe('1 MB');
    expect(tapeBytes([{ id: 'a', body: '', createdAt: 0, updatedAt: 0, source: 'capture', recordingMs: 3_600_000 }])).toBe(115_200_000);
    const { tapesHere } = await import('./tapes.ts');
    const tapes = [{ id: 'a', body: '', createdAt: 0, updatedAt: 0, source: 'capture' as const, recordingMs: 1 }, { id: 'b', body: '', createdAt: 0, updatedAt: 0, source: 'capture' as const, recordingMs: 1 }, { id: 'c', body: '', createdAt: 0, updatedAt: 0, source: 'editor' as const }];
    expect(tapesHere(tapes, (id) => id === 'b').map((n) => n.id)).toEqual(['a']);
    // Old is more than a month, of a tape, not archived.
    const day = 24 * 60 * 60 * 1000;
    const tapeOf = (id: string, ageDays: number, over: Record<string, unknown> = {}) => ({ id, body: '', createdAt: 100 * day - ageDays * day, updatedAt: 0, source: 'capture' as const, recordingMs: 60_000, ...over });
    expect(oldTapes([tapeOf('old', 31), tapeOf('edge', 30), tapeOf('typed', 40, { recordingMs: 0 }), tapeOf('gone', 40, { archivedAt: 1 })], 100 * day).map((n) => n.id)).toEqual(['old']);
    const { Pane } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(footer(host)).toBe('No tapes on this device.'));
  });
});
