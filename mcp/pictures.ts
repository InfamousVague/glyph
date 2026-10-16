import { randomUUID } from 'node:crypto';
import { lookup as dnsLookup } from 'node:dns';
import { request } from 'node:https';
import { BlockList, isIP, type LookupFunction } from 'node:net';
import type { Bytes } from '../tauri/src/app/core/sync/crypto.ts';

/**
 * A picture from the web, for `add_picture` (mcp/server.ts; Matt: "Update the note with embedded links and pictures").
 * The editor draws only a picture the library keeps (`![caption](image/<name>)`, lib/editor/media/images.dart), never
 * an address, so the connector does what a phone does with a picture it is given: takes the bytes, names them, and
 * keeps them where every device fetches them from.
 *
 * The bytes are read as what they are, not as what the server says they are: a JPEG, a PNG or a WebP by its first
 * bytes, as the phone's core checks a picture it keeps (native/src/kept/images.rs `valid_name` and its magic), and at
 * most [PICTURE_LIMIT], the clipper's (clipper/src/core/pictures.ts). Nothing is re-encoded: Node has no canvas.
 *
 * The hosted server fetches it from the box, so an address only reaches the public internet: https alone, every
 * address a name resolves to checked against the private, loopback and link-local ranges, at the moment of connecting
 * (the lookup the socket uses, so a name cannot answer one address to the check and another to the connection), and
 * each redirect checked again, at most [MOST_REDIRECTS].
 */

/** The most a picture may be, in bytes. */
export const PICTURE_LIMIT = 15 * 1024 * 1024;
const MOST_REDIRECTS = 5;
const TIMEOUT_MS = 20_000;
/** Who is asking, as the map tiles say it (lib/editor/media/map_tiles.dart): Wikimedia refuses an anonymous agent. */
const USER_AGENT = 'GhostMd/1.0 (https://ghostmarkdown.com)';

/** A picture's kind, by the extension its name takes. */
export type PictureKind = 'jpg' | 'png' | 'webp';

/** What a picture's first bytes say it is, or null for anything the app does not keep. */
export function pictureKindOf(bytes: Bytes): PictureKind | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'jpg';
  if (bytes.length >= 8 && [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((b, i) => bytes[i] === b)) return 'png';
  const ascii = (from: number, to: number) => String.fromCharCode(...bytes.subarray(from, to));
  if (bytes.length >= 12 && ascii(0, 4) === 'RIFF' && ascii(8, 12) === 'WEBP') return 'webp';
  return null;
}

/** A new picture's name, as a device names one: never used before, so sync never confuses two (core/images.ts). */
export function pictureName(kind: PictureKind): string {
  return `${randomUUID()}.${kind}`;
}

/** Addresses no picture is fetched from: this machine, its networks, and what is not an internet address at all. */
const closed = new BlockList();
for (const [net, bits] of [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.168.0.0', 16],
  ['198.18.0.0', 15],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
] as const)
  closed.addSubnet(net, bits, 'ipv4');
for (const [net, bits] of [
  ['::', 128],
  ['::1', 128],
  ['64:ff9b::', 96],
  ['fc00::', 7],
  ['fe80::', 10],
  ['ff00::', 8],
] as const)
  closed.addSubnet(net, bits, 'ipv6');

/** Whether `address` is one a picture may be fetched from. An IPv4 address written as IPv6 is judged as itself. */
export function isPublicAddress(address: string): boolean {
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address);
  if (mapped) return isPublicAddress(mapped[1]!);
  const family = isIP(address);
  if (family === 4) return !closed.check(address, 'ipv4');
  if (family === 6) return !closed.check(address, 'ipv6');
  return false;
}

/** The socket's own lookup, refusing a name that answers any address that is not public. */
const publicLookup: LookupFunction = (hostname, options, callback) => {
  dnsLookup(hostname, { ...options, all: true }, (failure, addresses) => {
    if (failure) return callback(failure, '', 0);
    const all = addresses as unknown as { address: string; family: number }[];
    if (!all.length || all.some((a) => !isPublicAddress(a.address))) {
      return callback(Object.assign(new Error(`${hostname} is not a public address.`), { code: 'ENOTPUBLIC' }), '', 0);
    }
    if ((options as { all?: boolean }).all) return (callback as unknown as (e: null, a: typeof all) => void)(null, all);
    callback(null, all[0]!.address, all[0]!.family);
  });
};

