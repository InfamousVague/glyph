import { beforeEach, describe, expect, it, vi } from 'vitest';

/*
 * The sample note's one arrival (seed.ts): into a library that has never had it and holds nothing, once, and never
 * onto a library that already has notes. The browser store is real; the bundled photograph and the picture store
 * are stood in for, since jsdom can neither fetch the asset nor draw it smaller.
 */

let photo: Blob | null = new Blob([new Uint8Array([1, 2, 3])], { type: 'image/jpeg' });
let keep: (blob: Blob) => Promise<string> = async () => 'smoke.jpg';
vi.mock('./sampleNote.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./sampleNote.ts')>()),
  sampleImageBlob: async () => photo,
}));
vi.mock('./images.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./images.ts')>()),
  saveImageFile: (blob: Blob) => keep(blob),
}));

const { addCanvasNote, seedSampleNote, sampleNoteSeeded } = await import('./seed.ts');
const { listNotes } = await import('./store.ts');

beforeEach(() => {
  localStorage.clear();
  photo = new Blob([new Uint8Array([1, 2, 3])], { type: 'image/jpeg' });
  keep = async () => 'smoke.jpg';
});

describe('the sample note', () => {
  it('arrives once in an empty library, with its picture', async () => {
    const note = await seedSampleNote(0);
    expect(note?.body).toContain('(image/smoke.jpg)');
    expect(sampleNoteSeeded()).toBe(true);
    expect(await seedSampleNote(0)).toBeNull();
    expect(await listNotes()).toHaveLength(1);
  });

  it('never arrives in a library that already has notes, and is not waiting for the day it is empty', async () => {
    expect(await seedSampleNote(3)).toBeNull();
    expect(sampleNoteSeeded()).toBe(true);
    expect(await seedSampleNote(0)).toBeNull();
    expect(await listNotes()).toEqual([]);
  });

  it('arrives without a picture where one cannot be kept, rather than not at all', async () => {
    keep = async () => {
      throw new Error('No picture storage in this browser.');
    };
    const note = await seedSampleNote(0);
    expect(note).not.toBeNull();
    expect(note?.body).not.toContain('image/');
    photo = null;
    const canvas = await addCanvasNote();
    expect(canvas.body).not.toContain('image/');
  });
});
