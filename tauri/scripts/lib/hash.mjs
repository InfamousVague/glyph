/**
 * SHA-256 as the releases write it: lowercase hex, the form ota.json,
 * apk.json and desktop.json carry and the app compares against.
 *
 * Two shapes because the files come in two sizes. A build's assets, the APK
 * and the served copies a deploy checks are already in memory as buffers;
 * a model is 60 MB to 5.7 GB and is hashed as it streams off the disk, so
 * fetch-model never holds one whole.
 *
 * Not here: the hashes that are built up piece by piece (the source
 * fingerprint in testReport/source.mjs, the running hash of a download in
 * fetch-model), which feed a hash as they go and have no bytes to hand over.
 */
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';

/** The SHA-256 of these bytes, in hex. */
export function sha256Hex(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

/** The SHA-256 of the file at `path`, in hex, read as a stream. */
export async function sha256OfFile(path) {
  const hash = createHash('sha256');
  await pipeline(createReadStream(path), hash);
  return hash.digest('hex');
}
