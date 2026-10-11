import { afterEach, describe, expect, it, vi } from 'vitest';
import { shrink } from './imageShrink.ts';

/**
 * Opening a picture to shrink it (core/imageShrink.ts): the one question here is how it is opened, since jsdom has no
 * image decoder and no canvas to draw on. An engine that refuses the turning option (WebKit on an older Mac) is asked
 * again without it; an engine that cannot open the picture at all is not asked twice.
 */

const picture = new Blob([new Uint8Array(16)], { type: 'image/jpeg' });

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('opening a picture to shrink it', () => {
  it('asks again without the turning option when the engine refuses the option', async () => {
    const asked: unknown[] = [];
    vi.stubGlobal('createImageBitmap', async (_file: Blob, options?: ImageBitmapOptions) => {
      asked.push(options);
      if (options) throw new TypeError('imageOrientation: from-image is not supported');
      return { width: 10, height: 10, close: () => undefined };
    });
    // jsdom draws nothing, so the picture gets as far as the canvas and no further: it was opened.
    await expect(shrink(picture)).rejects.toThrow('The picture could not be read.');
    expect(asked).toEqual([{ imageOrientation: 'from-image' }, undefined]);
  });

  it('asks once, and says so in words, when the picture itself cannot be opened', async () => {
    let asked = 0;
    vi.stubGlobal('createImageBitmap', async () => {
      asked += 1;
      throw new DOMException('The source image could not be decoded.', 'InvalidStateError');
    });
    await expect(shrink(picture)).rejects.toThrow('That picture couldn’t be opened.');
    expect(asked).toBe(1);
  });
});
