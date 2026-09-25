import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import type { ToastOptions } from '@glacier/react';
import { runsOf } from '../ai/log.ts';
import { createNote, getNote, listNotes, noteTitle, updateNote, type Note } from '../core/store.ts';
import { confirmCommand, type CommandOffer, type CommandPlan } from './noteCommand.ts';

/**
 * A command typed into the AI bar, confirmed on its card: into the open note through its editor, into another note by
 * the guarded write with an Undo, or a new list made with an Undo - and each written in the AI's log with the words it
 * was read from. The store is the real browser one (core/store.ts).
 */

let view: EditorView;
const toast = vi.fn<(options: ToastOptions) => void>();

function editorFor(note: Note): EditorView {
  view = new EditorView({ state: EditorState.create({ doc: note.body }), parent: document.body });
  return view;
}

/** A command to put `text` into `note` as a list item, as the bar reads "add … to …". */
function place(note: Note, text: string): CommandOffer {
  const plan: CommandPlan = { kind: 'place', note: { id: note.id, title: noteTitle(note.body), note }, text, how: 'item', task: true, many: false, target: null };
  return { plan, offer: { kind: 'new', span: { startMs: 0, endMs: 0 } }, words: `add ${text} to ${noteTitle(note.body)}` };
}

/** What the last toast said, and its Undo when it offered one. */
const said = () => toast.mock.calls.at(-1)?.[0];

beforeEach(() => {
  localStorage.clear();
  toast.mockClear();
});

afterEach(() => view?.destroy());

describe('a command from the bar, confirmed', () => {
  it('goes into the open note through its editor, and the log says the AI did, with the words asked', async () => {
    const open = await createNote('n1', '# Groceries\n- [ ] milk');
    editorFor(open);
    await confirmCommand(place(open, 'eggs'), { note: open, view, wisp: false, toast });
    expect(view.state.doc.toString()).toBe('# Groceries\n- [ ] milk\n- [ ] Eggs');
    expect(said()?.message).toBe('Added “Eggs”.');
    // Not written to the store under the open note: the editor saves it like typing.
    expect((await getNote('n1'))?.body).toBe('# Groceries\n- [ ] milk');
    const [record] = runsOf('n1');
    expect(record?.instruction).toBe('add eggs to Groceries');
    expect(record?.before).toBe('# Groceries\n- [ ] milk');
    expect(record?.after).toBe('# Groceries\n- [ ] milk\n- [ ] Eggs');
  });

  it('writes another note, and its Undo puts that note back', async () => {
    const open = await createNote('n1', '# Today');
    const other = await createNote('n2', '# Shopping\n- [ ] bread');
    editorFor(open);
    await confirmCommand(place(other, 'eggs'), { note: open, view, wisp: false, toast });
    expect((await getNote('n2'))?.body).toBe('# Shopping\n- [ ] bread\n- [ ] Eggs');
    expect(said()?.message).toBe('Added “Eggs” to Shopping.');
    expect(view.state.doc.toString()).toBe('# Today');
    said()?.action?.onPress();
    await vi.waitFor(async () => expect((await getNote('n2'))?.body).toBe('# Shopping\n- [ ] bread'), { timeout: 10_000 });
  });

  it('writes nothing to a note that changed after its card was drawn, and says so', async () => {
    const open = await createNote('n1', '# Today');
    const other = await createNote('n2', '# Shopping\n- [ ] bread');
    // Written elsewhere while the card was up.
    await updateNote('n2', '# Shopping\n- [ ] bread\n- [ ] jam', 1);
    editorFor(open);
    await confirmCommand(place(other, 'eggs'), { note: open, view, wisp: false, toast });
    expect(said()?.message).toBe('Shopping changed after the preview, so nothing was added.');
    expect((await getNote('n2'))?.body).toBe('# Shopping\n- [ ] bread\n- [ ] jam');
  });

  it('makes a new list, and its Undo takes the list away', async () => {
    const open = await createNote('n1', '# Today');
    editorFor(open);
    const plan: CommandPlan = { kind: 'create-list', title: 'Packing', items: ['socks', 'tent'] };
    await confirmCommand({ plan, offer: { kind: 'new', title: 'Packing', lines: ['socks', 'tent'], span: { startMs: 0, endMs: 0 } }, words: 'make a packing list' }, { note: open, view, wisp: false, toast });
    const made = (await listNotes()).find((note) => noteTitle(note.body) === 'Packing');
    expect(made?.body).toBe('Packing\n\n- Socks\n- Tent\n');
    expect(said()?.message).toBe('Made Packing.');
    said()?.action?.onPress();
    await vi.waitFor(async () => expect((await listNotes()).some((note) => noteTitle(note.body) === 'Packing')).toBe(false), { timeout: 10_000 });
  });
});
