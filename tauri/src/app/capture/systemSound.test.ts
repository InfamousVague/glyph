import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * A meeting's own sound (capture/systemSound.ts): where it can be had, by platform and by the binary's generation, the
 * words each platform says it in, and the Mac's tap commands answering safely when they fail.
 */

const platform = vi.hoisted(() => ({
  tauri: false,
  android: false,
  mac: false,
  generation: 0,
  available: { supported: true, reason: null } as { supported: boolean; reason: string | null },
  invoked: [] as string[],
}));
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => platform.tauri,
  invoke: async (command: string) => {
    platform.invoked.push(command);
    if (command === 'ota_status') return { nativeGeneration: platform.generation };
    if (command === 'system_audio_available') return platform.available;
    if (command === 'system_audio_start') throw new Error('coreaudiod went away');
    throw new Error(`no ${command} here`);
  },
}));
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isAndroid() {
    return platform.android;
  },
  get isMacApp() {
    return platform.mac;
  },
}));

async function fresh() {
  // The generation is asked once per page load and kept: each test loads the module afresh.
  vi.resetModules();
  return import('./systemSound.ts');
}

beforeEach(() => {
  platform.tauri = false;
  platform.android = false;
  platform.mac = false;
  platform.generation = 0;
  platform.available = { supported: true, reason: null };
  platform.invoked = [];
});

afterEach(() => {
  delete window.GlyphHost;
});

describe('where a meeting can have its own sound', () => {
  it('is nowhere in a browser, and nowhere on a binary before generation 25', async () => {
    const { meetingSoundSupport, MEETING_SOUND_GENERATION } = await fresh();
    expect(MEETING_SOUND_GENERATION).toBe(25);
    expect(await meetingSoundSupport()).toBeNull();
    platform.tauri = true;
    platform.mac = true;
    platform.generation = 24;
    const older = await fresh();
    expect(await older.meetingSoundSupport()).toBeNull();
    expect(platform.invoked).not.toContain('system_audio_available');
  });

  it('is the Mac’s answer on a Mac, which can be a no with the reason', async () => {
    platform.tauri = true;
    platform.mac = true;
    platform.generation = 25;
    const { meetingSoundSupport } = await fresh();
    expect(await meetingSoundSupport()).toEqual({ supported: true, reason: null });
    platform.available = { supported: false, reason: 'Recording the computer’s sound needs macOS 14.2 or later.' };
    expect(await meetingSoundSupport()).toEqual(platform.available);
  });

  it('is the activity’s answer on Android, and asked of the service only with the switch on', async () => {
    platform.tauri = true;
    platform.android = true;
    platform.generation = 25;
    window.GlyphHost = { meetingSound: () => '{"supported":true,"reason":null}' } as unknown as Window['GlyphHost'];
    const { meetingSoundSupport, wantsOtherApps } = await fresh();
    expect(await meetingSoundSupport()).toEqual({ supported: true, reason: null });
    expect(await wantsOtherApps(true)).toBe(true);
    expect(await wantsOtherApps(false)).toBe(false);
    window.GlyphHost = { meetingSound: () => '{"supported":false,"reason":"Android 10 or later."}' } as unknown as Window['GlyphHost'];
    expect(await wantsOtherApps(true)).toBe(false);
  });
});

describe('what it is called', () => {
  it('says Android’s limit plainly on Android, and both sides of a call on the Mac', async () => {
    platform.android = true;
    const android = (await fresh()).meetingSoundWords();
    expect(android.label).toBe('Include sound from other apps');
    expect(android.hint).toContain('Android lets Ghost.md hear media and games, never calls.');
    platform.android = false;
    const mac = (await fresh()).meetingSoundWords();
    expect(mac.label).toBe("Record the computer's sound too");
    expect(mac.hint).toContain('Both sides of a call');
  });
});

describe('the Mac’s tap', () => {
  it('answers a start that failed as not capturing, with why, and a status it could not read as null', async () => {
    platform.tauri = true;
    const { computerSoundStatus, startComputerSound, stopComputerSound } = await fresh();
    expect(await startComputerSound()).toEqual({ capturing: false, reason: 'Error: coreaudiod went away' });
    expect(await computerSoundStatus()).toBeNull();
    await expect(stopComputerSound()).resolves.toBeUndefined();
  });
});
