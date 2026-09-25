import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState, type Extension } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { choices } from './choices.ts';
import { taskToggle } from './taskToggle.ts';

// A tap on a box in the words, through both boxes that answer one (editor/boxTaps.ts): a to-do's and a choice's.

let view: EditorView | null = null;

afterEach(() => {
  view?.destroy();
  view = null;
  vi.restoreAllMocks();
});

/**
 * The note laid out on a grid, since jsdom lays nothing out: every character 10 px wide and every line 20 px tall,
 * so the box of `- [ ] milk` on the first line spans 20 to 50 px across.
 */
function open(doc: string, extension: Extension, readOnly = false): EditorView {
  view = new EditorView({ state: EditorState.create({ doc, extensions: [extension, EditorState.readOnly.of(readOnly)] }), parent: document.body });
  const on = view;
  const box = (pos: number) => {
    const line = on.state.doc.lineAt(pos);
    const left = (pos - line.from) * 10;
    const top = (line.number - 1) * 20;
    return { left, right: left + 10, top, bottom: top + 20 };
  };
  // Leaning back (`side` -1), a position is the character before it.
  vi.spyOn(on, 'coordsAtPos').mockImplementation((pos: number, side = 1) => (side < 0 && pos > 0 ? box(pos - 1) : box(pos)));
  vi.spyOn(on, 'posAtCoords').mockImplementation((({ x, y }: { x: number; y: number }) => {
    const line = on.state.doc.line(Math.min(on.state.doc.lines, Math.floor(y / 20) + 1));
    return Math.min(line.to, line.from + Math.floor(x / 10));
  }) as never);
  return on;
}

function tap(on: EditorView, x: number, y: number, init: MouseEventInit = {}): void {
  on.contentDOM.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0, ...init }));
}

/** Each press that is not a plain one: a modifier held, one at a time, or another button. */
const NOT_PLAIN: [string, MouseEventInit][] = [
  ['shift', { shiftKey: true }],
  ['meta', { metaKey: true }],
  ['ctrl', { ctrlKey: true }],
  ['alt', { altKey: true }],
  ['the other button', { button: 2 }],
];

describe('a tap on a to-do’s box', () => {
  const doc = '- [ ] milk\n- [x] eggs';

  it('ticks it, and another clears it, the caret left where it was', () => {
    const on = open(doc, taskToggle());
    on.dispatch({ selection: { anchor: doc.length } });
    tap(on, 35, 10);
    expect(on.state.doc.line(1).text).toBe('- [x] milk');
    expect(on.state.selection.main.head).toBe(doc.length);
    tap(on, 35, 30);
    expect(on.state.doc.line(2).text).toBe('- [ ] eggs');
  });

  it('counts a thumb a little off the box, and leaves a tap on the words to the editor', () => {
    const on = open(doc, taskToggle());
    // Six pixels short of the box's left edge.
    tap(on, 14, 10);
    expect(on.state.doc.line(1).text).toBe('- [x] milk');
    tap(on, 80, 10);
    expect(on.state.doc.line(1).text).toBe('- [x] milk');
  });

  it('is only a plain press: no modifier, the main button, and a note that can be changed', () => {
    const on = open(doc, taskToggle());
    // Each checked on its own, so two that did answer could not tick and untick the box back to where it was.
    for (const [what, init] of NOT_PLAIN) {
      tap(on, 35, 10, init);
      expect(on.state.doc.toString(), what).toBe(doc);
    }
    tap(on, 35, 10);
    expect(on.state.doc.line(1).text).toBe('- [x] milk');
    view?.destroy();
    const locked = open(doc, taskToggle(), true);
    tap(locked, 35, 10);
    expect(locked.state.doc.toString()).toBe(doc);
  });
});

describe('a tap on a choice’s round box', () => {
  const doc = 'Where do we stay?\n- ( ) Tent\n- (x) Cabin\n- ( ) Hotel';

  it('picks it and clears the one picked before, and a second tap clears it', () => {
    const on = open(doc, choices());
    tap(on, 35, 30);
    expect(on.state.doc.toString()).toBe('Where do we stay?\n- (x) Tent\n- ( ) Cabin\n- ( ) Hotel');
    tap(on, 35, 30);
    expect(on.state.doc.toString()).toBe('Where do we stay?\n- ( ) Tent\n- ( ) Cabin\n- ( ) Hotel');
  });

  it('leaves the words, a press that is not a plain one, and a note that cannot be changed, alone', () => {
    const on = open(doc, choices());
    tap(on, 90, 30);
    expect(on.state.doc.toString()).toBe(doc);
    for (const [what, init] of NOT_PLAIN) {
      tap(on, 35, 30, init);
      expect(on.state.doc.toString(), what).toBe(doc);
    }
    view?.destroy();
    const locked = open(doc, choices(), true);
    tap(locked, 35, 30);
    expect(locked.state.doc.toString()).toBe(doc);
  });

  it('draws each round box as one, the picked one marked', () => {
    const on = open(doc, choices());
    const boxes = [...on.dom.querySelectorAll('.cm-choiceBox')];
    expect(boxes.map((box) => box.textContent)).toEqual(['( )', '(x)', '( )']);
    expect(boxes.map((box) => box.classList.contains('cm-choicePicked'))).toEqual([false, true, false]);
  });
});
