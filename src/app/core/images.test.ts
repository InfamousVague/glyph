import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/*
 * Pictures in notes: how a body names one, and where a picture goes and is drawn from - the browser's store, or the
 * phone's through the host and Rust. The two things jsdom cannot do stand in for themselves: the IndexedDB database
 * is a map (core/webImages.ts), and the canvas that shrinks a paste answers a small JPEG of its own
 * (core/imageShrink.ts). A phone is the one bridge mocked, core/tauri.ts, as everywhere.
 */

let native = false;
/** The native generation the phone answers with. */
let generation = 18;
const invoked: { command: string; args: Record<string, unknown> | undefined }[] = [];
/** What each command answers, by name. */
const answers = new Map<string, unknown>();

vi.mock('./tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string, args?: Record<string, unknown>) => {
    invoked.push({ command, args });
    return answers.get(command);
  },
}));
vi.mock('./nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => native && generation >= wanted }));
vi.mock('@tauri-apps/api/core', () => ({ convertFileSrc: (path: string, protocol: string) => `${protocol}://localhost/${path}` }));

/** The browser's database, in memory. */
const kept = new Map<string, Blob>();
vi.mock('./webImages.ts', () => ({
  webPut: async (name: string, blob: Blob) => {
    kept.set(name, blob);
  },
  webGet: async (name: string) => kept.get(name) ?? null,
}));

/** What a paste is shrunk to: a picture of its own, so a test can tell the shrunk bytes from the pasted ones. */
const SHRUNK = new Uint8Array([0xff, 0xd8, 0xff, 1, 2, 3]);
/** Whether the shrink cannot open what it is given, as an older Mac's WebKit cannot open a HEIC. */
let unopenable = false;
vi.mock('./imageShrink.ts', () => ({
  shrink: async () => {
    if (unopenable) throw new Error('That picture couldn’t be opened.');
    return new Blob([SHRUNK], { type: 'image/jpeg' });
  },
}));

/** The Mac app: a Tauri page with no GlyphHost, whose file input the system's open panel answers. */
let mac = false;
vi.mock('./platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./platform.ts')>()),
  get isMacApp() {
    return mac;
  },
}));

/** The next file input answers with `file`, as a person choosing it in the open panel would. */
function chooseFile(file: File | null): { opened: HTMLInputElement[] } {
  const opened: HTMLInputElement[] = [];
  vi.spyOn(HTMLInputElement.prototype, 'click').mockImplementation(function (this: HTMLInputElement) {
    opened.push(this);
    Object.defineProperty(this, 'files', { value: file ? [file] : [], configurable: true });
    queueMicrotask(() => (file ? this.onchange?.(new Event('change')) : this.oncancel?.(new Event('cancel'))));
  });
  return { opened };
}

const { IMAGE_READY, imageBytes, imageMarkdown, imageNames, imageUrl, keepImage, lendImages, pickImage, saveImageFile } = await import('./images.ts');
const { noteTitle } = await import('./store.ts');

/** How many times IMAGE_READY has fired since the test began. */
let ready = 0;
const onReady = () => {
  ready += 1;
};

