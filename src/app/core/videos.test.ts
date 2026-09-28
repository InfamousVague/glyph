import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * A film picked on the phone (core/videos.ts): who may pick one, the shell's answer as the page reads it, the one pick
 * waiting and an answer nobody waits for, and whether a film is on this phone. The Android app, its generation and its
 * commands are stood in for; the shell's own words are read out of its source, since the bridge is typed twice.
 */

const device = vi.hoisted(() => ({
  tauri: true,
  android: true,
  generation: 21,
  commands: [] as { command: string; args: unknown }[],
  saved: { video: 'f1.mp4', poster: 'p1.jpg' } as { video: string; poster: string } | Error,
}));
vi.mock('./tauri.ts', () => ({
  isTauri: () => device.tauri,
  invoke: async (command: string, args: unknown) => {
    device.commands.push({ command, args });
    if (command === 'save_video') {
      if (device.saved instanceof Error) throw device.saved.message;
      return device.saved;
    }
    return null;
  },
}));
vi.mock('./nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => device.generation >= wanted }));
vi.mock('./platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./platform.ts')>()),
  get isAndroid() {
    return device.android;
  },
}));
vi.mock('@tauri-apps/api/core', () => ({ convertFileSrc: (path: string, protocol: string) => `http://${protocol}.localhost/${path}` }));

const videos = await import('./videos.ts');

/** What the shell would push to the page, as MainActivity's tellVideo does. */
const answer = (json: object | string) => window.__glyph?.video?.(typeof json === 'string' ? json : JSON.stringify(json));
const PICKED = { path: '/cache/picked/a.mp4', poster: '/cache/picked/a.jpg', ms: 12_345, width: 1080, height: 1920 };

beforeEach(() => {
  Object.assign(device, { tauri: true, android: true, generation: 21, commands: [], saved: { video: 'f1.mp4', poster: 'p1.jpg' } });
  window.GlyphHost = { pickVideo: () => 'started' } as unknown as Window['GlyphHost'];
});

afterEach(() => {
  delete window.GlyphHost;
  vi.unstubAllGlobals();
});

describe('who may add a film', () => {
  it('is an Android binary of generation 21 whose bridge has the picker, and nothing else', async () => {
    expect(await videos.canAddVideos()).toBe(true);
    device.generation = 20;
    expect(await videos.canAddVideos()).toBe(false);
    device.generation = 21;
    window.GlyphHost = { pickImage: () => 'started' } as unknown as Window['GlyphHost'];
    expect(await videos.canAddVideos()).toBe(false);
    window.GlyphHost = { pickVideo: () => 'started' } as unknown as Window['GlyphHost'];
    device.android = false;
    expect(await videos.canAddVideos()).toBe(false);
    Object.assign(device, { android: true, tauri: false });
    expect(await videos.canAddVideos()).toBe(false);
  });
});

describe('a pick', () => {
  it('keeps the film and its poster and answers them with the length and the shape', async () => {
    const picked = videos.pickVideo();
    answer(PICKED);
    expect(await picked).toEqual({ video: 'f1.mp4', poster: 'p1.jpg', ms: 12_345, width: 1080, height: 1920 });
    expect(device.commands).toEqual([{ command: 'save_video', args: { path: PICKED.path, poster: PICKED.poster } }]);
  });

  it('answers nothing when the picker is closed, and says why when it could not be read or kept', async () => {
    const cancelled = videos.pickVideo();
    answer({ cancelled: true });
    expect(await cancelled).toBeNull();
    const unread = videos.pickVideo();
    answer({ error: 'This video can’t be read.' });
    await expect(unread).rejects.toThrow('This video can’t be read.');
    const garbled = videos.pickVideo();
    answer('not json');
    await expect(garbled).rejects.toThrow('This video can’t be read.');
    device.saved = new Error('The video couldn’t be kept.');
    const unkept = videos.pickVideo();
    answer(PICKED);
    await expect(unkept).rejects.toBe('The video couldn’t be kept.');
  });

  it('says so when the bridge will not start the picker, or is not there', async () => {
    window.GlyphHost = { pickVideo: () => 'This phone has no video picker.' } as unknown as Window['GlyphHost'];
    await expect(videos.pickVideo()).rejects.toThrow('This phone has no video picker.');
    delete window.GlyphHost;
    await expect(videos.pickVideo()).rejects.toThrow('Videos need the newest Ghost.md.');
  });

  it('throws away a film nobody is waiting for, the film and its poster', async () => {
    videos.listenForVideos();
    answer(PICKED);
    await Promise.resolve();
    expect(device.commands).toEqual([
      { command: 'discard_picked', args: { path: PICKED.path } },
      { command: 'discard_picked', args: { path: PICKED.poster } },
    ]);
    device.commands.length = 0;
    answer({ cancelled: true });
    answer({ error: 'x' });
    await Promise.resolve();
    expect(device.commands).toEqual([]);
  });
});

