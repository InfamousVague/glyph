import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { isoDay, isoDayAfter } from '../core/days.ts';
import { HOLD_MS } from '../core/gestures.ts';
import type { QueryNote } from '../core/query/records.ts';
import { glyphMarkdown } from './language.ts';
import { queries, refreshQueries, type QueryOptions } from './queries.ts';

/**
 * A ```query fence drawn in its note (editor/queries.ts, editor/QueryView.tsx; docs/DESIGN.md §159): what it finds,
 * drawn in place of its lines and live as the note and the library change; its lines and the sentence where it cannot
 * be read; the lines again with the caret in them; and what a tap on a row and on a box does, here and in another note.
 */

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

vi.mock('../core/haptics.ts', () => ({ fireNativeHaptic: vi.fn() }));

const today = isoDay(new Date());
const day = (offset: number) => isoDayAfter(today, offset)!;

const SHOP: QueryNote = { id: 'shop', body: `# Groceries\n\n- [ ] Milk 📅 ${day(-1)} @sam\n- [x] Eggs\n- [ ] Bread ⏫ 📅 ${day(0)}\n`, createdAt: 0, updatedAt: 0 };
const TICKET: QueryNote = { id: 'gho1', body: '---\ntype: ticket\nid: GHO-1\nstatus: In progress\npriority: high\nestimate: 3\n---\n# Fix the login loop\n', createdAt: 0, updatedAt: 0 };

let library: QueryNote[];
let options: QueryOptions;
beforeEach(() => {
  library = [SHOP, TICKET];
  options = { notes: () => library, noteId: 'here', open: vi.fn(), tick: vi.fn(), move: vi.fn() };
});

const views: EditorView[] = [];
afterEach(() => {
  for (const view of views.splice(0)) act(() => view.destroy());
});

async function open(doc: string, given: QueryOptions | null = options, editable = true) {
  let view!: EditorView;
  await act(async () => {
    view = new EditorView({
      state: EditorState.create({ doc, extensions: [glyphMarkdown([], []), queries(() => given), EditorView.editable.of(editable)] }),
      parent: document.body,
    });
  });
  views.push(view);
  return view;
}

const drawn = (view: EditorView) => [...view.dom.querySelectorAll<HTMLElement>('.cm-query')];
/** A row of the open picker sheet, by its label: its words without its mark or its tick. */
const sheetRow = (label: string) => {
  const sheet = document.querySelector<HTMLElement>('[role="dialog"]');
  const said = (button: HTMLButtonElement) => [...button.children].find((child) => !child.hasAttribute('aria-hidden'))?.firstChild?.textContent?.trim();
  return [...(sheet?.querySelectorAll<HTMLButtonElement>('button') ?? [])].find((button) => said(button) === label)!;
};
const fence = (lines: string) => `# This week\n\n\`\`\`query\n${lines}\n\`\`\`\n`;

