import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';
import { useRedraw } from './useRedraw.ts';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

/** A truth React does not hold, as the find bar's count lives in the editor's state. */
let outside = 'first';
const seen: Array<() => void> = [];

function Mirror() {
  const redraw = useRedraw();
  seen.push(redraw);
  return <span>{outside}</span>;
}

describe('a render on demand', () => {
  const host = document.createElement('div');
  const root = createRoot(host);

  afterEach(() => {
    act(() => root.unmount());
    host.remove();
  });

  it('draws again when asked, reading the truth where it lives, with the same function every time', () => {
    document.body.append(host);
    act(() => root.render(<Mirror />));
    expect(host.textContent).toBe('first');

    outside = 'second';
    // Nothing React can see changed, so nothing is drawn until it is asked for.
    expect(host.textContent).toBe('first');
    act(() => seen[0]!());
    expect(host.textContent).toBe('second');

    outside = 'third';
    act(() => seen.at(-1)!());
    expect(host.textContent).toBe('third');
    expect(seen.length).toBe(3);
    expect(new Set(seen).size).toBe(1);
  });
});
