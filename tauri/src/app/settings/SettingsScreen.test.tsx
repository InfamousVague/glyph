import { readFileSync } from 'node:fs';
import { join } from 'node:path';
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
// The shell's own rows and panes here are made up; the app's sections are SettingsSheet.test.tsx's.

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
    // The list ends in air: the way back into the page is the swipe, not a line saying so (docs/DESIGN.md §138).
    expect(host.querySelector('.settingsScreen__hint')).toBeNull();
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

  it('lands on the list on a fresh open, not on the page the last request opened', () => {
    const goTo = { id: 'animations', nonce: 1 };
    host = show(<SettingsScreen open onClose={() => {}} sections={sections} goTo={goTo} />);
    expect(display()).toBe('Animations');
    // Closed with the request still held, as the sheet holds it (it stays mounted), and opened again.
    rerender(<SettingsScreen open={false} onClose={() => {}} sections={sections} goTo={goTo} />);
    rerender(<SettingsScreen open onClose={() => {}} sections={sections} goTo={goTo} />);
    expect(display()).toBeNull();
    // A request made while it was closed is still answered when it opens.
    rerender(<SettingsScreen open={false} onClose={() => {}} sections={sections} goTo={{ id: 'animations', nonce: 2 }} />);
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

  it('colours a section by its own hue, else by its id, else grey, and has no hue for a page that went', () => {
    host = show(
      <SettingsScreen
        open
        onClose={() => {}}
        sections={[
          { id: 'account', label: 'Account', icon: null, group: 0, content: null },
          { id: 'theme', label: 'Appearance', icon: null, group: 1, content: null },
          { id: 'recording', label: 'Recording', icon: null, group: 1, content: null },
          { id: 'plugins', label: 'Plugins', icon: null, group: 1, content: null },
          { id: 'about', label: 'About', icon: null, group: 2, content: null },
          { id: 'plugin:someday', label: 'Someday', icon: null, group: 3, content: null, hue: 'coral' },
          { id: 'plugin:unknown', label: 'Unknown', icon: null, group: 3, content: null },
          // Formatting's orange went with its page: a section by that id now is grey like any without one.
          { id: 'formatting', label: 'Formatting', icon: null, group: 3, content: null },
        ]}
      />,
    );
    const hues = [...host.querySelectorAll('.settingsScreen__rowIcon')].map((chip) => chip.getAttribute('data-hue'));
    expect(hues).toEqual(['blue', 'purple', 'red', 'green', 'grey', 'coral', 'grey', 'grey']);
  });
});

/**
 * Sub-pages (docs/DESIGN.md §138): a section off the list, opened from a row on its parent's page or by the search,
 * with its parent's name in the head and back stepping there first.
 */
