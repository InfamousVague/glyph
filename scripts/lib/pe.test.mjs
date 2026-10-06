import { describe, expect, it } from 'vitest';
import { readPe, versionIn } from './pe.mjs';

/** A Windows program read on a Mac (scripts/lib/pe.mjs), for the deploy that publishes the installer. */

/** The least of a PE file: a DOS header pointing at a PE header, its machine, and a certificate table or none. */
function pe({ machine = 0x14c, plus = false, certificate = [0, 0] } = {}) {
  const bytes = Buffer.alloc(0x200);
  bytes.writeUInt16LE(0x5a4d, 0);
  bytes.writeUInt32LE(0x80, 0x3c);
  bytes.writeUInt32LE(0x00004550, 0x80);
  bytes.writeUInt16LE(machine, 0x84);
  const optional = 0x80 + 24;
  bytes.writeUInt16LE(plus ? 0x20b : 0x10b, optional);
  const table = optional + (plus ? 112 : 96) + 4 * 8;
  bytes.writeUInt32LE(certificate[0], table);
  bytes.writeUInt32LE(certificate[1], table + 4);
  return bytes;
}

describe('a Windows program, read here', () => {
  it('says its machine, and that it is unsigned with no certificate table', () => {
    expect(readPe(pe())).toEqual({ arch: 'x86', signed: false });
    expect(readPe(pe({ machine: 0x8664, plus: true }))).toEqual({ arch: 'x64', signed: false });
    expect(readPe(pe({ machine: 0xaa64, plus: true }))).toEqual({ arch: 'arm64', signed: false });
  });

  it('is signed where the certificate table holds something', () => {
    expect(readPe(pe({ certificate: [0x1000, 0x2a10] }))?.signed).toBe(true);
    expect(readPe(pe({ plus: true, certificate: [0x1000, 0x2a10] }))?.signed).toBe(true);
  });

  it('is nothing where the file is not one', () => {
    expect(readPe(Buffer.from('not a program'))).toBeNull();
    expect(readPe(Buffer.alloc(0x200))).toBeNull();
  });

  it('finds the version in an installer’s name', () => {
    expect(versionIn('Ghost.md_1.14.0_x64-setup.exe')).toBe('1.14.0');
    expect(versionIn('setup.exe')).toBeNull();
  });
});
