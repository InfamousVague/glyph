import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createNote } from '../core/store.ts';
import { buttonSaying, show } from '../../test/render.tsx';

/**
 * A note's sharing, in its cog: signed out, only where to sign in; signed in, a link made, copied and stopped, with
 * each failure said on the row's own line. The service is stood in for: what the rows decide is what is offered and
 * what is said, not how a share is sealed (share/share.test.ts).
 */

const account = vi.hoisted(() => ({ session: null as { user: string } | null }));
vi.mock('../core/account/account.ts', () => ({ useAccount: () => ({ session: account.session }) }));

const shares = vi.hoisted(() => {
  const links = new Map<string, string>();
  const listeners = new Set<() => void>();
  const told = () => listeners.forEach((listener) => listener());
  return {
    links,
    fail: null as Error | null,
    told,
    onShares: (listener: () => void) => {
      listeners.add(listener);
      return () => void listeners.delete(listener);
    },
  };
});
vi.mock('./share.ts', () => ({
  onShares: shares.onShares,
  linkFor: (id: string) => shares.links.get(id) ?? null,
  shareNote: vi.fn(async (note: { id: string }) => {
    if (shares.fail) throw shares.fail;
    const link = `https://attack.fm/glyph/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`;
    shares.links.set(note.id, link);
    shares.told();
    return link;
  }),
  stopSharing: vi.fn(async (id: string) => {
    shares.links.delete(id);
    shares.told();
  }),
}));

const { ShareRows } = await import('./ShareRows.tsx');
const { shareNote, stopSharing } = await import('./share.ts');

const copied: string[] = [];
beforeEach(() => {
  localStorage.clear();
  account.session = { user: 'matt' };
  shares.links.clear();
  shares.fail = null;
  copied.length = 0;
  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async (text: string) => void copied.push(text) } });
});

const row = (words: string) => buttonSaying(document.body, words);
const said = () => document.querySelector('[role="status"]')?.textContent ?? null;

describe('a note’s sharing', () => {
  it('signed out, says where to sign in and offers nothing to press', () => {
    account.session = null;
    const host = show(<ShareRows noteId="a" />);
    expect(host.textContent).toContain('Sign in under Settings › Account first');
    expect(host.querySelector('button')).toBeNull();
  });

  it('shares a saved note by a link, copies it, and offers the link from then on', async () => {
    await createNote('a', '# Trip');
    show(<ShareRows noteId="a" />);
    await act(async () => row('Share a read-only link')!.click());
    expect(shareNote).toHaveBeenCalledWith(expect.objectContaining({ id: 'a' }), expect.any(Array));
    expect(copied).toEqual([shares.links.get('a')]);
    expect(said()).toBe('The link is copied.');
    expect(row('Copy the link')).toBeTruthy();
    await act(async () => row('Stop sharing')!.click());
    expect(stopSharing).toHaveBeenCalledWith('a');
    expect(row('Share a read-only link')).toBeTruthy();
  });

  it('says so when there is nothing saved to share yet, and what went wrong when sharing failed', async () => {
    show(<ShareRows noteId="unsaved" />);
    await act(async () => row('Share a read-only link')!.click());
    expect(said()).toBe('Save the note first: there is nothing to share yet.');
    await createNote('a', '# Trip');
    shares.fail = new Error('The service is not answering.');
    show(<ShareRows noteId="a" />);
    await act(async () => buttonSaying(document.body.lastElementChild!, 'Share a read-only link')!.click());
    expect(document.body.lastElementChild!.querySelector('[role="status"]')?.textContent).toBe('The service is not answering.');
  });

  it('shows the link itself where the clipboard will not take it', async () => {
    shares.links.set('a', 'https://attack.fm/glyph/read.html#kept');
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => Promise.reject(new Error('no')) } });
    show(<ShareRows noteId="a" />);
    await act(async () => row('Copy the link')!.click());
    expect(said()).toBe('https://attack.fm/glyph/read.html#kept');
  });
});
