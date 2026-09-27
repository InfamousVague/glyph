import { afterEach, describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { show, unmount } from '../../test/render.tsx';

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
