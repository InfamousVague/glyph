import { describe, expect, it } from 'vitest';
import { QuietWatch } from './quiet.ts';

/** Feeds `rms` five times a second from `from` to `to` ms. */
function hum(watch: QuietWatch, rms: number, from: number, to: number) {
  for (let t = from; t < to; t += 200) watch.level(rms, t);
}

describe('stop when I go quiet', () => {
  it('never stops before the first words, however quiet or loud it is', () => {
    const watch = new QuietWatch(4000);
    hum(watch, 0.005, 0, 3000);
    hum(watch, 0.2, 3000, 3400); // a door
    hum(watch, 0.005, 3400, 20_000);
    expect(watch.due(20_000)).toBe(false);
    expect(watch.remaining(20_000)).toBeNull();
  });

  it('stops four seconds after talking ends', () => {
    const watch = new QuietWatch(4000);
    hum(watch, 0.005, 0, 1000);
    hum(watch, 0.15, 1000, 5000); // talking
    watch.words(4200);
    hum(watch, 0.006, 5000, 12_000);
    expect(watch.due(8600)).toBe(false);
    expect(watch.due(9000)).toBe(true);
  });

  it('a steady fan is the floor, not talking', () => {
    const watch = new QuietWatch(4000);
    hum(watch, 0.15, 0, 3000);
    watch.words(3000);
    hum(watch, 0.03, 3000, 30_000); // the fan, after the voice stops
    expect(watch.due(30_000)).toBe(true);
  });

  it('late words keep it going', () => {
    const watch = new QuietWatch(4000);
    hum(watch, 0.15, 0, 2000);
    hum(watch, 0.005, 2000, 7000);
    watch.words(5500); // the recogniser catching up on what was said
    expect(watch.due(7000)).toBe(false);
    expect(watch.due(9600)).toBe(true);
  });
});
