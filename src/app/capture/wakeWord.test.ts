import { describe, expect, it } from 'vitest';
import { WakePacer, VOICE } from './wakeWord.ts';

describe('listening for the keyword while Glyph is open', () => {
  it('waits in quiet, and a single loud blip is not speech', () => {
    const pacer = new WakePacer();
    expect(pacer.step(0.02)).toBe('idle');
    expect(pacer.step(0.5)).toBe('idle');
    expect(pacer.step(0.02)).toBe('idle');
  });

  it('starts hearing after 400 ms of voice, and drops the speech after 1.2 s of quiet', () => {
    const pacer = new WakePacer();
    expect(pacer.step(VOICE)).toBe('idle');
    expect(pacer.step(0.4)).toBe('start');
    for (let i = 0; i < 5; i += 1) expect(pacer.step(0.01)).toBe('hearing');
    expect(pacer.step(0.01)).toBe('drop');
    expect(pacer.hearing).toBe(false);
  });

  it('never hears one stretch for longer than 7 seconds', () => {
    const pacer = new WakePacer();
    pacer.step(0.5);
    pacer.step(0.5);
    const steps = Array.from({ length: 40 }, () => pacer.step(0.5));
    expect(steps.indexOf('drop')).toBe(32);
  });
});
