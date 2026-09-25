import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { buttonSaying, press, show, waitUntil } from '../../../test/render.tsx';
import type { Board, NotionAccount } from './client.ts';

/**
 * Notion's two faces in the app: its page in Settings (signing in and out, the boards shared) and its picker on a
 * note's cog (a board to send the note's list to). The sign-in and the calls are client.test.ts; here the client is
 * stood in for by an account and boards each test sets.
 */

let native = true;
vi.mock('../../core/tauri.ts', () => ({ isTauri: () => native, invoke: () => Promise.reject(new Error('no binary in a test')) }));

let available = true;
let account: NotionAccount | null = { connected: false };
let problem: string | null = null;
let boards: Board[] | Error = [];
const startNotionSignIn = vi.fn(async () => undefined);
const disconnectNotion = vi.fn(async () => undefined);
const refresh = vi.fn(async () => undefined);
vi.mock('./client.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./client.ts')>()),
  notionAvailable: async () => available,
  useNotionAccount: () => ({ account, problem, refresh }),
  listBoards: async () => {
    if (boards instanceof Error) throw boards;
    return boards;
  },
  startNotionSignIn: () => startNotionSignIn(),
  disconnectNotion: () => disconnectNotion(),
}));

const { NotionPane } = await import('./NotionPane.tsx');
const { BoardPicker } = await import('./BoardPicker.tsx');
const { boardFor } = await import('./client.ts');

const road: Board = { id: 'b1', url: 'https://notion.so/b1', title: 'Roadmap', titleProperty: 'Task', doneProperty: null };
const home: Board = { id: 'b2', url: 'https://notion.so/b2', title: 'Home', titleProperty: 'Name', doneProperty: null };

beforeEach(() => {
  native = true;
  available = true;
  account = { connected: false };
  problem = null;
  boards = [road, home];
  startNotionSignIn.mockClear();
  disconnectNotion.mockClear();
  localStorage.clear();
});

describe('Settings > Notion', () => {
  it('in a browser, says Notion works in the app; on an old binary, that it needs the newest', async () => {
    native = false;
    available = false;
    let host = show(<NotionPane />);
    await waitUntil(() => expect(host.textContent).toContain('Notion works in the app.'));
    native = true;
    host = show(<NotionPane />);
    await waitUntil(() => expect(host.textContent).toContain('Notion needs the newest Ghost.md.'));
  });

  it('signed out, opens the sign-in and then says to finish it on Notion', async () => {
    const host = show(<NotionPane />);
    expect(host.textContent).toContain('Not signed in');
    await act(async () => buttonSaying(host, 'Sign in')!.click());
    expect(startNotionSignIn).toHaveBeenCalledOnce();
    expect(host.textContent).toContain('Finish signing in on Notion');
    expect(buttonSaying(host, 'Open again')).toBeTruthy();
  });

  it('says why the sign-in would not start', async () => {
    startNotionSignIn.mockRejectedValueOnce(new Error('Notion needs the newest Ghost.md. Install it from Settings > Updates.'));
    const host = show(<NotionPane />);
    await act(async () => buttonSaying(host, 'Sign in')!.click());
    expect(host.querySelector('.setk-callout')?.textContent).toBe('Notion needs the newest Ghost.md. Install it from Settings > Updates.');
  });

  it('signed in, names the workspace, lists the boards shared, and signs out', async () => {
    account = { connected: true, workspaceName: 'Studio' };
    const host = show(<NotionPane />);
    expect(host.textContent).toContain('Signed in to Studio');
    await waitUntil(() => expect(host.textContent).toContain('Tasks are named by “Task”.'));
    expect(host.textContent).toContain('Home');
    await act(async () => buttonSaying(host, 'Sign out')!.click());
    expect(disconnectNotion).toHaveBeenCalledOnce();
  });

  it('says when no boards were shared, and why they could not be read', async () => {
    account = { connected: true };
    boards = [];
    let host = show(<NotionPane />);
    await waitUntil(() => expect(host.textContent).toContain('No boards shared yet'));
    boards = new Error('Notion signed Ghost.md out. Sign in again in Settings > Notion.');
    host = show(<NotionPane />);
    await waitUntil(() => expect(host.textContent).toContain('Notion signed Ghost.md out.'));
  });
});

describe('the board picker on a note', () => {
  it('offers the sign-in while signed out', () => {
    const host = show(<BoardPicker noteId="n1" onDone={() => undefined} />);
    press(buttonSaying(host, 'Sign in with Notion'));
    expect(startNotionSignIn).toHaveBeenCalledOnce();
  });

  it('says it is checking before the account has answered', () => {
    account = null;
    expect(show(<BoardPicker noteId="n1" onDone={() => undefined} />).textContent).toBe('Checking Notion…');
  });

  it('links the board chosen, ticks it, and takes the note off Notion again', async () => {
    account = { connected: true, workspaceName: 'Studio' };
    const onDone = vi.fn();
    const host = show(<BoardPicker noteId="n1" onDone={onDone} />);
    expect(host.textContent).toContain('Boards in Studio that Ghost.md can see.');
    await waitUntil(() => expect(buttonSaying(host, 'Roadmap')).toBeTruthy());
    press(buttonSaying(host, 'Roadmap'));
    expect(boardFor('n1')?.id).toBe('b1');
    expect(onDone).toHaveBeenCalledOnce();
    expect(buttonSaying(host, 'Roadmap')?.getAttribute('aria-pressed')).toBe('true');
    press(buttonSaying(host, 'Don’t send this note to Notion'));
    expect(boardFor('n1')).toBeNull();
  });
});
