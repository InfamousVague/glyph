import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useRef } from 'react';
import { show } from '../../test/render.tsx';
import { useSheetDrag } from './sheetDrag.ts';

/**
 * A sheet taken by its handle: pulled down it follows the finger, and let go far enough down - or flicked - it closes;
 * pulled up it gives a little and never far; let go short, it springs back. Every bottom sheet's grip is this.
 */

function Panel({ onClose }: { onClose: () => void }) {
  const panel = useRef<HTMLElement>(null);
  const drag = useSheetDrag(panel, onClose);
  return (
    <section ref={panel} data-panel="">
      <span data-grip="" {...drag} />
    </section>
  );
}

let now = 0;
const panel = () => document.querySelector<HTMLElement>('[data-panel]')!;
const grip = () => document.querySelector<HTMLElement>('[data-grip]')!;
/** A pointer event on the grip, `ms` after the last one. */
const pointer = (type: string, clientY: number, ms = 16, isPrimary = true) =>
  act(() => {
    now += ms;
    grip().dispatchEvent(new PointerEvent(type, { bubbles: true, clientY, pointerId: 1, isPrimary }));
  });
/** How far down the panel is drawn now, in pixels. */
const offset = () => {
  const moved = /translateY\((-?[\d.]+)px\)/.exec(panel().style.transform);
  return moved ? Number(moved[1]) : 0;
};

beforeEach(() => {
  now = 0;
  vi.spyOn(performance, 'now').mockImplementation(() => now);
  // jsdom does not capture pointers; the grip asks it to, and asks whether it has.
  Element.prototype.setPointerCapture = () => undefined;
  Element.prototype.releasePointerCapture = () => undefined;
  Element.prototype.hasPointerCapture = () => true;
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("a sheet's handle", () => {
  it('follows the finger down, and closes when let go past 96 px', () => {
    const onClose = vi.fn();
    show(<Panel onClose={onClose} />);
    pointer('pointerdown', 100);
    pointer('pointermove', 150, 200);
    expect(offset()).toBe(50);
    pointer('pointermove', 200, 200);
    pointer('pointerup', 200, 200);
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(panel().style.transform).toBe('');
  });

  it('springs back when let go short of it, slowly', () => {
    const onClose = vi.fn();
    show(<Panel onClose={onClose} />);
    pointer('pointerdown', 100);
    pointer('pointermove', 160, 400);
    pointer('pointerup', 160, 400);
    expect(onClose).not.toHaveBeenCalled();
    expect(panel().style.transform).toBe('');
    expect(panel().style.transition).toContain('transform');
  });

  it('closes on a flick that ends fast, though it covered little ground', () => {
    const onClose = vi.fn();
    show(<Panel onClose={onClose} />);
    pointer('pointerdown', 100);
    pointer('pointermove', 110, 300);
    // 30 px in the last 20 ms: 1.5 px/ms, three times what a flick needs.
    pointer('pointerup', 140, 20);
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('does not close on a quick nudge of under 24 px', () => {
    const onClose = vi.fn();
    show(<Panel onClose={onClose} />);
    pointer('pointerdown', 100);
    pointer('pointerup', 120, 5);
    expect(onClose).not.toHaveBeenCalled();
  });

  it('gives when pulled up, less and less, and never as far as 28 px', () => {
    show(<Panel onClose={() => {}} />);
    pointer('pointerdown', 300);
    pointer('pointermove', 280);
    const little = offset();
    pointer('pointermove', 0);
    const far = offset();
    expect(little).toBeLessThan(0);
    expect(far).toBeLessThan(little);
    expect(far).toBeGreaterThan(-28);
  });

  it('ignores a second finger', () => {
    const onClose = vi.fn();
    show(<Panel onClose={onClose} />);
    pointer('pointerdown', 100, 16, false);
    pointer('pointermove', 300);
    pointer('pointerup', 300);
    expect(offset()).toBe(0);
    expect(onClose).not.toHaveBeenCalled();
  });
});
