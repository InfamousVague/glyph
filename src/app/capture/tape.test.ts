import { describe, expect, it } from 'vitest';
import { PACK_MAX_R, PACK_MIN_R, TAPE_MS, counter, packRadii, reelTurn } from './tape.ts';

describe('the tape', () => {
  it('starts full on the left and ends full on the right, conserving tape', () => {
    expect(packRadii(0)).toEqual({ supply: PACK_MAX_R, takeup: PACK_MIN_R });
    const end = packRadii(TAPE_MS * 2);
    expect(end.supply).toBeCloseTo(PACK_MIN_R);
    expect(end.takeup).toBeCloseTo(PACK_MAX_R);
    const mid = packRadii(TAPE_MS / 3);
    expect(mid.supply ** 2 + mid.takeup ** 2).toBeCloseTo(PACK_MAX_R ** 2 + PACK_MIN_R ** 2);
  });

  it('turns the smaller pack faster for the same tape', () => {
    const early = reelTurn(0, 1000);
    expect(early.takeup).toBeGreaterThan(early.supply);
    const late = reelTurn(TAPE_MS, 1000);
    expect(late.supply).toBeGreaterThan(late.takeup);
  });

  it('reads like a tape counter', () => {
    expect(counter(0)).toBe('0:00');
    expect(counter(7_900)).toBe('0:07');
    expect(counter(760_000)).toBe('12:40');
    expect(counter(3_723_000)).toBe('1:02:03');
  });
});
