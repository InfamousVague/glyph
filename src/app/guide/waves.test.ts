import { describe, expect, it } from 'vitest';
import { grown, paceWaves, REST_GAP_MS, REST_LIFE_MS, shining, wobbleAt, type Pacer } from './waves.ts';

describe('the rings from the side key', () => {
  it('keep a slow resting beat, one faint ring at a time', () => {
    const pacer: Pacer = { lastAt: -Infinity };
    const first = paceWaves(pacer, 0, 1);
    expect(first).toMatchObject({ born: 0, life: REST_LIFE_MS, reach: 1, alpha: 0.55, width: 1.5, seed: 1 });
    expect(paceWaves(pacer, REST_GAP_MS - 1)).toBeNull();
    expect(paceWaves(pacer, REST_GAP_MS)).not.toBeNull();
    // Frame by frame for three seconds: a ring every gap, and no more.
    const steady: Pacer = { lastAt: -Infinity };
    let sent = 0;
    for (let now = 0; now < 3000; now += 16) if (paceWaves(steady, now)) sent += 1;
    expect(sent).toBe(Math.ceil(3000 / REST_GAP_MS));
  });

  it('grow quickly then slowly, and shine then fade, within 0 and 1', () => {
    expect(grown(0)).toBe(0);
    expect(grown(1)).toBe(1);
    expect(grown(0.3)).toBeGreaterThan(0.5);
    expect(shining(0)).toBe(0);
    expect(shining(0.12)).toBeCloseTo(1, 5);
    expect(shining(1)).toBeCloseTo(0, 5);
    expect(shining(2)).toBeCloseTo(0, 5);
  });

  it('wobble within a bound, and never the same twice round', () => {
    for (let theta = 0; theta < Math.PI * 2; theta += 0.05) {
      const w = wobbleAt(theta, 1.5, 0.7);
      expect(Math.abs(w)).toBeLessThanOrEqual(1);
    }
    expect(wobbleAt(0.4, 1, 0.7)).not.toBe(wobbleAt(0.4, 1, 2.1));
    expect(wobbleAt(0.4, 1, 0.7)).not.toBe(wobbleAt(0.4, 2, 0.7));
  });
});
