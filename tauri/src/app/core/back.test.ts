// @vitest-environment jsdom
import { describe, expect, it, afterEach } from 'vitest';
import { goBack, installBack, markSteppedBack, onBack } from './back.ts';

describe('the back gesture', () => {
  let stop: (() => void) | null = null;
  afterEach(() => {
    stop?.();
    stop = null;
  });

  it('gives the gesture to the newest screen that wants it', () => {
    const taken: string[] = [];
    const offList = onBack(() => {
      taken.push('list');
      return false;
    });
    const offNote = onBack(() => {
      taken.push('note');
      return true;
    });
    expect(goBack()).toBe(true);
    expect(taken).toEqual(['note']);
    offNote();
    expect(goBack()).toBe(false);
    expect(taken).toEqual(['note', 'list']);
    offList();
  });

  it('always tells the activity the page used it, so a back swipe never leaves the app', () => {
    stop = installBack();
    const answer = window.__glyph?.back;
    expect(answer).toBeTypeOf('function');
    // Nothing on screen: the gesture still counts as used, where before it meant "put Glyph behind the home screen".
    expect(answer?.()).toBe(true);
    const off = onBack(() => true);
    expect(answer?.()).toBe(true);
    off();
  });

  it('steps back once for a swipe the page already used', () => {
    stop = installBack();
    const answer = window.__glyph?.back;
    let steps = 0;
    const off = onBack(() => {
      steps += 1;
      return true;
    });
    // The page's own right-swipe closed a screen; Android offers the same swipe a moment later.
    markSteppedBack();
    expect(answer?.()).toBe(true);
    expect(steps).toBe(0);
    off();
  });

  it('answers Escape from the same stack, and leaves a key nothing took to whatever else is listening', () => {
    stop = installBack();
    const escape = () => {
      const event = new KeyboardEvent('keydown', { key: 'Escape', cancelable: true });
      window.dispatchEvent(event);
      return event;
    };
    // Nothing on screen to close: the key is not claimed, unlike the activity's gesture.
    expect(escape().defaultPrevented).toBe(false);
    let closed = 0;
    const off = onBack(() => {
      closed += 1;
      return true;
    });
    expect(escape().defaultPrevented).toBe(true);
    expect(closed).toBe(1);
    // A key something else already handled is not stepped back on again.
    const handled = new KeyboardEvent('keydown', { key: 'Escape', cancelable: true });
    handled.preventDefault();
    window.dispatchEvent(handled);
    expect(closed).toBe(1);
    off();
    stop();
    stop = null;
    expect(window.__glyph?.back).toBeUndefined();
  });
});
