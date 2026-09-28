import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { history, undo } from '@codemirror/commands';
import { glyphMarkdown } from './language.ts';

/**
 * What the + beside the line offers (editor/addRows.ts): which rows are there on which device, in what order, and
 * exactly what each writes on an empty line. A phone, the Mac and the iPhone are core/platform.ts and core/tauri.ts
 * stood in for.
 */

const device = vi.hoisted(() => ({ tauri: false, android: false, mac: false, ios: false }));
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => device.tauri,
  invoke: async () => {
    throw new Error('no commands here');
  },
}));
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isAndroid() {
    return device.android;
  },
  get isMacApp() {
    return device.mac;
  },
  get isIOS() {
    return device.ios;
  },
}));

const { setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const rows = await import('./addRows.ts');
const { stamp } = await import('../core/stamp.ts');

const NOW = new Date(2026, 8, 28, 14, 5);
const gates = (over: Partial<import('./addRows.ts').AddGates> = {}) => ({ picture: true, video: false, place: 'on' as const, note: true, canvas: true, effects: [], ...over });

function viewOf(doc: string, caret = doc.length): EditorView {
  return new EditorView({ state: EditorState.create({ doc, selection: { anchor: caret }, extensions: [glyphMarkdown([], []), history()] }) });
}

/** What a row writes on `doc`, with the caret at its end: the note after, and the words selected or the caret's place as `|`. */
function written(id: import('./addRows.ts').AddRowId, doc = 'Lunch\n'): string {
  const view = viewOf(doc);
  expect(rows.writeRow(view, id, NOW)).toBe(true);
  const { from, to } = view.state.selection.main;
  const text = view.state.doc.toString();
  return from === to ? `${text.slice(0, from)}|${text.slice(from)}` : `${text.slice(0, from)}[${text.slice(from, to)}]${text.slice(to)}`;
}

function geolocation(present: boolean) {
  if (present) Object.defineProperty(navigator, 'geolocation', { configurable: true, value: { getCurrentPosition: () => undefined } });
  else Reflect.deleteProperty(navigator, 'geolocation');
}

beforeEach(() => {
  Object.assign(device, { tauri: false, android: false, mac: false, ios: false });
  geolocation(true);
  delete window.GlyphHost;
});

afterEach(() => {
  setPreferences({ localOnly: DEFAULT_PREFERENCES.localOnly });
  Reflect.deleteProperty(navigator, 'geolocation');
});

describe('the list’s rows', () => {
  it('are the seven things, the phone’s first, then More', () => {
    const top = rows.topRows(gates({ video: true }), NOW);
    expect(top.map((row) => row.words)).toEqual(['A picture', 'A video', 'A place', stamp(NOW), 'A table', 'A note', 'A to-do', 'More']);
  });

  it('say the time as it will be written, and read it aloud with the month in full', () => {
    const time = rows.topRows(gates(), NOW).find((row) => row.id === 'time')!;
    expect(time.words).toBe(stamp(NOW));
    expect(time.label).toMatch(/^The date and time, .*2026, 14:05$/);
    expect(time.label).toContain(new Intl.DateTimeFormat(undefined, { month: 'long' }).format(NOW));
  });

  it('leave out what the screen cannot do', () => {
    const top = rows.topRows(gates({ picture: false, place: 'absent', note: false }), NOW);
    expect(top.map((row) => row.id)).toEqual(['time', 'table', 'todo', 'more']);
  });

  it('dim a place under Local only, and say why', () => {
    const place = rows.topRows(gates({ place: 'dimmed' }), NOW).find((row) => row.id === 'place');
    expect(place?.dimmed).toBe('Local only is on.');
  });

  it('keep the rest behind More: the forms, the blocks, the small marks, and the effects that are on', () => {
    const heat = { name: 'Heat', delimiter: '🔥🔥', look: { kind: 'effect', effect: 'heat' } } as const;
    expect(rows.moreRows(gates({ effects: [heat] })).map((row) => row.words)).toEqual([
      'A heading',
      'A bulleted list',
      'A numbered list',
      'A quote',
      'A callout',
      'A choice',
      'A block of code',
      'A divider',
      'A board',
      'A chart',
      'A canvas',
      'A footnote',
      'A tag',
      'A counter',
      'A sum',
      'Heat',
    ]);
    expect(rows.moreRows(gates({ canvas: false })).map((row) => row.id)).not.toContain('canvas');
  });
});

describe('where a row is there at all', () => {
  it('offers no video until an Android binary with the video picker, which no binary has yet', () => {
    expect(rows.canPickVideo()).toBe(false);
    Object.assign(device, { tauri: true, android: true });
    // Today's binary, generation 20: a bridge with a picture picker and no video one.
    window.GlyphHost = { pickImage: () => 'started' } as unknown as Window['GlyphHost'];
    expect(rows.canPickVideo()).toBe(false);
    expect(rows.readGates({ picture: true, video: true, place: true, note: true, canvas: true }).video).toBe(false);
    // The generation 21 binary's bridge, and still only on Android.
    window.GlyphHost = { pickVideo: () => 'started' } as unknown as Window['GlyphHost'];
    expect(rows.canPickVideo()).toBe(true);
    device.android = false;
    expect(rows.canPickVideo()).toBe(false);
  });

  it('offers a picture in a browser and on Android with the picker, and not on the Mac until its picker has been run there', () => {
    expect(rows.canPickPicture()).toBe(true);
    Object.assign(device, { tauri: true, android: true });
    expect(rows.canPickPicture()).toBe(false);
    window.GlyphHost = { pickImage: () => 'started' } as unknown as Window['GlyphHost'];
    expect(rows.canPickPicture()).toBe(true);
    Object.assign(device, { android: false, mac: true });
    expect(rows.MAC_PICKER_TRIED).toBe(false);
    expect(rows.canPickPicture()).toBe(false);
    Object.assign(device, { mac: false, ios: true });
    expect(rows.canPickPicture()).toBe(false);
  });

  it('offers a place where the device can find one: never on the Mac, the iPhone app, a browser without it, or an old binary', () => {
    expect(rows.placeRow()).toBe('on');
    setPreferences({ localOnly: true });
    expect(rows.placeRow()).toBe('dimmed');
    setPreferences({ localOnly: false });
    Object.assign(device, { tauri: true, mac: true });
    expect(rows.placeRow()).toBe('absent');
    Object.assign(device, { mac: false, ios: true });
    expect(rows.placeRow()).toBe('absent');
    Object.assign(device, { ios: false, android: true });
    expect(rows.placeRow()).toBe('absent');
    window.GlyphHost = { locationAccess: () => 'granted' } as unknown as Window['GlyphHost'];
    expect(rows.placeRow()).toBe('on');
    Object.assign(device, { tauri: false, android: false });
    geolocation(false);
    expect(rows.placeRow()).toBe('absent');
  });
});

describe('what each row writes on an empty line', () => {
  it('the time and the words, at the caret', () => {
    expect(written('time')).toBe(`Lunch\n${stamp(NOW)}|`);
    expect(written('tag')).toBe('Lunch\n#[tag]');
    expect(written('counter')).toBe('Lunch\n| [0/8]');
  });

  it('a to-do, a choice and the lists as a line’s lead', () => {
    expect(written('todo')).toBe('Lunch\n- [ ] |');
    expect(written('choice')).toBe('Lunch\n- ( ) |');
    expect(written('bullets')).toBe('Lunch\n- |');
    expect(written('numbers', '1. one\n')).toBe('1. one\n2. |');
    expect(written('todo', '- milk\n- ')).toBe('- milk\n- [ ] |');
  });

  it('a heading, a quote and a sum as a line’s form', () => {
    expect(written('heading')).toBe('Lunch\n## |');
    expect(written('quote')).toBe('Lunch\n> |');
    expect(written('sum')).toBe('Lunch\n= |');
  });

  it('the blocks, with a blank line from the words above, and a seed to write over', () => {
    expect(written('table')).toBe('Lunch\n\n| [Column] | Column |\n| --- | --- |\n| Cell | Cell |');
    expect(written('divider')).toBe('Lunch\n\n---\n|');
    expect(written('code')).toBe('Lunch\n\n```\n|\n```');
    expect(written('callout')).toBe('Lunch\n\n> [!NOTE]\n> |');
    expect(written('chart')).toBe('Lunch\n\n```mermaid\nflowchart LR\n  A[[Start]] --> B[Then]\n  B --> C[Done]\n```');
  });

  it('a board as Make a board writes one, its card named by an anchor nothing else has', () => {
    expect(written('board', '- Tent ^first-card\n\n')).toBe('- Tent ^first-card\n\n```board\nTo do: first-card-2\nDoing:\nDone:\n```\n\n- [ ] [First card] ^first-card-2');
  });

  it('a footnote, its number at the caret and its line at the end', () => {
    expect(written('footnote', 'Lunch\n')).toBe('Lunch\n[^1]\n\n[^1]: |');
  });

  it('each as one step to undo', () => {
    for (const id of ['time', 'todo', 'table', 'board', 'footnote', 'heading'] as const) {
      const view = viewOf('Lunch\n');
      rows.writeRow(view, id, NOW);
      undo(view);
      expect(view.state.doc.toString(), id).toBe('Lunch\n');
    }
  });
});

describe('a note to link to', () => {
  it('is any title a link can hold, but this note’s own, at most twelve', () => {
    const titles = ['Lisbon', 'Lisbon, day two', 'Odd ] title', 'Pipe | title', 'Hash # title', ...Array.from({ length: 20 }, (_, i) => `Trip ${i}`)];
    expect(rows.linkableTitles(titles, 'Lisbon, day two', 'lis')).toEqual(['Lisbon']);
    expect(rows.linkableTitles(titles, 'Lisbon', '')).toHaveLength(12);
  });

  it('is written at the caret as a link, and a canvas as a frame on a line of its own', () => {
    const view = viewOf('Met at');
    rows.writeNoteLink(view, 'Lisbon');
    expect(view.state.doc.toString()).toBe('Met at [[Lisbon]]');
    const framed = viewOf('- ');
    rows.writeCanvasFrame(framed, 'Cabin weekend');
    expect(framed.state.doc.toString()).toBe('![[Cabin weekend]]\n');
  });
});
