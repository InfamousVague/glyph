import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/*
 * The notes' folder shown where the device shows folders (libraryFiles.ts): the Files app through the activity on a
 * phone, Finder through Rust on a Mac, and nothing in a browser. Offered only where the binary can, since an update
 * over the air reaches binaries older than the button.
 */

let native = false;
let generation = 18;
const invoked: string[] = [];
vi.mock('./tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string) => {
    invoked.push(command);
  },
}));
vi.mock('./nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => native && generation >= wanted }));

const { browseFiles, canBrowseFiles } = await import('./libraryFiles.ts');

beforeEach(() => {
  native = false;
  generation = 18;
  invoked.length = 0;
});

afterEach(() => {
  delete window.GlyphHost;
});

describe('the notes’ folder', () => {
  it('is not offered in a browser, where there is no folder to show', async () => {
    expect(await canBrowseFiles()).toBe(false);
  });

  it('is offered on a phone whose activity can open it, and opened there', async () => {
    let opened = 0;
    window.GlyphHost = { browseFiles: () => (opened += 1) } as unknown as Window['GlyphHost'];
    expect(await canBrowseFiles()).toBe(true);
    await browseFiles();
    expect(opened).toBe(1);
    expect(invoked).toEqual([]);
  });

  it('is not offered on a phone whose activity is from before it', async () => {
    window.GlyphHost = {} as unknown as Window['GlyphHost'];
    expect(await canBrowseFiles()).toBe(false);
  });

  it('is offered on a Mac from generation 18, and shown in Finder by Rust', async () => {
    native = true;
    generation = 17;
    expect(await canBrowseFiles()).toBe(false);
    generation = 18;
    expect(await canBrowseFiles()).toBe(true);
    await browseFiles();
    expect(invoked).toEqual(['library_reveal']);
  });
});
