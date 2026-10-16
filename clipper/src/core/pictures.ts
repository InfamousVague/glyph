import { fromBase64Url, type Bytes } from '../../../tauri/src/app/core/sync/crypto.ts';
import { randomId } from '../../../tauri/src/app/core/ids.ts';
import { MOST_PICTURES, PICTURE_SCHEME } from './kinds.ts';
import type { PictureRef } from './markdown.ts';

/**
 * A clip's pictures, stored as the app stores a picture: fetched, drawn smaller as the app draws a pasted picture
 * (core/imageShrink.ts: at most 1600 px on the long side, a JPEG, over white paper), named by a random id with the
 * `.jpg` its bytes are, and then sealed and sent through the app's own file route by the account (core/account.ts).
 * The phone keeps a picture only if its name ends in jpg, jpeg, png or webp and its bytes are that (native
 * kept/images.rs), so every picture is made a JPEG here, which also leaves behind what a camera wrote into it.
 *
 * A picture that cannot be stored stays a link to where it is (`![alt](https://…)`), which other Markdown apps
 * draw and Ghost.md shows as a link: one over `PICTURE_LIMIT` before it is made smaller, one the page's site will
 * not hand over, one the browser cannot open (an SVG, say), and every one after the first `MOST_PICTURES`. A picture
 * the page carried inline (`data:`) has nowhere to link to and is left out.
 */

/** The most bytes a picture may be, as fetched, to be stored: past this it is linked. */
export const PICTURE_LIMIT = 15 * 1024 * 1024;

/** The longest side a stored picture keeps, as the app keeps a pasted one, and the quality it is written at. */
export const LONG_SIDE = 1600;
export const QUALITY = 0.85;

export interface Fetched {
  bytes: Bytes;
  type: string;
}

/** Why a picture was linked rather than stored, said in the popup's count. */
export type LinkReason = 'too-big' | 'not-reachable' | 'unreadable' | 'too-many';

/** One way to fetch a picture: in the page (where its site lets the page have it), or by the extension (where the person allowed that site). */
export type PictureFetcher = (url: string, limit: number) => Promise<Fetched | 'too-big' | null>;

/** A picture made into a stored JPEG; null where the browser cannot open it. */
export type Shrinker = (picture: Fetched) => Promise<Bytes | null>;

export interface StoredPicture {
  index: number;
  name: string;
  bytes: Bytes;
}

export interface Placed {
  stored: StoredPicture[];
  linked: { index: number; url: string; why: LinkReason }[];
}

/** A `data:` address's bytes and type; null for one that is not a picture. */
export function fromDataUrl(url: string): Fetched | null {
  const found = /^data:(image\/[A-Za-z0-9.+-]+)(;base64)?,(.*)$/s.exec(url);
  if (!found) return null;
  const [, type, base64, data] = found;
  if (base64) {
    const text = data!.replace(/\s+/g, '').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    return { type: type!, bytes: fromBase64Url(text) };
  }
  return { type: type!, bytes: new TextEncoder().encode(decodeURIComponent(data!)) as Bytes };
}

/** A new stored picture's name: random, so it is never reused (core/sync/notes.ts relies on that), and short enough for the service's file id. */
export function pictureName(): string {
  return `clip-${randomId('img').replace(/[^A-Za-z0-9_-]/g, '')}.jpg`;
}

/** Each of `pictures` stored or linked: fetched by the first fetcher that has it, and made a JPEG. */
export async function resolvePictures(pictures: readonly PictureRef[], { fetchers, shrink, limit = PICTURE_LIMIT, most = MOST_PICTURES }: { fetchers: readonly PictureFetcher[]; shrink: Shrinker; limit?: number; most?: number }): Promise<Placed> {
  const placed: Placed = { stored: [], linked: [] };
  for (const [index, picture] of pictures.entries()) {
    if (index >= most) {
      placed.linked.push({ index, url: picture.url, why: 'too-many' });
      continue;
    }
    let fetched: Fetched | 'too-big' | null = null;
    if (picture.url.startsWith('data:')) fetched = fromDataUrl(picture.url);
    else {
      for (const fetcher of fetchers) {
        fetched = await fetcher(picture.url, limit).catch(() => null);
        if (fetched) break;
      }
    }
    if (fetched === 'too-big' || (fetched && fetched.bytes.length > limit)) {
      placed.linked.push({ index, url: picture.url, why: 'too-big' });
      continue;
    }
    if (!fetched) {
      placed.linked.push({ index, url: picture.url, why: 'not-reachable' });
      continue;
    }
    const bytes = await shrink(fetched).catch(() => null);
    if (!bytes) {
      placed.linked.push({ index, url: picture.url, why: 'unreadable' });
      continue;
    }
    placed.stored.push({ index, name: pictureName(), bytes });
  }
  return placed;
}

/**
 * The words with every picture where it now is: a stored one at `image/<name>`, as the app writes it
 * (core/imageRefs.ts), a linked one at its own address, and one that was inline and could not be stored taken out
 * with its line, if the line held nothing else.
 */
export function placePictures(markdown: string, pictures: readonly PictureRef[], placed: Placed): string {
  const where = new Map<number, string | null>();
  for (const s of placed.stored) where.set(s.index, `image/${s.name}`);
  for (const l of placed.linked) where.set(l.index, l.url.startsWith('data:') ? null : l.url.replace(/[ ()<>]/g, encodeURIComponent));
  const pattern = new RegExp(`!\\[([^\\]]*)\\]\\(${PICTURE_SCHEME.replace(/[/]/g, '\\/')}(\\d+)\\)`, 'g');
  return markdown
    .replace(pattern, (_m, alt: string, n: string) => {
      const index = Number(n);
      const to = where.has(index) ? where.get(index)! : (pictures[index]?.url.startsWith('data:') ? null : (pictures[index]?.url ?? null));
      return to ? `![${alt}](${to})` : '';
    })
    .replace(/\n{3,}/g, '\n\n');
}

/** Words for the popup about what was not stored: "2 pictures stay links". */
export function linkedWords(count: number): string {
  return count === 1 ? '1 picture stays a link' : `${count} pictures stay links`;
}

/**
 * The browser's own way to make a picture a JPEG, where there is no page to draw on (the extension's service
 * worker): an `ImageBitmap` drawn onto an `OffscreenCanvas` over white, at most `LONG_SIDE` on the long side, the
 * right way up. Null where the browser will not open the bytes.
 */
export async function shrinkInBrowser(picture: Fetched): Promise<Bytes | null> {
  if (typeof createImageBitmap !== 'function' || typeof OffscreenCanvas !== 'function') return null;
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(new Blob([picture.bytes], { type: picture.type }), { imageOrientation: 'from-image' });
  } catch {
    return null;
  }
  const scale = Math.min(1, LONG_SIDE / Math.max(bitmap.width, bitmap.height));
  const canvas = new OffscreenCanvas(Math.max(1, Math.round(bitmap.width * scale)), Math.max(1, Math.round(bitmap.height * scale)));
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: QUALITY });
  return new Uint8Array(await blob.arrayBuffer());
}
