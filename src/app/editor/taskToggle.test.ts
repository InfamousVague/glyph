import { EditorState } from '@codemirror/state';
import { describe, expect, it } from 'vitest';
import { boxAt, toggleBox } from './taskToggle.ts';

describe('tapping a to-do box', () => {
  it('finds the box on a to-do line, bulleted, numbered or indented, and nothing on other lines', () => {
    const state = EditorState.create({ doc: '- [ ] milk\n  * [x] eggs\n3. [X] bread\n- plain\n[ ] not a list' });
    const line = (n: number) => state.doc.line(n).from;
    expect(boxAt(state, line(1))).toEqual({ from: 2, to: 5, done: false });
    expect(boxAt(state, line(2) + 4)).toMatchObject({ from: line(2) + 4, done: true });
    expect(boxAt(state, line(3))).toMatchObject({ from: line(3) + 3, done: true });
    expect(boxAt(state, line(4))).toBeNull();
    expect(boxAt(state, line(5))).toBeNull();
  });

  it('ticks an empty box and clears a ticked one, touching nothing else, as one edit', () => {
    let state = EditorState.create({ doc: '- [ ] milk [notion](https://notion.so/x) ^milk' });
    const tr = toggleBox(state, boxAt(state, 0)!);
    expect(tr.isUserEvent('input')).toBe(true);
    state = tr.state;
    expect(state.doc.toString()).toBe('- [x] milk [notion](https://notion.so/x) ^milk');
    state = toggleBox(state, boxAt(state, 0)!).state;
    expect(state.doc.toString()).toBe('- [ ] milk [notion](https://notion.so/x) ^milk');
    const upper = EditorState.create({ doc: '- [X] done' });
    expect(toggleBox(upper, boxAt(upper, 0)!).state.doc.toString()).toBe('- [ ] done');
  });
});
