import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, unmount } from '../../test/render.tsx';
import { dropLiveTitles, setLiveTitle, titleNow, useLiveTitles } from './liveTitles.ts';

/**
 * An open note's title as its editor has it (liveTitles.ts): said as line 1 changes, read by whoever subscribes and
 * nobody else, and taken over the note App has only while it is the newer.
 */

afterEach(() => {
  unmount();
  dropLiveTitles(['n1', 'n2']);
});

describe('a note’s live title', () => {
  it('draws only what subscribes to it, each time it changes and not when it is said again unchanged', () => {
    let draws = 0;
    function Tab() {
      draws += 1;
      const live = useLiveTitles();
      return <span data-tab>{live.get('n1')?.title ?? 'Untitled'}</span>;
    }
    show(<Tab />);
    expect(draws).toBe(1);
    act(() => setLiveTitle('n1', '2026-09-28'));
    expect(document.querySelector('[data-tab]')?.textContent).toBe('2026-09-28');
    expect(draws).toBe(2);
    act(() => setLiveTitle('n1', '2026-09-28'));
    expect(draws).toBe(2);
    act(() => dropLiveTitles(['n1']));
    expect(document.querySelector('[data-tab]')?.textContent).toBe('Untitled');
  });

  it('is the tab’s title while it is newer than the note App has, so a rename by sync afterwards wins', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    try {
      vi.setSystemTime(2_000);
      setLiveTitle('n2', 'Typed');
      const live = new Map([['n2', { title: 'Typed', at: 2_000 }]]);
      expect(titleNow({ id: 'n2', updatedAt: 1_000 }, '', live)).toBe('Typed');
      expect(titleNow({ id: 'n2', updatedAt: 3_000 }, 'Renamed elsewhere', live)).toBe('Renamed elsewhere');
      expect(titleNow({ id: 'other', updatedAt: 0 }, 'Its own', live)).toBe('Its own');
    } finally {
      vi.useRealTimers();
    }
  });
});
