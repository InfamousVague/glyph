import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import type { NameOffer } from '../core/noteNames.ts';

/**
 * A new note's blank page (editor/nameChips.ts): the names under line 1 only while the page is being written in, which
 * is the editor's focus and a page ready for words, the press that never moves the caret, and the screen's element
 * under the names. The keyboard is core/keyboard.ts stood in for.
 */

const keyboard = vi.hoisted(() => ({ up: false, listeners: new Set<(up: boolean) => void>() }));
vi.mock('../core/keyboard.ts', () => ({
  keyboardUp: () => keyboard.up,
  watchKeyboard: (listener: (up: boolean) => void) => {
    keyboard.listeners.add(listener);
    return () => keyboard.listeners.delete(listener);
  },
}));

const { nameChips, offersShown, setOffers } = await import('./nameChips.ts');

const NAMES: NameOffer[] = [
  { kind: 'words', name: 'Monday, 28 September 2026', label: 'Name it for today, in words.' },
  { kind: 'day', name: '2026-09-28', label: 'Name it for today, 2026-09-28.' },
];

let named: string[];
let shown: boolean[];

/** An editor with the blank page, told what to offer; focused unless the test says not. */
async function mount(doc = '', { readyAtOnce = false, focus = true, host = null as HTMLElement | null } = {}): Promise<EditorView> {
  named = [];
  shown = [];
  const view = new EditorView({
    state: EditorState.create({ doc, extensions: [nameChips({ readyAtOnce, onName: (name) => named.push(name), onShown: (now) => shown.push(now) })] }),
    parent: document.body.appendChild(document.createElement('div')),
  });
  view.dispatch({ effects: setOffers.of({ names: NAMES, host }) });
  if (focus) {
    view.focus();
    // CodeMirror tells its extensions of a focus 10ms after the event.
    await vi.advanceTimersByTimeAsync(10);
  }
  return view;
}

const chips = (view: EditorView) => [...view.contentDOM.querySelectorAll<HTMLButtonElement>('.cm-nameChip')];

beforeEach(() => {
  vi.useFakeTimers();
  vi.spyOn(document, 'hasFocus').mockReturnValue(true);
  keyboard.up = false;
  keyboard.listeners.clear();
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  document.body.innerHTML = '';
});

describe('the names under line 1', () => {
  it('wait for the page to be ready: nothing on a focused phone page until the keyboard is up', async () => {
    const view = await mount();
    expect(chips(view)).toHaveLength(0);
    keyboard.up = true;
    for (const listener of keyboard.listeners) listener(true);
    expect(chips(view).map((chip) => chip.textContent)).toEqual(['Monday, 28 September 2026', '2026-09-28']);
    expect(shown).toEqual([true]);
    const group = view.contentDOM.querySelector('[role="group"]');
    expect(group?.getAttribute('aria-label')).toBe('Names for this note');
    expect(chips(view)[1]!.getAttribute('aria-label')).toBe('Name it for today, 2026-09-28.');
  });

  it('are ready at the end of the person’s own tap on the words, not at its start, or at a key', async () => {
    const view = await mount();
    view.contentDOM.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    expect(offersShown(view.state)).toBe(false);
    view.contentDOM.dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
    expect(offersShown(view.state)).toBe(true);
    const other = await mount();
    other.contentDOM.dispatchEvent(new KeyboardEvent('keydown', { key: 'Shift', bubbles: true }));
    expect(offersShown(other.state)).toBe(true);
  });

  it('are there at once where no keyboard is on the screen, and only with the focus', async () => {
    const view = await mount('', { readyAtOnce: true, focus: false });
    expect(offersShown(view.state)).toBe(false);
    view.focus();
    await vi.advanceTimersByTimeAsync(10);
    expect(offersShown(view.state)).toBe(true);
    view.contentDOM.blur();
    await vi.advanceTimersByTimeAsync(10);
    expect(offersShown(view.state)).toBe(false);
  });

  it('sit after line 1, and go once line 1 has a letter, whatever the screen still offers', async () => {
    const view = await mount('', { readyAtOnce: true });
    const block = view.contentDOM.querySelector('.cm-blankOffers')!;
    expect(block.previousElementSibling?.classList.contains('cm-line')).toBe(true);
    view.dispatch({ changes: { from: 0, insert: 'T' } });
    expect(offersShown(view.state)).toBe(false);
    view.dispatch({ changes: { from: 0, to: 1 } });
    expect(offersShown(view.state)).toBe(true);
    view.dispatch({ effects: setOffers.of({ names: null, host: null }) });
    expect(offersShown(view.state)).toBe(false);
    expect(shown).toEqual([true, false, true, false]);
  });

  it('name the note on a click, and a press never moves the caret or takes the focus', async () => {
    const view = await mount('', { readyAtOnce: true });
    const chip = chips(view)[1]!;
    const down = new PointerEvent('pointerdown', { bubbles: true, cancelable: true });
    chip.dispatchEvent(down);
    expect(down.defaultPrevented).toBe(true);
    const mouse = new MouseEvent('mousedown', { bubbles: true, cancelable: true });
    chip.dispatchEvent(mouse);
    expect(mouse.defaultPrevented).toBe(true);
    // A touch is only kept from the editor: one with its default taken never becomes a click on Android.
    const touch = new Event('touchstart', { bubbles: true, cancelable: true });
    chip.dispatchEvent(touch);
    expect(touch.defaultPrevented).toBe(false);
    chip.click();
    expect(named).toEqual(['2026-09-28']);
    expect(view.hasFocus).toBe(true);
  });

  it('carry the screen’s own element under them, and that alone once every name is taken', async () => {
    const host = document.createElement('div');
    host.textContent = 'cards';
    const view = await mount('', { readyAtOnce: true, host });
    const block = view.contentDOM.querySelector('.cm-blankOffers')!;
    expect(block.lastElementChild).toBe(host);
    view.dispatch({ effects: setOffers.of({ names: [], host }) });
    expect(chips(view)).toHaveLength(0);
    expect(view.contentDOM.querySelector('.cm-blankOffers')?.contains(host)).toBe(true);
  });

  it('keep the block while the focus is on a chip, reached by Tab', async () => {
    const view = await mount('', { readyAtOnce: true });
    chips(view)[0]!.focus();
    await vi.advanceTimersByTimeAsync(20);
    expect(offersShown(view.state)).toBe(true);
    expect(document.activeElement).toBe(chips(view)[0]);
  });
});
