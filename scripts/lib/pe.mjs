/**
 * A Windows program read on a Mac, for scripts/deploy-windows.mjs: what its PE header says, and the version in an
 * installer's name. No signtool here, so whether it is signed is read from the file itself.
 */

/**
 * What a PE file says of itself: whether it is one, its machine, and whether it carries an Authenticode signature
 * (a certificate table with something in it; whether Windows trusts the signer is Windows' to say).
 */
export function readPe(bytes) {
  if (bytes.length < 0x40 || bytes.readUInt16LE(0) !== 0x5a4d) return null;
  const pe = bytes.readUInt32LE(0x3c);
  if (pe + 24 > bytes.length || bytes.readUInt32LE(pe) !== 0x00004550) return null;
  const machine = bytes.readUInt16LE(pe + 4);
  const optional = pe + 24;
  const magic = bytes.readUInt16LE(optional);
  // The data directories follow the optional header's fixed part: 96 bytes in PE32, 112 in PE32+. The fifth is the
  // certificate table: a file offset and a size.
  const directories = optional + (magic === 0x20b ? 112 : 96);
  const certificate = directories + 4 * 8;
  const signed = certificate + 8 <= bytes.length && bytes.readUInt32LE(certificate) > 0 && bytes.readUInt32LE(certificate + 4) > 0;
  const arch = machine === 0x8664 ? 'x64' : machine === 0xaa64 ? 'arm64' : machine === 0x14c ? 'x86' : `machine ${machine.toString(16)}`;
  return { arch, signed };
}

/** The version in an installer's name as Tauri writes it: `Ghost.md_1.14.0_x64-setup.exe`. */
export function versionIn(name) {
  return /_(\d+\.\d+\.\d+)_/.exec(name)?.[1] ?? null;
}
