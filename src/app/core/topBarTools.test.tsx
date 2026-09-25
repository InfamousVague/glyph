import { act } from 'react';
import { describe, expect, it } from 'vitest';
import { show } from '../../test/render.tsx';
import { setTopBarTools, useTopBarTools } from './topBarTools.ts';

/*
 * The top bar's one slot for a screen's controls (topBarTools.ts): a screen asks for it, draws into it while the bar
 * is there, and draws its controls where it always did when there is no bar.
 */

let slot: HTMLElement | null | undefined;
function Screen() {
  slot = useTopBarTools();
  return null;
}

describe('the top bar’s slot', () => {
  it('is nothing before the bar is up, the slot while it is, and nothing again once it goes', () => {
    show(<Screen />);
    expect(slot).toBeNull();
    const bar = document.createElement('div');
    act(() => setTopBarTools(bar));
    expect(slot).toBe(bar);
    act(() => setTopBarTools(null));
    expect(slot).toBeNull();
  });
});
