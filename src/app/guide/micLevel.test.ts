import { describe, expect, it } from 'vitest';
import { listenToMicrophone } from './micLevel.ts';

describe('listening for the rings', () => {
  it('hears nothing, quietly, where there is no microphone to ask', () => {
    // jsdom has no mediaDevices: the same as a page served over plain http.
    let heard = 0;
    const stop = listenToMicrophone(() => {
      heard += 1;
    });
    expect(typeof stop).toBe('function');
    expect(() => stop()).not.toThrow();
    expect(heard).toBe(0);
  });
});
