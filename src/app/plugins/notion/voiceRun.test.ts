import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { CaptureContext } from '../types.ts';

type CaptureStatus = Parameters<CaptureContext['status']>[0];

/**
 * The Notion voice commands carried out, after the recorder has heard them (voice.ts `run`): which words become the
 * task, what is linked where, and what the chip on the recorder says when it cannot. What the commands hear is
 * voice.test.ts, and the recorder's own suite runs them end to end (capture/voiceSuite.test.ts). The client is
 * stubbed, with a board and tasks each test sets.
 */

const board = { id: 'b', title: 'Jobs', url: 'https://notion.so/b', titleProperty: 'Name', doneProperty: null };
const other = { id: 'c', title: 'Home', url: 'https://notion.so/c', titleProperty: 'Name', doneProperty: null };
let ready = true;
let linked: typeof board | null = board;
let tasks: Record<string, { id: string; title: string; url: string }[]> = {};
let refusal: Error | null = null;
const made: string[] = [];

vi.mock('./client.ts', () => ({
  createTask: vi.fn(async (_board: unknown, title: string) => {
    if (refusal) throw refusal;
    made.push(title);
    return { id: `id-${made.length}`, title, url: `https://notion.so/task-${made.length}` };
  }),
  boardFor: () => linked,
  boardLinks: () => ({ n1: board, n2: other }),
  findTasks: async (on: { id: string }) => tasks[on.id] ?? [],
  notionReadyNow: () => ready,
}));
vi.mock('../../core/haptics.ts', () => ({ fireNativeHaptic: () => undefined }));

const { sendCommand, taskNoteCommand } = await import('./voice.ts');

/** A take's context that keeps what the command did to it, and resolves once the chip says it is over. */
function take(lastSaid: ReturnType<CaptureContext['lastSaid']> = null) {
  const did = { said: [] as string[], links: [] as [string, string][], appended: [] as string[], statuses: [] as CaptureStatus[] };
  let over: () => void = () => undefined;
  const finished = new Promise<void>((resolve) => {
    over = resolve;
  });
  const ctx: CaptureContext = {
    noteId: () => 'take',
    lastSaid: () => lastSaid,
    said: (text) => did.said.push(text),
    status: (status) => {
      did.statuses.push(status);
      if (status.state !== 'working') over();
    },
    link: (words, url) => did.links.push([words, url]),
    append: (text) => did.appended.push(text),
    updateNote: async () => undefined,
  };
  return { ctx, did, finished, last: () => did.statuses.at(-1) };
}

beforeEach(() => {
  ready = true;
  linked = board;
  tasks = {};
  refusal = null;
  made.length = 0;
});

describe('“send that to Notion”', () => {
  it('makes the words before it a task, without a spoken marker or the full stop, and links them in the take', async () => {
    const { ctx, did, finished, last } = take();
    const parsed = sendCommand.parse('Bullet point: book the cabin. Send that to Notion')!;
    expect(sendCommand.run(parsed, ctx)).toBe(parsed.rest);
    await finished;
    expect(did.said).toEqual([parsed.rest]);
    expect(made).toEqual(['book the cabin']);
    expect(did.links).toEqual([['book the cabin', 'https://notion.so/task-1']]);
    expect(last()).toMatchObject({ state: 'done', lead: 'In Notion on', title: 'Jobs' });
  });

  it('on its own, sends the last thing said', async () => {
    const { ctx, finished } = take({ kind: 'take', text: 'Call Sam about the van.' });
    expect(sendCommand.describe(sendCommand.parse('send that to Notion')!, ctx).title).toBe('Send “Call Sam about the van” to Notion');
    expect(sendCommand.run(sendCommand.parse('send that to Notion')!, ctx)).toBeNull();
    await finished;
    expect(made).toEqual(['Call Sam about the van']);
  });

  it('says what went wrong on the chip, and makes nothing', async () => {
    const cases: [() => void, string][] = [
      [() => undefined, 'Say what to send first, then “send that to Notion”.'],
      [() => (ready = false), 'Notion needs the newest Ghost.md.'],
      [() => (linked = null), 'Link this note to a Notion board first, from its cog.'],
    ];
    for (const [arrange, words] of cases) {
      ready = true;
      linked = board;
      arrange();
      const { ctx, finished, last } = take(words.startsWith('Say') ? null : { kind: 'take', text: 'Oat milk' });
      sendCommand.run({ rest: '' }, ctx);
      await finished;
      expect(last()).toEqual({ state: 'failed', title: words });
    }
    expect(made).toEqual([]);
  });

  it('says Notion’s refusal on the chip', async () => {
    refusal = new Error('Notion can’t see that board. Share it with Ghost.md in Notion.');
    const { ctx, finished, last } = take();
    sendCommand.run({ rest: 'oat milk' }, ctx);
    await finished;
    expect(last()).toEqual({ state: 'failed', title: 'Notion can’t see that board. Share it with Ghost.md in Notion.' });
  });
});

describe('“add a note for the Notion task for …”', () => {
  it('links the closest task across the linked boards, this note’s own first', async () => {
    tasks = { b: [{ id: 't1', title: 'Fix the login page', url: 'https://notion.so/t1' }], c: [{ id: 't2', title: 'Fix login', url: 'https://notion.so/t2' }] };
    const { ctx, did, finished, last } = take();
    expect(taskNoteCommand.run(taskNoteCommand.parse('Add a note for the Notion task for fix login')!, ctx)).toBeNull();
    await finished;
    expect(did.appended).toEqual(['Notion task: [Fix login](https://notion.so/t2).']);
    expect(last()).toMatchObject({ state: 'done', lead: 'Linked', title: 'Fix login' });
  });

  it('says there is no such task rather than linking one that is only a little like it', async () => {
    tasks = { b: [{ id: 't1', title: 'Paint the fence', url: 'https://notion.so/t1' }] };
    const { ctx, did, finished, last } = take();
    taskNoteCommand.run({ name: 'fix login' }, ctx);
    await finished;
    expect(did.appended).toEqual([]);
    expect(last()).toEqual({ state: 'failed', title: 'No Notion task called “fix login”.' });
  });
});
