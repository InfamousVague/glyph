import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { bookmarkRibbon } from './bookmarkLine.ts';
import { SETTLE_MS, insertPlus, plusMenu, plusRecheck, type PlusHooks, type PlusKey } from './insertPlus.ts';

/**
 * The + beside the line (editor/insertPlus.ts): where it lives, when it comes and goes, and what its press does and
 * does not reach. The rules for which line are editor/plusLine.test.ts; the timings run on fake timers.
 */

let hooks: PlusHooks & { opened: unknown[]; closed: number; keys: PlusKey[]; take: boolean; allow: boolean };

/** An editor with the +, focused, once CodeMirror has told its plugins so (it waits 10ms after the focus event). */
async function mount(doc: string, caret = doc.length): Promise<EditorView> {
  hooks = {
    opened: [],
    closed: 0,
    keys: [],
    take: true,
    allow: true,
    allowed: () => hooks.allow,
    onOpen: (opening) => hooks.opened.push(opening),
    onClose: () => {
      hooks.closed += 1;
    },
    onKey: (key) => {
      hooks.keys.push(key);
      return hooks.take;
    },
  };
  const view = new EditorView({
    state: EditorState.create({ doc, selection: { anchor: caret }, extensions: [insertPlus(hooks), bookmarkRibbon()] }),
    parent: document.body.appendChild(document.createElement('div')),
  });
  view.focus();
  await vi.advanceTimersByTimeAsync(10);
  return view;
}

const plusOf = (view: EditorView) => view.scrollDOM.querySelector<HTMLButtonElement>('.cm-plus')!;
const stateOf = (view: EditorView) => plusOf(view).dataset.state;

/** Types a letter as the keyboard would: a change at the caret, the caret after it. */
function type(view: EditorView, text: string) {
  const at = view.state.selection.main.head;
  view.dispatch({ changes: { from: at, insert: text }, selection: { anchor: at + text.length }, userEvent: 'input.type' });
}

beforeEach(() => {
  vi.useFakeTimers();
  // jsdom's document never has the window's focus of its own; the editor's focus is what these tests are about.
  vi.spyOn(document, 'hasFocus').mockReturnValue(true);
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  document.body.innerHTML = '';
});

describe('the + beside the line', () => {
  it('is a button in the scroller, outside the lines CodeMirror listens on', async () => {
    const view = await mount('Lunch\n');
    const plus = plusOf(view);
    expect(plus.parentElement).toBe(view.scrollDOM);
    expect(view.contentDOM.contains(plus)).toBe(false);
    expect(plus.getAttribute('aria-label')).toBe('Add to this note');
    expect(plus.getAttribute('aria-haspopup')).toBe('menu');
  });

  it('comes once the caret has rested on an empty line, and not a moment before', async () => {
    const view = await mount('Lunch\n');
    expect(stateOf(view)).toBe('waiting');
    await vi.advanceTimersByTimeAsync(SETTLE_MS - 1);
    expect(stateOf(view)).toBe('waiting');
    await vi.advanceTimersByTimeAsync(1);
    expect(stateOf(view)).toBe('shown');
  });

  it('never comes on a line with words, however long the caret rests', async () => {
    const view = await mount('Lunch at the harbour');
    await vi.advanceTimersByTimeAsync(SETTLE_MS * 10);
    expect(stateOf(view)).toBe('off');
    expect(plusOf(view).hidden).toBe(true);
  });

  it('does not flicker through Enter, Enter typed in a run', async () => {
    const view = await mount('Lunch');
    type(view, '\n');
    await vi.advanceTimersByTimeAsync(SETTLE_MS / 2);
    type(view, '\n');
    await vi.advanceTimersByTimeAsync(SETTLE_MS / 2);
    type(view, 'N');
    await vi.advanceTimersByTimeAsync(SETTLE_MS * 4);
    expect(stateOf(view)).toBe('off');
  });

  it('goes at once with the first letter, with no fade when it had not finished arriving', async () => {
    const view = await mount('Lunch\n');
    await vi.advanceTimersByTimeAsync(SETTLE_MS);
    expect(stateOf(view)).toBe('shown');
    type(view, 'W');
    expect(plusOf(view).hidden).toBe(true);
  });

  it('fades on a deleted letter’s beat once it had arrived, and then waits beside the new line', async () => {
    const view = await mount('Lunch\n');
    await vi.advanceTimersByTimeAsync(SETTLE_MS + 1000);
    type(view, '\n');
    expect(stateOf(view)).toBe('leaving');
    await vi.advanceTimersByTimeAsync(SETTLE_MS);
    expect(stateOf(view)).toBe('shown');
  });

  it('goes when the note loses the focus, and when the screen says no', async () => {
    const view = await mount('Lunch\n');
    await vi.advanceTimersByTimeAsync(SETTLE_MS);
    hooks.allow = false;
    view.dispatch({ effects: plusRecheck.of(null) });
    await vi.advanceTimersByTimeAsync(1000);
    expect(plusOf(view).hidden).toBe(true);
  });

  it('marks its own line only, for the bookmark’s edge to step aside', async () => {
    const view = await mount('Lunch §§\n\nMore');
    view.dispatch({ selection: { anchor: 'Lunch §§\n'.length } });
    await vi.advanceTimersByTimeAsync(SETTLE_MS);
    const marked = [...view.contentDOM.querySelectorAll('.cm-plusLine')];
    expect(marked).toHaveLength(1);
    expect(marked[0]!.textContent).toBe('');
  });
});

