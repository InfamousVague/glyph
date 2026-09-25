import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, useRef, type ReactElement } from 'react';
import { show, unmount } from '../../test/render.tsx';
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

/** jsdom lays nothing out: every row is 40px tall, one under another. */
function layRowsOut(): void {
  document.querySelectorAll('li').forEach((li, i) => {
    li.getBoundingClientRect = () => ({ top: i * 40, bottom: i * 40 + 40, height: 40, left: 0, right: 100, width: 100, x: 0, y: i * 40, toJSON: () => ({}) }) as DOMRect;
  });
  if (!Element.prototype.setPointerCapture) Element.prototype.setPointerCapture = () => undefined;
}

/** The rows on the page, laid out. */
function showRows(element: ReactElement): void {
  show(element);
  layRowsOut();
}

afterEach(() => {
  // Unmounted before the real clock is back, so the tree's cleanup clears its timers on the fake clock that set them.
  unmount();
  vi.useRealTimers();
});

const grip = (name: string) => document.querySelector<HTMLElement>(`[data-grip="${name}"]`)!;
const pointer = (type: string, target: HTMLElement, clientY: number, pointerType = 'mouse') =>
  act(() => {
    target.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, clientY, button: 0 }), { pointerId: 1, pointerType }));
  });

describe('rows dragged by their grip', () => {
  it('lifts at once under a mouse, follows it, and lands where it is let go', () => {
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    pointer('pointerdown', grip('a'), 20);
    expect(document.querySelector('li[data-lifted]')?.textContent).toBe('a');
    pointer('pointermove', grip('a'), 110);
    expect(document.querySelector('li[data-lifted]')?.getAttribute('style')).toContain('translateY(90px)');
    pointer('pointerup', grip('a'), 110);
    expect(onMove).toHaveBeenCalledWith(0, 2);
    expect(document.querySelector('li[data-lifted]')).toBeNull();
  });

  it('under a finger, lifts only after the hold, and a move before it is a scroll', () => {
    vi.useFakeTimers();
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    pointer('pointerdown', grip('b'), 60, 'touch');
    expect(document.querySelector('li[data-lifted]')).toBeNull();
    pointer('pointermove', grip('b'), 90, 'touch');
    act(() => {
      vi.advanceTimersByTime(ROW_HOLD_MS + 10);
    });
    expect(document.querySelector('li[data-lifted]')).toBeNull();
    pointer('pointerup', grip('b'), 90, 'touch');
    expect(onMove).not.toHaveBeenCalled();

    pointer('pointerdown', grip('b'), 60, 'touch');
    act(() => {
      vi.advanceTimersByTime(ROW_HOLD_MS + 10);
    });
    expect(document.querySelector('li[data-lifted]')?.textContent).toBe('b');
    pointer('pointermove', grip('b'), 10, 'touch');
    pointer('pointerup', grip('b'), 10, 'touch');
    expect(onMove).toHaveBeenCalledWith(1, 0);
  });

  it('says nothing when a row is let go where it was', () => {
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    pointer('pointerdown', grip('c'), 100);
    pointer('pointermove', grip('c'), 104);
    pointer('pointerup', grip('c'), 104);
    expect(onMove).not.toHaveBeenCalled();
    // Nudged up as far, it is still over its own place: it moves up only once it is past the middle of the row above.
    pointer('pointerdown', grip('c'), 100);
    pointer('pointermove', grip('c'), 96);
    expect(document.querySelector('li[data-lifted]')?.previousElementSibling?.getAttribute('style') ?? '').not.toContain('translateY');
    pointer('pointerup', grip('c'), 96);
    expect(onMove).not.toHaveBeenCalled();
    pointer('pointerdown', grip('c'), 100);
    pointer('pointermove', grip('c'), 50);
    pointer('pointerup', grip('c'), 50);
    expect(onMove).toHaveBeenCalledWith(2, 1);
  });

  it('makes room as a row goes by: the rows it passes move a row the other way', () => {
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    const styleOf = (name: string) => document.querySelector<HTMLElement>(`[data-grip="${name}"]`)!.closest('li')!.getAttribute('style') ?? '';
    // Down: a's middle (20) moved 130px is 150, past the middles of b, c and d, which each move up a row.
    pointer('pointerdown', grip('a'), 20);
    pointer('pointermove', grip('a'), 150);
    expect(['b', 'c', 'd'].map(styleOf).every((style) => style.includes('translateY(-40px)'))).toBe(true);
    pointer('pointerup', grip('a'), 150);
    expect(onMove).toHaveBeenLastCalledWith(0, 3);
    // Up: d over b's middle, so b and c move down a row and a stays.
    pointer('pointerdown', grip('d'), 140);
    pointer('pointermove', grip('d'), 50);
    expect(styleOf('b')).toContain('translateY(40px)');
    expect(styleOf('c')).toContain('translateY(40px)');
    expect(styleOf('a')).not.toContain('translateY');
    pointer('pointerup', grip('d'), 50);
    expect(onMove).toHaveBeenLastCalledWith(3, 1);
  });

  it('lands past the last row as the last, and a cancelled drag moves nothing', () => {
    const onMove = vi.fn();
    showRows(<Rows onMove={onMove} />);
    pointer('pointerdown', grip('b'), 60);
    pointer('pointermove', grip('b'), 900);
    pointer('pointerup', grip('b'), 900);
    expect(onMove).toHaveBeenCalledWith(1, 3);
    onMove.mockClear();
    pointer('pointerdown', grip('b'), 60);
    pointer('pointermove', grip('b'), 900);
    pointer('pointercancel', grip('b'), 900);
    expect(onMove).not.toHaveBeenCalled();
    expect(document.querySelector('li[data-lifted]')).toBeNull();
  });
});
