import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { rerender, show, typeInto, unmount } from '../../test/render.tsx';

// The split view is the sidebar's line; each test says which side of it the window is.
let wide = false;
vi.mock('../core/useWideScreen.ts', () => ({ useSidebar: () => wide }));
vi.mock('../art/wispEdge.ts', () => ({ useWispEdge: () => undefined }));

const { SettingsScreen } = await import('./SettingsScreen.tsx');
const { goBack } = await import('../core/back.ts');
import type { SettingsSection } from './SettingsScreen.tsx';

const sections: SettingsSection[] = [
  { id: 'type', label: 'Type', icon: null, group: 0, summary: 'Larger · Inter', content: <div className="setk-row"><span className="setk-row__label">Text size</span></div>, settings: [{ name: 'Text size' }] },
  {
    id: 'animations',
    label: 'Animations',
    icon: null,
    group: 1,
    content: (
      <>
        <div className="setk-row"><span className="setk-row__label">Animation speed</span></div>
        <div className="setk-row" id="smoke"><span className="setk-row__label">Smoke at the edges</span></div>
      </>
    ),
    settings: [{ name: 'Animation speed' }, { name: 'Smoke at the edges', words: 'wisp' }],
  },
];

let host: HTMLDivElement;

afterEach(() => {
  // Unmounted before the real clock is back, so the tree's cleanup clears its timers on the fake clock that set them.
  unmount();
  vi.useRealTimers();
});

function render(onClose = () => {}) {
  host = show(<SettingsScreen open onClose={onClose} sections={sections} />);
}

/** Words in the search field, as typed; answers the field. */
function type(words: string) {
  const field = host.querySelector<HTMLInputElement>('input[type="search"]')!;
  typeInto(field, words);
  return field;
}

const labels = () => [...host.querySelectorAll('.settingsScreen__rowLabel')].map((label) => label.textContent);

describe('Settings search', () => {
  it('sits over the sections on a phone and swaps them for what it finds', () => {
    render();
    expect(host.querySelector('input[aria-label="Search settings"]')).not.toBeNull();
    expect(labels()).toEqual(['Type', 'Animations']);
    type('wisp');
    expect(labels()).toEqual(['Smoke at the edges']);
    expect(host.querySelector('.settingsScreen__rowSummary')?.textContent).toBe('Animations');
    type('nothing like it');
    expect(host.querySelector('.settingsScreen__none')?.textContent).toBe('Nothing in Settings matches “nothing like it”.');
  });

  it('opens a setting on its page and lights its row', () => {
    vi.useFakeTimers();
    render();
    type('smoke');
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__row')!.click());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Animations');
    act(() => vi.advanceTimersToNextFrame());
    expect(host.querySelector('#smoke')?.hasAttribute('data-found')).toBe(true);
    act(() => vi.advanceTimersByTime(1700));
    expect(host.querySelector('#smoke')?.hasAttribute('data-found')).toBe(false);
  });

  it('opens the first result on Enter, and empties the field on Escape before anything closes', () => {
    const onClose = vi.fn();
    wide = true;
    try {
      render(onClose);
      const field = type('anim');
      act(() => field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
      expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Animations');
      // The split view keeps what was found in its left column while the page on the right changes.
      expect(labels()).toEqual(['Animations']);
      const escape = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
      act(() => field.dispatchEvent(escape));
      expect(escape.defaultPrevented).toBe(true);
      expect(field.value).toBe('');
      expect(labels()).toEqual(['Type', 'Animations']);
      expect(onClose).not.toHaveBeenCalled();
    } finally {
      wide = false;
    }
  });

  it('takes ⌘F while it is open', () => {
    render();
    const find = new KeyboardEvent('keydown', { key: 'f', metaKey: true, bubbles: true, cancelable: true });
    act(() => window.dispatchEvent(find));
    expect(find.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(host.querySelector('input[type="search"]'));
  });
});

const display = () => host.querySelector('.settingsScreen__display')?.textContent ?? null;

/** A quick sideways drag across the page by `dx` pixels, right for back and left for forward (core/swipe.ts). */
function swipe(dx: number) {
  const surface = host.querySelector<HTMLElement>('.settingsScreen')!;
  const pointer = (type: string, clientX: number) =>
    surface.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, clientX, clientY: 300, button: 0 }), { pointerId: 1, isPrimary: true }));
  act(() => {
    pointer('pointerdown', 200);
    pointer('pointerup', 200 + dx);
  });
}
const rowFor = (label: string) => [...host.querySelectorAll<HTMLButtonElement>('.settingsScreen__row')].find((row) => row.querySelector('.settingsScreen__rowLabel')?.textContent === label)!;

