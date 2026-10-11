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

  it('fills the cassette over a longer tape when told how long it is', () => {
    // Three minutes on a five-minute tape is over half wound; on an hour's tape it is a thin ring.
    const hour = 3_600_000;
    expect(packRadii(180_000).takeup).toBeGreaterThan((PACK_MIN_R + PACK_MAX_R) / 2);
    expect(packRadii(180_000, hour).takeup).toBeLessThan(PACK_MIN_R + 3);
    // The whole of the tape fills the right reel, whatever its length.
    expect(packRadii(hour, hour).takeup).toBeCloseTo(PACK_MAX_R);
    expect(packRadii(hour, hour).supply).toBeCloseTo(PACK_MIN_R);
    // Left unsaid, the length is the five-minute tape it always was.
    expect(packRadii(TAPE_MS, TAPE_MS)).toEqual(packRadii(TAPE_MS));
    // The reels turn over the radii the length gives: a nearly empty take-up reel turns fast.
    expect(reelTurn(180_000, 1000, hour).takeup).toBeGreaterThan(reelTurn(180_000, 1000).takeup);
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
