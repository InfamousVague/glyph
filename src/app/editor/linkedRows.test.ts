import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { provideMarkDetails, type MarkDetails, type MarkEntry } from '../core/markDetails.ts';
import type { MarkMenuProps } from './MarkMenu.tsx';
import { linkedOn, linkedRows, unlinked } from './linkedRows.ts';

/** The drawer is a React sheet of its own (editor/MarkMenu.tsx); here only what it was opened with, and its closing. */
const drawer = vi.hoisted(() => ({ opened: [] as MarkMenuProps[], closed: 0 }));
vi.mock('./markMenuMount.tsx', () => ({
  mountMarkMenu: (_host: HTMLElement, props: MarkMenuProps) => {
    drawer.opened.push(props);
    return () => {
      drawer.closed += 1;
    };
  },
}));

/** What the plugin knows about each task now. */
const known = new Map<string, MarkEntry>();

provideMarkDetails('notion', () => ({
  peek: (url) => known.get(url) ?? null,
  want: () => undefined,
  open: async () => undefined,
  reads: (url) => url.includes('notion.so/'),
}));

const TASK = 'https://www.notion.so/Buy-milk-3db522a4563081298304c129ce6004e4';

describe('what a line is linked to', () => {
  it('finds an item’s mark, with the item’s words', () => {
    expect(linkedOn(`- [ ] Buy milk [notion](${TASK})`, 40)).toEqual({ from: 40, name: 'notion', url: TASK, words: 'Buy milk', kind: 'mark', item: true });
  });

  it('finds a link written the old way, and one in a sentence', () => {
    expect(linkedOn(`- [ ] [Buy milk](${TASK}) on the way home`)).toMatchObject({ kind: 'link', item: true, words: 'Buy milk on the way home' });
    expect(linkedOn(`Remember [the task](${TASK}) tomorrow.`)).toMatchObject({ kind: 'link', item: false, words: 'the task' });
  });

  it('leaves lines with no link, or a link no plugin reads', () => {
    expect(linkedOn('- [ ] Buy milk')).toBeNull();
    expect(linkedOn('- [ ] Read [the docs](https://example.com/docs)')).toBeNull();
  });

  it('unlinks, keeping the words', () => {
    expect(unlinked(`- [ ] Buy milk [notion](${TASK})`, { kind: 'mark', url: TASK })).toBe('- [ ] Buy milk');
    // A board's anchor after the mark stays, so the card is still the item (core/boards.ts).
    expect(unlinked(`- [ ] Buy milk [notion](${TASK}) ^buy-milk`, { kind: 'mark', url: TASK })).toBe('- [ ] Buy milk ^buy-milk');
    // And a counter typed after it (editor/counters.ts).
    expect(unlinked(`- [ ] Buy milk [notion](${TASK}) [2/6] ^buy-milk`, { kind: 'mark', url: TASK })).toBe('- [ ] Buy milk [2/6] ^buy-milk');
    expect(unlinked(`- [ ] [Buy milk](${TASK}) on the way home`, { kind: 'link', url: TASK })).toBe('- [ ] Buy milk on the way home');
  });
});

