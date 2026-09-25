/**
 * Bytes written out as text, the two ways the app needs them outside the sealed wire: standard base64, which is what
 * Rust reads when bytes cross the bridge as a string (`save_image_data`, `sync_put_file`), and hex, which is how a
 * digest is written down.
 *
 * The URL-safe base64 of the sync wire is core/sync/crypto.ts's (`toBase64Url`), since the MCP server shares it from
 * there. This one is standard base64 with its padding: the sync engine used to make it by turning `toBase64Url`'s
 * answer back, and the pictures kept a private copy of the loop below.
 *
 * A leaf with no imports, pure, so a test compares it with Node's own Buffer.
 */

/**
 * Standard, padded base64. Built in slices because `String.fromCharCode(...bytes)` on a large array overruns the
 * engine's argument limit, and a recording is a large array; 0x8000 is comfortably under it.
 */
export function toBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

/** Two lower-case hex digits a byte. */
export function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}