/** An address a picture may be fetched from, or why not. */
function checked(address: string): URL {
  let url: URL;
  try {
    url = new URL(address);
  } catch {
    throw new Error(`${address} is not an address.`);
  }
  if (url.protocol !== 'https:') throw new Error('A picture is fetched over https only.');
  if (url.username || url.password) throw new Error('A picture’s address may not carry a name or password.');
  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (isIP(host) && !isPublicAddress(host)) throw new Error(`${host} is not a public address.`);
  return url;
}

/** One GET: the status, where a redirect points, and the body up to the limit. */
function get(url: URL): Promise<{ status: number; location: string | null; bytes: Bytes }> {
  return new Promise((resolve, reject) => {
    const req = request(url, { method: 'GET', lookup: publicLookup, headers: { 'User-Agent': USER_AGENT, Accept: 'image/webp,image/png,image/jpeg,image/*;q=0.8' }, timeout: TIMEOUT_MS }, (res) => {
      const status = res.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        res.resume();
        return resolve({ status, location: res.headers.location ?? null, bytes: new Uint8Array() });
      }
      const said = Number(res.headers['content-length'] ?? 0);
      if (said > PICTURE_LIMIT) {
        res.destroy();
        return reject(new Error(`That picture is ${Math.ceil(said / 1024 / 1024)} MB; at most 15 MB is kept.`));
      }
      const chunks: Buffer[] = [];
      let length = 0;
      res.on('data', (chunk: Buffer) => {
        length += chunk.length;
        if (length > PICTURE_LIMIT) {
          res.destroy();
          reject(new Error('That picture is larger than 15 MB, which is the most kept.'));
        } else chunks.push(chunk);
      });
      res.on('end', () => resolve({ status, location: null, bytes: new Uint8Array(Buffer.concat(chunks)) }));
      res.on('error', reject);
    });
    req.on('timeout', () => req.destroy(new Error('The picture’s server took too long to answer.')));
    req.on('error', reject);
    req.end();
  });
}

/** A picture fetched from `address`, following its redirects, and what kind it is; refused with a sentence. */
export async function downloadPicture(address: string): Promise<{ bytes: Bytes; kind: PictureKind }> {
  let url = checked(address);
  for (let hop = 0; ; hop++) {
    const answer = await get(url);
    if (answer.location !== null) {
      if (hop >= MOST_REDIRECTS) throw new Error('That address redirects too many times.');
      url = checked(new URL(answer.location, url).toString());
      continue;
    }
    if (answer.status < 200 || answer.status >= 300) throw new Error(`The picture’s server answered ${answer.status}.`);
    const kind = pictureKindOf(answer.bytes);
    if (!kind) throw new Error('That address is not a JPEG, PNG or WebP picture.');
    return { bytes: answer.bytes, kind };
  }
}

/** Fetches a picture for the tool; a test hands one of its own. */
export type PictureDownloader = (address: string) => Promise<{ bytes: Bytes; kind: PictureKind }>;

/**
 * `body` with `line` (a picture's markdown) put under the first line that reads `after`, or at the end: on a line of
 * its own, a blank line from a list, a quote, a table or a paragraph above it (a picture straight under `- [ ] ` was a
 * to-do of it; under a table, a row), and from any words below it (docs/MARKDOWN.md, "Where an insert goes"). Null
 * when no line reads `after`.
 */
export function placePicture(body: string, line: string, after?: string): string | null {
  const lines = body.split('\n');
  let at: number;
  if (after !== undefined && after.trim()) {
    const want = after.trim();
    at = lines.findIndex((l) => l.trim() === want);
    if (at < 0) return null;
  } else {
    at = lines.length - 1;
    while (at > 0 && !lines[at]!.trim()) at--;
  }
  const above = lines[at] ?? '';
  const heading = /^#{1,6}\s/.test(above.trim());
  const put = [...(above.trim() && !heading ? [''] : []), line];
  const below = lines[at + 1];
  if (below !== undefined && below.trim()) put.push('');
  const next = [...lines.slice(0, at + 1), ...put, ...lines.slice(at + 1)];
  const joined = next.join('\n');
  return joined.endsWith('\n') ? joined : `${joined}\n`;
}
