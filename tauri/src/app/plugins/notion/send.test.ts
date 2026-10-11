import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { NoteEditing } from '../types.ts';

/**
 * Sending a list item to Notion: what happens when the same words are sent twice, and when the line they were on has
 * moved by the time Notion answers (Matt: "i click it once and it says sending then nothing happens then i click it
 * again and it fully processes creating the ticket").
 *
 * The client is stubbed: these are the plugin's own rules, not Notion's.
 */

const made: string[] = [];
const boardOf = (id: string, title: string) => ({ id, title, url: `https://notion.so/${id}`, titleProperty: 'Name', doneProperty: null });
/** The board the note is linked to; a test that moves the note to another sets it. */
let board = boardOf('b', 'Jobs');

vi.mock('./client.ts', () => ({
  createTask: vi.fn(async (_board: unknown, title: string) => {
    made.push(title);
    return { id: `id-${made.length}`, title, url: `https://notion.so/task-${made.length}` };
  }),
  boardFor: () => board,
  boardLinks: () => ({ 'note-1': board }),
  notionAvailable: async () => true,
  notionReadyNow: () => true,
}));

vi.mock('../../core/haptics.ts', () => ({ fireNativeHaptic: () => undefined }));

const { notionPlugin, forgetSent } = await import('./index.tsx');

/** A note in memory, as the editor would give it: the plugin reads it and writes lines back. */
function noteOf(body: string) {
  const state = { lines: body.split('\n'), said: [] as string[] };
  const editing: NoteEditing = {
    noteId: 'note-1',
    body: () => state.lines.join('\n'),
    replaceLine(find, next) {
      for (let n = 1; n <= state.lines.length; n += 1) {
        const text = state.lines[n - 1] ?? '';
        if (find(text, n)) {
          state.lines[n - 1] = next(text);
          return true;
        }
      }
      return false;
    },
    say: (message) => state.said.push(message),
  };
  return { state, editing };
}

beforeEach(() => {
  made.length = 0;
  board = boardOf('b', 'Jobs');
  forgetSent();
});

describe('sending an item to Notion', () => {
  it('makes the task and marks the line with it', async () => {
    const { state, editing } = noteOf('# Jobs\n\n- [ ] Book the cabin\n- [ ] Call Sam');
    await sendItemsFor(editing, 'Book the cabin');
    expect(made).toEqual(['Book the cabin']);
    expect(state.lines[2]).toBe('- [ ] Book the cabin [notion](https://notion.so/task-1)');
    expect(state.said.join(' ')).toContain('Sent 1 task');
  });

  it('makes one task however often the same words are sent', async () => {
    const { state, editing } = noteOf('- [ ] Book the cabin');
    await sendItemsFor(editing, 'Book the cabin');
    // The line is marked, so a second press would not normally be possible; the words are sent again all the same.
    state.lines[0] = '- [ ] Book the cabin';
    await sendItemsFor(editing, 'Book the cabin');
    expect(made, 'the same words must not become two tasks').toEqual(['Book the cabin']);
    expect(state.lines[0]).toBe('- [ ] Book the cabin [notion](https://notion.so/task-1)');
  });

  it('makes a new task when the same words go to another board', async () => {
    const { state, editing } = noteOf('- [ ] Book the cabin');
    await sendItemsFor(editing, 'Book the cabin');
    // Undone, and the note linked to another board: the words are that board's to have, not a link to the first one's.
    state.lines[0] = '- [ ] Book the cabin';
    board = boardOf('c', 'Home');
    await sendItemsFor(editing, 'Book the cabin');
    expect(made).toEqual(['Book the cabin', 'Book the cabin']);
    expect(state.lines[0]).toBe('- [ ] Book the cabin [notion](https://notion.so/task-2)');
    expect(state.said.at(-1)).toBe('Sent 1 task to Home.');
  });

  it('marks the line it was on when the words have changed since', async () => {
    const { state, editing } = noteOf('- [ ] Book the cabin');
    const run = sendItemsFor(editing, 'Book the cabin');
    // The person keeps typing while Notion answers.
    state.lines[0] = '- [ ] Book the cabin for Friday';
    await run;
    expect(made).toEqual(['Book the cabin']);
    expect(state.lines[0]).toBe('- [ ] Book the cabin for Friday [notion](https://notion.so/task-1)');
    expect(state.said.join(' ')).not.toContain('isn’t marked');
  });

  it('gives each task its own item when a line above them goes while Notion answers', async () => {
    const { state, editing } = noteOf('- [ ] One\n- [ ] Two\n- [ ] Three');
    const run = notionPlugin.noteActions!.find((a) => a.id === 'notion-send-list')!.run(editing);
    // The first item is deleted while its task is made: the others move up a line each.
    state.lines.splice(0, 1);
    await run;
    expect(made).toEqual(['One', 'Two', 'Three']);
    expect(state.lines, 'no item may take the link of the one before it').toEqual(['- [ ] Two [notion](https://notion.so/task-2)', '- [ ] Three [notion](https://notion.so/task-3)']);
    expect(state.said.join(' ')).toContain('isn’t marked');
  });

  it('says so when the task was made and the line is gone, rather than nothing at all', async () => {
    const { state, editing } = noteOf('- [ ] Book the cabin');
    const run = sendItemsFor(editing, 'Book the cabin');
    state.lines[0] = 'the whole line is different words now';
    await run;
    expect(made).toEqual(['Book the cabin']);
    expect(state.said.join(' ')).toContain('isn’t marked');
  });
});

/** Sends `text` the way the pill does, through the plugin's own suggestion for that line. */
async function sendItemsFor(editing: NoteEditing, text: string): Promise<void> {
  const suggestion = (notionPlugin.suggest?.('note-1', editing.body()) ?? []).find((s) => editing.body().split('\n')[s.line - 1]?.includes(text));
  if (!suggestion) throw new Error(`nothing offered for ${text}`);
  await suggestion.run(editing);
}