describe('its press', () => {
  it('keeps a pointer and a mouse press, and a long press, from the editor; a touch only from bubbling', async () => {
    const view = await mount('Lunch\n');
    await vi.advanceTimersByTimeAsync(SETTLE_MS);
    const plus = plusOf(view);
    const reached: string[] = [];
    for (const kind of ['pointerdown', 'mousedown', 'touchstart', 'contextmenu']) view.dom.addEventListener(kind, () => reached.push(kind));
    const events = {
      pointerdown: new Event('pointerdown', { bubbles: true, cancelable: true }),
      mousedown: new MouseEvent('mousedown', { bubbles: true, cancelable: true }),
      touchstart: new Event('touchstart', { bubbles: true, cancelable: true }),
      contextmenu: new MouseEvent('contextmenu', { bubbles: true, cancelable: true }),
    };
    for (const event of Object.values(events)) plus.dispatchEvent(event);
    expect(reached).toEqual([]);
    expect(events.pointerdown.defaultPrevented).toBe(true);
    expect(events.mousedown.defaultPrevented).toBe(true);
    expect(events.contextmenu.defaultPrevented).toBe(true);
    // A touchstart whose default is taken never becomes a click on Android.
    expect(events.touchstart.defaultPrevented).toBe(false);
  });

  it('asks for the list against its line, and says how it was pressed', async () => {
    const view = await mount('Lunch\n');
    await vi.advanceTimersByTimeAsync(SETTLE_MS);
    const plus = plusOf(view);
    const down = new Event('pointerdown', { bubbles: true, cancelable: true });
    Object.defineProperty(down, 'pointerType', { value: 'touch' });
    plus.dispatchEvent(down);
    plus.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 }));
    expect(hooks.opened).toEqual([{ button: plus, line: 2, by: 'touch' }]);
    expect(view.hasFocus).toBe(true);
  });

  it('closes the list on a second press, as a ×', async () => {
    const view = await mount('Lunch\n');
    await vi.advanceTimersByTimeAsync(SETTLE_MS);
    view.dispatch({ effects: plusMenu.of({ list: 'add-list', active: null }) });
    expect(plusOf(view).getAttribute('aria-expanded')).toBe('true');
    plusOf(view).dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 }));
    expect(hooks.closed).toBe(1);
  });

  it('shows at once when the keyboard reaches it, and opens with the keyboard', async () => {
    const view = await mount('Lunch\n');
    expect(stateOf(view)).toBe('waiting');
    plusOf(view).focus();
    expect(stateOf(view)).toBe('shown');
    plusOf(view).dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 0 }));
    expect(hooks.opened).toMatchObject([{ line: 2, by: 'keyboard' }]);
  });
});

describe('the list open from the editor', () => {
  const key = (view: EditorView, name: string) => {
    const event = new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true });
    view.contentDOM.dispatchEvent(event);
    return event;
  };

  it('takes Up, Down, Enter, Escape, Left and Right from the editor', async () => {
    const view = await mount('Lunch\n');
    view.dispatch({ effects: plusMenu.of({ list: 'add-list', active: 'add-picture' }) });
    for (const name of ['ArrowUp', 'ArrowDown', 'Enter', 'Escape', 'ArrowLeft', 'ArrowRight']) expect(key(view, name).defaultPrevented, name).toBe(true);
    expect(hooks.keys).toEqual(['up', 'down', 'enter', 'escape', 'left', 'right']);
    expect(hooks.closed).toBe(0);
  });

  it('closes on any other key, which then does what it always does', async () => {
    const view = await mount('Lunch\n');
    view.dispatch({ effects: plusMenu.of({ list: 'add-list', active: 'add-picture' }) });
    expect(key(view, 'Shift').defaultPrevented).toBe(false);
    expect(hooks.closed).toBe(0);
    expect(key(view, 'a').defaultPrevented).toBe(false);
    expect(hooks.closed).toBe(1);
  });

  it('closes on a change or a caret move in the note', async () => {
    const view = await mount('Lunch\n');
    view.dispatch({ effects: plusMenu.of({ list: 'add-list', active: null }) });
    view.dispatch({ selection: { anchor: 0 } });
    await vi.advanceTimersByTimeAsync(0);
    expect(hooks.closed).toBe(1);
  });

  it('names the lit row to a screen reader, and nothing once it closes', async () => {
    const view = await mount('Lunch\n');
    view.dispatch({ effects: plusMenu.of({ list: 'add-list', active: 'add-place' }) });
    expect(view.contentDOM.getAttribute('aria-activedescendant')).toBe('add-place');
    expect(view.contentDOM.getAttribute('aria-controls')).toBe('add-list');
    view.dispatch({ effects: plusMenu.of(null) });
    expect(view.contentDOM.hasAttribute('aria-activedescendant')).toBe(false);
  });

  it('leaves the keys alone while it is closed', async () => {
    const view = await mount('Lunch\n');
    expect(key(view, 'ArrowUp').defaultPrevented).toBe(false);
    expect(hooks.keys).toEqual([]);
  });
});
