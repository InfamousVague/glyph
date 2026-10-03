import { READER_URL } from '../../share/share.ts';
import { readStored, writeStored } from '../stored.ts';
import type { InviteLink } from './types.ts';

/**
 * Invite links on this side (docs/TEAMS.md, "Invite by link"; server/src/store/org_links.rs). Matt: "add the ability
 * to invite people to a team by link".
 *
 * A link is the reader page with the code in its hash, `https://ghostmarkdown.com/read.html#join=<code>`, as a share
 * link is the reader page with its key (share/share.ts): the hash never reaches a server's logs, and the page is there
 * for anyone, with the app or without. It offers the two ways in - `ghostmd://join/<code>`, which the phone and the
 * Mac hand to the app (src-tauri/src/links.rs), and the web app at `#join=<code>` - and the app asks "Join it?" with
 * the organization's name before anything is joined (notes/JoinSheet.tsx).
 *
 * Signed out, the code is held on this device until an account is signed in, and asked about then: a link followed
 * by someone who has not signed up yet is the commonest way in. Pure apart from the held code.
 */

/** A code as the service makes one: 22 base64url characters, taken at 16 to 64 as the route does. */
const CODE = /^[A-Za-z0-9_-]{16,64}$/;

/** The link that is copied and sent: the reader page, with the code where only the browser reads it. */
export function inviteUrl(code: string): string {
  return `${READER_URL}#join=${code}`;
}

/** The link that opens the app itself, from the reader page's "Open in the Ghost.md app". */
export function appJoinLink(code: string): string {
  return `ghostmd://join/${code}`;
}

/**
 * The code an invite link carries, from any of the shapes one arrives in: the link as sent, the web app's
 * `#join=<code>`, the app's `ghostmd://join/<code>`, or the code alone, pasted. Null for anything else.
 */
export function readJoinLink(text: string): string | null {
  const trimmed = text.trim();
  if (CODE.test(trimmed)) return trimmed;
  const app = /^ghostmd:\/\/join\/([^/?#\s]+)\/?$/.exec(trimmed)?.[1];
  if (app) return CODE.test(app) ? app : null;
  const hash = /#join=([^&\s]+)$/.exec(trimmed)?.[1];
  return hash && CODE.test(hash) ? hash : null;
}

/** A link's name on its row: the end of its code, enough to tell two apart, where the whole link would be cut off. */
export function linkName(code: string): string {
  return `Link ending ${code.slice(-5)}`;
}

// --- how long, and how many --------------------------------------------------------------

const HOUR = 3600;
const DAY = 24 * HOUR;

/** How long a new link lasts: the choices offered, seconds, and null for until it is turned off. */
export const LIFETIMES: readonly { value: string; label: string; seconds: number | null }[] = [
  { value: 'day', label: 'A day', seconds: DAY },
  { value: 'week', label: 'A week', seconds: 7 * DAY },
  { value: 'month', label: '30 days', seconds: 30 * DAY },
  { value: 'never', label: 'No end', seconds: null },
];

/** How many may join by a new link: the choices offered, and null for no limit. */
export const USES: readonly { value: string; label: string; uses: number | null }[] = [
  { value: 'one', label: 'One person', uses: 1 },
  { value: 'five', label: 'Five', uses: 5 },
  { value: 'many', label: 'Twenty-five', uses: 25 },
  { value: 'any', label: 'No limit', uses: null },
];

/** How long is left, in the plainest words: "in 5 hours", "in 6 days". */
function within(ms: number): string {
  const hours = Math.max(1, Math.round(ms / (HOUR * 1000)));
  if (hours < 48) return `in ${hours} hour${hours === 1 ? '' : 's'}`;
  const days = Math.round(hours / 24);
  return `in ${days} days`;
}

/** What a link's row says under it: how long it lasts and how many have used it. */
export function linkTermsWords(link: InviteLink, now: number): string {
  const lasts = link.expiresAt === null ? 'Lasts until turned off' : `Stops ${within(link.expiresAt - now)}`;
  const used =
    link.maxUses === null
      ? link.uses === 0
        ? 'none joined yet'
        : `${link.uses} joined`
      : `${link.uses} of ${link.maxUses} used`;
  return `${lasts} · ${used}`;
}

// --- a code held across signing in -------------------------------------------------------

const HELD = 'glyph-join-held';

/** A code is held at most a week: a link followed and forgotten should not ask a month later. */
const HELD_FOR = 7 * DAY * 1000;

function asHeld(raw: unknown): { code: string; at: number } | null {
  if (!raw || typeof raw !== 'object') return null;
  const { code, at } = raw as { code?: unknown; at?: unknown };
  return typeof code === 'string' && CODE.test(code) && typeof at === 'number' ? { code, at } : null;
}

/** Keeps a code on this device until it is asked about: followed while signed out. */
export function holdJoin(code: string, now = Date.now()): void {
  writeStored(HELD, { code, at: now });
}

/** The code held, if one is and it is not stale. */
export function heldJoin(now = Date.now()): string | null {
  const held = readStored(HELD, null, asHeld);
  return held && now - held.at < HELD_FOR ? held.code : null;
}

/** The held code let go: joined, or the person said no. */
export function dropHeldJoin(): void {
  writeStored(HELD, null);
}
