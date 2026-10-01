import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, createRef, type MutableRefObject } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { history } from '@codemirror/commands';
import { goBack } from '../core/back.ts';
import { DEFAULT_PREFERENCES, setPreferences } from '../core/preferences.ts';
import { press, show, typeInto, unmount } from '../../test/render.tsx';
import { AddList, type AddListProps } from './AddList.tsx';
import { insertPlus, type PlusKey, type PlusOpening } from './insertPlus.ts';
import { glyphMarkdown } from './language.ts';

/**
 * The + beside the line's list (editor/AddList.tsx): its rows, where it goes against the +'s row (never over it, and on
 * one side of the Fold's crease), what closes it and what does not, the page behind More, the step that asks which
 * note, and that a press on it never takes the editor's focus.
 */

let view: EditorView;
let closed: number;
let keys: MutableRefObject<((key: PlusKey) => boolean) | null>;
let button: HTMLButtonElement;

/** The +'s row, where the list is placed from: the gutter's width and a row's height. */
function rowAt(top: number, left = 0, width = 22.4, height = 27) {
  button.getBoundingClientRect = () => new DOMRect(left, top, width, height);
}

function open(over: Partial<AddListProps> = {}, by: PlusOpening['by'] = 'touch') {
  const props: AddListProps = {
    view,
    opening: { button, line: 2, by },
    pane: () => new DOMRect(0, 60, window.innerWidth, window.innerHeight - 60),
    onClose: () => {
      closed += 1;
      unmount();
    },
    keys,
    onPicture: vi.fn(),
    onPlace: vi.fn(),
    titles: () => ['Lisbon', 'Lisbon, day two', 'Porto'],
    canvases: () => ['Cabin weekend'],
    own: 'Lisbon, day two',
    ...over,
  };
  const host = show(<AddList {...props} />);
  return { host, props, list: () => document.getElementById('add-list') as HTMLElement | null };
}

const words = () => [...document.querySelectorAll('#add-list [role=menuitem]')].map((row) => row.textContent);
const rowSaying = (text: string) => [...document.querySelectorAll<HTMLButtonElement>('#add-list button')].find((row) => row.textContent?.startsWith(text));
/** The time row, in whatever order the locale puts the day and the month. */
const timeRow = () => [...document.querySelectorAll<HTMLButtonElement>('#add-list button')].find((row) => row.textContent?.includes('2026'))!;

/** How much of the card is not the rows that scroll: More held at its foot, and the padding round it. */
const HELD = 44 + 4;

/** The sizes the list draws at, which jsdom does not lay out: a 256-wide card of 44px rows, one of them held at its foot. */
function sized(rows: number) {
  Object.defineProperty(HTMLElement.prototype, 'offsetHeight', {
    configurable: true,
    get(this: HTMLElement) {
      if (this.id === 'add-list') return rows * 44 + 8;
      if (this.dataset.index !== undefined) return 44;
      if (this.dataset.rows !== undefined) return rows * 44 + 8 - HELD;
      return 0;
    },
  });
  Object.defineProperty(HTMLElement.prototype, 'offsetWidth', {
    configurable: true,
    get(this: HTMLElement) {
      return this.id === 'add-list' ? 256 : 0;
    },
  });
  // The rows' whole height, whatever they are capped to.
  Object.defineProperty(HTMLElement.prototype, 'scrollHeight', {
    configurable: true,
    get(this: HTMLElement) {
      return this.dataset.rows !== undefined ? rows * 44 + 8 - HELD : 0;
    },
  });
}

/** The rows that scroll, inside the card. */
const scrolling = () => document.querySelector<HTMLElement>('#add-list [data-rows]')!;

function screen(width: number, height: number, { coarse = true } = {}) {
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: width });
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: height });
  vi.stubGlobal('matchMedia', (query: string) => ({ matches: coarse && query.includes('pointer: coarse') && width >= 600, media: query, addEventListener: () => undefined, removeEventListener: () => undefined }));
}

const placed = (list: HTMLElement) => ({ left: parseFloat(list.style.left), top: parseFloat(list.style.top), width: list.style.inlineSize ? parseFloat(list.style.inlineSize) : 256 });

