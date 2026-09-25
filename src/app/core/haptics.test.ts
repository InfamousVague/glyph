import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/*
 * The motor (haptics.ts): what each kind says through the Tauri plugin, the switch that silences all of it, the
 * 28 ms floor that keeps the typing hand from flooding the Taptic Engine, and the tap tick that fires on a finger's
 * lift rather than its landing. A phone with a motor is core/platform.ts mocked to say so; the plugin is mocked to
 * say what it was asked. The module decides at import whether there is a motor, so each test imports it fresh.
 */

let motor = true;
vi.mock('./platform.ts', () => ({
  get isNativeMobile() {
    return motor;
  },
}));

/** Everything the plugin was asked to say, in order. */
const said: string[] = [];
vi.mock('@tauri-apps/plugin-haptics', () => ({
  selectionFeedback: async () => {
    said.push('selection');
  },
  impactFeedback: async (style: string) => {
    said.push(`impact ${style}`);
  },
  notificationFeedback: async (kind: string) => {
    said.push(`notification ${kind}`);
  },
}));

let haptics: typeof import('./haptics.ts');

/** Lets the plugin's lazy import and its call land. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

beforeEach(async () => {
  motor = true;
  said.length = 0;
  localStorage.clear();
  vi.resetModules();
  haptics = await import('./haptics.ts');
});

describe('the motor', () => {
  it('says each of the kit’s kinds in the phone’s own words', async () => {
    for (const kind of ['selection', 'light', 'medium', 'heavy', 'success', 'warning', 'error'] as const) haptics.fireNativeHaptic(kind);
    haptics.fireNativeHaptic();
    await settle();
    expect(said).toEqual([
      'selection',
      'impact light',
      'impact medium',
      'impact heavy',
      'notification success',
      'notification warning',
      'notification error',
      'impact light',
    ]);
  });

  it('is silent with the switch off, on every path into it, and remembers the choice', async () => {
    expect(haptics.hapticsPref()).toBe(true);
    haptics.setHapticsPref(false);
    haptics.fireNativeHaptic('heavy');
    haptics.fireFelt('light', 1_000);
    haptics.fireMicroTick(2_000);
    await settle();
    expect(said).toEqual([]);
    vi.resetModules();
    const again = await import('./haptics.ts');
    expect(again.hapticsPref()).toBe(false);
  });

  it('is not there at all without a motor: no impl for the kit, no switch turned on, nothing said', async () => {
    motor = false;
    vi.resetModules();
    const none = await import('./haptics.ts');
    expect(none.hapticsImpl).toBeUndefined();
    expect(none.hapticsAvailable()).toBe(false);
    expect(none.hapticsPref()).toBe(false);
    none.fireNativeHaptic('heavy');
    none.fireMicroTick(5_000);
    await settle();
    expect(said).toEqual([]);
    expect(haptics.hapticsImpl).toBe(haptics.fireNativeHaptic);
  });
});

describe('the floor the typing hand is held to', () => {
  it('lets one haptic through in any 28 ms, and the next once 28 ms have passed', async () => {
    haptics.fireFelt('light', 1_000);
    haptics.fireFelt('medium', 1_010);
    haptics.fireFelt('heavy', 1_027);
    haptics.fireFelt('selection', 1_028);
    await settle();
    expect(said).toEqual(['impact light', 'selection']);
  });

  it('holds the soft tick to the same floor, shared with every other editor haptic', async () => {
    haptics.fireFelt('light', 1_000);
    haptics.fireMicroTick(1_020);
    haptics.fireMicroTick(1_030);
    haptics.fireFelt('light', 1_040);
    await settle();
    expect(said).toEqual(['impact light', 'impact soft']);
  });

  it('never holds back a one-shot: a press answers every time', async () => {
    haptics.fireNativeHaptic('light');
    haptics.fireNativeHaptic('light');
    await settle();
    expect(said).toEqual(['impact light', 'impact light']);
  });
});

describe('the tap tick', () => {
  let stop: () => void = () => undefined;
  let button: HTMLButtonElement;
  let words: HTMLParagraphElement;

  beforeEach(() => {
    button = document.body.appendChild(document.createElement('button'));
    words = document.body.appendChild(document.createElement('p'));
    stop = haptics.installTapHaptics();
  });

  afterEach(() => {
    stop();
    button.remove();
    words.remove();
  });

  /** A pointer event from a finger (or `pointerType`) at `x`, `y`, at `at` ms, on `on`. */
  function pointer(type: string, on: Element, { x = 0, y = 0, at = 0, pointerType = 'touch' } = {}): void {
    const event = new Event(type, { bubbles: true });
    Object.defineProperties(event, { clientX: { value: x }, clientY: { value: y }, pointerType: { value: pointerType }, timeStamp: { value: at } });
    on.dispatchEvent(event);
  }

  /** A press on `down` lifted from `up`. */
  function tap(down: Element, up: Element = down, lift: { x?: number; y?: number; at?: number; pointerType?: string } = {}): void {
    pointer('pointerdown', down, { pointerType: lift.pointerType });
    pointer('pointerup', up, { at: 100, ...lift });
  }

  it('ticks when a finger lifts from something tappable, where it landed', async () => {
    tap(button);
    await settle();
    expect(said).toEqual(['selection']);
  });

  it('stays quiet for a scroll, a press and hold, a lift somewhere else, a mouse, and a cancelled press', async () => {
    tap(button, button, { y: 11 });
    tap(button, button, { x: -11 });
    tap(button, button, { at: 701 });
    tap(button, words);
    tap(words);
    tap(button, button, { pointerType: 'mouse' });
    pointer('pointerdown', button);
    pointer('pointercancel', button);
    pointer('pointerup', button, { at: 50 });
    await settle();
    expect(said).toEqual([]);
    // Within the slop and the time, it is still a tap.
    tap(button, button, { x: 10, y: -10, at: 700 });
    await settle();
    expect(said).toEqual(['selection']);
  });

  it('is taken down by its cleanup, and is never put up without a motor', async () => {
    stop();
    tap(button);
    motor = false;
    vi.resetModules();
    const none = await import('./haptics.ts');
    const nothing = none.installTapHaptics();
    tap(button);
    nothing();
    await settle();
    expect(said).toEqual([]);
  });
});
