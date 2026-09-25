import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, useRef, type ReactElement } from 'react';
import { show, unmount } from '../../test/render.tsx';
import { layRowsOut, onGrip } from '../../test/rows.ts';
import { ROW_HOLD_MS, useRowDrag } from './rowDrag.ts';

/**
 * Rows dragged by their grip: a mouse lifts at once, a finger after a hold - and a finger that moves before the
 * hold is scrolling, not dragging. The row's new place comes back on release, and only when it changed.
 */

function Rows({ onMove }: { onMove: (from: number, to: number) => void }) {
  const els = useRef<(HTMLElement | null)[]>([]);
  const drag = useRowDrag(() => els.current, onMove);
  return (
    <ol>
      {['a', 'b', 'c', 'd'].map((name, i) => (
        <li
          key={name}
          ref={(el) => {
            els.current[i] = el;
          }}
          data-lifted={drag.lifted?.index === i || undefined}
          style={drag.rowStyle(i)}
        >
          <span data-grip={name} {...drag.grip(i)} />
          {name}
        </li>
      ))}
    </ol>
  );
}

/** The rows on the page, each 40px tall, one under another. */
function showRows(element: ReactElement): void {
  show(element);
  layRowsOut(document.querySelectorAll('li'));
}

afterEach(() => {
  // Unmounted before the real clock is back, so the tree's cleanup clears its timers on the fake clock that set them.
  unmount();
  vi.useRealTimers();
});

const grip = (name: string) => document.querySelector<HTMLElement>(`[data-grip="${name}"]`)!;

describe('rows dragged by their grip', () => {
  it('lifts at once under a mouse, follows it, and lands where it is let go', () => {
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    onGrip(grip('a'), 'pointerdown', 20);
    expect(document.querySelector('li[data-lifted]')?.textContent).toBe('a');
    onGrip(grip('a'), 'pointermove', 110);
    expect(document.querySelector('li[data-lifted]')?.getAttribute('style')).toContain('translateY(90px)');
    onGrip(grip('a'), 'pointerup', 110);
    expect(onMove).toHaveBeenCalledWith(0, 2);
    expect(document.querySelector('li[data-lifted]')).toBeNull();
  });

  it('under a finger, lifts only after the hold, and a move before it is a scroll', () => {
    vi.useFakeTimers();
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    onGrip(grip('b'), 'pointerdown', 60, 'touch');
    expect(document.querySelector('li[data-lifted]')).toBeNull();
    onGrip(grip('b'), 'pointermove', 90, 'touch');
    act(() => {
      vi.advanceTimersByTime(ROW_HOLD_MS + 10);
    });
    expect(document.querySelector('li[data-lifted]')).toBeNull();
    onGrip(grip('b'), 'pointerup', 90, 'touch');
    expect(onMove).not.toHaveBeenCalled();

    onGrip(grip('b'), 'pointerdown', 60, 'touch');
    act(() => {
      vi.advanceTimersByTime(ROW_HOLD_MS + 10);
    });
    expect(document.querySelector('li[data-lifted]')?.textContent).toBe('b');
    onGrip(grip('b'), 'pointermove', 10, 'touch');
    onGrip(grip('b'), 'pointerup', 10, 'touch');
    expect(onMove).toHaveBeenCalledWith(1, 0);
  });

  it('says nothing when a row is let go where it was', () => {
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    onGrip(grip('c'), 'pointerdown', 100);
    onGrip(grip('c'), 'pointermove', 104);
    onGrip(grip('c'), 'pointerup', 104);
    expect(onMove).not.toHaveBeenCalled();
  });

  it('makes room as a row goes by: the rows it passes move a row the other way', () => {
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    const styleOf = (name: string) => document.querySelector<HTMLElement>(`[data-grip="${name}"]`)!.closest('li')!.getAttribute('style') ?? '';
    // Down: a's middle (20) moved 130px is 150, past the middles of b, c and d, which each move up a row.
    onGrip(grip('a'), 'pointerdown', 20);
    onGrip(grip('a'), 'pointermove', 150);
    expect(['b', 'c', 'd'].map(styleOf).every((style) => style.includes('translateY(-40px)'))).toBe(true);
    onGrip(grip('a'), 'pointerup', 150);
    expect(onMove).toHaveBeenLastCalledWith(0, 3);
    // Up: d's middle (140) moved 130px is 10, above the middles of a, b and c, which each move down a row.
    onGrip(grip('d'), 'pointerdown', 140);
    onGrip(grip('d'), 'pointermove', 10);
    expect(['a', 'b', 'c'].map(styleOf).every((style) => style.includes('translateY(40px)'))).toBe(true);
    onGrip(grip('d'), 'pointerup', 10);
    expect(onMove).toHaveBeenLastCalledWith(3, 0);
  });

  it('lands past the last row as the last, and a cancelled drag moves nothing', () => {
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    onGrip(grip('b'), 'pointerdown', 60);
    onGrip(grip('b'), 'pointermove', 900);
    onGrip(grip('b'), 'pointerup', 900);
    expect(onMove).toHaveBeenCalledWith(1, 3);
    onMove.mockClear();
    onGrip(grip('b'), 'pointerdown', 60);
    onGrip(grip('b'), 'pointermove', 900);
    onGrip(grip('b'), 'pointercancel', 900);
    expect(onMove).not.toHaveBeenCalled();
    expect(document.querySelector('li[data-lifted]')).toBeNull();
  });
});
