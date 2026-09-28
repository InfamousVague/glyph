import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createNote } from '../core/store.ts';
import { buttonSaying, show, unmount } from '../../test/render.tsx';

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
    /** The notes whose share carries the places in their words, and the notes whose words hold one. */
    withPlaces: new Set<string>(),
    inWords: new Set<string>(),
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
  sharesPlaces: (note: { id: string }) => shares.inWords.has(note.id),
  sharingPlaces: (id: string) => shares.withPlaces.has(id),
  shareWithPlaces: vi.fn(async (id: string, on: boolean) => {
    if (on) shares.withPlaces.add(id);
    else shares.withPlaces.delete(id);
    shares.told();
  }),
}));

const { ShareRows } = await import('./ShareRows.tsx');
const { shareNote, shareWithPlace, shareWithPlaces, stopSharing } = await import('./share.ts');

const copied: string[] = [];
beforeEach(() => {
  localStorage.clear();
  account.session = { user: 'matt' };
  shares.links.clear();
  shares.withPlace.clear();
  shares.placed.clear();
  shares.withPlaces.clear();
  shares.inWords.clear();
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
    expect(row('Share the places in it')).toBeUndefined();
    expect(row('Copy the link')?.textContent).not.toContain('stays out');
  });
});

describe('the places written in a shared note', () => {
  const shared = async (id: string, { tag, places }: { tag: boolean; places: boolean }) => {
    await createNote(id, '# Lisbon');
    if (tag) shares.placed.add(id);
    if (places) shares.inWords.add(id);
    shares.links.set(id, 'https://attack.fm/glyph/read.html#kept');
    show(<ShareRows noteId={id} />);
    await act(async () => Promise.resolve());
    await act(async () => Promise.resolve());
  };
  const hint = () => row('Copy the link')!.textContent!.replace('Copy the linkShared, read-only. Your edits reach readers a few seconds after you save.', '').trim();

  it('offers their own row only where the words hold one, and leaves the tag’s row word for word', async () => {
    await shared('a', { tag: true, places: false });
    expect(row('Share where it was written')?.textContent).toBe('Share where it was writtenThe place and the map, on the shared page.');
    expect(row('Share the places in it')).toBeUndefined();
    expect(hint()).toBe('Where it was written stays out of the link.');
  });

  it('ticks the places apart from the tag', async () => {
    await shared('b', { tag: false, places: true });
    const places = row('Share the places in it')!;
    expect(places.textContent).toBe('Share the places in itThe places written in it, and their maps.');
    expect(places.getAttribute('aria-pressed')).toBe('false');
    await act(async () => places.click());
    expect(shareWithPlaces).toHaveBeenCalledWith('b', true);
    expect(shareWithPlace).not.toHaveBeenCalledWith('b', expect.anything());
    expect(row('Share the places in it')?.getAttribute('aria-pressed')).toBe('true');
  });

  it('says in the link’s hint exactly what the link carries, one sentence for what the pages hold', async () => {
    const cases: [boolean, boolean, boolean, boolean, string][] = [
      // tag held, places held, tag ticked, places ticked
      [true, false, true, false, 'The link carries where it was written.'],
      [true, false, false, false, 'Where it was written stays out of the link.'],
      [false, true, false, true, 'The link carries the places in it.'],
      [false, true, false, false, 'The places in it stay out of the link.'],
      [true, true, true, true, 'The link carries where it was written and the places in it.'],
      [true, true, false, true, 'The link carries the places in it. Where it was written stays out.'],
      [true, true, true, false, 'The link carries where it was written. The places in it stay out.'],
      [true, true, false, false, 'Where it was written and the places in it stay out of the link.'],
    ];
    for (const [index, [tag, places, withTag, withPlaces, words]] of cases.entries()) {
      const id = `c${index}`;
      if (withTag) shares.withPlace.add(id);
      if (withPlaces) shares.withPlaces.add(id);
      await shared(id, { tag, places });
      expect(hint(), words).toBe(words);
      unmount();
    }
  });
});