beforeEach(() => {
  closed = 0;
  keys = createRef() as MutableRefObject<((key: PlusKey) => boolean) | null>;
  view = new EditorView({
    state: EditorState.create({
      doc: 'Lunch\n',
      selection: { anchor: 6 },
      extensions: [glyphMarkdown([], []), history(), insertPlus({ allowed: () => true, onOpen: () => undefined, onClose: () => undefined, onKey: () => false })],
    }),
    parent: document.body.appendChild(document.createElement('div')),
  });
  button = view.scrollDOM.querySelector('.cm-plus')!;
  Object.defineProperty(navigator, 'geolocation', { configurable: true, value: { getCurrentPosition: () => undefined } });
  screen(412, 915, { coarse: false });
  sized(8);
  rowAt(100);
});

afterEach(() => {
  unmount();
  view.destroy();
  document.body.innerHTML = '';
  Reflect.deleteProperty(HTMLElement.prototype, 'offsetHeight');
  Reflect.deleteProperty(HTMLElement.prototype, 'offsetWidth');
  Reflect.deleteProperty(HTMLElement.prototype, 'scrollHeight');
  Reflect.deleteProperty(navigator, 'geolocation');
  vi.unstubAllGlobals();
  setPreferences({ localOnly: DEFAULT_PREFERENCES.localOnly });
});

describe('the list', () => {
  it('holds the seven things in a browser, less the video, and More', () => {
    open();
    expect(words()).toEqual(['A picture', 'A place', expect.stringMatching(/2026|20\d\d/), 'A table', 'A note', 'A to-do', 'More']);
    expect(document.getElementById('add-list')?.getAttribute('role')).toBe('menu');
  });

  it('holds A video second where the screen adds films, and a press on it is the screen’s', () => {
    const onVideo = vi.fn();
    open({ onVideo });
    expect(words().slice(0, 3)).toEqual(['A picture', 'A video', 'A place']);
    const row = [...document.querySelectorAll<HTMLButtonElement>('#add-list button')].find((found) => found.textContent === 'A video')!;
    act(() => row.click());
    expect(onVideo).toHaveBeenCalledTimes(1);
    expect(closed).toBe(1);
  });

  it('holds no row the screen cannot do', () => {
    open({ onPicture: undefined, onPlace: undefined, titles: undefined });
    expect(words().filter((row) => !/\d/.test(row ?? ''))).toEqual(['A table', 'A to-do', 'More']);
  });

  it('writes the time its row says, even pressed after the minute has turned and before the row has', () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
    try {
      vi.setSystemTime(new Date(2026, 8, 28, 14, 5, 59, 900));
      open();
      const time = timeRow();
      const says = time.textContent!;
      expect(says).toMatch(/14:05$/);
      // The clock moves on; the row's minute timer has not fired yet.
      vi.setSystemTime(new Date(2026, 8, 28, 14, 6, 0, 50));
      press(time);
      expect(view.state.doc.toString()).toBe(`Lunch\n${says}`);
    } finally {
      vi.useRealTimers();
    }
  });

  it('turns the time row at the minute, and writes what it turns to', () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
    try {
      vi.setSystemTime(new Date(2026, 8, 28, 14, 5, 59, 900));
      open();
      act(() => void vi.advanceTimersByTime(200));
      const time = timeRow();
      expect(time.textContent).toMatch(/14:06$/);
      press(time);
      expect(view.state.doc.toString()).toMatch(/^Lunch\n.*14:06$/);
    } finally {
      vi.useRealTimers();
    }
  });

  it('dims the place under Local only, says why, and adds nothing when it is pressed', () => {
    setPreferences({ localOnly: true });
    const { props } = open();
    const place = rowSaying('A place')!;
    expect(place.getAttribute('aria-disabled')).toBe('true');
    expect(place.textContent).toContain('Local only is on.');
    press(place);
    expect(props.onPlace).not.toHaveBeenCalled();
    expect(closed).toBe(0);
  });

  it('keeps the editor’s focus and caret: its press is taken from the page', () => {
    const { list } = open();
    const down = new MouseEvent('pointerdown', { bubbles: true, cancelable: true });
    rowSaying('A table')!.dispatchEvent(down);
    expect(down.defaultPrevented).toBe(true);
    expect(list()).not.toBeNull();
  });
});

