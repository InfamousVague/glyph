import { beforeEach, describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { history, undo } from '@codemirror/commands';
import { markDetailsChanged, provideMarkDetails, type MarkDetails, type MarkEntry } from '../core/markDetails.ts';
import { doneSync } from './doneSync.ts';

const answers = new Map<string, MarkEntry | null>();
provideMarkDetails('notion', () => ({
  peek: (url) => answers.get(url) ?? null,
  want: () => undefined,
  open: () => Promise.resolve(),
  reads: (url) => url.startsWith('https://www.notion.so/'),
}));

const A = 'https://www.notion.so/a-1234';
const B = 'https://www.notion.so/b-5678';

function ready(url: string, stage: MarkDetails['status'] extends infer S ? (S extends { stage: infer G } ? G : never) : never, extra: Partial<MarkDetails> = {}): MarkEntry {
  return {
    state: 'ready',
    loading: false,
    details: { url, title: 'A task', status: { label: stage === 'done' ? 'Done' : 'To do', stage }, brief: [], fields: [], editedAt: 1000, readAt: 2000, ...extra },
  };
}

function open(doc: string): EditorView {
  const state = EditorState.create({ doc, extensions: [history(), doneSync()] });
  return new EditorView({ state, parent: document.createElement('div') });
}

const settled = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

describe('ticking a to-do whose task is done', () => {
  beforeEach(() => answers.clear());

  it('ticks the box of an item whose task reads as done, and leaves the rest', async () => {
    answers.set(A, ready(A, 'done'));
    answers.set(B, ready(B, 'doing'));
    const view = open(`- [ ] milk [notion](${A})\n- [ ] eggs [notion](${B})\n- [ ] bread\n  - [ ] jam [notion](${A})\nplain [notion](${A})\n`);
    await settled();
    expect(view.state.doc.toString()).toBe(`- [x] milk [notion](${A})\n- [ ] eggs [notion](${B})\n- [ ] bread\n  - [x] jam [notion](${A})\nplain [notion](${A})\n`);
    view.destroy();
  });

  it('ticks when the answer arrives later, and not for a task in the trash', async () => {
    const view = open(`- [ ] milk [notion](${A})\n- [ ] eggs [notion](${B})\n`);
    await settled();
    expect(view.state.doc.toString()).toContain('- [ ] milk');
    answers.set(A, ready(A, 'done'));
    answers.set(B, ready(B, 'done', { gone: true }));
    markDetailsChanged();
    await settled();
    expect(view.state.doc.toString()).toBe(`- [x] milk [notion](${A})\n- [ ] eggs [notion](${B})\n`);
    view.destroy();
  });

  it('is not undone with typing, and does not fight a box unticked by hand', async () => {
    answers.set(A, ready(A, 'done'));
    const view = open(`- [ ] milk [notion](${A})\n`);
    await settled();
    expect(view.state.doc.toString()).toBe(`- [x] milk [notion](${A})\n`);
    view.dispatch({ changes: { from: view.state.doc.length, insert: 'more' }, userEvent: 'input.type' });
    undo(view);
    expect(view.state.doc.toString()).toBe(`- [x] milk [notion](${A})\n`);
    // Unticked on purpose: the same answer from Notion does not tick it again.
    view.dispatch({ changes: { from: 3, to: 4, insert: ' ' }, userEvent: 'input.type' });
    markDetailsChanged();
    await settled();
    expect(view.state.doc.toString()).toBe(`- [ ] milk [notion](${A})\n`);
    // The task changed in Notion since: it does.
    answers.set(A, ready(A, 'done', { editedAt: 3000 }));
    markDetailsChanged();
    await settled();
    expect(view.state.doc.toString()).toBe(`- [x] milk [notion](${A})\n`);
    view.destroy();
  });

  it('ticks an item linked the old way, its words the link', async () => {
    answers.set(A, ready(A, 'done'));
    const view = open(`- [ ] [milk](${A})\n- [ ] read the [docs](https://example.com/d)\n`);
    await settled();
    expect(view.state.doc.toString()).toBe(`- [x] [milk](${A})\n- [ ] read the [docs](https://example.com/d)\n`);
    view.destroy();
  });

  it('ticks a linked item pasted into the note', async () => {
    answers.set(A, ready(A, 'done'));
    const view = open('plain\n');
    await settled();
    view.dispatch({ changes: { from: view.state.doc.length, insert: `- [ ] milk [notion](${A})\n` } });
    await settled();
    expect(view.state.doc.toString()).toBe(`plain\n- [x] milk [notion](${A})\n`);
    view.destroy();
  });
});
