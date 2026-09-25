import { describe, expect, it } from 'vitest';
import { show } from '../../test/render.tsx';
import { pitchRadius, toothPhase } from './gears.ts';
import { WorkingGears } from './WorkingGears.tsx';

/**
 * The update card's three cogs, read back from what is drawn: each placed a pitch apart from the one driving it, at
 * the angle that puts a tooth of one in a gap of the other, and turning the other way at the ratio of their teeth.
 * The teeth and the module are the component's own design (WorkingGears.tsx), written down again here as what the
 * drawing has to agree with.
 */

const MODULE = 1.9;
const TEETH = [13, 9, 7];

interface Cog {
  x: number;
  y: number;
  /** Its starting angle, radians. */
  angle: number;
  /** One turn, in seconds, and which way. */
  seconds: number;
  way: number;
}

function cogs(): Cog[] {
  const host = show(<WorkingGears label="Downloading" />);
  return [...host.querySelectorAll<SVGGElement>('g')].map((g) => {
    const at = /translate\(([-\d.e]+)px, ([-\d.e]+)px\)/.exec(g.style.transform);
    const from = parseFloat(g.style.getPropertyValue('--from'));
    const to = parseFloat(g.style.getPropertyValue('--to'));
    return { x: Number(at?.[1]), y: Number(at?.[2]), angle: (from / 360) * Math.PI * 2, seconds: parseFloat(g.style.getPropertyValue('--turn')), way: Math.sign(to - from) };
  });
}

describe('the working cogs', () => {
  it('are one picture, named for what is happening', () => {
    const host = show(<WorkingGears label="Downloading" />);
    expect(host.querySelector('[role="img"]')?.getAttribute('aria-label')).toBe('Downloading');
    expect(host.querySelectorAll('path')).toHaveLength(3);
  });

  it('sit a pitch apart and mesh, each with the one that drives it', () => {
    const drawn = cogs();
    expect(drawn).toHaveLength(3);
    for (const i of [1, 2]) {
      const driver = drawn[i - 1]!;
      const driven = drawn[i]!;
      const direction = Math.atan2(driven.y - driver.y, driven.x - driver.x);
      expect(Math.hypot(driven.x - driver.x, driven.y - driver.y)).toBeCloseTo(pitchRadius(TEETH[i - 1]!, MODULE) + pitchRadius(TEETH[i]!, MODULE), 6);
      const sum = toothPhase(TEETH[i - 1]!, driver.angle, direction) + toothPhase(TEETH[i]!, driven.angle, direction + Math.PI);
      // A tooth of one faces a gap of the other: the phases add up to a half, to the two places the angle is written in.
      expect(Math.abs(sum - Math.floor(sum) - 0.5)).toBeLessThan(1e-3);
    }
  });

  it('turn the other way from their driver, faster by the ratio of their teeth', () => {
    const drawn = cogs();
    for (const i of [1, 2]) {
      expect(drawn[i]!.way).toBe(-drawn[i - 1]!.way);
      // Rounded to the hundredth of a second the stylesheet is given.
      expect(drawn[i]!.seconds).toBeCloseTo((drawn[0]!.seconds * TEETH[i]!) / TEETH[0]!, 1);
    }
  });
});