describe('a query in a note', () => {
  it('is drawn as what it finds, in place of its lines', async () => {
    const view = await open(fence('from: tasks'));
    const [query] = drawn(view);
    expect(query).toBeDefined();
    expect(query!.textContent).toContain('To-dos');
    expect(query!.textContent).toContain('Milk');
    expect(query!.textContent).toContain('Bread');
    // Open ones only, unless it asks.
    expect(query!.textContent).not.toContain('Eggs');
    expect(view.contentDOM.textContent).not.toContain('from: tasks');
  });

  it('draws a ticket table with its columns and its total', async () => {
    const view = await open(fence('from: tickets\ntotal: estimate'));
    const table = drawn(view)[0]!.querySelector('table')!;
    expect([...table.querySelectorAll('thead th')].map((th) => th.textContent)).toEqual(['ID', 'Title', 'Status', 'Assignee', 'Priority', 'Due']);
    expect(table.querySelector('tbody')!.textContent).toContain('GHO-1');
    expect(table.querySelector('tbody')!.textContent).toContain('In progress');
    expect(drawn(view)[0]!.textContent).toContain('Estimate 3');
  });

  it('draws a ticket board as the whole workflow', async () => {
    const view = await open(fence('from: tickets\nshow: board'));
    const lanes = [...drawn(view)[0]!.querySelectorAll('[role="listitem"]')].map((lane) => lane.getAttribute('aria-label'));
    expect(lanes).toEqual(['Backlog, 0', 'To do, 0', 'In progress, 1', 'In review, 0', 'Done, 0']);
  });

  it('draws a count, and a month', async () => {
    const view = await open(`${fence('from: tasks\nshow: count')}\n${fence('from: tasks\nshow: calendar')}`);
    const [count, month] = drawn(view);
    expect(count!.textContent).toContain('2to-dos');
    expect(month!.querySelectorAll('[role="gridcell"]').length).toBeGreaterThanOrEqual(28);
  });

  it('reads this note as it is typed', async () => {
    const view = await open(`${fence('from: tasks')}\n- [ ] Call the plumber\n`);
    expect(drawn(view)[0]!.textContent).toContain('Call the plumber');
    await act(async () => view.dispatch({ changes: { from: view.state.doc.length, insert: '- [ ] Post the letter\n' } }));
    expect(drawn(view)[0]!.textContent).toContain('Post the letter');
  });

  it('is drawn again when the library changes', async () => {
    const view = await open(fence('from: tasks'));
    library = [...library, { id: 'more', body: '- [ ] Water the plants', createdAt: 0, updatedAt: 0 }];
    await act(async () => view.dispatch({ effects: refreshQueries.of(null) }));
    expect(drawn(view)[0]!.textContent).toContain('Water the plants');
  });

  it('cannot be read: its lines, and the sentence that says what is wrong and where', async () => {
    const view = await open(fence('from: tickets\nwhere: status ='));
    const query = drawn(view)[0]!;
    expect(query.querySelector('pre')!.textContent).toBe('from: tickets\nwhere: status =');
    expect(query.textContent).toContain('Line 2, column 16: After “status =”, something to compare it with');
  });

  it('stays as its lines where there is no library to read', async () => {
    const view = await open(fence('from: tasks'), null);
    expect(drawn(view)).toEqual([]);
    expect(view.contentDOM.textContent).toContain('from: tasks');
  });

  it('steps aside for its lines with the caret in them, and the pencil puts it there', async () => {
    const view = await open(fence('from: tasks'));
    await act(async () => drawn(view)[0]!.querySelector<HTMLButtonElement>('button[aria-label="Edit the query"]')!.click());
    expect(drawn(view)).toEqual([]);
    expect(view.state.doc.lineAt(view.state.selection.main.head).text).toBe('from: tasks');
  });

  it('has no pencil and no box to tick where the note cannot be edited', async () => {
    const view = await open(fence('from: tasks'), options, false);
    const query = drawn(view)[0]!;
    expect(query.querySelector('button[aria-label="Edit the query"]')).toBeNull();
    expect(query.querySelector<HTMLButtonElement>('[role="checkbox"]')!.disabled).toBe(true);
  });
});

