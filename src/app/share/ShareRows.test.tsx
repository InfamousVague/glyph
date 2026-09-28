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
    /** The notes whose share carries where it was written, and the notes with a place to carry. */
    withPlace: new Set<string>(),
    placed: new Set<string>(),
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
  sharesPlace: (note: { id: string }) => shares.placed.has(note.id),
  sharingPlace: (id: string) => shares.withPlace.has(id),
  shareWithPlace: vi.fn(async (id: string, on: boolean) => {
    if (on) shares.withPlace.add(id);
    else shares.withPlace.delete(id);
    shares.told();
  }),
}));

const { ShareRows } = await import('./ShareRows.tsx');
const { shareNote, shareWithPlace, stopSharing } = await import('./share.ts');

const copied: string[] = [];
beforeEach(() => {
  localStorage.clear();
  account.session = { user: 'matt' };
  shares.links.clear();
  shares.withPlace.clear();
  shares.placed.clear();
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

  it('says a notebook’s pages go with it, and a note’s row says nothing of pages', () => {
    show(<ShareRows noteId="a" kind="notebook" />);
    expect(row('Share a read-only link')?.textContent).toContain('Every page goes with it.');
    show(<ShareRows noteId="b" />);
    expect(buttonSaying(document.body.lastElementChild!, 'Share a read-only link')?.textContent).not.toContain('page');
  });

  it('says a journal is shared an entry at a time, with nothing to press, signed in or out, until it is shared', () => {
    const host = show(<ShareRows noteId="j" kind="journal" />);
    expect(host.textContent).toContain('A journal is shared an entry at a time. Open one to share it.');
    expect(host.querySelector('button')).toBeNull();
    account.session = null;
    const out = show(<ShareRows noteId="j" kind="journal" />);
    expect(out.textContent).toContain('A journal is shared an entry at a time.');
    // A notebook shared before it was kept as a journal goes on as it was.
    account.session = { user: 'matt' };
    shares.links.set('k', 'https://attack.fm/glyph/read.html#x');
    const shared = show(<ShareRows noteId="k" kind="journal" />);
    expect(buttonSaying(shared, 'Copy the link')).toBeTruthy();
    expect(shared.textContent).not.toContain('an entry at a time');
  });

  it('shows the link itself where the clipboard will not take it', async () => {
    shares.links.set('a', 'https://attack.fm/glyph/read.html#kept');
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => Promise.reject(new Error('no')) } });
    show(<ShareRows noteId="a" />);
    await act(async () => row('Copy the link')!.click());
    expect(said()).toBe('https://attack.fm/glyph/read.html#kept');
  });
});

describe('where a shared note was written', () => {
  it('offers to share it only where the note has a place, ticked once chosen, and says which way the link reads', async () => {
    await createNote('a', '---\nlocation: 51.5074,-0.1278\n---\n# Trip');
    shares.placed.add('a');
    show(<ShareRows noteId="a" />);
    await act(async () => row('Share a read-only link')!.click());
    await act(async () => Promise.resolve());
    expect(row('Copy the link')?.textContent).toContain('Where it was written stays out of the link.');
    const share = row('Share where it was written')!;
    expect(share.getAttribute('aria-pressed')).toBe('false');
    await act(async () => share.click());
    expect(shareWithPlace).toHaveBeenCalledWith('a', true);
    expect(row('Share where it was written')?.getAttribute('aria-pressed')).toBe('true');
    expect(row('Copy the link')?.textContent).toContain('The link carries where it was written.');
    await act(async () => row('Share where it was written')!.click());
    expect(shareWithPlace).toHaveBeenLastCalledWith('a', false);
  });

  it('has no such row for a note with nothing to carry', async () => {
    await createNote('b', '# Plain');
    show(<ShareRows noteId="b" />);
    await act(async () => row('Share a read-only link')!.click());
    await act(async () => Promise.resolve());
    expect(row('Share where it was written')).toBeUndefined();
    expect(row('Copy the link')?.textContent).not.toContain('stays out');
  });
});