describe('a sub-page', () => {
  const withSub: SettingsSection[] = [
    ...sections,
    {
      id: 'plugins',
      label: 'Plugins',
      icon: null,
      group: 1,
      content: <div className="setk-row"><span className="setk-row__label">Notion</span></div>,
    },
    {
      id: 'plugin:notion',
      label: 'Notion',
      icon: null,
      group: 1,
      listed: false,
      parent: 'plugins',
      hue: 'graphite',
      content: (
        <section className="setk">
          <div className="setk__title">Boards</div>
          <div className="setk-row"><span className="setk-row__label">Kitchen</span></div>
        </section>
      ),
      settings: [{ name: 'Boards', words: 'databases' }],
    },
  ];
  const headWord = () => host.querySelector('.settingsScreen__headWord')?.textContent?.trim();

  it('is not a row on the list, but the search finds it and what is on it', () => {
    host = show(<SettingsScreen open onClose={() => {}} sections={withSub} />);
    expect(labels()).toEqual(['Type', 'Animations', 'Plugins']);
    type('notion');
    expect(labels()).toEqual(['Notion']);
    type('databases');
    expect(labels()).toEqual(['Boards']);
    expect(host.querySelector('.settingsScreen__rowSummary')?.textContent).toBe('Notion');
  });

  it('opens from its parent’s page, names the parent in the head, and steps back to it, then to the list', () => {
    const onClose = vi.fn();
    host = show(<SettingsScreen open onClose={onClose} sections={withSub} goTo={{ id: 'plugin:notion', nonce: 1 }} />);
    expect(display()).toBe('Notion');
    expect(headWord()).toBe('Plugins');
    act(() => {
      goBack();
    });
    expect(display()).toBe('Plugins');
    expect(headWord()).toBe('Settings');
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(display()).toBeNull();
    act(() => {
      goBack();
    });
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('steps to its parent on a swipe to the right, and back into it on one to the left, from the parent only', () => {
    host = show(<SettingsScreen open onClose={() => {}} sections={withSub} goTo={{ id: 'plugin:notion', nonce: 1 }} />);
    swipe(120);
    expect(display()).toBe('Plugins');
    swipe(-120);
    expect(display()).toBe('Notion');
    // Back twice, to the list: from there the swipe forward goes into Plugins, the page just left, not to Notion.
    swipe(120);
    swipe(120);
    expect(display()).toBeNull();
    swipe(-120);
    expect(display()).toBe('Plugins');
  });

  it('opened from a search hit, still steps back to its parent', () => {
    host = show(<SettingsScreen open onClose={() => {}} sections={withSub} />);
    type('boards');
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__row')!.click());
    expect(display()).toBe('Notion');
    act(() => {
      goBack();
    });
    expect(display()).toBe('Plugins');
  });

  it('shows on the right of a wide window with its parent’s row current, and back steps to the parent before it leaves', () => {
    const onClose = vi.fn();
    wide = true;
    try {
      host = show(<SettingsScreen open onClose={onClose} sections={withSub} goTo={{ id: 'plugin:notion', nonce: 1 }} />);
      expect(display()).toBe('Notion');
      expect(labels()).toEqual(['Type', 'Animations', 'Plugins']);
      expect(rowFor('Plugins').getAttribute('aria-current')).toBe('page');
      expect(host.querySelector('.settingsScreen__pane')?.getAttribute('data-hue')).toBe('graphite');
      act(() => {
        goBack();
      });
      expect(display()).toBe('Plugins');
      expect(onClose).not.toHaveBeenCalled();
      act(() => {
        goBack();
      });
      expect(onClose).toHaveBeenCalledOnce();
    } finally {
      wide = false;
    }
  });

  it('says its parent in the head of a wide window, where the head steps back as back does, and leaves from a pane', () => {
    const onClose = vi.fn();
    wide = true;
    try {
      host = show(<SettingsScreen open onClose={onClose} sections={withSub} goTo={{ id: 'plugin:notion', nonce: 1 }} />);
      expect(headWord()).toBe('Plugins');
      expect(host.querySelector('.settingsScreen__headWord')?.getAttribute('aria-label')).toBeNull();
      act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
      expect(display()).toBe('Plugins');
      expect(onClose).not.toHaveBeenCalled();
      expect(headWord()).toBe('Settings');
      expect(host.querySelector('.settingsScreen__headWord')?.getAttribute('aria-label')).toBe('Back to your notes');
      act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
      expect(onClose).toHaveBeenCalledOnce();
    } finally {
      wide = false;
    }
  });
});

/**
 * The same screen as an organization's (docs/TEAMS.md, D6; settings/OrganizationSheet.tsx): its name in place of
 * "Settings" everywhere the word stood, no search over its few sections, and a head that can say where closing goes.
 */
describe('a screen called something else', () => {
  it('wears its title over the list, in the head’s way out, in its label and in what the search says', () => {
    const onClose = vi.fn();
    host = show(<SettingsScreen open onClose={onClose} sections={sections} title="Ghost" />);
    expect(host.querySelector('.settingsScreen')?.getAttribute('aria-label')).toBe('Ghost');
    expect(host.querySelector('.settingsScreen__headWord')?.textContent?.trim()).toBe('Ghost');
    expect(host.querySelector('.settingsScreen__headWord')?.getAttribute('aria-label')).toBe('Back to your notes');
    expect(host.querySelector('input[aria-label="Search Ghost"]')).not.toBeNull();
    type('nothing like it');
    expect(host.querySelector('.settingsScreen__none')?.textContent).toBe('Nothing in Ghost matches “nothing like it”.');
    type('');
    act(() => rowFor('Animations').click());
    expect(host.querySelector('.settingsScreen__headWord')?.textContent?.trim()).toBe('Ghost');
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('draws no search when told not to, on a phone and on a wide window, and ⌘F then goes nowhere', () => {
    host = show(<SettingsScreen open onClose={() => {}} sections={sections} title="Ghost" search={false} />);
    expect(host.querySelector('input[type="search"]')).toBeNull();
    expect(labels()).toEqual(['Type', 'Animations']);
    const find = new KeyboardEvent('keydown', { key: 'f', metaKey: true, bubbles: true, cancelable: true });
    act(() => window.dispatchEvent(find));
    expect(find.defaultPrevented).toBe(false);
    unmount();
    wide = true;
    try {
      host = show(<SettingsScreen open onClose={() => {}} sections={sections} title="Ghost" search={false} />);
      expect(host.querySelector('input[type="search"]')).toBeNull();
      expect(display()).toBe('Type');
      expect(host.querySelector('.settingsScreen__headWord')?.textContent?.trim()).toBe('Ghost');
    } finally {
      wide = false;
    }
  });

  it('says where closing goes when told, in place of its name, on a phone and on a wide window', () => {
    const onClose = vi.fn();
    host = show(<SettingsScreen open onClose={onClose} sections={sections} title="Ghost" closeWord="Organizations" />);
    expect(host.querySelector('.settingsScreen__headWord')?.textContent?.trim()).toBe('Organizations');
    expect(host.querySelector('.settingsScreen__headWord')?.getAttribute('aria-label')).toBeNull();
    // Over a pane the head still steps back to the list, and names the screen.
    act(() => rowFor('Type').click());
    expect(host.querySelector('.settingsScreen__headWord')?.textContent?.trim()).toBe('Ghost');
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(onClose).toHaveBeenCalledOnce();
    unmount();
    wide = true;
    try {
      host = show(<SettingsScreen open onClose={onClose} sections={sections} title="Ghost" closeWord="Organizations" />);
      expect(host.querySelector('.settingsScreen__headWord')?.textContent?.trim()).toBe('Organizations');
    } finally {
      wide = false;
    }
  });
});

describe('a target', () => {
  it('opens a page at a setting named with it, scrolled to and lit as a search hit is', () => {
    vi.useFakeTimers();
    host = show(<SettingsScreen open onClose={() => {}} sections={sections} goTo={{ id: 'animations', setting: 'Smoke at the edges', nonce: 1 }} />);
    expect(display()).toBe('Animations');
    act(() => vi.advanceTimersToNextFrame());
    expect(host.querySelector('#smoke')?.hasAttribute('data-found')).toBe(true);
    act(() => vi.advanceTimersByTime(1700));
    expect(host.querySelector('#smoke')?.hasAttribute('data-found')).toBe(false);
    // Asked again from the page it is already on (a word on Account for Account's own card): lit again.
    rerender(<SettingsScreen open onClose={() => {}} sections={sections} goTo={{ id: 'animations', setting: 'Smoke at the edges', nonce: 2 }} />);
    act(() => vi.advanceTimersToNextFrame());
    expect(host.querySelector('#smoke')?.hasAttribute('data-found')).toBe(true);
  });

  it('lights a setting once for each request: coming back to the page from the list is only opening it', () => {
    vi.useFakeTimers();
    host = show(<SettingsScreen open onClose={() => {}} sections={sections} goTo={{ id: 'animations', setting: 'Smoke at the edges', nonce: 1 }} />);
    act(() => vi.advanceTimersToNextFrame());
    act(() => vi.advanceTimersByTime(1700));
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    act(() => rowFor('Animations').click());
    act(() => vi.advanceTimersToNextFrame());
    expect(host.querySelector('#smoke')?.hasAttribute('data-found')).toBe(false);
  });

  it('lights the setting on the right of a wide window too', () => {
    vi.useFakeTimers();
    wide = true;
    try {
      host = show(<SettingsScreen open onClose={() => {}} sections={sections} goTo={{ id: 'animations', setting: 'Smoke at the edges', nonce: 1 }} />);
      act(() => vi.advanceTimersToNextFrame());
      expect(host.querySelector('#smoke')?.hasAttribute('data-found')).toBe(true);
    } finally {
      wide = false;
    }
  });

  // The tests run with CSS off, so this is read from the sheet: a card lit and let go must not run its arrival again.
  it('keeps a lit card’s arrival beside its light, so letting the light go does not blink the card', () => {
    const css = readFileSync(join(import.meta.dirname, 'settings.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].filter(([, selector = '']) => selector.split(',').some((one) => one.trim() === '.settingsScreen__pane .setk[data-found]'));
    const animations = rules.map(([, , body = '']) => /animation:([^;]*);/.exec(body)?.[1]?.replace(/\s+/g, ' ').trim());
    // Moving: the arrival first, as the card's own rule has it, then the light. Reduced: neither.
    expect(animations).toEqual(['settingsRise 360ms var(--glacier-ease-out) both, settingsFound 1.6s var(--glacier-ease-out)', 'none']);
  });

  it('opens the page alone when it names no setting', () => {
    vi.useFakeTimers();
    host = show(<SettingsScreen open onClose={() => {}} sections={sections} goTo={{ id: 'animations', nonce: 1 }} />);
    act(() => vi.advanceTimersToNextFrame());
    expect(host.querySelector('[data-found]')).toBeNull();
  });
});
