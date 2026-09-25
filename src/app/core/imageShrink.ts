/**
 * A picture made smaller on the page: drawn onto a canvas at most so many pixels on its long side, the right way up,
 * over white paper, and taken back as a JPEG.
 *
 * Two callers, for two reasons. A picture pasted from the clipboard is kept at 1600 px (core/images.ts
 * `saveImageFile`), since a phone's screenshot or a photo straight off the camera is several times what a note ever
 * draws; the phone's own picker shrinks in the activity instead (MainActivity.kt), before the page sees it. And a
 * share that would not hold its pictures as they are carries reading copies drawn smaller (share/share.ts, through
 * `smallerImage`).
 *
 * Its own module because it is the one part of the pictures that needs a real browser's canvas and image decoder,
 * which jsdom has neither of: a test of where pictures go stands in for this, and this alone.
 */

/** A picture shrunk so its long side is at most `longSide` px (1600 as it is kept), as a JPEG, turned the right way up. */
export async function shrink(file: Blob, longSide = 1600, quality = 0.85): Promise<Blob> {
  // An empty file is a clipboard pointing at a picture that has since been
  // cleaned up: Chrome on Android copies a picture as a link to a file it
  // deletes after a while, and the paste still says "image" with no bytes.
  if (!file.size) throw new Error('That picture isn’t on the clipboard anymore. Copy it again and paste.');
  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' }).catch(() => {
    throw new Error('That picture couldn’t be opened.');
  });
  const scale = Math.min(1, longSide / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('The picture could not be read.');
  // Paper under a transparent PNG, so a screenshot with no background does not turn black as a JPEG.
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
  if (!blob) throw new Error('The picture could not be read.');
  return blob;
}
