import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Whether the phone's keyboard is up (keyboard.ts): the viewport 150px under the tallest it has been at its width,
 * kept by width so a Fold opening is not a keyboard, and never up before it can be known. jsdom has no visual viewport,
 * so the window's own size stands in for it, and the module is imported fresh at each size it starts at.
 */

function size(width: number, height: number): void {
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: width });
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: height });
  window.dispatchEvent(new Event('resize'));
}

async function fresh(width: number, height: number): Promise<typeof import('./keyboard.ts')> {
  size(width, height);
  vi.resetModules();
  return import('./keyboard.ts');
}

beforeEach(() => size(1024, 768));
afterEach(() => {
  Reflect.deleteProperty(window, 'innerWidth');
  Reflect.deleteProperty(window, 'innerHeight');
});

describe('the keyboard', () => {
  it('is up when the viewport is 150px under the tallest it has been at its width, and says so as it comes and goes', async () => {
    const keyboard = await fresh(412, 915);
    const told: boolean[] = [];
    const stop = keyboard.watchKeyboard((up) => told.push(up));
    expect(keyboard.keyboardUp()).toBe(false);
    size(412, 780);
    expect(keyboard.keyboardUp()).toBe(false);
    size(412, 585);
    expect(keyboard.keyboardUp()).toBe(true);
    size(412, 915);
    expect(keyboard.keyboardUp()).toBe(false);
    expect(told).toEqual([true, false]);
    stop();
    size(412, 585);
    expect(told).toEqual([true, false]);
  });

  it('keeps each width apart, so the Fold opening is not a keyboard, and one up on the inner screen still is', async () => {
    const keyboard = await fresh(412, 915);
    size(880, 790);
    expect(keyboard.keyboardUp()).toBe(false);
    size(880, 480);
    expect(keyboard.keyboardUp()).toBe(true);
    size(412, 915);
    expect(keyboard.keyboardUp()).toBe(false);
    // The cover screen turned on its side: 412 tall is the tallest it has been at that width, not a keyboard.
    size(915, 412);
    expect(keyboard.keyboardUp()).toBe(false);
  });

  it('reads a keyboard already up at launch as down, until it has gone once', async () => {
    const keyboard = await fresh(412, 585);
    expect(keyboard.keyboardUp()).toBe(false);
    size(412, 915);
    size(412, 585);
    expect(keyboard.keyboardUp()).toBe(true);
  });
});
