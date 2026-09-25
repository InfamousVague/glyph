import { afterEach, describe, expect, it, vi } from 'vitest';
import { assistantPath, canOpenAssistantSettings, deviceMaker, isAssistantNow, openAssistantSettings, phoneKind, sideKeyPath } from './assistant.ts';

const FOLD = 'Mozilla/5.0 (Linux; Android 16; SM-F971U1 Build/BP2A; wv) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36';
const PIXEL = 'Mozilla/5.0 (Linux; Android 16; Pixel 10 Pro) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36';
const ONEPLUS = 'Mozilla/5.0 (Linux; Android 15; CPH2649) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36';

afterEach(() => {
  delete (window as { GlyphHost?: unknown }).GlyphHost;
});

describe('which phone the side-key page is talking to', () => {
  it('knows a Samsung or a Pixel by its maker, and by its model when the maker will not say', () => {
    expect(phoneKind('samsung', '')).toBe('samsung');
    expect(phoneKind('', FOLD)).toBe('samsung');
    expect(phoneKind('Google', '')).toBe('pixel');
    expect(phoneKind('', PIXEL)).toBe('pixel');
    expect(phoneKind('OnePlus', ONEPLUS)).toBe('other');
    expect(phoneKind('', '')).toBe('other');
  });

  it('prints the rows each maker’s Settings really has, the last the one to pick', () => {
    expect(assistantPath('samsung')).toEqual(['Settings', 'Apps', 'Choose default apps', 'Digital assistant app', 'Device assistance app', 'Ghost.md']);
    expect(assistantPath('pixel').at(-1)).toBe('Ghost.md');
    expect(assistantPath('other')).toEqual(assistantPath('pixel'));
    expect(sideKeyPath('samsung')).toContain('Side button');
    expect(sideKeyPath('pixel')).toContain('Press and hold power button');
    expect(sideKeyPath('other')).toEqual(['Settings', 'search “press and hold”', 'Digital assistant']);
  });
});

describe('the activity’s assistant helpers', () => {
  it('answer as a phone that will not say where there is no activity', () => {
    expect(deviceMaker()).toBe('');
    expect(isAssistantNow()).toBeNull();
    expect(canOpenAssistantSettings()).toBe(false);
    expect(() => openAssistantSettings()).not.toThrow();
  });

  it('answer as a phone that will not say when an older bridge throws', () => {
    const broken = () => {
      throw new Error('no such method');
    };
    Object.assign(window, { GlyphHost: { deviceMaker: broken, isAssistant: broken, openAssistantSettings: broken } });
    expect(deviceMaker()).toBe('');
    expect(isAssistantNow()).toBeNull();
    expect(canOpenAssistantSettings()).toBe(true);
    expect(() => openAssistantSettings()).not.toThrow();
  });

  it('read the maker and the role, and open the settings, where the activity has them', () => {
    const open = vi.fn(() => true);
    Object.assign(window, { GlyphHost: { deviceMaker: () => 'samsung', isAssistant: () => true, openAssistantSettings: open } });
    expect(deviceMaker()).toBe('samsung');
    expect(isAssistantNow()).toBe(true);
    openAssistantSettings();
    expect(open).toHaveBeenCalledTimes(1);
  });
});
