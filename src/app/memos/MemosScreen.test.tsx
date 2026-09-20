import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import type { Note } from '../core/store.ts';
import { MemosScreen } from './MemosScreen.tsx';
import { memoBody } from './memo.ts';

// The wisp under the bar watches the page's size (art/wispEdge.ts); jsdom has no such watcher, and the test has no smoke to draw.
vi.stubGlobal(
  'ResizeObserver',
  class {
    observe() {}
    unobserve() {}
    disconnect() {}
  },
);

let root: Root | null = null;
let host: HTMLDivElement | null = null;

function show(element: React.ReactElement): HTMLDivElement {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
  act(() => root!.render(element));
  return host;
}

afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  root = null;
  host = null;
});

const memo = (id: string, text: string, updatedAt: number): Note => ({ id, body: memoBody(text), createdAt: updatedAt, updatedAt, source: 'editor' });

function type(el: HTMLTextAreaElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

describe('the memos on a wall', () => {
  it('shows every memo as a card with its words, and keeps a new one from the field on Enter', async () => {
    const onAdd = vi.fn(async () => undefined);
    const shown = show(<MemosScreen memos={[memo('a', 'Milk', 2), memo('b', 'Ask Sam\nabout the dog', 1)]} onBack={() => undefined} onAdd={onAdd} onChange={async () => undefined} onRemove={() => undefined} />);
    const cards = shown.querySelectorAll('ul li');
    expect(cards).toHaveLength(2);
    expect(cards[0]?.textContent).toContain('Milk');
    expect(cards[1]?.textContent).toContain('Ask Sam\nabout the dog');

    const field = shown.querySelector('textarea[aria-label="A new memo"]') as HTMLTextAreaElement;
    type(field, 'Eggs and coffee');
    await act(async () => {
      field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    });
    expect(onAdd).toHaveBeenCalledWith('Eggs and coffee');
    expect(field.value).toBe('');
    // Shift+Enter is a new line, not a keep; and nothing is kept of nothing.
    type(field, '   ');
    await act(async () => {
      field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    });
    expect(onAdd).toHaveBeenCalledTimes(1);
  });

  it('turns a tapped card into a field over its words, and Done keeps a change; emptied, the memo goes', async () => {
    const onChange = vi.fn(async () => undefined);
    const onRemove = vi.fn();
    const shown = show(<MemosScreen memos={[memo('a', 'Milk', 2)]} onBack={() => undefined} onAdd={async () => undefined} onChange={onChange} onRemove={onRemove} />);
    const card = shown.querySelector('ul li button') as HTMLButtonElement;
    act(() => card.click());
    const field = shown.querySelector('textarea[aria-label="This memo"]') as HTMLTextAreaElement;
    expect(field.value).toBe('Milk');
    type(field, 'Oat milk');
    const done = [...shown.querySelectorAll('button')].find((b) => b.textContent === 'Done') as HTMLButtonElement;
    await act(async () => done.click());
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ id: 'a' }), 'Oat milk');
    expect(shown.querySelector('textarea[aria-label="This memo"]')).toBeNull();

    act(() => (shown.querySelector('ul li button') as HTMLButtonElement).click());
    type(shown.querySelector('textarea[aria-label="This memo"]') as HTMLTextAreaElement, '');
    const doneAgain = [...shown.querySelectorAll('button')].find((b) => b.textContent === 'Done') as HTMLButtonElement;
    await act(async () => doneAgain.click());
    expect(onRemove).toHaveBeenCalledWith(expect.objectContaining({ id: 'a' }));
  });

  it('says so when there is nothing kept yet', () => {
    const shown = show(<MemosScreen memos={[]} onBack={() => undefined} onAdd={async () => undefined} onChange={async () => undefined} onRemove={() => undefined} />);
    expect(shown.textContent).toContain('Nothing kept yet');
  });
});
