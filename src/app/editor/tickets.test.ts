import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState, type Extension } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import type { TicketChoice } from '../book/tickets.ts';
import { DEFAULT_STATUSES } from '../core/properties.ts';
import { extendedMarkdown, frontMatterFolded } from './extended.ts';
import { glyphMarkdown } from './language.ts';
import { refreshTickets, tickets, writeProperty, type TicketOptions } from './tickets.ts';

/**
 * A ticket drawn in its note (editor/tickets.ts; docs/DESIGN.md §157): its front matter as a panel in place of the
 * folded keys, stepping aside for the lines when the caret is in them; a property written as the smallest change; and a
 * `[[GHO-12]]` drawn with its ticket's title.
 */

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const COOKIE: TicketChoice = { key: 'GHO-9', title: 'Fix the session cookie', status: 'In review', category: 'doing' };
const SHIPPED: TicketChoice = { key: 'GHO-3', title: 'Ship the beta', status: 'Done', category: 'done' };

function optionsWith(found: readonly TicketChoice[] = [COOKIE, SHIPPED]): TicketOptions {
  return {
    statuses: () => DEFAULT_STATUSES,
    people: () => ['Sam', 'Priya'],
    choices: () => found,
    find: (target) => found.find((choice) => choice.key === target.toUpperCase()) ?? null,
    open: vi.fn(),
  };
}

const TICKET = '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\nblocked-by: "[[GHO-9]]"\nauthors: Matt\n---\n# Fix the login loop\n\nSee [[GHO-9]], [[GHO-3]] and [[GHO-404]].';

const views: EditorView[] = [];
afterEach(() => {
  for (const view of views.splice(0)) act(() => view.destroy());
});

async function open(doc: string, options: TicketOptions | null = optionsWith(), more: Extension = []) {
  let view!: EditorView;
  await act(async () => {
    view = new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown([], []), extendedMarkdown(), tickets(() => options), more] }), parent: document.body });
  });
  views.push(view);
  return view;
}

const panel = (view: EditorView) => view.dom.querySelector<HTMLElement>('.cm-ticketPanel');

describe('a ticket’s panel', () => {
  it('draws the front matter as the ticket’s properties, in place of the folded keys', async () => {
    const view = await open(TICKET);
    expect(panel(view)).not.toBeNull();
    expect(view.dom.querySelector('.cm-frontFold')).toBeNull();
    expect(frontMatterFolded(view.state)).toBe(false);
    const words = panel(view)!.textContent ?? '';
    expect(words).toContain('GHO-12');
    expect(words).toContain('In progress');
    expect(words).toContain('Sam');
    // What it waits on first, with a lock; the keys a ticket does not have on the quiet line.
    expect(words).toContain('Waiting onGHO-9Fix the session cookie');
    expect(words).toContain('authors');
    // The words under it as they are.
    expect(view.contentDOM.textContent).toContain('Fix the login loop');
  });

  it('leaves a note that is not a ticket folded as it was, and a ticket too where no tickets were given', async () => {
    const plain = await open('---\ntitle: "A note"\nauthors: Matt\n---\n# A note');
    expect(panel(plain)).toBeNull();
    expect(frontMatterFolded(plain.state)).toBe(true);
    const bare = await open(TICKET, null);
    expect(panel(bare)).toBeNull();
    expect(frontMatterFolded(bare.state)).toBe(true);
  });

  it('steps aside for the lines when the caret is in them, and comes back when it leaves', async () => {
    const view = await open(TICKET);
    await act(async () => {
      view.focus();
      view.dispatch({ selection: { anchor: 4 } });
      await Promise.resolve();
    });
    expect(panel(view)).toBeNull();
    expect(view.contentDOM.querySelectorAll('.cm-front')).toHaveLength(8);
    await act(async () => view.dispatch({ selection: { anchor: view.state.doc.length } }));
    expect(panel(view)).not.toBeNull();
  });

  it('opens the lines from its button, the caret on the first key', async () => {
    const view = await open(TICKET);
    const button = panel(view)!.querySelector<HTMLButtonElement>('[aria-label="Show the properties as text"]')!;
    await act(async () => {
      button.click();
      // The editor tells its blocks of the focus a moment after it takes it.
      await new Promise((done) => setTimeout(done, 30));
    });
    expect(view.state.doc.lineAt(view.state.selection.main.head).text).toBe('type: ticket');
    expect(panel(view)).toBeNull();
  });

  it('is read, with nothing to pick, where the note cannot be edited', async () => {
    const view = await open(TICKET, optionsWith(), [EditorState.readOnly.of(true), EditorView.editable.of(false)]);
    expect(panel(view)).not.toBeNull();
    expect(panel(view)!.querySelector('[aria-haspopup="dialog"]')).toBeNull();
    expect(panel(view)!.querySelector('input')).toBeNull();
  });
});

describe('a property written', () => {
  it('is one change, the smallest, with the caret where it was and the key in the case the note wrote it', async () => {
    const view = await open('---\ntype: ticket\nStatus: To do\n---\n# Login\n\nWords.');
    view.dispatch({ selection: { anchor: view.state.doc.length } });
    const changes: string[] = [];
    view.dispatch = ((spec: Parameters<EditorView['dispatch']>[0]) => {
      changes.push(JSON.stringify((spec as { changes: unknown }).changes));
      EditorView.prototype.dispatch.call(view, spec);
    }) as EditorView['dispatch'];
    act(() => writeProperty(view, 'status', 'Done'));
    expect(view.state.doc.toString()).toBe('---\ntype: ticket\nStatus: Done\n---\n# Login\n\nWords.');
    expect(changes).toEqual([JSON.stringify({ from: 25, to: 30, insert: 'Done' })]);
    expect(view.state.selection.main.head).toBe(view.state.doc.length);
    act(() => writeProperty(view, 'priority', 'high'));
    expect(view.state.doc.toString()).toBe('---\ntype: ticket\nStatus: Done\npriority: high\n---\n# Login\n\nWords.');
    act(() => writeProperty(view, 'priority', null));
    expect(view.state.doc.toString()).toBe('---\ntype: ticket\nStatus: Done\n---\n# Login\n\nWords.');
  });
});

describe('a key as a link', () => {
  it('is drawn with its ticket’s title and its status’s colour, struck once done, and a key no ticket has is left alone', async () => {
    const view = await open(TICKET);
    const titles = [...view.contentDOM.querySelectorAll<HTMLElement>('.cm-ticketTitle')];
    expect(titles.map((title) => [title.textContent, title.dataset.category])).toEqual([
      ['Fix the session cookie', 'doing'],
      ['Ship the beta', 'done'],
    ]);
  });

  it('is drawn again when the library’s tickets change', async () => {
    let cookie = COOKIE;
    const options = { ...optionsWith(), find: (target: string) => (target === 'GHO-9' ? cookie : null) };
    const view = await open('See [[GHO-9]].', options);
    expect(view.contentDOM.querySelector<HTMLElement>('.cm-ticketTitle')?.dataset.category).toBe('doing');
    cookie = { ...COOKIE, status: 'Done', category: 'done' };
    await act(async () => view.dispatch({ effects: refreshTickets.of(null) }));
    expect(view.contentDOM.querySelector<HTMLElement>('.cm-ticketTitle')?.dataset.category).toBe('done');
  });
});
