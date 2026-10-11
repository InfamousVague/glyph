import type { BatteryLike } from '../app/format/battery.ts';

/**
 * A phone battery a test can drain and plug in: the slice of the Battery API that format/battery.ts watches, with
 * its events fired by hand. jsdom has no `navigator.getBattery`, so a test that wants a battery hands this over as
 * the source, or defines `getBattery` on the navigator to answer it.
 */
export function fakeBattery(charging: boolean, level = 0.5): BatteryLike & { plug(on: boolean): void; drain(to: number): void } {
  const listeners = new Set<() => void>();
  const battery = {
    charging,
    level,
    addEventListener: (_type: 'chargingchange' | 'levelchange', listener: () => void) => listeners.add(listener),
    removeEventListener: (_type: 'chargingchange' | 'levelchange', listener: () => void) => listeners.delete(listener),
    plug(on: boolean) {
      battery.charging = on;
      listeners.forEach((listener) => listener());
    },
    drain(to: number) {
      battery.level = to;
      listeners.forEach((listener) => listener());
    },
  };
  return battery;
}
