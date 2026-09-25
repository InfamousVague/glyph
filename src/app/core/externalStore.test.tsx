import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { renderToString } from 'react-dom/server';
import { externalStore, type ExternalStore } from './externalStore.ts';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | null = null;
let host: HTMLDivElement | null = null;
afterEach(() => {
  if (root) act(() => root!.unmount());
  host?.remove();
  root = null;
  host = null;
});

function show(store: ExternalStore<string>): HTMLDivElement {
  function Shows() {
    return <span>{store.use()}</span>;
  }
  host = document.createElement('div');
  document.body.append(host);
  root = createRoot(host);
  act(() => root!.render(<Shows />));
  return host;
}

describe('a store outside React', () => {
  it('tells its listeners when the value changes, and not when it is set to what it was', () => {
    const store = externalStore({ n: 1 });
    const heard = vi.fn();
    const stop = store.subscribe(heard);
    const same = store.get();
    store.set(same);
    expect(heard).not.toHaveBeenCalled();
    store.update((was) => ({ n: was.n + 1 }));
    expect(store.get()).toEqual({ n: 2 });
    expect(heard).toHaveBeenCalledTimes(1);
    stop();
    store.set({ n: 3 });
    expect(heard).toHaveBeenCalledTimes(1);
  });

  it('renders a component again when it changes', () => {
    const store = externalStore('first');
    const shown = show(store);
    expect(shown.textContent).toBe('first');
    act(() => store.set('second'));
    expect(shown.textContent).toBe('second');
  });

  it('answers a render with no client from the snapshot it was given, and has none when given none', () => {
    const withServer = externalStore('live', { server: () => 'server' });
    const without = externalStore('live');
    function Shows({ store }: { store: ExternalStore<string> }) {
      return <span>{store.use()}</span>;
    }
    expect(renderToString(<Shows store={withServer} />)).toBe('<span>server</span>');
    expect(() => renderToString(<Shows store={without} />)).toThrow(/getServerSnapshot/);
  });
});
