import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Notion from the page (client.ts), through a phone that is stood in for: the binary's generation and its four
 * commands are `invoke` below, the browser that opens Notion's consent page is the opener, and glyph-api's `claim` is
 * `fetch`. What is pinned is the contract with the other two halves - the PKCE state and challenge server/src/notion.rs
 * checks, what a claim's answers mean, how long a sign-in in flight is kept - and Notion's refusals as the sentences
 * a person reads. Each test loads the module afresh, since the sign-in in flight and the binary's answer are kept in
 * it for the page's life.
 */

const API = 'https://attack.fm/glyph/api/notion';
const SIGN_IN_KEY = 'glyph-notion-signin';
const LINKS_KEY = 'glyph-notion-links';

/** The binary: its generation, and what each Notion command answers. Replaced per test where it matters. */
let generation = 12;
let request: (args: { request: { method: string; path: string; body: unknown } }) => { status: number; body: unknown } = () => ({ status: 200, body: {} });
const invoke = vi.fn(async (command: string, args?: Record<string, unknown>): Promise<unknown> => {
  if (command === 'ota_status') return { nativeGeneration: generation };
  if (command === 'notion_save_account') return { connected: true, workspaceName: (args?.account as { workspace_name?: string }).workspace_name ?? null };
  if (command === 'notion_account') return { connected: false };
  if (command === 'notion_disconnect') return null;
  if (command === 'notion_request') return request(args as never);
  throw new Error(`no command ${command}`);
});
vi.mock('../../core/tauri.ts', () => ({ isTauri: () => true, invoke: (command: string, args?: Record<string, unknown>) => invoke(command, args) }));
const openUrl = vi.fn(async (_url: string) => undefined);
vi.mock('@tauri-apps/plugin-opener', () => ({ openUrl: (url: string) => openUrl(url) }));

const fetcher = vi.fn<typeof fetch>();

async function client() {
  vi.resetModules();
  return import('./client.ts');
}

const answer = (status: number, body?: unknown) => new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

