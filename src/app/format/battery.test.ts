import { describe, expect, it } from 'vitest';
import { fakeBattery } from '../../test/battery.ts';
import { UNKNOWN, watchBattery } from './battery.ts';

const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('watching the battery', () => {
  it('says now, and again when the phone is plugged in or unplugged', async () => {
    const battery = fakeBattery(false, 0.4);
    const heard: (boolean | null)[] = [];
    const stop = watchBattery((state) => heard.push(state.charging), () => Promise.resolve(battery));
    await tick();
    battery.plug(true);
    battery.plug(false);
    stop();
    battery.plug(true);
    expect(heard).toEqual([false, true, false]);
  });

  it('answers unknown where the phone will not say', () => {
    const heard: unknown[] = [];
    watchBattery((state) => heard.push(state), null);
    expect(heard).toEqual([UNKNOWN]);
  });

  it('answers unknown when the battery cannot be read', async () => {
    const heard: unknown[] = [];
    watchBattery((state) => heard.push(state), () => Promise.reject(new Error('no')));
    await tick();
    expect(heard).toEqual([UNKNOWN]);
  });
});