describe('a tap in a drawn query', () => {
  it('opens another note, and a to-do’s note at its line', async () => {
    const view = await open(fence('from: tasks'));
    await act(async () => [...drawn(view)[0]!.querySelectorAll<HTMLButtonElement>('button')].find((b) => b.textContent?.includes('Bread'))!.click());
    expect(options.open).toHaveBeenCalledWith('shop', 4);
    const tickets = await open(fence('from: tickets'));
    await act(async () => [...drawn(tickets)[0]!.querySelectorAll<HTMLButtonElement>('button')].find((b) => b.textContent?.includes('Fix the login loop'))!.click());
    expect(options.open).toHaveBeenCalledWith('gho1', null);
  });

  it('ticks a to-do in another note through the screen', async () => {
    const view = await open(fence('from: tasks'));
    await act(async () => drawn(view)[0]!.querySelector<HTMLButtonElement>('[aria-label="Tick Milk"]')!.click());
    expect(options.tick).toHaveBeenCalledWith('shop', 2, `- [ ] Milk 📅 ${day(-1)} @sam`, true);
  });

  it('moves a ticket to the lane its card is dragged to, through the screen', async () => {
    const view = await open(fence('from: tickets\nshow: board'));
    const query = drawn(view)[0]!;
    const card = [...query.querySelectorAll<HTMLElement>('li[data-movable]')].find((li) => li.textContent?.includes('Fix the login loop'))!;
    const target = [...query.querySelectorAll<HTMLElement>('[role="listitem"]')].find((lane) => lane.getAttribute('aria-label') === 'In review, 0')!;
    // The pointer lands on the "In review" lane, whichever pixel it is over.
    const realFrom = document.elementFromPoint;
    document.elementFromPoint = () => target;
    try {
      const ptr = (type: string, x: number) => {
        const event = new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: 0, button: 0 });
        Object.defineProperty(event, 'pointerType', { value: 'mouse' });
        Object.defineProperty(event, 'pointerId', { value: 1 });
        return event;
      };
      await act(async () => card.dispatchEvent(ptr('pointerdown', 0)));
      // Pressed and held, as a ```board's card is (core/holdDrag.ts): only a wait as long as the hold, never a race.
      await act(async () => new Promise((done) => setTimeout(done, HOLD_MS + 30)));
      expect(document.querySelector('.app-dragGhost')?.textContent).toContain('Fix the login loop');
      await act(async () => window.dispatchEvent(ptr('pointermove', 40)));
      // Held over another lane, the card leaves its own for the gap in that one.
      expect(target.querySelector('[data-drag-gap]')).not.toBeNull();
      await act(async () => window.dispatchEvent(ptr('pointerup', 40)));
    } finally {
      document.elementFromPoint = realFrom;
    }
    expect(options.move).toHaveBeenCalledWith('gho1', expect.any(Number), expect.any(String), 'ticket', 'status', 'In review');
    expect(document.querySelector('.app-dragGhost')).toBeNull();
  });

  it.each(['list', 'table'])('moves a ticket to the group its row is dragged to in a grouped %s, by the same drag', async (show) => {
    // A second ticket, so there is another group to carry it to.
    library = [...library, { id: 'gho2', body: '---\ntype: ticket\nid: GHO-2\nstatus: Done\n---\n# Ship the fix\n', createdAt: 0, updatedAt: 0 }];
    const view = await open(fence(`from: tickets\ngroup: status\nshow: ${show}`));
    const query = drawn(view)[0]!;
    const row = [...query.querySelectorAll<HTMLElement>('[data-movable]')].find((li) => li.textContent?.includes('Fix the login loop'))!;
    expect(row).toBeDefined();
    const target = [...query.querySelectorAll<HTMLElement>('[data-lane-key]')].find((group) => group.dataset.laneKey !== row.closest<HTMLElement>('[data-lane-key]')!.dataset.laneKey)!;
    const realFrom = document.elementFromPoint;
    document.elementFromPoint = () => target;
    try {
      const ptr = (type: string, y: number) => {
        const event = new MouseEvent(type, { bubbles: true, cancelable: true, clientX: 0, clientY: y, button: 0 });
        Object.defineProperty(event, 'pointerType', { value: 'mouse' });
        Object.defineProperty(event, 'pointerId', { value: 1 });
        return event;
      };
      await act(async () => row.dispatchEvent(ptr('pointerdown', 0)));
      await act(async () => new Promise((done) => setTimeout(done, HOLD_MS + 30)));
      await act(async () => window.dispatchEvent(ptr('pointermove', 60)));
      expect(target.querySelector('[data-drag-gap]')).not.toBeNull();
      await act(async () => window.dispatchEvent(ptr('pointerup', 60)));
    } finally {
      document.elementFromPoint = realFrom;
    }
    expect(options.move).toHaveBeenCalledWith('gho1', expect.any(Number), expect.any(String), 'ticket', 'status', 'Done');
  });

  it('ticks a to-do in this note in the note itself, and puts the caret on one it opens', async () => {
    const view = await open(`${fence('from: tasks')}\n- [ ] Call the plumber\n`);
    await act(async () => drawn(view)[0]!.querySelector<HTMLButtonElement>('[aria-label="Tick Call the plumber"]')!.click());
    expect(view.state.doc.toString()).toContain('- [x] Call the plumber');
    expect(options.tick).not.toHaveBeenCalled();
    // Ticked, it has left the list of open to-dos; Milk opens in its own note.
    expect(drawn(view)[0]!.textContent).not.toContain('Call the plumber');
    const other = await open(`${fence('from: tasks')}\n- [ ] Post the letter\n`);
    await act(async () => [...drawn(other)[0]!.querySelectorAll<HTMLButtonElement>('button')].find((b) => b.textContent?.includes('Post the letter'))!.click());
    expect(other.state.doc.lineAt(other.state.selection.main.head).text).toBe('- [ ] Post the letter');
  });

  it('picks a ticket’s status from its cell, and writes it in its own note through the screen', async () => {
    const view = await open(fence('from: tickets'));
    await act(async () => drawn(view)[0]!.querySelector<HTMLButtonElement>('button[aria-label^="Status: In progress"]')!.click());
    expect(document.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('Status');
    await act(async () => sheetRow('Done').click());
    expect(options.move).toHaveBeenCalledWith('gho1', -1, '', 'ticket', 'status', 'Done');
    expect(document.querySelector('[role="dialog"]')).toBeNull();
  });

  it('picks a to-do’s priority and person in this note, on its own line', async () => {
    const view = await open(`${fence('from: tasks\nshow: table')}\n- [ ] Call the plumber\n`);
    const rowOf = () => [...drawn(view)[0]!.querySelectorAll('tr')].find((tr) => tr.textContent?.includes('Call the plumber'))!;
    await act(async () => rowOf().querySelector<HTMLButtonElement>('button[aria-label^="Priority: none"]')!.click());
    await act(async () => sheetRow('High').click());
    expect(view.state.doc.toString()).toContain('- [ ] Call the plumber ⏫');
    await act(async () => rowOf().querySelector<HTMLButtonElement>('button[aria-label^="Assignee: none"]')!.click());
    // The people the library names are offered: Milk's @sam.
    await act(async () => sheetRow('sam').click());
    expect(view.state.doc.toString()).toContain('- [ ] Call the plumber @sam ⏫');
    expect(options.move).not.toHaveBeenCalled();
  });

  it('picks a card’s priority on a board, without carrying the card', async () => {
    const view = await open(fence('from: tickets\nshow: board'));
    const card = [...drawn(view)[0]!.querySelectorAll<HTMLElement>('li[data-movable]')].find((li) => li.textContent?.includes('Fix the login loop'))!;
    const priority = card.querySelector<HTMLButtonElement>('button[aria-label^="Priority: high"]')!;
    await act(async () => priority.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, button: 0 })));
    expect(card.hasAttribute('data-carrying')).toBe(false);
    await act(async () => priority.click());
    await act(async () => sheetRow('Highest').click());
    expect(options.move).toHaveBeenCalledWith('gho1', -1, '', 'ticket', 'priority', 'highest');
  });

  it('picks nothing where the note cannot be edited', async () => {
    const view = await open(fence('from: tickets'), options, false);
    expect(drawn(view)[0]!.querySelector('[aria-haspopup="dialog"]')).toBeNull();
    // The status is still drawn, in its colour, as words.
    expect(drawn(view)[0]!.textContent).toContain('In progress');
  });
});