beforeEach(() => {
  generation = 12;
  request = () => ({ status: 200, body: {} });
  invoke.mockClear();
  openUrl.mockClear();
  fetcher.mockReset();
  vi.stubGlobal('fetch', fetcher);
  localStorage.clear();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

/** SHA-256 of `text`, base64url without padding: the challenge the server recomputes from the verifier. */
async function challengeOf(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
  return btoa(String.fromCharCode(...digest)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

describe('signing in with Notion', () => {
  it('keeps a fresh state and verifier, and opens the consent page with the verifier hashed', async () => {
    const { startNotionSignIn } = await client();
    await startNotionSignIn();
    const kept = JSON.parse(localStorage.getItem(SIGN_IN_KEY)!) as { state: string; verifier: string; at: number };
    expect(kept.state).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(kept.verifier).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(kept.verifier).not.toBe(kept.state);
    expect(openUrl).toHaveBeenCalledExactlyOnceWith(`${API}/start?state=${kept.state}&challenge=${await challengeOf(kept.verifier)}`);
  });

  it('refuses on a binary too old to hold the sign-in, before anything is kept or opened', async () => {
    generation = 11;
    const { startNotionSignIn } = await client();
    await expect(startNotionSignIn()).rejects.toThrow('Notion needs the newest Ghost.md. Install it from Settings > Updates.');
    expect(localStorage.getItem(SIGN_IN_KEY)).toBeNull();
    expect(openUrl).not.toHaveBeenCalled();
  });

  it('has nothing to collect when no sign-in was started', async () => {
    const { collectNotionSignIn } = await client();
    expect(await collectNotionSignIn()).toBeNull();
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('says pending while the person is still on Notion’s page, and asks again next time', async () => {
    const { startNotionSignIn, collectNotionSignIn } = await client();
    await startNotionSignIn();
    const { state, verifier } = JSON.parse(localStorage.getItem(SIGN_IN_KEY)!) as { state: string; verifier: string };
    fetcher.mockResolvedValue(answer(202));
    expect(await collectNotionSignIn()).toBe('pending');
    expect(await collectNotionSignIn()).toBe('pending');
    expect(fetcher).toHaveBeenCalledTimes(2);
    const [url, init] = fetcher.mock.calls[0]!;
    expect(url).toBe(`${API}/claim`);
    expect(init?.method).toBe('POST');
    expect(JSON.parse(String(init?.body))).toEqual({ state, verifier });
  });

  it('hands a finished sign-in to the binary to keep, and forgets it', async () => {
    const { startNotionSignIn, collectNotionSignIn } = await client();
    await startNotionSignIn();
    fetcher.mockResolvedValue(answer(200, { access_token: 'secret', workspace_name: 'Studio' }));
    expect(await collectNotionSignIn()).toEqual({ connected: true, workspaceName: 'Studio' });
    expect(invoke).toHaveBeenCalledWith('notion_save_account', { account: { access_token: 'secret', workspace_name: 'Studio' } });
    // The tokens went to Rust; the page keeps nothing of them, nor the flight.
    expect(localStorage.getItem(SIGN_IN_KEY)).toBeNull();
    expect(await collectNotionSignIn()).toBeNull();
  });

  it('says why a sign-in was refused, in the service’s words or its own, and forgets it', async () => {
    let loaded = await client();
    await loaded.startNotionSignIn();
    fetcher.mockResolvedValueOnce(answer(400, { error: 'The sign-in was cancelled on Notion.' }));
    await expect(loaded.collectNotionSignIn()).rejects.toThrow('The sign-in was cancelled on Notion.');
    expect(await loaded.collectNotionSignIn()).toBeNull();

    loaded = await client();
    await loaded.startNotionSignIn();
    fetcher.mockResolvedValueOnce(new Response('Bad gateway', { status: 502 }));
    await expect(loaded.collectNotionSignIn()).rejects.toThrow('Notion sign-in did not finish.');
  });

  it('collects a sign-in the page kept across a reload for ten minutes, and not after', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-25T12:00:00Z'));
    localStorage.setItem(SIGN_IN_KEY, JSON.stringify({ state: 's', verifier: 'v', at: Date.now() - 9 * 60_000 }));
    fetcher.mockResolvedValue(answer(202));
    expect(await (await client()).collectNotionSignIn()).toBe('pending');
    localStorage.setItem(SIGN_IN_KEY, JSON.stringify({ state: 's', verifier: 'v', at: Date.now() - 11 * 60_000 }));
    expect(await (await client()).collectNotionSignIn()).toBeNull();
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it('forgets a sign-in in flight when Notion is disconnected, and tells the binary', async () => {
    const { startNotionSignIn, disconnectNotion, collectNotionSignIn } = await client();
    await startNotionSignIn();
    await disconnectNotion();
    expect(invoke).toHaveBeenCalledWith('notion_disconnect', undefined);
    expect(await collectNotionSignIn()).toBeNull();
  });

  it('knows the binary can talk to Notion once it has answered, for code that cannot wait', async () => {
    const { notionReadyNow, notionAvailable } = await client();
    expect(await notionAvailable()).toBe(true);
    expect(notionReadyNow()).toBe(true);
  });
});

describe('asking Notion', () => {
  it('answers the body, and says each refusal as a sentence', async () => {
    const { notionRequest } = await client();
    request = () => ({ status: 200, body: { ok: 1 } });
    expect(await notionRequest('GET', 'users/me')).toEqual({ ok: 1 });
    request = () => ({ status: 401, body: { message: 'API token is invalid.' } });
    await expect(notionRequest('GET', 'users/me')).rejects.toThrow('Notion signed Ghost.md out. Sign in again in Settings > Notion.');
    request = () => ({ status: 404, body: null });
    await expect(notionRequest('PATCH', 'pages/abc')).rejects.toThrow('Notion can’t see that task. Share its board with Ghost.md in Notion.');
    await expect(notionRequest('POST', 'databases/abc/query')).rejects.toThrow('Notion can’t see that board. Share it with Ghost.md in Notion.');
    request = () => ({ status: 409, body: { message: 'Conflict occurred while saving.' } });
    await expect(notionRequest('POST', 'pages')).rejects.toThrow('Conflict occurred while saving.');
    request = () => ({ status: 503, body: null });
    await expect(notionRequest('POST', 'pages')).rejects.toThrow('Notion answered 503.');
  });

  it('lists the boards shared with it, each with its title property and what marks a task done', async () => {
    const { listBoards } = await client();
    request = ({ request: sent }) => {
      expect(sent).toMatchObject({ method: 'POST', path: 'search', body: { filter: { property: 'object', value: 'database' } } });
      return {
        status: 200,
        body: {
          results: [
            { id: 'b1', url: 'https://notion.so/b1', title: [{ plain_text: 'Road' }, { plain_text: 'map' }], properties: { Task: { type: 'title' }, Done: { type: 'checkbox' }, Stage: { type: 'status' } } },
            { id: 'b2', url: 'https://notion.so/b2', title: [], properties: { Name: { type: 'title' }, Shipped: { type: 'checkbox' } } },
            { id: 'b3', url: 'https://notion.so/b3' },
          ],
        },
      };
    };
    expect(await listBoards()).toEqual([
      // A status is preferred to a checkbox for done: it is what a board's columns are.
      { id: 'b1', url: 'https://notion.so/b1', title: 'Roadmap', titleProperty: 'Task', doneProperty: { name: 'Stage', kind: 'status' } },
      { id: 'b2', url: 'https://notion.so/b2', title: 'Untitled board', titleProperty: 'Name', doneProperty: { name: 'Shipped', kind: 'checkbox' } },
      { id: 'b3', url: 'https://notion.so/b3', title: 'Untitled board', titleProperty: 'Name', doneProperty: null },
    ]);
  });

  const board = { id: 'b1', url: 'https://notion.so/b1', title: 'Roadmap', titleProperty: 'Task', doneProperty: null };

  it('makes a task on the board under its title property, cut to what Notion takes', async () => {
    const { createTask } = await client();
    let sent: { method: string; path: string; body: unknown } | null = null;
    request = ({ request: asked }) => {
      sent = asked;
      return { status: 200, body: { id: 'p1', url: 'https://notion.so/p1' } };
    };
    expect(await createTask(board, 'x'.repeat(2500))).toEqual({ id: 'p1', title: 'x'.repeat(2500), url: 'https://notion.so/p1' });
    expect(sent).toEqual({
      method: 'POST',
      path: 'pages',
      body: { parent: { database_id: 'b1' }, properties: { Task: { title: [{ type: 'text', text: { content: 'x'.repeat(2000) } }] } } },
    });
  });

  it('finds tasks by the first word said, and reads their titles back', async () => {
    const { findTasks } = await client();
    const bodies: unknown[] = [];
    request = ({ request: asked }) => {
      bodies.push(asked.body);
      return {
        status: 200,
        body: { results: [{ id: 'p1', url: 'u1', properties: { Task: { type: 'title', title: [{ plain_text: 'Invoice run' }] } } }, { id: 'p2', url: 'u2', properties: { Due: { type: 'date' } } }] },
      };
    };
    expect(await findTasks(board, '  invoice for March ')).toEqual([
      { id: 'p1', url: 'u1', title: 'Invoice run' },
      { id: 'p2', url: 'u2', title: 'Untitled' },
    ]);
    await findTasks(board, '   ');
    expect(bodies).toEqual([{ filter: { property: 'Task', title: { contains: 'invoice' } }, page_size: 50 }, { page_size: 50 }]);
  });
});

describe('which board a note sends to', () => {
  const road = { id: 'b1', url: 'u', title: 'Roadmap', titleProperty: 'Task', doneProperty: null };

  it('is kept on this phone per note, and unlinked by a null', async () => {
    const { linkBoard, boardFor, boardLinks } = await client();
    expect(boardFor('n1')).toBeNull();
    linkBoard('n1', road);
    linkBoard('n2', road);
    expect(boardFor('n1')).toEqual(road);
    linkBoard('n1', null);
    expect(boardFor('n1')).toBeNull();
    expect(Object.keys(boardLinks())).toEqual(['n2']);
    expect(JSON.parse(localStorage.getItem(LINKS_KEY)!)).toEqual({ n2: road });
  });

  it('never changes the links another reader already holds', async () => {
    const { linkBoard, boardLinks } = await client();
    linkBoard('n1', road);
    const held = boardLinks();
    linkBoard('n2', road);
    expect(Object.keys(held)).toEqual(['n1']);
  });
});
