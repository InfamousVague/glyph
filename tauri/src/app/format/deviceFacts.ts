import { useEffect, useState } from 'react';
import { watchBattery } from './battery.ts';

/**
 * What the page can read about the phone on its own, for the AI card: the
 * cores, the memory class the browser rounds to, and the battery. An older
 * binary reports nothing from the engine, and this still shows the phone.
 */

interface DeviceFacts {
  cores: number | null;
  /** The device memory class in gigabytes, as the browser rounds it. */
  memoryGb: number | null;
  battery: { level: number; charging: boolean } | null;
}

export function useDeviceFacts(): DeviceFacts {
  const [facts, setFacts] = useState<DeviceFacts>(() => ({
    cores: typeof navigator !== 'undefined' && navigator.hardwareConcurrency ? navigator.hardwareConcurrency : null,
    memoryGb: typeof navigator !== 'undefined' && 'deviceMemory' in navigator ? ((navigator as { deviceMemory?: number }).deviceMemory ?? null) : null,
    battery: null,
  }));

  useEffect(
    () =>
      watchBattery(({ charging, level }) => {
        // A battery that will not say is no reading at all, and nothing to draw again for.
        const battery = charging === null || level === null ? null : { level, charging };
        setFacts((previous) => (battery === null && previous.battery === null ? previous : { ...previous, battery }));
      }),
    [],
  );

  return facts;
}
