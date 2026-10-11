import { afterEach, describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { addAiChanges, aiChanges, aiChangesField, aiEdit, groupChanges, keepChanges, landingField, revertChanges, setLanding, type AiChange } from './aiChanges.ts';

let view: EditorView | null = null;

function open(doc: string, onMarks?: (changes: readonly AiChange[]) => void): EditorView {
  const host = document.createElement('div');
  document.body.appendChild(host);
  view = new EditorView({ state: EditorState.create({ doc, extensions: [aiChanges({ onMarks })] }), parent: host });
  return view;
}

afterEach(() => {
  view?.destroy();
  view?.dom.parentElement?.remove();
  view = null;
});

const change = (patch: Partial<AiChange>): AiChange => ({ id: 'c1', runId: 'r1', from: 0, to: 0, removed: '', block: true, ...patch });

describe('the AI’s changes, tracked', () => {
  it('marks added words, draws the words that went, and tells the note when the marks change', () => {
    const told: number[] = [];
    const v = open('# Trip\nCall the plumber.\n', (changes) => told.push(changes.length));
    v.dispatch({ effects: addAiChanges.of([change({ from: 7, to: 24, removed: 'call plumber' })]) });
    expect(told).toEqual([1]);
    expect(v.dom.querySelector('.cm-aiAdded')?.textContent).toBe('Call the plumber.');
    expect(v.dom.querySelector('.cm-aiGoneBlock')?.textContent).toBe('call plumber');
    expect([...v.dom.querySelectorAll('.cm-aiPill')].map((b) => b.textContent)).toEqual(['Keep', 'Revert']);
  });

  it('keeps a change: the marks go and the words stay', () => {
    const v = open('a\nb\n');
    v.dispatch({ effects: addAiChanges.of([change({ from: 2, to: 3 })]) });
    keepChanges(v, ['c1']);
    expect(v.state.field(aiChangesField)).toEqual([]);
    expect(v.state.doc.toString()).toBe('a\nb\n');
  });

  it('reverts a line the AI added, a line it took away, and a line it rewrote', () => {
    const v = open('a\nNEW\nc\n');
    v.dispatch({ effects: addAiChanges.of([change({ from: 2, to: 5 })]) });
    revertChanges(v, ['c1']);
    expect(v.state.doc.toString()).toBe('a\nc\n');
    expect(v.state.field(aiChangesField)).toEqual([]);

    v.dispatch({ effects: addAiChanges.of([change({ id: 'c2', from: 2, to: 2, removed: 'b' })]) });
    revertChanges(v, ['c2']);
    expect(v.state.doc.toString()).toBe('a\nb\nc\n');

    v.dispatch({ effects: addAiChanges.of([change({ id: 'c3', from: 2, to: 3, removed: 'bee' })]) });
    revertChanges(v, ['c3']);
    expect(v.state.doc.toString()).toBe('a\nbee\nc\n');
  });

  it('reverts words within a line, with and without words to put back', () => {
    const v = open('Call the plumber on Thursday.\n');
    v.dispatch({
      effects: addAiChanges.of([change({ id: 'w1', from: 0, to: 4, removed: 'call', block: false }), change({ id: 'w2', from: 16, to: 28, removed: ' thursday', block: false })]),
    });
    expect(v.dom.querySelector('.cm-aiGone')?.textContent).toBe('call');
    revertChanges(v, ['w1', 'w2']);
    expect(v.state.doc.toString()).toBe('call the plumber thursday.\n');
  });

  it('maps its marks through typing elsewhere, and keeps a change whose line the person types on', () => {
    const v = open('a\nb\nc\n');
    v.dispatch({ effects: addAiChanges.of([change({ from: 4, to: 5 })]) });
    v.dispatch({ changes: { from: 0, insert: 'xx' }, userEvent: 'input.type' });
    expect(v.state.field(aiChangesField)[0]).toMatchObject({ from: 6, to: 7 });
    v.dispatch({ changes: { from: 7, insert: '!' }, userEvent: 'input.type' });
    expect(v.state.field(aiChangesField)).toEqual([]);
    expect(v.state.doc.toString()).toBe('xxa\nb\nc!\n');
  });

  it('leaves the marks alone for the AI’s own edits', () => {
    const v = open('a\nb\n');
    v.dispatch({ effects: addAiChanges.of([change({ from: 2, to: 3 })]) });
    v.dispatch({ changes: { from: 3, insert: '\nc' }, annotations: aiEdit.of('land') });
    expect(v.state.field(aiChangesField).length).toBe(1);
  });

  it('shares one pair of pills across changes on neighbouring lines from one run', () => {
    const v = open('a\nb\nc\n\n\ne\n');
    const changes = [change({ id: '1', from: 0, to: 1 }), change({ id: '2', from: 2, to: 3 }), change({ id: '3', from: 7, to: 8 }), change({ id: '4', runId: 'r2', from: 4, to: 5 })];
    v.dispatch({ effects: addAiChanges.of(changes) });
    const groups = groupChanges(v.state.doc, v.state.field(aiChangesField));
    expect(groups.map((g) => g.ids)).toEqual([['1', '2', '4'].slice(0, 2), ['4'], ['3']]);
    expect(v.dom.querySelectorAll('.cm-aiPills').length).toBe(3);
  });

  it('keeps the landing bookmark, moving it with the person’s typing and remembering what they touched', () => {
    const v = open('a\nb\nc\n');
    v.dispatch({ effects: setLanding.of({ runId: null, start: 2, cursor: 2, oldEnd: 6 }) });
    v.dispatch({ changes: { from: 0, insert: 'X' }, userEvent: 'input.type' });
    expect(v.state.field(landingField)).toMatchObject({ start: 3, cursor: 3, oldEnd: 7, touched: [{ from: 0, to: 1 }] });
    v.dispatch({ changes: { from: 5, insert: 'yy' }, annotations: aiEdit.of('land') });
    expect(v.state.field(landingField)?.touched).toEqual([{ from: 0, to: 1 }]);
    v.dispatch({ effects: setLanding.of(null) });
    expect(v.state.field(landingField)).toBeNull();
  });
});
