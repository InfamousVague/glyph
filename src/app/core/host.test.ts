import { afterEach, describe, expect, it } from 'vitest';
import { answerHost, endCapture, isLocked, setCapturing, takeCaptureLaunch } from './host.ts';

/*
 * The page's line to the Android activity (host.ts). `window.__glyph` is one object every module answers on, and
 * the reason the file exists is that one answer must never wipe another: a side key that does nothing while the app
 * is open is the failure, and no desktop test would otherwise see it.
 */

afterEach(() => {
  delete window.__glyph;
  delete window.GlyphHost;
  delete window.__glyphLaunch;
  window.history.replaceState(null, '', '/');
});

describe('what the activity calls on the page', () => {
  it('reaches every module that answers, each under its own name', () => {
    const heard: string[] = [];
    const offRefresh = answerHost('refresh', () => heard.push('refresh'));
    const offCapture = answerHost('capture', () => heard.push('capture'));
    window.__glyph?.refresh?.();
    window.__glyph?.capture?.();
    expect(heard).toEqual(['refresh', 'capture']);
    offRefresh();
    offCapture();
  });

  it('takes one answer away without touching the others', () => {
    const offRefresh = answerHost('refresh', () => undefined);
    const capture = () => undefined;
    answerHost('capture', capture);
    offRefresh();
    expect(window.__glyph?.refresh).toBeUndefined();
    expect(window.__glyph?.capture).toBe(capture);
  });

  it('leaves a newer answer in place when an older one is taken away', () => {
    const offFirst = answerHost('refresh', () => undefined);
    const second = () => undefined;
    answerHost('refresh', second);
    offFirst();
    expect(window.__glyph?.refresh).toBe(second);
  });
});

describe('what the page asks the activity', () => {
  it('reads a side-key launch once from the host and keeps it for a second mount in the same page', () => {
    let reads = 0;
    window.GlyphHost = {
      takeLaunch: () => {
        reads += 1;
        return reads === 1 ? 'capture' : '';
      },
    } as unknown as Window['GlyphHost'];
    expect(takeCaptureLaunch()).toBe(true);
    expect(takeCaptureLaunch()).toBe(true);
    expect(reads).toBe(1);
  });

  it('stands a ?capture address in for the side key in a browser', () => {
    expect(takeCaptureLaunch()).toBe(false);
    window.history.replaceState(null, '', '/?capture');
    expect(takeCaptureLaunch()).toBe(true);
  });

  it('answers safely with no host, or a host from before a method existed', () => {
    expect(isLocked()).toBe(false);
    expect(() => endCapture(true)).not.toThrow();
    expect(setCapturing(true)).toBe(false);
    window.GlyphHost = {
      isLocked: () => {
        throw new Error('old build');
      },
      endCapture: () => {
        throw new Error('old build');
      },
    } as unknown as Window['GlyphHost'];
    expect(isLocked()).toBe(false);
    expect(() => endCapture(false)).not.toThrow();
    expect(setCapturing(true)).toBe(false);
  });

  it('tells a host that can keep the screen on that a recording started, and says it can', () => {
    const told: boolean[] = [];
    let left: boolean | null = null;
    window.GlyphHost = {
      isLocked: () => true,
      endCapture: (leave: boolean) => {
        left = leave;
      },
      setCapturing: (on: boolean) => told.push(on),
    } as unknown as Window['GlyphHost'];
    expect(isLocked()).toBe(true);
    expect(setCapturing(true)).toBe(true);
    expect(setCapturing(false)).toBe(true);
    expect(told).toEqual([true, false]);
    endCapture(true);
    expect(left).toBe(true);
  });
});
