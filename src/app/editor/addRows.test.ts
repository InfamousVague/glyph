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
  it('lead with the phone’s things, then the data trio (table, board, database), then a note and a to-do, then More', () => {
    const top = rows.topRows(gates({ video: true }), NOW);
    expect(top.map((row) => row.words)).toEqual(['A picture', 'A video', 'A place', stamp(NOW), 'A table', 'A board', 'A database', 'A note', 'A to-do', 'More']);
    // A board and a database are steps now, not direct writes (editor/AddList.tsx opens their page).
    expect(top.find((row) => row.id === 'board')?.step).toBe('board');
    expect(top.find((row) => row.id === 'query')?.step).toBe('database');
  });

  it('say the time as it will be written, and read it aloud with the month in full', () => {
    const time = rows.topRows(gates(), NOW).find((row) => row.id === 'time')!;
    expect(time.words).toBe(stamp(NOW));
    expect(time.label).toMatch(/^The date and time, .*2026, 14:05$/);
    expect(time.label).toContain(new Intl.DateTimeFormat(undefined, { month: 'long' }).format(NOW));
  });

  it('write the minute’s name on the line that names the note, not the stamp, and say so', () => {
    const naming = rows.topRows(gates(), NOW, true).find((row) => row.id === 'time')!;
    expect(naming.words).toBe('2026-09-28 14.05');
    expect(naming.label).toBe('The date and time as a name, 2026-09-28 14.05');
    expect(written('time', '')).toBe('2026-09-28 14.05|');
    expect(written('time', '# ')).toBe('# 2026-09-28 14.05|');
    // Anywhere else, the stamp as before.
    expect(written('time', '# Lunch\n\n')).toContain(stamp(NOW));
    expect(written('time')).toContain(stamp(NOW));
  });

  it('leave out what the screen cannot do', () => {
    const top = rows.topRows(gates({ picture: false, place: 'absent', note: false }), NOW);
    expect(top.map((row) => row.id)).toEqual(['time', 'table', 'board', 'query', 'todo', 'more']);
  });

  it('dim a place under Local only, and say why', () => {
    const place = rows.topRows(gates({ place: 'dimmed' }), NOW).find((row) => row.id === 'place');
    expect(place?.dimmed).toBe('Local only is on.');
  });

  it('keep the rest behind More: the forms, the blocks, the small marks, and the effects that are on', () => {
    const heat = { name: 'Heat', delimiter: '🔥🔥', look: { kind: 'effect', effect: 'heat' }, cue: 'heated' } as const;
    expect(rows.moreRows(gates({ effects: [heat] })).map((row) => row.words)).toEqual([
      'A heading',
      'A bulleted list',
      'A numbered list',
      'A quote',
      'A callout',
      'A choice',
      'A to-do with a due date',
      'A block of code',
      'A divider',
      'A diagram',
      'A formula',
      'A canvas',
      'A footnote',
      'A tag',
      'A counter',
      'A sum',
      'A blank for the AI',
      'Heated words',
    ]);
    expect(rows.moreRows(gates({ canvas: false })).map((row) => row.id)).not.toContain('canvas');
  });
});

