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
 * from Ghost.md's guess to where the key really is, and put back.
 */

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

  it('offers Ghost.md’s guess back only once the side key has been moved, and forgets the move', () => {
    let host = show(<RecordingPane />);
    expect(host.textContent).toContain('Where the side key is');
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

  it('has no side key to place in a browser, nor on the Mac, where the first section is not the key’s', () => {
    native = false;
    android = false;
    expect(show(<RecordingPane />).textContent).not.toContain('Where the side key is');
    native = true;
    const mac = show(<RecordingPane />);
    expect(mac.textContent).not.toContain('Where the side key is');
    expect(mac.textContent).not.toContain('The side key');
    expect(mac.textContent).toContain('While recording');
    expect(mac.textContent).toContain('Summaries');
  });

  it('offers the summaries three ways, meetings by default, and writes the choice the queue reads', () => {
    const host = show(<RecordingPane />);
    expect(preferences().summaries).toBe('meetings');
    expect(host.textContent).toContain('A long voice note is one over three minutes.');
    // Each choice is a label round a hidden radio input, as the kit draws a segmented control.
    const choose = (value: string) => act(() => host.querySelector<HTMLInputElement>(`input[type="radio"][value="${value}"]`)!.click());
    expect(host.textContent).toContain('Meetings and long voice notes');
    choose('long');
    expect(preferences().summaries).toBe('long');
    choose('off');
    expect(preferences().summaries).toBe('off');
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

  it('is on an Android phone with the service, where Write up is the phone’s choice and Allow asks the meeting’s own prompt', async () => {
    phone.generation = 20;
    const asked = vi.fn(() => 'asked');
    let canNotify = false;
    window.GlyphHost = { requestNotifications: asked, canNotify: () => canNotify } as unknown as Window['GlyphHost'];
    const { Pane, prefs } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(host.textContent).toContain('Meetings'));
    expect(host.textContent).toContain('A meeting is written up when the phone is charging or above half. Straight away uses more of the battery.');
    expect(prefs.preferences().writeUp).toBe('charging');
    act(() => host.querySelector<HTMLInputElement>('input[type="radio"][value="now"]')!.click());
    expect(prefs.preferences().writeUp).toBe('now');
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
    await waitUntil(() => expect(older.textContent).toContain('Your tapes'));
    expect(older.textContent).not.toContain('Tell me when a meeting is written up');
    unmount();
    phone.generation = 20;
    android = false;
    const { Pane: Mac } = await freshPage();
    const host = show(<Mac />);
    await waitUntil(() => expect(host.textContent).toContain('Your tapes'));
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

  it('says how much room the tapes take, and on a phone that can, removes the audio of the old ones after a second tap, keeping the words', async () => {
    phone.generation = 20;
    seed();
    const { Pane, recordings } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(host.textContent).toContain('Your tapes take about 117 MB on this device.'));
    act(() => button('Remove audio older than a month', host).click());
    expect(phone.removed).toEqual([]);
    expect(host.textContent).toContain('Tap again to remove the audio');
    await act(async () => button('Tap again to remove the audio', host).click());
    await waitUntil(() => expect(host.textContent).toContain('Removed the audio of one tape. The words stay.'));
    expect(phone.removed).toEqual([['old']]);
    expect(recordings.audioRemoved('old')).toBe(true);
    expect(recordings.audioRemoved('new')).toBe(false);
    // The words are still there, and the size no longer counts it.
    expect(JSON.parse(localStorage.getItem('glyph-notes')!)).toHaveLength(3);
  });

  it('only says the size on an older phone, which cannot remove a file', async () => {
    seed();
    const { Pane } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(host.textContent).toContain('Your tapes take about 117 MB on this device.'));
    expect(buttonSaying(host, 'Remove audio')).toBeUndefined();
  });

  it('counts in gigabytes past one, and says when there are no tapes', async () => {
    const { oldTapes, tapeBytes, tapeSize } = await import('./tapes.ts');
    expect(tapeSize(2_300_000_000)).toBe('2.3 GB');
    expect(tapeSize(117_120_000)).toBe('117 MB');
    expect(tapeSize(10)).toBe('1 MB');
    expect(tapeBytes([{ id: 'a', body: '', createdAt: 0, updatedAt: 0, source: 'capture', recordingMs: 3_600_000 }])).toBe(115_200_000);
    // Old is more than a month, of a tape, not archived.
    const day = 24 * 60 * 60 * 1000;
    const tapeOf = (id: string, ageDays: number, over: Record<string, unknown> = {}) => ({ id, body: '', createdAt: 100 * day - ageDays * day, updatedAt: 0, source: 'capture' as const, recordingMs: 60_000, ...over });
    expect(oldTapes([tapeOf('old', 31), tapeOf('edge', 30), tapeOf('typed', 40, { recordingMs: 0 }), tapeOf('gone', 40, { archivedAt: 1 })], 100 * day).map((n) => n.id)).toEqual(['old']);
    const { Pane } = await freshPage();
    const host = show(<Pane />);
    await waitUntil(() => expect(host.textContent).toContain('No tapes on this device.'));
  });
});
