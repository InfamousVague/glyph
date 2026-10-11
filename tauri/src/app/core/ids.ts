import { toBase64Url } from './sync/crypto.ts';

/**
 * A fresh id that nothing else has: a note's, a conflict copy's, a picture's, a notification's.
 *
 * `crypto.randomUUID` needs a secure context, which a Tauri custom protocol is
 * and an `http://` dev server on a phone on the LAN is not - so the fallback is
 * not hypothetical, it is what runs when the editor is opened from another
 * device on the network. The fallback is the time and eight random characters
 * behind a prefix that says what the id is for, which is unique enough for
 * the ids one device makes.
 *
 * Two modules wrote this out, and a third - the pictures' - called
 * `crypto.randomUUID` with no fallback, so pasting a picture on the LAN dev
 * server threw. Shared with the MCP server, whose only other import from here
 * is the crypto module this one leans on for the base64url spelling.
 */

/** A UUID where the context allows one, and `<prefix>-<time>-<random>` where it does not. */
export function randomId(prefix = 'n'): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

/** How long a short id is: 128 random bits as base64url, with no padding. */
export const SHORT_ID_LENGTH = 22;

/**
 * A short id: 22 base64url characters, 128 random bits, made the way a share's id is (share/share.ts `newShareId`).
 * The shape the service gives an organization and asks of a notification (docs/TEAMS.md): the page makes one for
 * each self notification it records (core/notifications/record.ts), and the MCP server for each it posts after a
 * write. `getRandomValues` needs no secure context, so there is no fallback to have.
 */
export function shortId(): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(16)));
}

/** Whether `text` is a short id as `shortId` makes one: the service's check, made here before a round trip. */
export function isShortId(text: string): boolean {
  return /^[A-Za-z0-9_-]{22}$/.test(text);
}