describe('where a row is there at all', () => {
  it('offers a video exactly where the screen says the binary adds one (core/videos.ts canAddVideos)', () => {
    const gates = (video: boolean) => rows.readGates({ picture: true, video, place: true, note: true, canvas: true });
    expect(gates(false).video).toBe(false);
    expect(gates(true).video).toBe(true);
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
    expect(written('counter')).toBe('Lunch\n[Count] [0/8]');
    expect(written('counter', 'Goals\n- ')).toBe('Goals\n- [Count] [0/8]');
  });

  it('an effect as words to write over between its marks, named as it is said', async () => {
    const { plugins } = await import('../plugins/registry.ts');
    const heat = { name: 'Heat', delimiter: '🔥🔥', look: { kind: 'effect', effect: 'heat' }, cue: 'heated' } as const;
    const spy = vi.spyOn(plugins, 'formats').mockReturnValue([heat]);
    try {
      expect(written('effect:Heat')).toBe('Lunch\n🔥🔥[words]🔥🔥');
      expect(rows.effectWords(heat)).toBe('Heated words');
      expect(rows.effectWords({ ...heat, cue: undefined, name: 'Glow' })).toBe('Glow words');
    } finally {
      spy.mockRestore();
    }
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
    // A formula is a $$ block drawn by KaTeX, the caret on the empty line between its fences.
    expect(written('formula')).toBe('Lunch\n\n$$\n|\n$$');
  });

  it('a board as a page of the two ways to start one', () => {
    expect(rows.boardRows().map((row) => ({ id: row.id, words: row.words }))).toEqual([
      { id: 'board', words: 'Fresh columns' },
      { id: 'query:board', words: 'From your tickets' },
    ]);
    // Neither way is in More any more; the board and the database are steps on the first page.
    expect(rows.moreRows(gates()).map((row) => row.id)).not.toContain('board');
    expect(rows.moreRows(gates()).map((row) => row.id)).not.toContain('query');
  });

  it('a database as a page of ready-made ones, each drawn at once, and Write your own with its kind to write over', () => {
    expect(rows.databaseRows().map((row) => row.words)).toEqual([
      'To-dos due this week',
      'Overdue to-dos',
      'To-dos by person',
      'To-dos on a calendar',
      'A ticket board',
      'Open tickets, with estimates',
      'A ticket timeline',
      'Notes changed this week',
      'How many to-dos are open',
      'Write your own',
    ]);
    expect(written('query:board')).toBe('Lunch\n\n```query\nfrom: tickets\nshow: board\n```\n|');
    expect(written('query:own')).toBe('Lunch\n\n```query\nfrom: [tasks]\nwhere: due <= today+7\nsort: due, priority\nshow: list\n```');
    expect(rows.querySeed('query:nothing')).toBeNull();
  });

  it('a to-do with a due date, due tomorrow, its words to write over', () => {
    expect(written('dated')).toBe('Lunch\n- [ ] [To-do] 📅 2026-09-29');
    expect(written('dated', 'Lunch\n- [ ] ')).toBe('Lunch\n- [ ] [To-do] 📅 2026-09-29');
    // One undo takes the whole of it away.
    const view = viewOf('Lunch\n');
    rows.writeRow(view, 'dated', NOW);
    undo(view);
    expect(view.state.doc.toString()).toBe('Lunch\n');
  });

  it('a note made a ticket, its front matter written for it, a status kept where it has one', () => {
    expect(written('ticket', '# Fix the login loop\n\nIt loops.')).toBe('---\ntype: ticket\nstatus: To do\n---\n# Fix the login loop\n\nIt loops.|');
    expect(written('ticket', '---\ntitle: "Plan"\nstatus: In review\n---\n# Plan')).toBe('---\ntitle: "Plan"\nstatus: In review\ntype: ticket\n---\n# Plan|');
    expect(rows.writeRow(viewOf('---\ntype: ticket\n---\n# Done already'), 'ticket', NOW)).toBe(false);
    expect(rows.moreRows(gates()).map((row) => row.id)).not.toContain('ticket');
    expect(rows.moreRows(gates({ ticket: true })).map((row) => row.id)).toContain('ticket');
  });

  it('a board as Make a board writes one, its card named by an anchor nothing else has', () => {
    expect(written('board', '- Tent ^first-card\n\n')).toBe('- Tent ^first-card\n\n```board\nTo do: first-card-2\nDoing:\nDone:\n```\n\n- [ ] [First card] ^first-card-2');
  });

  it('a footnote, its number closing the words above and its line at the end', () => {
    expect(written('footnote', 'Lunch  \n')).toBe('Lunch[^1]  \n\n[^1]: |');
    expect(written('footnote', 'Tent[^1]\n\n[^1]: Borrowed.\n\nStove\n')).toBe('Tent[^1]\n\n[^1]: Borrowed.\n\nStove[^2]\n\n[^2]: |');
    // With no words just above, or a table's row, it goes where the caret is.
    expect(written('footnote', 'Lunch\n\n')).toBe('Lunch\n\n[^1]\n\n[^1]: |');
    expect(written('footnote', '| a | b |\n')).toBe('| a | b |\n[^1]\n\n[^1]: |');
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

describe('a blank for the AI (docs/DESIGN.md §145)', () => {
  it('writes {?} with the caret between its ? and }, a line of its own', () => {
    expect(written('blank', '')).toBe('{?|}\n');
    expect(written('blank', 'Lunch\n')).toBe('Lunch\n{?|}\n');
  });

  it('is an item’s words on an empty item, and keeps a blank line from a table, a list or a quote above', () => {
    expect(written('blank', '- ')).toBe('- {?|}');
    expect(written('blank', '- [ ] ')).toBe('- [ ] {?|}');
    expect(written('blank', '| A | B |\n| --- | --- |\n| x | y |\n')).toBe('| A | B |\n| --- | --- |\n| x | y |\n\n{?|}\n');
    expect(written('blank', '- Passport\n')).toBe('- Passport\n\n{?|}\n');
  });

  it('fills every empty body cell of the table above, in one Undo, only where there is one', () => {
    const table = '| Say | In Japanese |\n| --- | --- |\n| Thank you |  |\n| Excuse me | すみません |\n| Goodbye | |\n';
    expect(rows.moreRows(gates({ tableAbove: true })).map((r) => r.id)).toContain('blankCells');
    expect(rows.moreRows(gates()).map((r) => r.id)).not.toContain('blankCells');
    const view = viewOf(table);
    expect(rows.emptyCellsAbove(view.state, table.length)).toHaveLength(2);
    expect(rows.writeRow(view, 'blankCells', NOW)).toBe(true);
    expect(view.state.doc.toString()).toBe('| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |\n| Excuse me | すみません |\n| Goodbye | {?} |\n');
    expect(view.state.selection.main.head).toBe(view.state.doc.length);
    undo(view);
    expect(view.state.doc.toString()).toBe(table);
    expect(rows.emptyCellsAbove(viewOf('| A |\n| --- |\n| x |\n').state, 17)).toBeNull();
  });
});

