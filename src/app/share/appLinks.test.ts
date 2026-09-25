import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Share links that opened the app are taken from the native side once the app has its notes, and again each time the
 * side says another has arrived; only the ones that are shares are opened, and nothing is done in a browser.
 */

const native = vi.hoisted(() => ({ on: true, kept: [] as string[][], heard: null as (() => void) | null, stopped: 0 }));
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => native.on,
  invoke: vi.fn(async (command: string) => {
    if (command !== 'links_take') throw new Error(`unexpected ${command}`);
    return native.kept.shift() ?? [];
  }),
}));
vi.mock('../core/events.ts', () => ({
  listenTo: vi.fn(async (event: string, handler: () => void) => {
    if (event === 'glyph://link') native.heard = handler;
    return () => {
      native.stopped += 1;
    };
  }),
}));

const { followAppLinks } = await import('./appLinks.ts');
const share = `ghostmd://fork#${'a'.repeat(22)}.${'b'.repeat(43)}`;
/** The native side's answers and the listener are promises: let them land. */
const settle = async () => {
  for (let i = 0; i < 5; i += 1) await Promise.resolve();
};

beforeEach(() => {
  native.on = true;
  native.kept = [];
  native.heard = null;
  native.stopped = 0;
});

describe('links that opened the app', () => {
  it('opens the shares the native side kept, and leaves anything else', async () => {
    native.kept = [[share, 'ghostmd://something-else']];
    const open = vi.fn();
    followAppLinks(open);
    await settle();
    expect(open.mock.calls).toEqual([[share]]);
  });

  it('takes again when another arrives while the app runs, and stops listening when asked', async () => {
    const open = vi.fn();
    const stop = followAppLinks(open);
    await settle();
    expect(open).not.toHaveBeenCalled();
    native.kept = [[share]];
    native.heard!();
    await settle();
    expect(open).toHaveBeenCalledWith(share);
    stop();
    expect(native.stopped).toBe(1);
    // A take that answers after the stop opens nothing.
    native.kept = [[share]];
    native.heard!();
    await settle();
    expect(open).toHaveBeenCalledTimes(1);
  });

  it('does nothing in a browser', async () => {
    native.on = false;
    const open = vi.fn();
    followAppLinks(open)();
    await settle();
    expect(native.heard).toBeNull();
    expect(open).not.toHaveBeenCalled();
  });
});