describe('the row of pills under a linked line', () => {
  let view: EditorView | null = null;
  const said: string[] = [];

  function open(doc: string, menus = true): EditorView {
    view = new EditorView({ state: EditorState.create({ doc, extensions: [linkedRows(menus ? { say: (message) => said.push(message) } : null)] }), parent: document.body });
    return view;
  }
  const details = (more: Partial<MarkDetails>): MarkEntry => ({
    state: 'ready',
    loading: false,
    details: { url: TASK, title: 'Buy milk', status: null, brief: [], fields: [], editedAt: 1, readAt: 1, ...more },
  });
  const pills = (on: EditorView) => [...on.dom.querySelectorAll<HTMLElement>('.cm-linkRow .cm-linkPill')];
  const words = (on: EditorView) => pills(on).map((pill) => pill.textContent);
  const tap = (element: Element) => element.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));

  beforeEach(() => {
    known.clear();
    drawer.opened.length = 0;
    drawer.closed = 0;
    said.length = 0;
  });

  afterEach(() => {
    view?.destroy();
    view = null;
    document.querySelectorAll('.cm-linkMenu').forEach((host) => host.remove());
  });

  it('says what the task is doing: its service, then its stage and status, then each fact, an overdue one marked', () => {
    known.set(TASK, details({ status: { label: 'Doing', stage: 'doing' }, brief: ['P1', 'Overdue by 2 days'] }));
    const on = open(`- [ ] Buy milk [notion](${TASK})\n`);
    expect(words(on)).toEqual(['Notion', 'Doing', 'P1', 'Overdue by 2 days']);
    expect(on.dom.querySelector('.cm-linkPill-status')?.getAttribute('data-stage')).toBe('doing');
    expect(pills(on).map((pill) => pill.hasAttribute('data-late'))).toEqual([false, false, false, true]);
    expect(on.dom.querySelector('.cm-linkRow')?.getAttribute('title')).toBe('Buy milk');
  });

  it('names a stage in words where the board has none of its own, and says a task in the trash is there', () => {
    known.set(TASK, details({ status: { label: '', stage: 'todo' } }));
    const on = open(`- [ ] Buy milk [notion](${TASK})\n`);
    expect(words(on)).toEqual(['Notion', 'To do']);
    known.set(TASK, details({ gone: true, brief: ['P1'] }));
    view?.destroy();
    const gone = open(`- [ ] Buy milk [notion](${TASK})\n`);
    expect(words(gone)).toEqual(['Notion', 'In trash']);
  });

  it('says so while the task is read, and when it cannot be', () => {
    known.set(TASK, { state: 'loading' });
    const on = open(`- [ ] Buy milk [notion](${TASK})\n`);
    expect(words(on)).toEqual(['Notion', 'Reading…']);
    known.set(TASK, { state: 'failed', message: 'Notion said no' });
    view?.destroy();
    const failed = open(`- [ ] Buy milk [notion](${TASK})\n`);
    expect(words(failed)).toEqual(['Notion', 'Can’t read it']);
    expect(pills(failed)[1]?.title).toBe('Notion said no');
  });

  it('always draws a mark’s row, and an ordinary link’s only once it has been read', () => {
    const on = open(`Remember [the task](${TASK}) tomorrow.\n`);
    expect(on.dom.querySelector('.cm-linkRow')).toBeNull();
    known.set(TASK, details({ status: { label: 'Done', stage: 'done' } }));
    view?.destroy();
    expect(words(open(`Remember [the task](${TASK}) tomorrow.\n`))).toEqual(['Notion', 'Done']);
  });

  it('opens the drawer for its line on a tap on a pill, and closes it on another', () => {
    const on = open(`- [ ] Buy milk [notion](${TASK})\n`);
    const row = on.dom.querySelector('.cm-linkRow')!;
    expect(row.getAttribute('role')).toBe('button');
    tap(pills(on)[0]!);
    expect(drawer.opened).toHaveLength(1);
    expect(drawer.opened[0]).toMatchObject({ name: 'notion', url: TASK, words: 'Buy milk' });
    expect(on.dom.querySelector('.cm-linkRow')?.hasAttribute('data-open')).toBe(true);
    tap(pills(on)[0]!);
    expect(drawer.closed).toBe(1);
    expect(on.dom.querySelector('.cm-linkRow')?.hasAttribute('data-open')).toBe(false);
  });

  it('leaves a tap on the empty rest of the row to the note, and opens nothing where menus are off', () => {
    const on = open(`- [ ] Buy milk [notion](${TASK})\n`);
    tap(on.dom.querySelector('.cm-linkRow')!);
    expect(drawer.opened).toHaveLength(0);
    view?.destroy();
    const plain = open(`- [ ] Buy milk [notion](${TASK})\n`, false);
    expect(plain.dom.querySelector('.cm-linkRow')?.hasAttribute('role')).toBe(false);
    tap(pills(plain)[0]!);
    expect(drawer.opened).toHaveLength(0);
  });

  it('unlinks from the drawer, keeping the words, and closes it', () => {
    const on = open(`- [ ] Buy milk [notion](${TASK}) ^milk\nnext\n`);
    tap(pills(on)[0]!);
    drawer.opened[0]!.unlink();
    expect(on.state.doc.toString()).toBe('- [ ] Buy milk ^milk\nnext\n');
    expect(drawer.closed).toBe(1);
    expect(on.dom.querySelector('.cm-linkRow')).toBeNull();
  });

  it('closes the drawer when its line loses its link some other way', async () => {
    const on = open(`- [ ] Buy milk [notion](${TASK})\n`);
    tap(pills(on)[0]!);
    const line = on.state.doc.line(1);
    on.dispatch({ changes: { from: line.from, to: line.to, insert: '- [ ] Buy milk' } });
    expect(drawer.closed).toBe(1);
    // And the open menu is let go of, once that update is done, so the next link on the line starts closed.
    await Promise.resolve();
    on.dispatch({ changes: { from: on.state.doc.line(1).to, insert: ` [notion](${TASK})` } });
    expect(drawer.opened).toHaveLength(1);
  });
});
