/**
 * The phone's battery, live, from the browser's Battery API: whether it is on
 * charge and how full it is, for the AI card's Battery reading
 * (format/deviceFacts.ts, format/AiCard.tsx).
 *
 * The API is there in Android's WebView and in Chrome; where it isn't
 * (Safari, a browser that hides it, jsdom), the state is unknown and the card
 * leaves the reading out rather than guessing. The source is injectable, so a
 * test can plug the phone in.
 *
 * A source that refuses to be read (a permissions policy can) is unknown the
 * same way. This was guide/charging.ts, written for the guide's heads-up
 * page, which has gone.
 */

export interface BatteryState {
  /** On charge, off charge, or null when the phone won't say. */
  charging: boolean | null;
  /** 0 to 1, or null. */
  level: number | null;
}

/** The slice of the Battery API this uses. */
export interface BatteryLike {
  charging: boolean;
  level: number;
  addEventListener(type: 'chargingchange' | 'levelchange', listener: () => void): void;
  removeEventListener(type: 'chargingchange' | 'levelchange', listener: () => void): void;
}

type GetBattery = () => Promise<BatteryLike>;

/** The page's battery source, or null where there is none. */
export function batterySource(): GetBattery | null {
  if (typeof navigator === 'undefined') return null;
  const getBattery = (navigator as Navigator & { getBattery?: GetBattery }).getBattery;
  return typeof getBattery === 'function' ? getBattery.bind(navigator) : null;
}

export const UNKNOWN: BatteryState = { charging: null, level: null };

/**
 * Tells `listener` the battery's state now and whenever it changes. Answers
 * the way to stop listening. With no source, or one that fails, the listener
 * hears `UNKNOWN` once and nothing more.
 */
export function watchBattery(listener: (state: BatteryState) => void, source: GetBattery | null = batterySource()): () => void {
  if (!source) {
    listener(UNKNOWN);
    return () => undefined;
  }
  let battery: BatteryLike | null = null;
  let stopped = false;
  const tell = () => {
    if (battery && !stopped) listener({ charging: battery.charging, level: battery.level });
  };
  source()
    .then((found) => {
      if (stopped) return;
      battery = found;
      battery.addEventListener('chargingchange', tell);
      battery.addEventListener('levelchange', tell);
      tell();
    })
    .catch(() => {
      if (!stopped) listener(UNKNOWN);
    });
  return () => {
    stopped = true;
    battery?.removeEventListener('chargingchange', tell);
    battery?.removeEventListener('levelchange', tell);
  };
}