describe('where it goes', () => {
  it('opens below the +’s row when there is room there', () => {
    const { list } = open();
    expect(placed(list()!).top).toBe(100 + 27 + 6);
    expect(placed(list()!).left).toBeCloseTo(22.4);
  });

  it('opens above the row when the keyboard leaves no room below', () => {
    rowAt(700);
    const { list } = open();
    const at = placed(list()!);
    expect(at.top + 8 * 44 + 8).toBe(700 - 6);
  });

  it('takes the larger side when neither holds it all, scrolls, and never covers the row', () => {
    screen(412, 500, { coarse: false });
    rowAt(240);
    const { list } = open();
    const at = placed(list()!);
    const height = parseFloat(scrolling().style.maxBlockSize) + HELD;
    // Above is 234 - 68 = 166 and below 492 - 273 = 219: below is larger, and the list keeps off the row.
    expect(at.top).toBe(240 + 27 + 6);
    expect(height).toBe(500 - 8 - at.top);
    expect(at.top).toBeGreaterThanOrEqual(240 + 27);
  });

  it('keeps More in sight however little room there is: it is held at the foot, and only the rows above it scroll', () => {
    // The phone with the keyboard up (412 by 579), the + where the editor keeps the caret, and the note's pane under
    // its header and tabs: seven rows and More fit neither side.
    screen(412, 579, { coarse: false });
    rowAt(444);
    const { list } = open({ pane: () => new DOMRect(0, 110, 412, 469) });
    const more = rowSaying('More')!;
    expect(list()!.contains(more)).toBe(true);
    expect(scrolling().contains(more)).toBe(false);
    expect(scrolling().style.maxBlockSize).not.toBe('');
    expect(scrolling().contains(rowSaying('A to-do')!)).toBe(true);
    // On More, Back is held at the top the same way.
    press(more);
    const back = rowSaying('Back')!;
    expect(scrolling().contains(back)).toBe(false);
    expect(list()!.contains(back)).toBe(true);
  });

  it('keeps to one side of the opened Fold’s crease: at the text when it fits before it', () => {
    screen(880, 790);
    rowAt(200, 0, 24.5);
    const { list } = open();
    expect(placed(list()!)).toMatchObject({ left: 24.5, width: 256 });
  });

  it('starts past the crease when the docked sidebar leaves too little before it', () => {
    screen(880, 790);
    rowAt(200, 300, 24.5);
    const { list } = open();
    expect(placed(list()!).left).toBe(456);
  });

  it('crosses it only when neither side has room', () => {
    screen(880, 790);
    rowAt(200, 375.5, 24.5);
    const { list } = open({ pane: () => new DOMRect(375.5, 60, 224.5, 730) });
    expect(placed(list()!).left).toBe(400);
  });
});

describe('what closes it', () => {
  it('a row chosen, first, and then the row does what it says', () => {
    open();
    press(rowSaying('A table'));
    expect(closed).toBe(1);
    expect(view.state.doc.toString()).toBe('Lunch\n\n| Column | Column |\n| --- | --- |\n| Cell | Cell |');
  });

  it('a press outside it, a wheel or a drag outside it, the back gesture, and Escape', () => {
    open();
    act(() => document.body.dispatchEvent(new Event('pointerdown', { bubbles: true })));
    expect(closed).toBe(1);
    open();
    act(() => document.body.dispatchEvent(new Event('wheel', { bubbles: true })));
    expect(closed).toBe(2);
    open();
    act(() => void goBack());
    expect(closed).toBe(3);
    open();
    act(() => void keys.current?.('escape'));
    expect(closed).toBe(4);
  });

  it('not a press on the + itself, which is the ×’s to answer', () => {
    open();
    act(() => button.dispatchEvent(new Event('pointerdown', { bubbles: true })));
    expect(closed).toBe(0);
  });

  it('not a scroll: the keyboard rising scrolls the note, and the list follows the + instead', async () => {
    const { list } = open();
    rowAt(300);
    await act(async () => {
      document.dispatchEvent(new Event('scroll'));
      await new Promise((resolve) => requestAnimationFrame(resolve));
    });
    expect(closed).toBe(0);
    expect(placed(list()!).top).toBe(300 + 27 + 6);
  });

  it('not a scroll of its own rows, which keep where they are scrolled to', async () => {
    screen(412, 500, { coarse: false });
    rowAt(240);
    const { list } = open();
    const rows = scrolling();
    const was = placed(list()!).top;
    // Were the list placed again on its own scroll, it would move to where the + now says, and its cap would be taken
    // off and put back, which drops the rows' scroll in a real layout.
    rowAt(200);
    await act(async () => {
      rows.dispatchEvent(new Event('scroll'));
      await new Promise((resolve) => requestAnimationFrame(resolve));
    });
    expect(closed).toBe(0);
    expect(placed(list()!).top).toBe(was);
  });

  it('once the + has left the screen', async () => {
    open();
    rowAt(-200);
    await act(async () => {
      document.dispatchEvent(new Event('scroll'));
      await new Promise((resolve) => requestAnimationFrame(resolve));
    });
    expect(closed).toBe(1);
  });
});

