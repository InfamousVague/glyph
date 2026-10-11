import { useSyncExternalStore } from 'react';
import { externalStore } from './externalStore.ts';
import { readStoredText, writeStoredText } from './stored.ts';

/**
 * A switch that belongs to this device and to no other: developer mode, live typing, the haptics.
 *
 * Kept in localStorage rather than in the preferences, which travel to the account's other devices, because each of
 * these is about the hardware or the person holding it - trying live typing on the Fold must not turn it on for the
 * Mac. And live rather than a function that reads storage, because a switch is flipped from inside one screen and has
 * to change another at once: developer mode is turned on from About and grows a section in the list that holds About,
 * and `storage` events never fire in the tab that wrote them.
 *
 * Kept as `on` or `off`, and as nothing where the flag is off by default and off - the form all three were first
 * written in. Storage stays the truth: every read asks it, which is a cheap synchronous lookup, so a key set by hand
 * in the console counts from the next read, and a switch storage would not keep reads back as not kept rather than
 * claiming it stuck. The store under it is only the change channel, counting the flips so the hooks read again.
 */

export interface DeviceFlag {
  read(): boolean;
  set(on: boolean): void;
  /** The flag, live across every component that reads it. */
  use(): boolean;
}

/** On a server, and before there is a client, every switch reads off. */
const serverOff = () => false;

export function deviceFlag(key: string, fallback = false): DeviceFlag {
  const flips = externalStore(0);
  const read = (): boolean => {
    const text = readStoredText(key);
    if (text === 'on') return true;
    if (text === 'off') return false;
    return fallback;
  };
  return {
    read,
    set(on) {
      writeStoredText(key, on ? 'on' : fallback ? 'off' : null);
      flips.update((n) => n + 1);
    },
    use: () => useSyncExternalStore(flips.subscribe, read, serverOff),
  };
}
