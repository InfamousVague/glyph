import { afterEach, describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { show, unmount } from '../../test/render.tsx';
import { setPendingTag } from '../core/location.ts';

/**
 * A note's card: what its foot says. A note with a tape wears the tape's counter before the date, in figures and
 * with no icon, which is how a typed note that was spoken into is told from a typed one (docs/DESIGN.md §127).
 */

// A card's small drawing is the editor (notes/NotePeek.tsx), which is nothing the card's foot decides.
vi.mock('./NotePeek.tsx', () => ({ NotePeek: () => null }));
const { NoteCard } = await import('./NoteCard.tsx');

afterEach(() => unmount());

const foot = (host: HTMLElement) => host.querySelector('[class*=when]');

describe('a note card', () => {
  it('wears the tape counter in its foot when the note has a recording, and no icon', () => {
    const host = show(
      <ol>
        <NoteCard note={makeNote('t', '# Trip', { recordingMs: 760_000, updatedAt: Date.now() })} index={0} onOpen={() => undefined} />
      </ol>,
    );
    expect(foot(host)?.textContent).toBe('12:40 · Just now');
    expect(host.querySelector('[class*=tapeLength]')?.textContent).toBe('12:40');
    expect(foot(host)?.querySelector('svg')).toBeNull();
  });

  it('says only when it was touched on a note with no recording, or one whose tape was removed', () => {
    const host = show(
      <ol>
        <NoteCard note={makeNote('a', '# Plain', { updatedAt: Date.now() })} index={0} onOpen={() => undefined} />
        <NoteCard note={makeNote('b', '# Removed', { recordingMs: null, updatedAt: Date.now() })} index={1} onOpen={() => undefined} />
      </ol>,
    );
    expect([...host.querySelectorAll('[class*=when]')].map((el) => el.textContent)).toEqual(['Just now', 'Just now']);
    expect(host.querySelector('[class*=tapeLength]')).toBeNull();
  });
});

describe('where the note was written, on its card', () => {
  it('says the place after the date, and nothing for a tag with no name', () => {
    setPendingTag('c', { lat: 51.5074, lon: -0.1278, place: 'Pending Square', rough: false });
    const host = show(
      <ol>
        <NoteCard note={makeNote('a', '---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square"\n---\n# Walk', { updatedAt: Date.now() })} index={0} onOpen={() => undefined} />
        <NoteCard note={makeNote('b', '---\nlocation: 51.5074,-0.1278\n---\n# Walk', { recordingMs: 760_000, updatedAt: Date.now() })} index={1} onOpen={() => undefined} />
        <NoteCard note={makeNote('c', '# Waiting', { updatedAt: Date.now() })} index={2} onOpen={() => undefined} />
      </ol>,
    );
    // The place, and never the coordinates; and never a tag still waiting to be written.
    expect([...host.querySelectorAll('[class*=when]')].map((el) => el.textContent)).toEqual(['Just now · Trafalgar Square', '12:40 · Just now', 'Just now']);
  });
});

describe('a notebook’s card', () => {
  it('counts a journal’s entries and lists the newest, and a notebook’s pages as its index has them', () => {
    const journal = makeNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[A]]\n', { updatedAt: Date.now() });
    const host = show(
      <ol>
        <NoteCard note={journal} index={0} onOpen={() => undefined} entries={{ count: 212, newest: ['2026-09-28 14.05', '2026-09-28 08.10', '2026-09-27 21.40', '2026-09-27 07.55'] }} />
        <NoteCard note={makeNote('n', '---\ntitle: "Guide"\nbook: true\n---\n# Guide\n\n- [[Trees]]\n', { updatedAt: Date.now() })} index={1} onOpen={() => undefined} />
        <NoteCard note={makeNote('e', '---\ntitle: ""\nbook: true\njournal: true\n---\n', { updatedAt: Date.now() })} index={2} onOpen={() => undefined} entries={{ count: 0, newest: [] }} />
      </ol>,
    );
    const cards = [...host.querySelectorAll('li > button')];
    expect(cards[0]!.textContent).toContain('212 entries');
    expect(cards[0]!.textContent).toContain('1' + '2026-09-28 14.05');
    expect(cards[0]!.textContent).toContain('and 208 more');
    expect(cards[1]!.textContent).toContain('1 page');
    expect(cards[2]!.textContent).toContain('Untitled journal');
    expect(cards[2]!.textContent).toContain('No entries yet');
  });

  it('marks an entry with its journal, said as an entry rather than a page number', async () => {
    const { BookPlaceMark } = await import('./BookPlaceMark.tsx');
    const journal = makeNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n');
    const host = show(<BookPlaceMark place={{ book: journal, title: 'Diary', chapters: [], at: 3, journal: true }} />);
    expect(host.querySelector('[title]')?.getAttribute('title')).toBe('An entry in Diary');
    show(<BookPlaceMark place={{ book: journal, title: 'Guide', chapters: [], at: 3, journal: false }} />);
    expect(document.querySelectorAll('[title]')[1]?.getAttribute('title')).toBe('Page 4 of Guide');
  });
});
