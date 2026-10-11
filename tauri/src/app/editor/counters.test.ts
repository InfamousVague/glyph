import { history, undo } from '@codemirror/commands';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { counters, countersIn, stepped } from './counters.ts';
import { parseWhole } from '../../test/syntaxTree.ts';
import { glyphMarkdown } from './language.ts';

describe('counters', () => {
  it('finds a count and a goal in brackets, and nothing that only looks like one', () => {
    expect(countersIn('- Water [3/8] and push-ups [0/50]').map((c) => [c.count, c.goal])).toEqual([
      [3, 8],
      [0, 50],
    ]);
    expect(countersIn('[1/2](https://x.dev) ![3/4](image/a.jpg) a[1/2] [0/0] [ 1/2 ]')).toEqual([]);
    expect(countersIn('x [2/5]', 10)[0]).toEqual({ from: 12, to: 17, count: 2, goal: 5 });
  });

  it('steps up to the goal and down to nothing, and no further', () => {
    const at = (count: number) => ({ from: 0, to: 0, count, goal: 3 });
    expect(stepped(at(1), 1)).toBe('[2/3]');
    expect(stepped(at(3), 1)).toBe('[3/3]');
    expect(stepped(at(1), -1)).toBe('[0/3]');
    expect(stepped(at(0), -1)).toBe('[0/3]');
  });
});

describe('a counter in a note', () => {
  let view: EditorView | null = null;

  afterEach(() => {
    view?.destroy();
    view = null;
    vi.useRealTimers();
  });

  function open(doc: string, readOnly = false): EditorView {
    vi.useFakeTimers();
    view = parseWhole(new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown(), counters(), history(), EditorState.readOnly.of(readOnly)] }), parent: document.body }));
    return view;
  }
  const chip = (on: EditorView) => on.contentDOM.querySelector<HTMLElement>('.cm-counter')!;
  const press = (target: HTMLElement, type: string) =>
    target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, isPrimary: true, button: 0, pointerId: 1, pointerType: 'touch' }));

  it('is drawn as a chip that fills as the count rises, full at its goal', () => {
    const on = open('- Water [3/8]\n- Stretch [2/2]');
    const chips = [...on.contentDOM.querySelectorAll<HTMLElement>('.cm-counter')];
    expect(chips.map((one) => one.textContent)).toEqual(['[3/8]', '[2/2]']);
    expect(chips[0]?.style.getPropertyValue('--fill')).toBe('38%');
    expect(chips.map((one) => one.classList.contains('cm-counterFull'))).toEqual([false, true]);
  });

  it('counts one up on a tap, as an edit of its own that one undo takes back', () => {
    const on = open('- Water [3/8]');
    press(chip(on), 'pointerdown');
    press(chip(on), 'pointerup');
    expect(on.state.doc.toString()).toBe('- Water [4/8]');
    undo(on);
    expect(on.state.doc.toString()).toBe('- Water [3/8]');
  });

  it('takes one away on a hold, and the lift after it adds nothing', () => {
    const on = open('- Water [3/8]');
    press(chip(on), 'pointerdown');
    vi.advanceTimersByTime(449);
    expect(on.state.doc.toString()).toBe('- Water [3/8]');
    vi.advanceTimersByTime(1);
    expect(on.state.doc.toString()).toBe('- Water [2/8]');
    press(chip(on), 'pointerup');
    expect(on.state.doc.toString()).toBe('- Water [2/8]');
  });

  it('stays full when tapped at its goal, and empty when held at nothing', () => {
    const on = open('- Stretch [2/2] and rest [0/3]');
    press(chip(on), 'pointerdown');
    press(chip(on), 'pointerup');
    const empty = on.contentDOM.querySelectorAll<HTMLElement>('.cm-counter')[1]!;
    press(empty, 'pointerdown');
    vi.advanceTimersByTime(500);
    press(empty, 'pointerup');
    expect(on.state.doc.toString()).toBe('- Stretch [2/2] and rest [0/3]');
  });

  it('is a control: the caret stays put, the phone’s long-press menu does not open, and a locked note is left alone', () => {
    const on = open('- Water [3/8]');
    const down = new MouseEvent('mousedown', { bubbles: true, cancelable: true });
    chip(on).dispatchEvent(down);
    expect(down.defaultPrevented).toBe(true);
    const menu = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
    chip(on).dispatchEvent(menu);
    expect(menu.defaultPrevented).toBe(true);
    view?.destroy();
    const locked = open('- Water [3/8]', true);
    press(chip(locked), 'pointerdown');
    press(chip(locked), 'pointerup');
    expect(locked.state.doc.toString()).toBe('- Water [3/8]');
  });

  it('is not a counter in code', () => {
    const on = open('Run `[3/8]` as written');
    expect(on.contentDOM.querySelector('.cm-counter')).toBeNull();
  });
});
