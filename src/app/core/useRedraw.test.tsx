import { act } from 'react';
import { describe, expect, it } from 'vitest';
import { show } from '../../test/render.tsx';
import { useRedraw } from './useRedraw.ts';

/** A truth React does not hold, as the find bar's count lives in the editor's state. */
let outside = 'first';
const seen: Array<() => void> = [];

function Mirror() {
  const redraw = useRedraw();
  seen.push(redraw);
  return <span>{outside}</span>;
}

describe('a render on demand', () => {
  it('draws again when asked, reading the truth where it lives, with the same function every time', () => {
    const host = show(<Mirror />);
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