describe('whether a film is on this phone', () => {
  it('asks the app’s own scheme once, with a HEAD, and only on a phone that plays films', async () => {
    const heads: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        heads.push(`${init?.method} ${url}`);
        return { ok: url.endsWith('here.mp4') } as Response;
      }),
    );
    expect(await videos.filmHere('here.mp4')).toBe('here');
    expect(await videos.filmHere('here.mp4')).toBe('here');
    expect(await videos.filmHere('gone.mp4')).toBe('missing');
    expect(heads).toEqual(['HEAD http://vid.localhost/here.mp4', 'HEAD http://vid.localhost/gone.mp4']);
    videos.filmGone('here.mp4');
    expect(await videos.filmHere('here.mp4')).toBe('missing');
    device.generation = 20;
    expect(await videos.filmHere('other.mp4')).toBe('update');
    device.android = false;
    expect(await videos.filmHere('other.mp4')).toBe('elsewhere');
    expect(heads).toHaveLength(2);
  });

  it('knows a film just added is here without asking', async () => {
    const fetch = vi.fn();
    vi.stubGlobal('fetch', fetch);
    device.saved = { video: 'new.mp4', poster: 'p.jpg' };
    const picked = videos.pickVideo();
    answer(PICKED);
    await picked;
    expect(await videos.filmHere('new.mp4')).toBe('here');
    expect(fetch).not.toHaveBeenCalled();
  });
});

/*
 * The shell's answer is typed twice, once in Kotlin (media/VideoPick.kt) and once here, and a key misspelt in either is
 * read as nothing without a word. So the keys the shell writes are read out of its source and held to what the page
 * reads, and the event it pushes to what the page listens for.
 */
describe('what the Kotlin says, and what the page reads', () => {
  const android = join(process.cwd(), 'src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph');
  const pick = readFileSync(join(android, 'media/VideoPick.kt'), 'utf8');
  const activity = readFileSync(join(android, 'MainActivity.kt'), 'utf8');
  /** The keys `fun <name>(` writes: each `"key" to` in its body. */
  const keysOf = (name: string) => {
    const from = pick.indexOf(`fun ${name}(`);
    expect(from, `fun ${name}`).toBeGreaterThan(-1);
    const body = pick.slice(from, pick.indexOf('\n\n', from));
    return [...body.matchAll(/"([A-Za-z]+)" to /g)].map((found) => found[1]!).sort();
  };

  it('writes every key of a picked film the page reads, and no other', () => {
    const read = videos.readVideoAnswer(JSON.stringify(PICKED));
    expect(keysOf('picked')).toEqual(Object.keys(read).sort());
    expect(keysOf('cancelled')).toEqual(Object.keys(videos.readVideoAnswer('{"cancelled":true}')));
    expect(keysOf('failed')).toEqual(Object.keys(videos.readVideoAnswer('{"error":"x"}')));
  });

  it('pushes the event the page listens for, never the picture’s', () => {
    expect(activity).toContain('window.__glyph.video(');
    videos.listenForVideos();
    expect(typeof window.__glyph?.video).toBe('function');
    expect(pick).not.toContain('__glyph.image');
  });

  it('says the words the page shows as they are', () => {
    for (const words of ['There isn’t room on this phone for that video.', 'This video can’t be read.', 'This phone has no video picker.']) {
      expect(pick).toContain(`"${words}"`);
    }
  });
});