describe('the Settings shell', () => {
  it('steps out of a page and then closes, by the back word or the phone’s back', () => {
    const onClose = vi.fn();
    render(onClose);
    act(() => rowFor('Animations').click());
    expect(display()).toBe('Animations');
    act(() => {
      goBack();
    });
    expect(display()).toBeNull();
    // Coming back out of a page says the way back into it.
    expect(host.querySelector('.settingsScreen__hint')?.textContent).toBe('Swipe left to go back into Animations.');
    expect(onClose).not.toHaveBeenCalled();
    act(() => rowFor('Type').click());
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(display()).toBeNull();
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('lands on the page it is asked to from inside another, each time it is asked', () => {
    host = show(<SettingsScreen open onClose={() => {}} sections={sections} goTo={{ id: 'animations', nonce: 1 }} />);
    expect(display()).toBe('Animations');
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(display()).toBeNull();
    rerender(<SettingsScreen open onClose={() => {}} sections={sections} goTo={{ id: 'animations', nonce: 2 }} />);
    expect(display()).toBe('Animations');
  });

  it('drops back to the list when the page on screen leaves the sections', () => {
    const onClose = vi.fn();
    render(onClose);
    act(() => rowFor('Animations').click());
    // Developer mode switched off from inside its own page takes the page away.
    rerender(<SettingsScreen open onClose={onClose} sections={sections.slice(0, 1)} />);
    expect(display()).toBeNull();
    expect(labels()).toEqual(['Type']);
    // Truly on the list, not on a page that is only missing for now: it does not come back with its section,
    rerender(<SettingsScreen open onClose={onClose} sections={sections} />);
    expect(display()).toBeNull();
    // and back leaves Settings rather than stepping out of it.
    act(() => {
      goBack();
    });
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('steps out of a page on a swipe to the right, and back into it on one to the left', () => {
    render();
    act(() => rowFor('Animations').click());
    swipe(120);
    expect(display()).toBeNull();
    swipe(-120);
    expect(display()).toBe('Animations');
    // A page opened from the list has nothing ahead of it: a swipe to the left there stays put.
    swipe(120);
    act(() => rowFor('Type').click());
    swipe(-120);
    expect(display()).toBe('Type');
  });

  it('shows the first page beside the list on a wide window, and back leaves at once', () => {
    const onClose = vi.fn();
    wide = true;
    try {
      render(onClose);
      expect(display()).toBe('Type');
      expect(rowFor('Type').getAttribute('aria-current')).toBe('page');
      act(() => rowFor('Animations').click());
      expect(display()).toBe('Animations');
      act(() => {
        goBack();
      });
      expect(onClose).toHaveBeenCalledOnce();
    } finally {
      wide = false;
    }
  });

  it('colours a section by its own hue, else by its id, else grey', () => {
    host = show(
      <SettingsScreen
        open
        onClose={() => {}}
        sections={[
          { id: 'account', label: 'Account', icon: null, group: 0, content: null },
          { id: 'plugin:someday', label: 'Someday', icon: null, group: 1, content: null, hue: 'coral' },
          { id: 'plugin:unknown', label: 'Unknown', icon: null, group: 1, content: null },
        ]}
      />,
    );
    const hues = [...host.querySelectorAll('.settingsScreen__rowIcon')].map((chip) => chip.getAttribute('data-hue'));
    expect(hues).toEqual(['blue', 'coral', 'grey']);
  });
});
