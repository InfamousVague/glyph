import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

// The split view is the sidebar's line; each test says which side of it the window is.
let wide = false;
vi.mock('../core/useWideScreen.ts', () => ({ useSidebar: () => wide }));
vi.mock('../art/wispEdge.ts', () => ({ useWispEdge: () => undefined }));

const { SettingsScreen } = await import('./SettingsScreen.tsx');
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

let root: Root;
let host: HTMLDivElement;

beforeEach(() => {
  host = document.createElement('div');
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.useRealTimers();
});

function render(onClose = () => {}) {
  act(() => root.render(<SettingsScreen open onClose={onClose} sections={sections} />));
}

function type(words: string) {
  const field = host.querySelector<HTMLInputElement>('input[type="search"]')!;
  const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    set.call(field, words);
    field.dispatchEvent(new Event('input', { bubbles: true }));
  });
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
