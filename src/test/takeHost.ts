import type { TakeNote } from '../app/capture/takeTypes.ts';
import type { TakeHost } from '../app/capture/takeHost.ts';

/**
 * A host for a Take (capture/take.ts) under test: every member does nothing, or answers what nothing answers, until a
 * test says otherwise by passing its own.
 *
 * The host has two dozen members, and each test of the take cares about three or four of them - the offer it made,
 * the chip it showed, the note it changed. Three test files each wrote out the whole object, and every member the
 * interface lost or gained was an edit to all three. Here the quiet defaults are written once; `notes` and `target`
 * are the only ones a test usually has to fill, and they default to none.
 */
export function quietHost<N extends TakeNote>(overrides: Partial<TakeHost<N>> = {}): TakeHost<N> {
  return {
    notes: () => [],
    target: () => null,
    commandWord: () => true,
    instructionCommands: () => true,
    voiceCommands: () => [],
    itemTargets: () => [],
    route: () => undefined,
    offer: () => undefined,
    table: () => undefined,
    itemWords: () => undefined,
    haptic: () => undefined,
    changed: () => undefined,
    addItems: () => undefined,
    changeNote: () => undefined,
    addTable: () => undefined,
    moveTo: () => undefined,
    newNote: () => undefined,
    newBook: () => undefined,
    runPlugin: () => null,
    describePlugin: () => ({ title: '', action: '' }),
    clip: () => '',
    log: () => undefined,
    said: () => undefined,
    ...overrides,
  };
}