describe('driven from the editor’s keys', () => {
  it('lights a row and moves it, names it to the editor, and chooses it with Enter', () => {
    open({}, 'pointer');
    const lit = () => document.querySelector('#add-list [data-active]')?.textContent;
    expect(lit()).toBe('A picture');
    expect(view.contentDOM.getAttribute('aria-activedescendant')).toBe('add-picture');
    act(() => void keys.current?.('down'));
    act(() => void keys.current?.('down'));
    expect(lit()).toMatch(/2026/);
    act(() => void keys.current?.('up'));
    expect(lit()).toBe('A place');
    act(() => void keys.current?.('up'));
    act(() => void keys.current?.('up'));
    expect(lit()).toBe('More');
    act(() => void keys.current?.('enter'));
    expect(words()[0]).toBe('Back');
  });

  it('rings the lit row only once a key has moved it, never where the pointer lit it', () => {
    open({}, 'pointer');
    const list = () => document.getElementById('add-list')!;
    expect(document.querySelector('#add-list [data-active]')?.textContent).toBe('A picture');
    expect(list().hasAttribute('data-keys')).toBe(false);
    act(() => void keys.current?.('down'));
    expect(list().hasAttribute('data-keys')).toBe(true);
    const table = rowSaying('A table')!;
    act(() => table.dispatchEvent(Object.assign(new MouseEvent('pointerover', { bubbles: true }), { pointerType: 'mouse' })));
    act(() => table.dispatchEvent(Object.assign(new MouseEvent('pointerenter', { bubbles: false }), { pointerType: 'mouse' })));
    expect(document.querySelector('#add-list [data-active]')?.textContent).toBe('A table');
    expect(list().hasAttribute('data-keys')).toBe(false);
  });

  it('goes into More with Right, and leaves Right on any other row to the editor', () => {
    open({}, 'pointer');
    let taken = true;
    act(() => void (taken = keys.current?.('right') ?? false));
    expect(taken).toBe(false);
    expect(words()).toContain('A to-do');
    act(() => void keys.current?.('up'));
    expect(document.querySelector('#add-list [data-active]')?.textContent).toBe('More');
    act(() => void (taken = keys.current?.('right') ?? false));
    expect(taken).toBe(true);
    expect(words()[0]).toBe('Back');
  });

  it('lights the first row of a page turned to, wherever the keys were on the page before', () => {
    open({}, 'pointer');
    act(() => void keys.current?.('up'));
    act(() => void keys.current?.('enter'));
    expect(document.querySelector('#add-list [data-active]')?.textContent).toBe('Back');
    act(() => void keys.current?.('down'));
    act(() => void keys.current?.('down'));
    act(() => void keys.current?.('left'));
    expect(document.querySelector('#add-list [data-active]')?.textContent).toBe('A picture');
  });

  it('goes back from More with Left, and closes on Left at the top, leaving the key to the editor', () => {
    open({}, 'pointer');
    press(rowSaying('More'));
    expect(words()).toContain('A heading');
    let taken = false;
    act(() => void (taken = keys.current?.('left') ?? false));
    expect(taken).toBe(true);
    expect(words()).toContain('A to-do');
    act(() => void (taken = keys.current?.('left') ?? false));
    expect(taken).toBe(false);
  });
});

