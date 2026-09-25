import { afterEach, describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { aiChanges, aiChangesField, landingField, setLanding } from '../editor/aiChanges.ts';
import { Lander } from './land.ts';

let view: EditorView | null = null;

function open(doc: string, landing: { start: number; cursor: number; oldEnd: number }): EditorView {
  const host = document.createElement('div');
  document.body.appendChild(host);
  view = new EditorView({ state: EditorState.create({ doc, extensions: [aiChanges()] }), parent: host });
  view.dispatch({ effects: setLanding.of(landing) });
  return view;
}

afterEach(() => {
  view?.destroy();
  view?.dom.parentElement?.remove();
  view = null;
});

const quiet = { wisp: false, haptic: false };
const make = (v: EditorView, id: string) => new Lander(v, id, quiet, v.state.doc.toString());
const marks = (v: EditorView) => v.state.field(aiChangesField).map((c) => ({ from: c.from, to: c.to, removed: c.removed, block: c.block }));

describe('the lander', () => {
  it('lands a rewrite of the whole note line by line: kept lines stay, dropped lines are struck, new ones are marked', () => {
    const doc = 'trip\n\ncall the plumber thursday\neggs and coffee\nold thing\n';
    const v = open(doc, { start: 0, cursor: 0, oldEnd: doc.length });
    const lander = make(v, 'r1');
    lander.land(['# Trip']);
    expect(v.state.doc.toString()).toBe('# Trip\n\ncall the plumber thursday\neggs and coffee\nold thing\n');
    // The title made a heading: the one line rewritten, its old word kept beside the new ones.
    expect(marks(v)).toEqual([{ from: 0, to: 6, removed: 'trip', block: false }]);
    lander.land(['# Trip', '']);
    expect(v.state.doc.toString()).toBe('# Trip\n\ncall the plumber thursday\neggs and coffee\nold thing\n');
    lander.land(['# Trip', '', '- [ ] Call the plumber, before Thursday.']);
    expect(v.state.doc.toString()).toBe('# Trip\n\n- [ ] Call the plumber, before Thursday.\neggs and coffee\nold thing\n');
    // The rewritten line: only the words that differ carry marks, the old ones kept beside them.
    const inline = marks(v).filter((m) => !m.block && m.from >= 8);
    expect(inline.length).toBeGreaterThan(0);
    expect(inline.map((m) => m.removed.trim()).filter(Boolean)).toEqual(['call', 'thursday']);
    lander.land(['# Trip', '', '- [ ] Call the plumber, before Thursday.', '- [ ] Eggs and coffee.']);
    expect(v.state.doc.toString()).toBe('# Trip\n\n- [ ] Call the plumber, before Thursday.\n- [ ] Eggs and coffee.\nold thing\n');
    lander.finish(['# Trip', '', '- [ ] Call the plumber, before Thursday.', '- [ ] Eggs and coffee.']);
    expect(v.state.doc.toString()).toBe('# Trip\n\n- [ ] Call the plumber, before Thursday.\n- [ ] Eggs and coffee.\n');
    expect(marks(v).find((m) => m.removed === 'old thing')).toMatchObject({ block: true, from: v.state.doc.length, to: v.state.doc.length });
    expect(v.state.field(landingField)).toBeNull();
  });

  it('lands lines the model added before old ones, and strikes what it passed over', () => {
    const doc = 'a\nb\nc\n';
    const v = open(doc, { start: 0, cursor: 0, oldEnd: doc.length });
    const lander = make(v, 'r2');
    lander.land(['# Title', 'b']);
    expect(v.state.doc.toString()).toBe('# Title\nb\nc\n');
    expect(marks(v)).toEqual([
      { from: 0, to: 7, removed: '', block: true },
      { from: 8, to: 8, removed: 'a', block: true },
    ]);
    lander.finish(['# Title', 'b']);
    expect(v.state.doc.toString()).toBe('# Title\nb\n');
    expect(marks(v).map((m) => m.removed)).toEqual(['', 'a', 'c']);
  });

  it('adds under the note, and above it, on lines of their own', () => {
    const v = open('a\nb', { start: 3, cursor: 3, oldEnd: 3 });
    const lander = make(v, 'r3');
    lander.land(['c', 'd']);
    expect(v.state.doc.toString()).toBe('a\nb\nc\nd\n');
    lander.finish(['c', 'd']);
    expect(v.state.doc.toString()).toBe('a\nb\nc\nd\n');
    expect(marks(v)).toEqual([
      { from: 4, to: 5, removed: '', block: true },
      { from: 6, to: 7, removed: '', block: true },
    ]);

    const above = open('# Note\nwords\n', { start: 0, cursor: 0, oldEnd: 0 });
    const top = make(above, 'r4');
    top.land(['# Summary', 'Two things.', '']);
    top.finish(['# Summary', 'Two things.', '']);
    expect(above.state.doc.toString()).toBe('# Summary\nTwo things.\n\n# Note\nwords\n');
  });

  it('never strikes or rewrites what the person typed while it ran, and counts the model’s line it dropped', () => {
    const doc = 'a\nb\nc\n';
    const v = open(doc, { start: 0, cursor: 0, oldEnd: doc.length });
    const lander = make(v, 'r5');
    lander.land(['a']);
    // The person writes over line b while the model works.
    v.dispatch({ changes: { from: 2, to: 3, insert: 'b, mine now' }, userEvent: 'input.type' });
    lander.land(['a', 'b, the model’s', 'c']);
    expect(v.state.doc.toString()).toBe('a\nb, mine now\nc\n');
    expect(lander.dropped).toBe(1);
    lander.finish(['a', 'b, the model’s', 'c']);
    expect(v.state.doc.toString()).toBe('a\nb, mine now\nc\n');
  });

  it('reads the finished text over the landed lines, so a late tidy-up lands as a small change', () => {
    const doc = 'x\n';
    const v = open(doc, { start: 0, cursor: 0, oldEnd: doc.length });
    const lander = make(v, 'r6');
    lander.land(['* one', '* two']);
    expect(v.state.doc.toString()).toBe('* one\n* two\nx\n');
    lander.finish(['- one', '- two']);
    expect(v.state.doc.toString()).toBe('- one\n- two\n');
    expect(marks(v).filter((m) => !m.block).map((m) => m.removed.trim())).toEqual(['*', '*']);
  });

  it('leaves what landed when the run is abandoned', () => {
    const doc = 'a\nb\n';
    const v = open(doc, { start: 0, cursor: 0, oldEnd: doc.length });
    const lander = make(v, 'r7');
    lander.land(['A']);
    lander.abandon();
    expect(v.state.doc.toString()).toBe('A\nb\n');
    expect(v.state.field(landingField)).toBeNull();
  });
});
