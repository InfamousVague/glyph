import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';
import { AccentSwatch } from './AccentSwatch.tsx';

/**
 * The accent swatch as a radio group: named for the finger that cannot see the colour, the chosen one ticked as well
 * as ringed, one tab stop, and the arrow keys stepping round - past the last back to the first.
 */

function swatch(accent: Parameters<typeof AccentSwatch>[0]['accent'] = 'ink') {
  const onAccent = vi.fn();
  const host = show(<AccentSwatch accent={accent} onAccent={onAccent} />);
  const dots = [...host.querySelectorAll<HTMLButtonElement>('[role="radio"]')];
  return { dots, onAccent };
}

const key = (el: HTMLElement, name: string) => {
  const event = new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true });
  act(() => {
    el.dispatchEvent(event);
  });
  return event;
};

describe('the accent swatch', () => {
  it('names every accent, ticks the chosen one, and is one stop for the Tab key', () => {
    const { dots } = swatch('teal');
    expect(dots.map((dot) => dot.getAttribute('aria-label'))).toEqual(['Ink', 'Graphite', 'Red', 'Amber', 'Green', 'Teal', 'Purple']);
    const chosen = dots.filter((dot) => dot.getAttribute('aria-checked') === 'true');
    expect(chosen.map((dot) => dot.getAttribute('aria-label'))).toEqual(['Teal']);
    expect(chosen[0]!.querySelector('svg')).not.toBeNull();
    expect(dots.filter((dot) => dot.tabIndex === 0)).toEqual(chosen);
    // Each dot is drawn in the ramp choosing it would put on the app; Ink is the page's own.
    expect(dots[5]!.dataset.accent).toBe('teal');
    expect(dots[0]!.hasAttribute('data-ink')).toBe(true);
  });

  it('chooses the one pressed', () => {
    const { dots, onAccent } = swatch();
    act(() => dots[2]!.click());
    expect(onAccent).toHaveBeenCalledWith('red');
  });

  it('steps with the arrows, round from the last to the first and back', () => {
    const last = swatch('purple');
    expect(key(last.dots[6]!, 'ArrowRight').defaultPrevented).toBe(true);
    expect(last.onAccent).toHaveBeenLastCalledWith('ink');
    const first = swatch('ink');
    key(first.dots[0]!, 'ArrowUp');
    expect(first.onAccent).toHaveBeenLastCalledWith('purple');
    key(first.dots[0]!, 'ArrowDown');
    expect(first.onAccent).toHaveBeenLastCalledWith('graphite');
    // Any other key is the page's.
    expect(key(first.dots[0]!, 'Enter').defaultPrevented).toBe(false);
  });
});
