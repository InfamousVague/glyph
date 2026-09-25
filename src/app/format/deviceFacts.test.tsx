import { afterEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';
import { fakeBattery } from '../../test/battery.ts';
import { useDeviceFacts } from './deviceFacts.ts';

const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

/** The card's facts, as a component using the hook sees them on its latest render. */
function mounted(): { current: ReturnType<typeof useDeviceFacts> | null } {
  const seen: { current: ReturnType<typeof useDeviceFacts> | null } = { current: null };
  function Card() {
    seen.current = useDeviceFacts();
    return null;
  }
  show(<Card />);
  return seen;
}

describe('the phone as the AI card reads it', () => {
  afterEach(() => {
    delete (navigator as { getBattery?: unknown }).getBattery;
  });

  it('follows the battery as it drains and is plugged in', async () => {
    const battery = fakeBattery(false, 0.8);
    Object.defineProperty(navigator, 'getBattery', { configurable: true, value: () => Promise.resolve(battery) });
    const seen = mounted();
    expect(seen.current?.battery).toBeNull();
    await act(tick);
    expect(seen.current?.battery).toEqual({ level: 0.8, charging: false });
    act(() => battery.drain(0.3));
    act(() => battery.plug(true));
    expect(seen.current?.battery).toEqual({ level: 0.3, charging: true });
  });

  it('leaves the battery out where the phone will not say, or will not be read', async () => {
    const seen = mounted();
    await act(tick);
    expect(seen.current?.battery).toBeNull();
    Object.defineProperty(navigator, 'getBattery', { configurable: true, value: () => Promise.reject(new Error('not allowed')) });
    const refused = mounted();
    await act(tick);
    expect(refused.current?.battery).toBeNull();
  });

  it('reads the cores the browser reports', () => {
    expect(mounted().current?.cores).toBe(navigator.hardwareConcurrency || null);
  });
});
