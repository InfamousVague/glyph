import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';

// An Android phone, as far as the page can tell: the rows it prints are for the key it has.
vi.mock('../../core/platform.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../../core/platform.ts')>()), isAndroid: true }));

import { buttonSaying, press, show } from '../../../test/render.tsx';
import { SideKey } from './SideKey.tsx';

/** The activity's helpers, as a phone of this maker answers them. */
function phone(maker: string, assistant: { now: boolean }) {
  const open = vi.fn(() => true);
  Object.assign(window, { GlyphHost: { deviceMaker: () => maker, isAssistant: () => assistant.now, openAssistantSettings: open } });
  return open;
}

afterEach(() => {
  delete (window as { GlyphHost?: unknown }).GlyphHost;
});

const paths = (el: HTMLElement) => [...el.querySelectorAll('ol > li > p:first-of-type')].map((p) => p.textContent);

describe('the side-key page on an Android phone', () => {
  it('prints a Samsung’s own rows, opens its assistant settings, and says it replaces Bixby or Gemini', () => {
    const open = phone('samsung', { now: false });
    const el = show(<SideKey />);
    expect(paths(el)[0]).toBe('Settings › Apps › Choose default apps › Digital assistant app › Device assistance app › Ghost.md');
    expect(paths(el)[1]).toBe('Settings › Advanced features › Side button › Press and hold › Digital assistant');
    expect(el.textContent).toContain('Choose Digital assistant, not Bixby.');
    expect(el.textContent).toContain('This replaces Bixby or Gemini as your assistant.');
    press(buttonSaying(el, 'Open assistant settings'));
    expect(open).toHaveBeenCalledTimes(1);
  });

  it('prints a Pixel’s rows, and Gemini alone as what it replaces', () => {
    phone('Google', { now: false });
    const el = show(<SideKey />);
    expect(paths(el)[1]).toBe('Settings › System › Gestures › Press and hold power button › Digital assistant');
    expect(el.textContent).not.toContain('not Bixby');
    expect(el.textContent).toContain('This replaces Gemini as your assistant.');
  });

  it('looks again when the person comes back from Settings, and says it worked', () => {
    const assistant = { now: false };
    phone('samsung', assistant);
    const el = show(<SideKey />);
    expect(el.textContent).not.toContain('Ghost.md is your assistant.');
    assistant.now = true;
    act(() => document.dispatchEvent(new Event('visibilitychange')));
    expect(el.querySelector('[role="status"]')?.textContent).toContain('Ghost.md is your assistant.');
    // Nothing left to open.
    expect(buttonSaying(el, 'Open assistant settings')).toBeUndefined();
  });

  it('prints the steps without the button on a build that cannot open the settings', () => {
    Object.assign(window, { GlyphHost: { deviceMaker: () => 'OnePlus' } });
    const el = show(<SideKey />);
    expect(paths(el)[1]).toBe('Settings › search “press and hold” › Digital assistant');
    expect(buttonSaying(el, 'Open assistant settings')).toBeUndefined();
  });
});