describe('from the keyboard on the + itself', () => {
  it('puts the focus on the first row', () => {
    open({}, 'keyboard');
    expect(document.activeElement?.textContent).toBe('A picture');
  });

  it('goes back from More with Left while the focus is in the list, and not while it is in a field', () => {
    open({}, 'keyboard');
    press(rowSaying('More'));
    expect(words()[0]).toBe('Back');
    const left = () => {
      const event = new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true, cancelable: true });
      act(() => void document.activeElement!.dispatchEvent(event));
      return event;
    };
    expect(left().defaultPrevented).toBe(true);
    expect(words()).toContain('A to-do');
    expect(closed).toBe(0);
    press(rowSaying('A note'));
    const field = document.querySelector<HTMLInputElement>('#add-list input')!;
    field.focus();
    expect(left().defaultPrevented).toBe(false);
    expect(document.querySelector('#add-list input')).not.toBeNull();
  });
});

describe('More', () => {
  it('turns the list over to the rest, with Back at its top', () => {
    open();
    press(rowSaying('More'));
    expect(words().slice(0, 4)).toEqual(['Back', 'A heading', 'A bulleted list', 'A numbered list']);
    press(rowSaying('A heading'));
    expect(closed).toBe(1);
    expect(view.state.doc.toString()).toBe('Lunch\n## ');
  });

  it('goes back to the first page with Back, and does not close', () => {
    open();
    press(rowSaying('More'));
    press(rowSaying('Back'));
    expect(closed).toBe(0);
    expect(words()).toEqual(['A picture', 'A place', expect.stringMatching(/2026|20\d\d/), 'A table', 'A note', 'A to-do', 'More']);
  });

  it('goes back a page with the phone’s back gesture, and closes from the first page', () => {
    open();
    press(rowSaying('More'));
    act(() => void goBack());
    expect(closed).toBe(0);
    expect(words()).toContain('A to-do');
    act(() => void goBack());
    expect(closed).toBe(1);
  });

  it('opens at its top, whatever the page before was scrolled to', () => {
    open();
    const rows = scrolling();
    Object.defineProperty(rows, 'scrollTop', { configurable: true, writable: true, value: 120 });
    press(rowSaying('More'));
    expect(rows.scrollTop).toBe(0);
  });
});

describe('A database', () => {
  it('turns More over to the ready-made databases, and one chosen is written and drawn at once', () => {
    open();
    press(rowSaying('More'));
    press(rowSaying('A database'));
    expect(words().slice(0, 3)).toEqual(['Back', 'To-dos due this week', 'Overdue to-dos']);
    expect(words().at(-1)).toBe('Write your own');
    press(rowSaying('A ticket board'));
    expect(closed).toBe(1);
    expect(view.state.doc.toString()).toBe('Lunch\n\n```query\nfrom: tickets\nshow: board\n```\n');
  });

  it('goes back to More, not the first page, with Back and the back gesture', () => {
    open();
    press(rowSaying('More'));
    press(rowSaying('A database'));
    press(rowSaying('Back'));
    expect(closed).toBe(0);
    expect(words()).toContain('A database');
    press(rowSaying('A database'));
    act(() => void goBack());
    expect(words()).toContain('A heading');
    expect(closed).toBe(0);
  });

  it('offers Make this a ticket only in a note that is not one', () => {
    open();
    press(rowSaying('More'));
    expect(words()).toContain('Make this a ticket');
  });
});

describe('A note', () => {
  it('asks which, by part of its title, and writes the link where the caret was', () => {
    open();
    press(rowSaying('A note'));
    const field = document.querySelector<HTMLInputElement>('#add-list input')!;
    expect(field.getAttribute('placeholder')).toBe('Type part of its title');
    expect(document.getElementById('add-list')?.textContent).toContain('Which note?');
    typeInto(field, 'lis');
    // Its own title is not offered.
    expect(rowSaying('Lisbon, day two')).toBeUndefined();
    press(rowSaying('Lisbon'));
    expect(view.state.doc.toString()).toBe('Lunch\n[[Lisbon]]');
    expect(closed).toBe(1);
  });

  it('goes back to the list with its Back, held above the field', () => {
    open();
    press(rowSaying('A note'));
    const back = rowSaying('Back')!;
    expect(scrolling().contains(back)).toBe(false);
    press(back);
    expect(closed).toBe(0);
    expect(document.querySelector('#add-list input')).toBeNull();
    expect(words()).toContain('A note');
  });

  it('says when nothing is called that', () => {
    open();
    press(rowSaying('A note'));
    typeInto(document.querySelector<HTMLInputElement>('#add-list input')!, 'zzz');
    expect(document.getElementById('add-list')?.textContent).toContain('No note by that name.');
  });
});
