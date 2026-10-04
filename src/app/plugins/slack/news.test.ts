import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Notification } from '../../core/notifications/kinds.ts';

/**
 * An organization's news to its Slack channel: only the new rows of a pass, never a device's first look, only the
 * organization a channel was chosen for, only its news, each row once however often it comes back above the cursor,
 * and nothing from before the channel was chosen. Posting itself is stood in for; channels.test.ts has the native side.
 */

vi.mock('../../core/tauri.ts', () => ({
  isTauri: () => true,
  invoke: vi.fn(async (command: string) => (command === 'ota_status' ? { nativeGeneration: 25 } : undefined)),
}));

const { addChannel } = await import('./channels.ts');
const { forwardNews, newsChannelFor, setNewsChannel } = await import('./news.ts');
const { slackPlugin } = await import('./index.tsx');
const { createRegistry } = await import('../registry.ts');
const { tellArrived } = await import('../../core/notifications/arrived.ts');

const HOOK = 'https://hooks.slack.com/services/T0/B0/abc';
const SET_AT = 1_000;

function row(id: string, rev: number, over: Partial<Notification> = {}): Notification {
  return { id, rev, kind: 'member-joined', at: SET_AT + rev, readAt: null, hidden: false, from: 'sam', org: { id: 'acme', name: 'Acme' }, ...over };
}

let sent: { channel: string; text: string }[] = [];
const post = vi.fn(async (channel: { name: string }, text: string) => {
  sent.push({ channel: channel.name, text });
});
const deps = { post, member: (orgId: string) => orgId === 'acme' || orgId === 'globex' };

beforeEach(async () => {
  localStorage.clear();
  sent = [];
  post.mockClear();
  const launch = await addChannel('#acme', HOOK);
  setNewsChannel('acme', launch.id, SET_AT);
});

describe('an organization’s news in Slack', () => {
  it('posts the rows a pass brought, oldest first, as the bell’s sentences', async () => {
    const rows = [row('r3', 13, { kind: 'role-changed', body: { role: 'admin' } }), row('r2', 12), row('r1', 11)];
    expect(await forwardNews(11, rows, deps)).toBe(2);
    expect(sent).toEqual([
      { channel: '#acme', text: 'sam joined Acme.' },
      { channel: '#acme', text: 'sam made you an admin of Acme.' },
    ]);
  });

  it('posts nothing on a device’s first look at the feed', async () => {
    expect(await forwardNews(0, [row('r1', 5)], deps)).toBe(0);
    expect(post).not.toHaveBeenCalled();
  });

  it('posts each row once, however often it comes back above the cursor', async () => {
    await forwardNews(10, [row('r1', 11)], deps);
    // Read on another device: written again, at a later revision.
    await forwardNews(11, [row('r1', 14, { readAt: 2_000 })], deps);
    expect(sent).toHaveLength(1);
  });

  it('posts only the organization a channel was chosen for, and only its news', async () => {
    const rows = [
      row('g1', 11, { org: { id: 'globex', name: 'Globex' } }),
      row('i1', 12, { kind: 'invite' }),
      row('c1', 13, { kind: 'note-edited', org: undefined }),
      row('a1', 14, { kind: 'org-renamed', body: { was: 'Acme Ltd' } }),
    ];
    await forwardNews(10, rows, deps);
    expect(sent.map((s) => s.text)).toEqual(['sam renamed Acme Ltd to Acme.']);
  });

  it('posts nothing from before the channel was chosen, nor for an organization the person has left', async () => {
    await forwardNews(10, [row('old', 11, { at: SET_AT - 1 })], deps);
    await forwardNews(10, [row('left', 12)], { ...deps, member: () => false });
    expect(sent).toEqual([]);
  });

  it('stops when the channel is set to nowhere, or forgotten', async () => {
    setNewsChannel('acme', null);
    expect(newsChannelFor('acme')).toBeNull();
    expect(await forwardNews(10, [row('r1', 11)], deps)).toBe(0);
  });

  it('escapes what Slack would read as its own marks', async () => {
    await forwardNews(10, [row('r1', 11, { from: '<!channel>' })], deps);
    expect(sent[0]?.text).toBe('&lt;!channel&gt; joined Acme.');
  });

  it('is not tried again when a post fails', async () => {
    post.mockRejectedValueOnce(new Error('Slack had a problem.'));
    expect(await forwardNews(10, [row('r1', 11)], deps)).toBe(0);
    expect(await forwardNews(10, [row('r1', 12)], deps)).toBe(0);
    expect(post).toHaveBeenCalledTimes(1);
  });
});

describe('the feed’s new rows', () => {
  it('reach a plugin through the registry only while it is on', async () => {
    const heard = vi.fn(async () => undefined);
    const on = { ...slackPlugin, manifest: { ...slackPlugin.manifest, id: 'listens', standard: true }, newRows: heard };
    const off = { ...slackPlugin, manifest: { ...slackPlugin.manifest, id: 'quiet', standard: false }, newRows: vi.fn(async () => undefined) };
    const store = { read: () => ({}), write: () => undefined };
    const registry = createRegistry([on, off], store);
    await registry.newRows(4, [row('r1', 5)]);
    expect(heard).toHaveBeenCalledWith(4, [row('r1', 5)]);
    expect(off.newRows).not.toHaveBeenCalled();
  });

  it('are told to every listener, and one that throws stops nobody', async () => {
    const { onArrived } = await import('../../core/notifications/arrived.ts');
    const second = vi.fn();
    const stopFirst = onArrived(() => {
      throw new Error('mine');
    });
    const stopSecond = onArrived(second);
    tellArrived(3, []);
    expect(second).toHaveBeenCalledWith(3, []);
    stopFirst();
    stopSecond();
  });
});
