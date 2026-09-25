import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorView } from '@codemirror/view';
import { act } from 'react';
import { show, unmount } from '../../test/render.tsx';
import { NotePeek } from './NotePeek.tsx';

afterEach(() => vi.useRealTimers());

describe('a note drawn small on a card', () => {
  it('is the note’s own editor, read-only, in the formatted view, without the title', () => {
    const shown = show(<NotePeek body={'# Groceries\n\n- [ ] Eggs\n- [x] Milk\n\nSome words.'} />);
    const editor = shown.querySelector('.cm-editor');
    expect(editor).not.toBeNull();
    expect(shown.querySelector('[data-view="formatted"]')).not.toBeNull();
    expect(shown.querySelector('.cm-content')?.getAttribute('contenteditable')).toBe('false');
    const text = shown.querySelector('.cm-content')?.textContent ?? '';
    expect(text).toContain('Eggs');
    expect(text).toContain('Some words.');
    expect(text).not.toContain('Groceries');
  });

  it('draws nothing for a note that is only its title', () => {
    const shown = show(<NotePeek body={'# Just a title'} />);
    expect(shown.querySelector('.cm-editor')).toBeNull();
  });

  it('keeps what its editor drew and lets the editor go, and a card of the same text draws with no editor at all', () => {
    // A card keeps its drawing a quarter of a second after its editor mounts (NotePeek.tsx, SETTLE_MS), timed here on
    // a clock turned by hand: a real 400 ms sleep was a guess a loaded machine could outrun.
    vi.useFakeTimers();
    const body = '# Kept\n\n- [ ] A box\n\nWords drawn once.';
    const first = show(<NotePeek body={body} />);
    expect(EditorView.findFromDOM(first.querySelector('.cm-editor') as HTMLElement)).not.toBeNull();
    // Not yet: the editor may still be drawing.
    act(() => void vi.advanceTimersByTime(200));
    expect(EditorView.findFromDOM(first.querySelector('.cm-editor') as HTMLElement)).not.toBeNull();
    act(() => void vi.advanceTimersByTime(100));
    // The drawing is the editor's own, with no view behind it.
    const kept = first.querySelector('.cm-editor') as HTMLElement;
    expect(kept.textContent).toContain('Words drawn once.');
    expect(EditorView.findFromDOM(kept)).toBeNull();
    unmount();
    const again = show(<NotePeek body={body} />);
    const drawn = again.querySelector('.cm-editor') as HTMLElement;
    expect(drawn.textContent).toContain('A box');
    expect(EditorView.findFromDOM(drawn)).toBeNull();
  });
});
