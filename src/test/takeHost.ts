import type { TakeNote } from '../app/capture/takeTypes.ts';
import type { TakeHost } from '../app/capture/takeHost.ts';

/**
 * A host for a Take (capture/take.ts) under test: every member does nothing until a test says otherwise by passing
 * its own.
 *
 * Each test of the take cares about one or two of the host's members - the offer it made, the chip it showed, the
 * note it changed. So the quiet defaults are written once, here, and a member the interface gains or loses is one edit.
 */
export function quietHost<N extends TakeNote>(overrides: Partial<TakeHost<N>> = {}): TakeHost<N> {
  return {
    route: () => undefined,
    offer: () => undefined,
    haptic: () => undefined,
    changed: () => undefined,
    addItems: () => undefined,
    log: () => undefined,
    ...overrides,
  };
}
