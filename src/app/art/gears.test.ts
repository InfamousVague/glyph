import { describe, expect, it } from 'vitest';
import { outsidePhase, spurPath, toothPhase } from './gears.ts';

/** How far a phase sum may be from a half before the teeth would show crossing: well under a hundredth of a tooth. */
const NEAR = 1e-6;

/** Distance around the unit circle from `value`'s fraction to a half. */
const offHalf = (value: number) => Math.abs(value - Math.floor(value) - 0.5);

describe('two gears meshing', () => {
  it('keeps a tooth of one in a gap of the other as they turn at their rolling speeds', () => {
    const teethA = 30;
    const teethB = 12;
    const direction = 0.83;
    const a = { phase: 0.4, omega: 0.7 };
    const b = { phase: outsidePhase(teethA, a.phase, direction, teethB), omega: (-a.omega * teethA) / teethB };
    for (let t = 0; t < 40; t += 0.37) {
      const sum = toothPhase(teethA, a.phase + a.omega * t, direction) + toothPhase(teethB, b.phase + b.omega * t, direction + Math.PI);
      expect(offHalf(sum)).toBeLessThan(NEAR);
    }
  });

  it('would cross their teeth without the meshing angle, so the check above can fail', () => {
    // The same pair with the second gear simply at zero: a tooth of each points at the other.
    expect(offHalf(toothPhase(30, 0.4, 0.83) + toothPhase(12, 0, 0.83 + Math.PI))).toBeGreaterThan(0.01);
  });
});

describe('a spur gear', () => {
  it('draws a tip arc and a root arc for each tooth, then its hub', () => {
    const arcs = (path: string) => path.match(/ A /g)?.length ?? 0;
    expect(arcs(spurPath(16, 4, 'plain'))).toBeGreaterThanOrEqual(32);
    // The hub is cut after the teeth: more holes, more arcs, the same teeth.
    expect(arcs(spurPath(24, 4, 'holes'))).toBeGreaterThan(arcs(spurPath(24, 4, 'plain')));
    expect(spurPath(24, 4, 'spokes').match(/Z/g)!.length).toBeGreaterThan(2);
  });
});
