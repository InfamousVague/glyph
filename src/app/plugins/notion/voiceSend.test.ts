import { describe, expect, it, vi } from 'vitest';
import type { CaptureContext } from '../types.ts';

/**
 * "New task for AttackFM in Notion, …": the recorder puts the items in the note's list, and the plugin sends the
 * lines it added (plugins/notion/voice.ts `notionItems`). What each task is called is what the item says, read the way
 * any item sent to Notion is (core/itemLinks.ts `itemWords`). The client is stubbed: these are the plugin's rules.
 */

const made: string[] = [];

vi.mock('./client.ts', () => ({
  createTask: vi.fn(async (_board: unknown, title: string) => {
    made.push(title);
    return { id: `id-${made.length}`, title, url: `https://notion.so/task-${made.length}` };
  }),
  boardFor: () => ({ id: 'b', title: 'Jobs', url: 'https://notion.so/b', titleProperty: 'Name', doneProperty: null }),
  boardLinks: () => ({}),
  findTasks: async () => [],
  notionReadyNow: () => true,
}));

vi.mock('../../core/haptics.ts', () => ({ fireNativeHaptic: () => undefined }));

const { notionItems } = await import('./voice.ts');

/** A take's context whose chip says when the sending is over, so nothing here waits on a clock. */
function context(body: string) {
  let note = body;
  let over: () => void = () => undefined;
  const finished = new Promise<void>((resolve) => {
    over = resolve;
  });
  const ctx: CaptureContext = {
    noteId: () => 'take',
    lastSaid: () => null,
    said: () => undefined,
    status: (status) => {
      if (status.state !== 'working') over();
    },
    link: () => undefined,
    append: () => undefined,
    updateNote: async (_id, change) => {
      note = change(note);
    },
  };
  return { ctx, finished, body: () => note };
}

describe('items said for a note, sent on to Notion', () => {
  it('names each task by what its item says: no box after any marker, no counter, no anchor', async () => {
    made.length = 0;
    const lines = ['1. [ ] Call the plumber', '* [ ] Pack socks [3/8]', '- [ ] Ship it ^ship-it'];
    const { ctx, finished, body } = context(`# Jobs\n\n${lines.join('\n')}\n`);
    notionItems.afterAdd('note-1', lines, ctx);
    await finished;
    // The numbered and starred lines used to be sent as "[ ] Call the plumber", box and all.
    expect(made).toEqual(['Call the plumber', 'Pack socks', 'Ship it']);
    expect(body()).toContain('1. [ ] Call the plumber [notion](https://notion.so/task-1)');
    expect(body()).toContain('- [ ] Ship it [notion](https://notion.so/task-3) ^ship-it');
  });

  it('sends a paragraph left in the note as it is', async () => {
    made.length = 0;
    const { ctx, finished } = context('# Jobs\n\nThe login is broken on Android.\n');
    notionItems.afterAdd('note-1', ['The login is broken on Android.'], ctx);
    await finished;
    expect(made).toEqual(['The login is broken on Android.']);
  });
});
