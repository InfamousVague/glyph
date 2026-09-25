import { useEffect, useState } from 'react';
import { readStoredText, writeStoredText } from '../core/stored.ts';
import { invoke, isTauri } from '../core/tauri.ts';
import { deviceMaker } from '../guide/assistant.ts';

/**
 * Where the side key is, on the screen, so the recorder can send its waves
 * from it.
 *
 * Android has no API for where a phone's buttons are, so this is a small
 * table of what is known and a guess for the rest, with a Developer setting
 * to move it. The key is always on a long edge; which edge of the SCREEN that
 * is depends on how the phone is turned, and `screen.orientation.angle` says.
 */

export type Edge = 'top' | 'right' | 'bottom' | 'left';

/** A point on the screen's edge: which edge, and how far along it (0 at the top or left). */
export interface Spot {
  edge: Edge;
  along: number;
}

const KEY = 'glyph-side-key';

/**
 * How far down the phone's right edge the key sits, from its top, for the
 * phones that are known. Samsung model codes: SM-F9 is the Fold line, SM-F7
 * the Flip, SM-S9 the S series. Fractions of the frame's height, measured off
 * product photos: close enough for a ripple, and the Developer setting is
 * there for the rest.
 */
export function knownHeight(phone: string | null | undefined, maker: string | null | undefined): number {
  const model = (phone ?? '').toUpperCase();
  if (model.startsWith('SM-F9')) return 0.47; // Fold: volume above, the key with the fingerprint reader below it
  if (model.startsWith('SM-F7')) return 0.3; // Flip, upper half
  if (model.startsWith('SM-S9') || model.startsWith('SM-A')) return 0.4;
  if ((maker ?? '').toLowerCase() === 'google') return 0.3; // Pixel: power above volume
  return 0.4;
}

/** The Developer setting's height, if one was set. */
export function savedHeight(): number | null {
  const raw = readStoredText(KEY);
  const value = raw === null ? NaN : Number(raw);
  return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : null;
}

/** In a private window or with storage blocked, the setting just does not stick. */
export function saveHeight(value: number | null): void {
  writeStoredText(KEY, value === null ? null : String(Math.min(1, Math.max(0, value))));
}

/**
 * The key's spot on the screen for a phone whose key is `height` of the way
 * down its right edge, turned `angle` degrees (screen.orientation.angle: 90
 * when the top of the phone is to the left, 270 when it is to the right).
 */
export function spotOnScreen(height: number, angle: number): Spot {
  switch (((angle % 360) + 360) % 360) {
    case 90:
      return { edge: 'top', along: height };
    case 180:
      return { edge: 'left', along: 1 - height };
    case 270:
      return { edge: 'bottom', along: 1 - height };
    default:
      return { edge: 'right', along: height };
  }
}

/** The spot as coordinates, just outside the edge so the rings rise from the frame. */
export function origin(spot: Spot, width: number, height: number, outset = 12): { x: number; y: number } {
  switch (spot.edge) {
    case 'top':
      return { x: spot.along * width, y: -outset };
    case 'bottom':
      return { x: spot.along * width, y: height + outset };
    case 'left':
      return { x: -outset, y: spot.along * height };
    default:
      return { x: width + outset, y: spot.along * height };
  }
}

// ---- the hook ------------------------------------------------------------------------------

interface Phone {
  phone: string | null;
  maker: string | null;
}

let phoneLookup: Promise<Phone> | null = null;

/** The phone's model code, asked of Rust once (`ai_device`, generation 11); nothing in a browser. */
function whichPhone(): Promise<Phone> {
  phoneLookup ??= (async () => {
    const maker = deviceMaker() || null;
    if (!isTauri()) return { phone: null, maker };
    try {
      const device = await invoke<{ phone?: string | null }>('ai_device');
      return { phone: device.phone ?? null, maker };
    } catch {
      return { phone: null, maker };
    }
  })();
  return phoneLookup;
}

function angleNow(): number {
  try {
    return screen.orientation?.angle ?? 0;
  } catch {
    return 0;
  }
}

/**
 * How far down its edge the side key is on this phone (the Developer
 * setting's answer, or the table's), and the spot on the screen as the phone
 * is turned right now. `override` shows a height being dragged in Settings.
 */
export function useSideKeySpot(override?: number): Spot {
  const [known, setKnown] = useState(() => savedHeight() ?? knownHeight(null, null));
  const [angle, setAngle] = useState(angleNow);

  useEffect(() => {
    let live = true;
    void whichPhone().then(({ phone, maker }) => {
      if (live) setKnown(savedHeight() ?? knownHeight(phone, maker));
    });
    const turned = () => setAngle(angleNow());
    screen.orientation?.addEventListener?.('change', turned);
    window.addEventListener('resize', turned);
    return () => {
      live = false;
      screen.orientation?.removeEventListener?.('change', turned);
      window.removeEventListener('resize', turned);
    };
  }, []);

  return spotOnScreen(override ?? known, angle);
}

/** The table's height for this phone, ignoring the Developer setting: for Settings' Reset. */
export async function defaultHeight(): Promise<number> {
  const { phone, maker } = await whichPhone();
  return knownHeight(phone, maker);
}
