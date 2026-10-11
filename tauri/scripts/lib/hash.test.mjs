// @vitest-environment node
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';
import { sha256Hex, sha256OfFile } from './hash.mjs';

/*
 * The form the manifests carry and the app compares against: lowercase hex of
 * SHA-256. The answer for "abc" is FIPS 180-2's own worked example, so a slip
 * in either helper cannot hide behind the other agreeing with it.
 */

const ABC = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const EMPTY = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

describe('SHA-256 in hex', () => {
  const dir = mkdtempSync(join(tmpdir(), 'glyph-hash-'));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));

  it('of bytes in memory, for strings and buffers alike', () => {
    expect(sha256Hex(Buffer.from('abc'))).toBe(ABC);
    expect(sha256Hex('abc')).toBe(ABC);
    expect(sha256Hex(Buffer.alloc(0))).toBe(EMPTY);
  });

  it('of a file read as a stream, the same answer as its bytes in memory', async () => {
    const small = join(dir, 'abc');
    writeFileSync(small, 'abc');
    expect(await sha256OfFile(small)).toBe(ABC);
    // Past one read chunk (64 KiB), so the stream really does arrive in pieces.
    const bytes = Buffer.alloc(300_000, 7);
    const large = join(dir, 'large');
    writeFileSync(large, bytes);
    expect(await sha256OfFile(large)).toBe(sha256Hex(bytes));
  });

  it('of a file that is not there, a rejection rather than a hash', async () => {
    await expect(sha256OfFile(join(dir, 'missing'))).rejects.toThrow(/ENOENT/);
  });
});
