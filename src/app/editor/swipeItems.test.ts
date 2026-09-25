import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { swipeItemAction, swipeItemTheme, type SwipeAction } from './swipeItems.ts';

const doc = '- [ ] Buy milk\nplain words\n- [ ] Call Sam [notion](https://www.notion.so/Call-Sam-3db522a4563081298304c129ce6004e4)';

let view: EditorView | null = null;

afterEach(() => {
  view?.destroy();
  view = null;
});

/** The note, the action a swipe runs on it, and the finished run it is waiting on. */
function open(offered: boolean = true) {
  let finish: () => void = () => undefined;
  const run = vi.fn((_text: string) => new Promise<void>((resolve) => (finish = resolve)));
  const action: SwipeAction = { label: 'Send to Notion', busyLabel: 'Sending…', run };
  view = new EditorView({ state: EditorState.create({ doc, extensions: [swipeItemAction({ action: () => (offered ? action : null) }), swipeItemTheme] }), parent: document.body });
  const on = view;
  const line = (n: number) => {
    const element = on.contentDOM.querySelectorAll<HTMLElement>('.cm-line')[n - 1]!;
    // jsdom lays nothing out: every line is 300 px wide, so the swipe counts once it is 90 px along.
    Object.defineProperty(element, 'offsetWidth', { configurable: true, value: 300 });
    return element;
  };
  return { on, run, line, finish: () => finish() };
}

function pointer(target: EventTarget, type: string, x: number, y: number, id = 1): void {
  target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0, pointerId: id, pointerType: 'touch' }));
}
const tile = (on: EditorView) => on.scrollDOM.querySelector<HTMLElement>('.cm-swipeItem');

describe('swiping a list item left', () => {
  it('follows the finger, fills a tile with the action’s word, and runs it on the item’s words past the point where it counts', async () => {
    const { on, run, line, finish } = open();
    const item = line(1);
    pointer(item, 'pointerdown', 250, 10);
    // Under a finger's intent, nothing moves yet.
    pointer(item, 'pointermove', 242, 10);
    expect(item.style.transform).toBe('');
    pointer(item, 'pointermove', 140, 14);
    expect(item.style.transform).toBe('translateX(-110px)');
    expect(tile(on)?.textContent).toBe('Send to Notion');
    expect(tile(on)?.hasAttribute('data-armed')).toBe(true);

    pointer(item, 'pointerup', 140, 14);
    expect(run).toHaveBeenCalledWith('Buy milk');
    // The line springs back, and the tile says what is happening until it is done.
    expect(item.style.transform).toBe('');
    expect(tile(on)?.textContent).toBe('Sending…');
    finish();
    await vi.waitFor(() => expect(tile(on)).toBeNull());
  });

  it('springs back short of the point, running nothing', () => {
    const { on, run, line } = open();
    const item = line(1);
    pointer(item, 'pointerdown', 250, 10);
    pointer(item, 'pointermove', 200, 10);
    expect(tile(on)?.hasAttribute('data-armed')).toBe(false);
    pointer(item, 'pointerup', 200, 10);
    expect(run).not.toHaveBeenCalled();
    expect(item.style.transform).toBe('');
    expect(tile(on)).toBeNull();
  });

  it('leaves a drag that is mostly down the page, or to the right, to the editor', () => {
    const { run, line } = open();
    const item = line(1);
    pointer(item, 'pointerdown', 250, 10);
    pointer(item, 'pointermove', 230, 60);
    pointer(item, 'pointermove', 100, 60);
    expect(item.style.transform).toBe('');
    pointer(item, 'pointerup', 100, 60);
    pointer(item, 'pointerdown', 100, 10, 2);
    pointer(item, 'pointermove', 200, 10, 2);
    pointer(item, 'pointerup', 200, 10, 2);
    expect(item.style.transform).toBe('');
    expect(run).not.toHaveBeenCalled();
  });

  it('springs back when the pointer is called off', () => {
    const { on, run, line } = open();
    const item = line(1);
    pointer(item, 'pointerdown', 250, 10);
    pointer(item, 'pointermove', 100, 10);
    pointer(item, 'pointercancel', 100, 10);
    expect(item.style.transform).toBe('');
    expect(tile(on)).toBeNull();
    expect(run).not.toHaveBeenCalled();
  });

  it('is only on an item not linked yet, in a note a plugin offers an action on', () => {
    const plain = open();
    for (const n of [2, 3]) {
      const other = plain.line(n);
      pointer(other, 'pointerdown', 250, 10);
      pointer(other, 'pointermove', 100, 10);
      expect(other.style.transform).toBe('');
      pointer(other, 'pointerup', 100, 10);
    }
    view?.destroy();
    const unoffered = open(false);
    const item = unoffered.line(1);
    pointer(item, 'pointerdown', 250, 10);
    pointer(item, 'pointermove', 100, 10);
    expect(item.style.transform).toBe('');
    expect(tile(unoffered.on)).toBeNull();
  });
});