/** Lets every promise already queued run: a fetch from the map, the event after it. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

beforeEach(() => {
  native = false;
  mac = false;
  unopenable = false;
  generation = 18;
  invoked.length = 0;
  answers.clear();
  kept.clear();
  ready = 0;
  window.addEventListener(IMAGE_READY, onReady);
  let next = 0;
  URL.createObjectURL = vi.fn(() => `blob:picture-${(next += 1)}`);
});

afterEach(() => {
  window.removeEventListener(IMAGE_READY, onReady);
  delete window.GlyphHost;
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('pictures in notes', () => {
  it('writes and reads back the relative reference', () => {
    const md = imageMarkdown('a1b2.jpg', 'the cabin');
    expect(md).toBe('![the cabin](image/a1b2.jpg)');
    expect(imageNames(`# Trip\n\n${md}\n\n![](image/c3d4.png)\n\n![](http://elsewhere/x.png)`)).toEqual(['a1b2.jpg', 'c3d4.png']);
  });

  it('does not make a picture the note title', () => {
    expect(noteTitle('![](image/a1b2.jpg)\n\nThe cabin')).toBe('The cabin');
    expect(noteTitle('![the cabin](image/a1b2.jpg)')).toBe('');
    expect(noteTitle('# Trip\n\n![](image/a1b2.jpg)')).toBe('Trip');
  });
});

describe('a picture in a browser', () => {
  it('is kept shrunk when pasted, under a name of its own, and drawn at once', async () => {
    const name = await saveImageFile(new Blob([new Uint8Array(4096)], { type: 'image/png' }));
    expect(name).toMatch(/\.jpg$/);
    expect(new Uint8Array(await kept.get(name)!.arrayBuffer())).toEqual(SHRUNK);
    // Seen this run, so the editor has it without waiting for the database.
    expect(imageUrl(name)).toMatch(/^blob:/);
    expect(invoked).toEqual([]);
  });

  it('gets a name on the LAN dev server too, where there is no randomUUID', async () => {
    vi.stubGlobal('crypto', { getRandomValues: crypto.getRandomValues.bind(crypto) });
    const name = await saveImageFile(new Blob([new Uint8Array(8)]));
    expect(name).toMatch(/^img-[a-z0-9]+-[a-z0-9]+\.jpg$/);
  });

  it('is blank while it is fetched from storage, then says so and is drawn', async () => {
    kept.set('cabin.jpg', new Blob([new Uint8Array([1])]));
    expect(imageUrl('cabin.jpg')).toBe('');
    await settle();
    expect(ready).toBe(1);
    expect(imageUrl('cabin.jpg')).toMatch(/^blob:/);
  });

  it('stays blank, and says nothing, when storage has no picture by that name', async () => {
    expect(imageUrl('nowhere.jpg')).toBe('');
    await settle();
    expect(ready).toBe(0);
    expect(imageUrl('nowhere.jpg')).toBe('');
  });

  it('keeps a picture that arrived by sync, typed by its name, and draws it wherever a page is waiting', async () => {
    await keepImage('shot.png', new Uint8Array([9, 8, 7]));
    expect(kept.get('shot.png')?.type).toBe('image/png');
    expect(ready).toBe(1);
    expect(imageUrl('shot.png')).toMatch(/^blob:/);
    expect(await imageBytes('shot.png')).toEqual(new Uint8Array([9, 8, 7]));
    expect(await imageBytes('missing.png')).toBeNull();
  });

  it('draws a share’s lent pictures without keeping them', () => {
    lendImages({ 'lent.webp': new Uint8Array([1, 2]) });
    expect(imageUrl('lent.webp')).toMatch(/^blob:/);
    expect(kept.size).toBe(0);
    expect(ready).toBe(1);
    lendImages({});
    expect(ready).toBe(1);
  });
});

describe('a picture on the phone', () => {
  beforeEach(() => {
    native = true;
  });

  it('refuses a paste on a binary too old to take one, and sends the shrunk bytes to one that can', async () => {
    generation = 8;
    await expect(saveImageFile(new Blob([new Uint8Array(4)]))).rejects.toThrow('Pasting pictures needs the newest Ghost.md.');
    expect(invoked).toEqual([]);
    generation = 9;
    answers.set('save_image_data', { name: 'pasted.jpg' });
    expect(await saveImageFile(new Blob([new Uint8Array(4)]))).toBe('pasted.jpg');
    expect(invoked).toEqual([{ command: 'save_image_data', args: { base64: Buffer.from(SHRUNK).toString('base64') } }]);
  });

  it('files a picture that arrived by sync with Rust, and gives it a fresh address each time it lands', async () => {
    expect(imageUrl('trip.jpg')).toBe('img://localhost/trip.jpg');
    await keepImage('trip.jpg', new Uint8Array([1, 2, 3]));
    expect(invoked).toEqual([{ command: 'sync_put_file', args: { kind: 'image', name: 'trip.jpg', base64: 'AQID' } }]);
    expect(ready).toBe(1);
    // A page that asked before the picture was there asks again, rather than keeping the failed load.
    expect(imageUrl('trip.jpg')).toBe('img://localhost/trip.jpg?v=1');
    await keepImage('trip.jpg', new Uint8Array([4]));
    expect(imageUrl('trip.jpg')).toBe('img://localhost/trip.jpg?v=2');
  });

  it('reads a picture’s bytes through the img scheme, and has none when the scheme has none', async () => {
    const fetched: string[] = [];
    vi.stubGlobal('fetch', async (url: string) => {
      fetched.push(url);
      return url.endsWith('here.jpg') ? new Response(new Uint8Array([5, 6])) : new Response(null, { status: 404 });
    });
    expect(await imageBytes('here.jpg')).toEqual(new Uint8Array([5, 6]));
    expect(await imageBytes('gone.jpg')).toBeNull();
    expect(fetched).toEqual(['img://localhost/here.jpg', 'img://localhost/gone.jpg']);
  });

  it('is picked by the activity and filed by Rust, and a cancelled pick is no picture', async () => {
    let started = 0;
    const pick = () => {
      started += 1;
      return 'started';
    };
    window.GlyphHost = { pickImage: pick } as unknown as Window['GlyphHost'];
    answers.set('save_image', { name: 'picked.jpg' });
    const picking = pickImage();
    await settle();
    window.__glyph?.image?.(JSON.stringify({ path: '/cache/pick.jpg' }));
    expect(await picking).toBe('picked.jpg');
    expect(invoked).toEqual([{ command: 'save_image', args: { path: '/cache/pick.jpg' } }]);

    const cancelled = pickImage();
    await settle();
    window.__glyph?.image?.(JSON.stringify({ cancelled: true }));
    expect(await cancelled).toBeNull();
    expect(started).toBe(2);
  });

  it('says why a pick failed: an old build, a picker that would not open, the activity’s words, or an answer it could not read', async () => {
    window.GlyphHost = {} as unknown as Window['GlyphHost'];
    await expect(pickImage()).rejects.toThrow('This build cannot add pictures yet. Install the newest Ghost.md.');

    window.GlyphHost = { pickImage: () => 'busy' } as unknown as Window['GlyphHost'];
    await expect(pickImage()).rejects.toThrow('busy');

    window.GlyphHost = { pickImage: () => 'started' } as unknown as Window['GlyphHost'];
    const refused = pickImage();
    await settle();
    window.__glyph?.image?.(JSON.stringify({ error: 'No room left on the phone.' }));
    await expect(refused).rejects.toThrow('No room left on the phone.');

    const garbled = pickImage();
    await settle();
    window.__glyph?.image?.('not json');
    await expect(garbled).rejects.toThrow('The picture could not be read.');
    expect(invoked).toEqual([]);
  });
});

describe('a picture on the Mac', () => {
  beforeEach(() => {
    native = true;
    mac = true;
    generation = 20;
    answers.set('save_image_data', { name: 'from-mac.jpg' });
  });

  it('is chosen in the open panel the file input brings, and filed by Rust as bytes, never through the phone’s picker', async () => {
    const asked = vi.fn(() => 'started');
    window.GlyphHost = { pickImage: asked } as unknown as Window['GlyphHost'];
    const { opened } = chooseFile(new File([new Uint8Array(8)], 'harbour.jpg', { type: 'image/jpeg' }));
    expect(await pickImage()).toBe('from-mac.jpg');
    expect(opened).toHaveLength(1);
    expect(opened[0]!.accept).toBe('image/*');
    expect(asked).not.toHaveBeenCalled();
    expect(invoked).toEqual([{ command: 'save_image_data', args: { base64: Buffer.from(SHRUNK).toString('base64') } }]);
  });

  it('is nothing when the panel is closed', async () => {
    chooseFile(null);
    expect(await pickImage()).toBeNull();
    expect(invoked).toEqual([]);
  });

  it('refuses a file that is not a picture, in words, before trying to open it', async () => {
    chooseFile(new File([new Uint8Array(8)], 'menu.pdf', { type: 'application/pdf' }));
    await expect(pickImage()).rejects.toThrow('That isn’t a picture.');
    expect(invoked).toEqual([]);
  });

  it('says a HEIC it cannot open is a HEIC, and what to do', async () => {
    unopenable = true;
    chooseFile(new File([new Uint8Array(8)], 'IMG_0042.HEIC', { type: '' }));
    await expect(pickImage()).rejects.toThrow('This Mac can’t open HEIC pictures. Save it as a JPEG first.');
    chooseFile(new File([new Uint8Array(8)], 'broken.jpg', { type: 'image/jpeg' }));
    await expect(pickImage()).rejects.toThrow('That picture couldn’t be opened.');
  });
});
