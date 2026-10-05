import type { SignedIn } from '../app/core/account/account.ts';
import { NO_SUCH_ROUTE } from '../app/core/account/api.ts';
import { shortId } from '../app/core/ids.ts';
import { isSelfKind, type Kind, type Notification } from '../app/core/notifications/kinds.ts';
import type { InviteLink, Member, Org, OrgRow, Role } from '../app/core/orgs/types.ts';
import type { Note } from '../app/core/store.ts';
import { derive, fromBase64Url, newAccountKey, open, passwordSalt, seal, wrap, type Bytes } from '../app/core/sync/crypto.ts';
import type { FeedItem, NotePayload } from '../app/core/sync/notes.ts';
import { WORKSPACE_HUES } from '../app/core/workspaces.ts';

/** How many updates a note's log holds before a snapshot must cut it (docs/SHARED.md, S11), as the service keeps it. */
export const UPDATES_KEPT = 500;

/**
 * Glyph's account and sync service in memory, for tests: the routes, revisions and refusals of
 * server/src/accounts.rs and server/src/sync.rs, so every rule a client lives by is tried without a server. Served to
 * the code under test as a `fetch` (`fetcher`), which is how the app's calls (core/account/api.ts), the MCP server's
 * (mcp/glyph.ts) and the hosted page's all take it.
 *
 * One account at most, as a device only ever knows one: already there (`fakeService({ handle, password })`, the
 * account a test signs in to), or made by a signup through the fetcher (`fakeService()`, for the account flows
 * themselves). Its feed of notes, its settings, its recordings and its notifications share one revision counter, as
 * the server's do. Other people exist only as `peers`: handles that resolve for an invitation without being the
 * account, and never call anything.
 *
 * The organizations and notifications routes (server/src/orgs.rs, notifications.rs; docs/TEAMS.md) are here with
 * the server's refusals in its own words, since the client is built on telling those apart from a route the service
 * does not have yet: `{ teams: false }` plays that older service, answering every one of them `no such route`. What
 * the server would write into OTHER accounts' feeds goes nowhere here, since the one account is always the caller;
 * `notifies(row)` plays a row the server wrote into this account's feed, and `invited(name, by)` an organization a
 * peer invited the account to.
 *
 * What it does NOT do: rate limits, and most shape checks on ids and blobs - those are the server's own, tested in
 * server/src. And it never holds the account key the way the server never does, with one exception it says out loud:
 * for an account it was given a password for, it made the key itself, so it can play "another device" - sealing a
 * note as the app seals one (`deviceWrites`) and opening what a client wrote (`stored`).
 *
 * The MCP's tests (mcp/glyph.test.ts, mcp/hosted.test.ts) and the app's (core/sync/pictures.test.ts,
 * core/account/account.test.ts, core/sync/prefs.test.ts, core/notifications/feed.test.ts, core/orgs/orgs.test.ts)
 * all use this one; there were two copies, and they had started to answer differently.
 */

/** PBKDF2 rounds for a test: the real 600 000 are for a person's password, not for a test that makes ten accounts. */
export const FAST = 1_000;

/** The id the one account is given, whoever makes it. */
const ACCOUNT_ID = 7;

/** A note as the service keeps it: a feed item, filed under the id it leaves out. */
type Stored = Omit<FeedItem, 'id'>;

interface Account {
  handle: string;
  /** The login half of the password, as sign-in sends it (the server keeps a hash of it; a test needs no hash). */
  loginSecret: string;
  /** The account key wrapped under the password's other half. */
  wrapped: string;
  /** Each device's public signing key, as base64url. */
  devices: string[];
  /** The recovery sheet: each code's login half, and the account key wrapped under that code. */
  recovery: Map<string, string>;
  /** The account key itself, only for an account this service was given a password for (see the header). */
  key: CryptoKey | null;
  /** The account's colour (docs/SHARED.md, S7), and its encryption key pair as registered (S3). */
  hue?: string | null;
  encryption?: { pub: string; sealed: string } | null;
}

export interface FakeServiceOptions {
  /** False: a HEAD never reaches the service, and the fetch throws as a browser's does when something drops it. */
  head?: boolean;
  /** False: a service from before organizations, answering every orgs and notifications route `no such route`. */
  teams?: boolean;
  /** Handles that resolve for an invitation without being the account (`'sam'` by default). */
  peers?: string[];
}

/** A row of an organization as the service keeps it: who, their role, and whether they joined, wait, or declined. */
interface Row {
  handle: string;
  role: Role;
  state: 'member' | 'invited' | 'declined';
  since: number;
  invitedBy: string | null;
  /** Their colour in this organization, overriding their account's (docs/SHARED.md, S7). */
  hue?: string | null;
}

/** An invite link as the service keeps it (server/src/store/org_links.rs): its organization, and who made it. */
interface StoredLink extends InviteLink {
  orgId: string;
}

interface StoredOrg {
  id: string;
  name: string;
  hue: string | null;
  createdAt: number;
  /** By handle, lower-cased. */
  rows: Map<string, Row>;
  /** The organization key's generation in force (docs/SHARED.md, S2); absent for none yet. */
  generation?: number;
  /** Turns the key owes (S11): members gone since the generation was made; cleared by the next generation. */
  turns?: number;
  /** The key wrapped per member, by handle lower-cased, then by generation. */
  wraps?: Map<string, Map<number, string>>;
  /** The team's notes (S4), its write counter, each note's log and its next seq, and its files. */
  rev?: number;
  notes?: Map<string, TeamRow>;
  updates?: Map<string, { seq: number; blob: string; by: string; at: number }[]>;
  seqs?: Map<string, number>;
  files?: Map<string, { rev: number; bytes: Bytes }>;
}

/** A team note's row as the service keeps it (server/src/store/org_notes.rs). */
interface TeamRow {
  rev: number;
  deleted: boolean;
  blob: string | null;
  by: string;
  updatedAt: number;
}

/** The most rows an organization holds, and the most invitations one account may have waiting (docs/TEAMS.md). */
const ORG_ROWS = 50;
const PENDING_INVITES = 20;
/** How long after declining the same organization may not ask again. */
const DECLINE_GAP_MS = 24 * 60 * 60_000;

const encoder = new TextEncoder();

/** The service in memory. `seed`: an account it already holds, signed up with that password. */
export async function fakeService(seed?: { handle: string; password: string }, { head = true, teams = true, peers = ['sam'] }: FakeServiceOptions = {}) {
  let account: Account | null = null;
  if (seed) {
    const key = await newAccountKey();
    const { login, wrapKey } = await derive(seed.password, passwordSalt(seed.handle), FAST);
    account = { handle: seed.handle, loginSecret: login, wrapped: await wrap(key, wrapKey), devices: [], recovery: new Map(), key };
  }
  const notes = new Map<string, Stored>();
  const files = new Map<string, { rev: number; bytes: Bytes }>();
  let prefs: { rev: number; blob: string } | null = null;
  const orgs = new Map<string, StoredOrg>();
  /** Invite links, by code. */
  const links = new Map<string, StoredLink>();
  /** The peers' colours and public keys (docs/SHARED.md), by handle lower-cased: a test gives a peer either. */
  const peerHues = new Map<string, string>();
  const peerKeys = new Map<string, string>();
  /** The account's notifications, by id. */
  const feed = new Map<string, Notification>();
  let counter = 0;
  const tokens = new Set<string>();
  const nonces = new Set<string>();
  let issued = 0;
  /** Every request, as `METHOD path`: what a test asserts the client asked, and in what order. */
  const calls: string[] = [];

  const token = () => {
    const t = `tok-${++issued}`;
    tokens.add(t);
    return t;
  };
  const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  const refuse = (status: number, error: string) => json(status, { error });
  const who = (a: Account) => ({ id: ACCOUNT_ID, handle: a.handle });
  const signedIn = (a: Account, wrapped?: string) => json(200, { token: token(), account: who(a), ...(wrapped ? { wrapped } : {}) } satisfies SignedIn);
  const sameHandle = (a: Account | null, handle: unknown): a is Account => !!a && a.handle.toLowerCase() === String(handle ?? '').trim().toLowerCase();
  const nextRev = () => ++counter;
  const forget = () => {
    account = null;
    notes.clear();
    files.clear();
    prefs = null;
    orgs.clear();
    links.clear();
    feed.clear();
    counter = 0;
    tokens.clear();
  };

  // --- organizations and notifications, as the server keeps them ---

  const lower = (handle: string) => handle.trim().toLowerCase();
  /** A handle as the service knows it: the account's, or a peer's; null for nobody. */
  const resolve = (handle: unknown): string | null => {
    const wanted = lower(String(handle ?? ''));
    if (!wanted) return null;
    if (account && lower(account.handle) === wanted) return account.handle;
    return peers.find((peer) => lower(peer) === wanted) ?? null;
  };
  const isHue = (hue: unknown) => hue === null || (typeof hue === 'string' && (WORKSPACE_HUES as readonly string[]).includes(hue));
  const rowOf = (org: StoredOrg, handle: string) => org.rows.get(lower(handle)) ?? null;
  const joined = (org: StoredOrg) => [...org.rows.values()].filter((r) => r.state === 'member');
  /** A handle's account colour: the account's, or a peer's as a test gave it. */
  const hueOf = (handle: string): string | null => (account && lower(account.handle) === lower(handle) ? (account.hue ?? null) : (peerHues.get(lower(handle)) ?? null));
  /** A handle's encryption public key, as registered. */
  const pubOf = (handle: string): string | null => (account && lower(account.handle) === lower(handle) ? (account.encryption?.pub ?? null) : (peerKeys.get(lower(handle)) ?? null));
  /** A row's colour: its override in the organization, else the account's. */
  const colourOf = (r: Row): string | null => r.hue ?? hueOf(r.handle);
  const wrapOf = (org: StoredOrg, handle: string, at = org.generation): string | null => (at ? (org.wraps?.get(lower(handle))?.get(at) ?? null) : null);
  const stale = (org: StoredOrg) => (org.generation ?? 0) > 0 && (org.turns ?? 0) > 0;
  /** The generation in force, against a body's or a query's: 409 with the one in force when it is another (S11). */
  const inForce = (org: StoredOrg, generation: unknown): Response | null => (typeof generation === 'number' && generation !== (org.generation ?? 0) ? json(409, { error: 'That is not the generation in force.', generation: org.generation ?? 0 }) : null);
  /** Members with a public key and no wrap at the generation in force (every one with a key, before a generation). */
  const lacking = (org: StoredOrg) => joined(org).filter((r) => pubOf(r.handle) !== null && wrapOf(org, r.handle) === null);
  const keysJson = (org: StoredOrg, me: Row) => ({ generation: org.generation ?? 0, mine: wrapOf(org, me.handle) !== null, missing: lacking(org).length, stale: stale(org) });
  const memberJson = (r: Row): Member => ({ handle: r.handle, role: r.role, state: r.state === 'declined' ? 'invited' : r.state, since: r.since, invitedBy: r.invitedBy, colour: colourOf(r), pub: pubOf(r.handle) });
  const orgJson = (org: StoredOrg, me: Row): Org => ({
    id: org.id,
    name: org.name,
    hue: org.hue,
    role: me.role,
    state: me.state === 'declined' ? 'invited' : me.state,
    invitedBy: me.invitedBy,
    createdAt: org.createdAt,
    colour: colourOf(me),
    keys: keysJson(org, me),
    members: [...org.rows.values()].filter((r) => r.state !== 'declined').map(memberJson),
  });
  const rowJson = (org: StoredOrg, me: Row): OrgRow => ({
    id: org.id,
    name: org.name,
    hue: org.hue,
    role: me.role,
    state: me.state === 'declined' ? 'invited' : me.state,
    members: joined(org).length,
    invitedBy: me.invitedBy,
    createdAt: org.createdAt,
    colour: colourOf(me),
    keys: keysJson(org, me),
  });
  /** A row written into the account's feed by the service, at a new revision: what `notifies` plays. */
  const fed = (row: Partial<Notification> & { kind: Kind }): Notification => {
    const item: Notification = { id: shortId(), at: Date.now(), readAt: null, hidden: false, ...row, rev: nextRev() };
    feed.set(item.id, item);
    return item;
  };
  /** The account's pending invitation to `org`, as a feed row, if there is one. */
  const pendingInvite = (orgId: string) => [...feed.values()].find((n) => n.kind === 'invite' && n.org?.id === orgId && n.state === 'pending') ?? null;
  /** A change to a feed row takes a new revision, so every device is fed it again. */
  const touch = (item: Notification, change: Partial<Notification>) => {
    const next = { ...item, ...change, rev: nextRev() };
    feed.set(item.id, next);
    return next;
  };
  /** Whether a link still works: not expired, not used up. */
  const working = (link: StoredLink) => (link.expiresAt === null || link.expiresAt > Date.now()) && (link.maxUses === null || link.uses < link.maxUses);
  const linkJson = ({ orgId: _orgId, ...link }: StoredLink): InviteLink => link;
  /** A link to `org`, made by `by`. */
  const linkTo = (org: StoredOrg, by: string, expiresAt: number | null, maxUses: number | null): StoredLink => {
    const link: StoredLink = { id: shortId(), code: shortId(), orgId: org.id, createdAt: Date.now(), expiresAt, maxUses, uses: 0, by };
    links.set(link.code, link);
    return link;
  };
  /** An organization made by a peer, with the account invited to it: the one way an invitation reaches the account. */
  const inviteAccount = (name: string, by: string): StoredOrg => {
    const org: StoredOrg = { id: shortId(), name, hue: null, createdAt: Date.now(), rows: new Map() };
    org.rows.set(lower(by), { handle: by, role: 'owner', state: 'member', since: org.createdAt, invitedBy: null });
    if (account) {
      org.rows.set(lower(account.handle), { handle: account.handle, role: 'member', state: 'invited', since: Date.now(), invitedBy: by });
      fed({ kind: 'invite', from: by, org: { id: org.id, name }, body: { name }, state: 'pending' });
    }
    orgs.set(org.id, org);
    return org;
  };

  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? 'GET';
    const path = url.pathname.replace(/^.*\/v1\//, '');
    calls.push(`${method} ${path}`);
    // JSON for every route but a recording's PUT, whose body is the bytes themselves.
    const body = typeof init?.body === 'string' && init.body ? (JSON.parse(init.body) as Record<string, unknown>) : {};
    const bearer = new Headers(init?.headers).get('Authorization')?.replace(/^Bearer /, '') ?? null;

    // --- the ways in, which need no session ---
    if (method === 'POST' && path === 'signup') {
      if (account && !sameHandle(account, body.handle)) throw new Error('The fake service holds one account, and this test signed up a second.');
      if (account) return refuse(409, 'That handle is taken.');
      const sheet = (body.recovery ?? []) as { login: string; wrapped: string }[];
      if (sheet.length !== 8) return refuse(400, 'A recovery sheet is eight codes.');
      const made: Account = {
        handle: String(body.handle).trim(),
        loginSecret: String(body.loginSecret ?? '').toLowerCase(),
        wrapped: String(body.wrapped ?? ''),
        devices: body.devicePublicKey ? [String(body.devicePublicKey)] : [],
        recovery: new Map(sheet.map((code) => [code.login.toLowerCase(), code.wrapped])),
        key: null,
      };
      account = made;
      return signedIn(made);
    }
    if (method === 'POST' && path === 'login') {
      // The same answer for a wrong handle and a wrong password, as the server gives.
      if (!sameHandle(account, body.handle) || account.loginSecret !== String(body.loginSecret).toLowerCase()) return refuse(401, 'Wrong handle or password.');
      return signedIn(account, account.wrapped);
    }
    if (method === 'POST' && path === 'login/challenge') {
      // A nonce whether or not the handle exists, so this says nothing about which do.
      const nonce = `nonce-${++issued}`;
      nonces.add(nonce);
      return json(200, { nonce });
    }
    if (method === 'POST' && path === 'login/device') {
      // The nonce is spent by the attempt, whether or not the signature holds.
      if (!nonces.delete(String(body.nonce))) return refuse(401, 'That sign-in took too long. Try again.');
      if (!sameHandle(account, body.handle)) return refuse(401, 'This device could not be verified.');
      const signature = fromBase64Url(String(body.signature));
      for (const device of account.devices) {
        const key = await crypto.subtle.importKey('raw', fromBase64Url(device), { name: 'Ed25519' }, false, ['verify']);
        if (await crypto.subtle.verify({ name: 'Ed25519' }, key, signature, encoder.encode(String(body.nonce)))) return signedIn(account);
      }
      return refuse(401, 'This device could not be verified.');
    }
    if (method === 'POST' && path === 'login/recovery') {
      // The code is spent, and what comes back is the key wrapped under that code alone.
      const login = String(body.login).toLowerCase();
      const wrapped = sameHandle(account, body.handle) ? account.recovery.get(login) : undefined;
      if (!account || wrapped === undefined) return refuse(401, 'Wrong handle or code, or a code already used.');
      account.recovery.delete(login);
      return signedIn(account, wrapped);
    }

    // --- everything else is for a signed-in device ---
    if (!bearer) return refuse(401, 'Sign in first.');
    if (!tokens.has(bearer) || !account) return refuse(401, 'Your session has ended. Sign in again.');
    const mine: Account = account;

    if (method === 'POST' && path === 'refresh') return signedIn(mine);
    if (method === 'POST' && path === 'device') {
      mine.devices.push(String(body.devicePublicKey));
      return json(200, { ok: true });
    }
    if (method === 'GET' && path === 'keys') return json(200, { wrapped: mine.wrapped });
    if (method === 'PUT' && path === 'password') {
      mine.loginSecret = String(body.loginSecret).toLowerCase();
      mine.wrapped = String(body.wrapped);
      return json(200, { ok: true });
    }
    if (method === 'GET' && path === 'recovery') return json(200, { left: mine.recovery.size });
    if (method === 'POST' && path === 'recovery') {
      const sheet = (body.codes ?? []) as { login: string; wrapped: string }[];
      if (sheet.length !== 8) return refuse(400, 'A recovery sheet is eight codes.');
      mine.recovery = new Map(sheet.map((code) => [code.login.toLowerCase(), code.wrapped]));
      return json(200, { left: 8 });
    }
    if (method === 'DELETE' && path === 'account') {
      // 403 rather than 401: the session is fine, only the password is wrong, and a 401 reads as signed out.
      if (mine.loginSecret !== String(body.loginSecret ?? '').toLowerCase()) return refuse(403, 'That is not the password.');
      forget();
      return json(200, { deleted: true });
    }

    // --- colours and the encryption key pair (docs/SHARED.md, S3, S7) ---
    if (path === 'account/colour' || path === 'account/key') {
      if (!teams) return refuse(404, NO_SUCH_ROUTE);
      if (method === 'PUT' && path === 'account/colour') {
        const hue = body.hue ?? null;
        if (!isHue(hue)) return refuse(400, 'That hue is not one of the workspace hues.');
        mine.hue = hue === 'ink' ? null : (hue as string | null);
        return json(200, { colour: mine.hue });
      }
      if (method === 'GET' && path === 'account/key') {
        return mine.encryption ? json(200, mine.encryption) : refuse(404, 'No key pair yet.');
      }
      if (method === 'PUT' && path === 'account/key') {
        if (typeof body.pub !== 'string' || typeof body.sealed !== 'string' || !body.pub || !body.sealed) return refuse(400, 'That key pair could not be read.');
        if (mine.encryption) return json(409, { ...mine.encryption, error: 'The account has a key pair already; this is it.' });
        mine.encryption = { pub: body.pub, sealed: body.sealed };
        return json(201, mine.encryption);
      }
    }

    if (method === 'GET' && path === 'notes') {
      const since = Number(url.searchParams.get('since') ?? 0);
      const items = [...notes.entries()]
        .filter(([, n]) => n.rev > since)
        .sort(([, a], [, b]) => a.rev - b.rev)
        .map(([id, n]): FeedItem => ({ id, ...n }));
      return json(200, { rev: counter, items, more: false });
    }
    const note = /^notes\/([^/]+)$/.exec(path);
    if (note && (method === 'PUT' || method === 'DELETE')) {
      const id = decodeURIComponent(note[1]!);
      const current = notes.get(id);
      // A note never seen is taken whatever its base: there is nothing it could overwrite.
      if (current && current.rev !== Number(body.base ?? 0)) return json(409, { id, ...current } satisfies FeedItem);
      const rev = nextRev();
      notes.set(id, method === 'PUT' ? { rev, deleted: false, blob: String(body.blob) } : { rev, deleted: true, blob: null });
      return json(200, { rev });
    }

    if (path === 'prefs' && method === 'GET') return json(200, { rev: prefs?.rev ?? 0, blob: prefs?.blob ?? null });
    if (path === 'prefs' && method === 'PUT') {
      if ((prefs?.rev ?? 0) !== Number(body.base ?? 0)) return prefs ? json(409, prefs) : refuse(500, 'Those settings could not be stored.');
      prefs = { rev: nextRev(), blob: String(body.blob) };
      return json(200, { rev: prefs.rev });
    }

    // --- organizations and notifications (docs/TEAMS.md) ---
    if (/^(orgs|notifications|joins)(\/|$)/.test(path)) {
      // A service from before these routes: the one 404 the client reads as "not yet".
      if (!teams) return refuse(404, NO_SUCH_ROUTE);
      const me = mine.handle;
      /** The organization at `id` and the account's row in it; null for one the account is not in. */
      const inOrg = (id: string, states: Row['state'][] = ['member']) => {
        const org = orgs.get(id);
        const row = org ? rowOf(org, me) : null;
        return org && row && states.includes(row.state) ? { org, row } : null;
      };

      if (method === 'POST' && path === 'orgs') {
        const name = String(body.name ?? '').trim();
        if (!name || name.length > 60) return refuse(400, 'An organization’s name is 1 to 60 characters.');
        if (!isHue(body.hue ?? null)) return refuse(400, 'That is not one of the hues.');
        if ([...orgs.values()].filter((o) => rowOf(o, me)?.role === 'owner').length >= 20) return refuse(409, 'You own as many organizations as you can.');
        const org: StoredOrg = { id: shortId(), name, hue: (body.hue as string | null | undefined) ?? null, createdAt: Date.now(), rows: new Map() };
        const owner: Row = { handle: me, role: 'owner', state: 'member', since: org.createdAt, invitedBy: null };
        org.rows.set(lower(me), owner);
        orgs.set(org.id, org);
        return json(201, { org: orgJson(org, owner) });
      }
      if (method === 'GET' && path === 'orgs') {
        const rows: OrgRow[] = [];
        for (const org of orgs.values()) {
          const row = rowOf(org, me);
          if (row && row.state !== 'declined') rows.push(rowJson(org, row));
        }
        return json(200, { orgs: rows, colour: mine.hue ?? null });
      }
      // Team notes (docs/SHARED.md, S4, S5): the feed, a row, its log, each log's head, and the organization's files.
      const teamHeads = /^orgs\/([^/]+)\/heads$/.exec(path);
      if (teamHeads && method === 'GET') {
        const found = inOrg(decodeURIComponent(teamHeads[1]!));
        if (!found) return refuse(404, 'No such organization.');
        const heads: Record<string, number> = {};
        for (const [id, row] of found.org.notes ?? []) if (!row.deleted) heads[id] = found.org.seqs?.get(id) ?? 0;
        return json(200, { heads });
      }
      const teamNotes = /^orgs\/([^/]+)\/notes(?:\/([^/]+))?(\/updates)?$/.exec(path);
      if (teamNotes) {
        const found = inOrg(decodeURIComponent(teamNotes[1]!));
        if (!found) return refuse(404, 'No such organization.');
        const { org } = found;
        org.notes ??= new Map();
        org.updates ??= new Map();
        org.seqs ??= new Map();
        const rowJson = (id: string, row: TeamRow) => ({ id, ...row });
        const bump = () => (org.rev = (org.rev ?? 0) + 1);
        if (teamNotes[2] === undefined && method === 'GET') {
          const since = Number(url.searchParams.get('since') ?? 0);
          const items = [...org.notes.entries()]
            .filter(([, n]) => n.rev > since)
            .sort(([, a], [, b]) => a.rev - b.rev)
            .map(([id, n]) => rowJson(id, n));
          return json(200, { rev: org.rev ?? 0, items, more: false });
        }
        const id = decodeURIComponent(teamNotes[2] ?? '');
        if (teamNotes[3]) {
          const row = org.notes.get(id);
          if (!row || row.deleted) return refuse(404, 'No such note.');
          const log = org.updates.get(id) ?? [];
          if (method === 'GET') {
            const since = Number(url.searchParams.get('since') ?? 0);
            const items = log.filter((u) => u.seq > since);
            return json(200, { seq: log.length ? log[log.length - 1]!.seq : (org.seqs.get(id) ?? 0), items, more: false });
          }
          if (method === 'POST') {
            const blobs = Array.isArray(body.blobs) ? (body.blobs as string[]) : [];
            if (!blobs.length || blobs.some((b) => typeof b !== 'string' || !b)) return refuse(400, 'Those updates could not be read.');
            const turned = inForce(org, body.generation);
            if (turned) return turned;
            let seq = org.seqs.get(id) ?? 0;
            // A log past its length asks for a snapshot first (S11; server/src/store/org_notes.rs UPDATES_KEPT).
            if (log.length + blobs.length > UPDATES_KEPT) return json(409, { error: 'snapshot', seq });
            for (const blob of blobs) log.push({ seq: ++seq, blob, by: me, at: Date.now() });
            org.updates.set(id, log);
            org.seqs.set(id, seq);
            return json(200, { seq });
          }
        }
        if (method === 'PUT' || method === 'DELETE') {
          const current = org.notes.get(id);
          const turned = method === 'PUT' ? inForce(org, body.generation) : null;
          if (turned) return turned;
          if (current && current.rev !== Number(body.base ?? 0)) return json(409, rowJson(id, current));
          if (method === 'PUT' && (typeof body.blob !== 'string' || !body.blob)) return refuse(400, 'That note is empty or too large to sync.');
          const rev = bump();
          const row: TeamRow = method === 'PUT' ? { rev, deleted: false, blob: String(body.blob), by: me, updatedAt: Date.now() } : { rev, deleted: true, blob: null, by: me, updatedAt: Date.now() };
          org.notes.set(id, row);
          if (method === 'DELETE') org.updates.delete(id);
          else if (typeof body.upTo === 'number') org.updates.set(id, (org.updates.get(id) ?? []).filter((u) => u.seq > (body.upTo as number)));
          return json(200, { rev });
        }
      }
      const teamFile = /^orgs\/([^/]+)\/files\/([^/]+)$/.exec(path);
      if (teamFile) {
        const found = inOrg(decodeURIComponent(teamFile[1]!));
        if (!found) return refuse(404, 'No such organization.');
        const { org } = found;
        org.files ??= new Map();
        const id = teamFile[2]!;
        const had = org.files.get(id);
        if (method === 'HEAD') return had ? new Response(null, { status: 200, headers: { 'x-glyph-rev': String(had.rev) } }) : new Response(null, { status: 404 });
        if (method === 'GET') return had ? new Response(had.bytes, { status: 200, headers: { 'x-glyph-rev': String(had.rev) } }) : refuse(404, 'No file by that id.');
        if (method === 'PUT') {
          const base = Number(url.searchParams.get('base') ?? 0);
          const asked = url.searchParams.get('generation');
          const turned = inForce(org, asked === null ? undefined : Number(asked));
          if (turned) return turned;
          if (had && had.rev !== base) return json(409, { rev: had.rev });
          const rev = (org.rev = (org.rev ?? 0) + 1);
          org.files.set(id, { rev, bytes: new Uint8Array(init?.body as Bytes) });
          return json(200, { rev });
        }
      }
      // The caller's colour in one organization (docs/SHARED.md, S7), and the organization key's wraps (S2).
      const colour = /^orgs\/([^/]+)\/colour$/.exec(path);
      if (colour && method === 'PUT') {
        const found = inOrg(decodeURIComponent(colour[1]!));
        if (!found) return refuse(404, 'No such organization.');
        const hue = body.hue ?? null;
        if (!isHue(hue)) return refuse(400, 'That hue is not one of the workspace hues.');
        found.row.hue = hue === 'ink' ? null : (hue as string | null);
        return json(200, { org: orgJson(found.org, found.row) });
      }
      const keys = /^orgs\/([^/]+)\/keys$/.exec(path);
      if (keys) {
        const found = inOrg(decodeURIComponent(keys[1]!));
        if (!found) return refuse(404, 'No such organization.');
        const { org, row } = found;
        const answer = (at?: number) => json(200, { generation: org.generation ?? 0, mine: wrapOf(org, row.handle, at ?? org.generation), missing: lacking(org).map((r) => ({ handle: r.handle, pub: pubOf(r.handle) })), stale: stale(org) });
        if (method === 'GET') {
          const at = url.searchParams.get('generation');
          if (at !== null && !(Number(at) >= 1)) return refuse(400, 'That generation could not be read.');
          return answer(at === null ? undefined : Number(at));
        }
        if (method === 'POST') {
          const generation = Number(body.generation);
          const wraps = Array.isArray(body.wraps) ? (body.wraps as { handle: string; wrapped: string }[]) : [];
          if (!(generation >= 1) || wraps.some((w) => typeof w.handle !== 'string' || typeof w.wrapped !== 'string')) return refuse(400, 'Those wraps could not be read.');
          const inForce = org.generation ?? 0;
          if (body.make === true) {
            if (generation !== inForce + 1) return json(409, { error: 'That is not the generation in force.', generation: inForce });
            org.generation = generation;
            org.turns = 0;
          } else if (generation !== inForce) return json(409, { error: 'That is not the generation in force.', generation: inForce });
          org.wraps ??= new Map();
          for (const { handle, wrapped } of wraps) {
            const member = rowOf(org, handle);
            if (!member || member.state !== 'member') continue;
            const theirs = org.wraps.get(lower(handle)) ?? new Map<number, string>();
            if (!theirs.has(generation)) theirs.set(generation, wrapped);
            org.wraps.set(lower(handle), theirs);
          }
          return answer();
        }
      }
      const one = /^orgs\/([^/]+)$/.exec(path);
      if (one) {
        const found = inOrg(decodeURIComponent(one[1]!));
        if (!found) return refuse(404, 'No such organization.');
        const { org, row } = found;
        if (method === 'GET') return json(200, { org: orgJson(org, row) });
        if (method === 'PUT') {
          if (row.role === 'member') return refuse(403, 'Only the owner or an admin can change the organization.');
          if (body.name !== undefined) {
            const name = String(body.name).trim();
            if (!name || name.length > 60) return refuse(400, 'An organization’s name is 1 to 60 characters.');
            org.name = name;
          }
          if (body.hue !== undefined) {
            if (!isHue(body.hue)) return refuse(400, 'That is not one of the hues.');
            org.hue = body.hue as string | null;
          }
          return json(200, { org: orgJson(org, row) });
        }
        if (method === 'DELETE') {
          if (row.role !== 'owner') return refuse(403, 'Only the owner can delete the organization.');
          orgs.delete(org.id);
          return json(200, { deleted: true });
        }
      }
      const members = /^orgs\/([^/]+)\/members(?:\/([^/]+))?$/.exec(path);
      if (members) {
        const found = inOrg(decodeURIComponent(members[1]!));
        if (!found) return refuse(404, 'No such organization.');
        const { org, row } = found;
        if (method === 'POST' && members[2] === undefined) {
          if (row.role === 'member') return refuse(403, 'Only the owner or an admin can invite.');
          const handle = resolve(body.handle);
          if (!handle) return refuse(404, 'No one has that handle.');
          const had = rowOf(org, handle);
          if (had?.state === 'member') return refuse(409, 'They are already a member.');
          if (had?.state === 'declined' && Date.now() - had.since < DECLINE_GAP_MS) return refuse(409, 'They declined; ask again tomorrow.');
          if (had?.state === 'invited') {
            // A pending invitation is refreshed, not doubled.
            had.since = Date.now();
            had.invitedBy = me;
            return json(200, { member: memberJson(had) });
          }
          const waiting = [...orgs.values()].filter((o) => rowOf(o, handle)?.state === 'invited').length;
          if (waiting >= PENDING_INVITES) return refuse(409, 'They have as many invitations waiting as they can.');
          if ([...org.rows.values()].filter((r) => r.state !== 'declined').length >= ORG_ROWS) return refuse(409, 'The organization is full.');
          const invited: Row = { handle, role: 'member', state: 'invited', since: Date.now(), invitedBy: me };
          org.rows.set(lower(handle), invited);
          return json(200, { member: memberJson(invited) });
        }
        if (members[2] !== undefined) {
          const target = rowOf(org, decodeURIComponent(members[2]));
          if (!target || target.state === 'declined') return refuse(404, 'No one by that handle is in this organization.');
          if (method === 'DELETE') {
            const self = lower(target.handle) === lower(me);
            if (target.role === 'owner') return refuse(403, 'Hand the organization over first.');
            if (!self) {
              if (row.role === 'member') return refuse(403, 'Only the owner or an admin can remove a member.');
              if (target.role === 'admin' && row.role !== 'owner') return refuse(403, 'Only the owner can remove an admin.');
            }
            // A member gone owes the key a turn (S11); an invitee withdrawn had no wrap.
            if (target.state === 'member') org.turns = (org.turns ?? 0) + 1;
            org.rows.delete(lower(target.handle));
            return json(200, { removed: true });
          }
          if (method === 'PUT') {
            if (row.role !== 'owner') return refuse(403, 'Only the owner can change a role.');
            if (lower(target.handle) === lower(me)) return refuse(403, 'Hand the organization over first.');
            if (target.state === 'invited') return refuse(409, 'They have not joined yet.');
            const role = body.role;
            if (role !== 'owner' && role !== 'admin' && role !== 'member') return refuse(400, 'A role is owner, admin or member.');
            if (role === 'owner') row.role = 'admin';
            target.role = role;
            return json(200, { member: memberJson(target) });
          }
        }
      }
      const orgLinks = /^orgs\/([^/]+)\/links(?:\/([^/]+))?$/.exec(path);
      if (orgLinks) {
        const found = inOrg(decodeURIComponent(orgLinks[1]!));
        if (!found) return refuse(404, 'No such organization.');
        const { org, row } = found;
        if (row.role === 'member') return refuse(403, 'Only the owner or an admin can do that.');
        const live = [...links.values()].filter((l) => l.orgId === org.id && working(l));
        if (method === 'GET' && orgLinks[2] === undefined) return json(200, { links: live.reverse().map(linkJson) });
        if (method === 'POST' && orgLinks[2] === undefined) {
          const expiresIn = body.expiresIn as number | undefined;
          const maxUses = body.maxUses as number | undefined;
          if (expiresIn !== undefined && (expiresIn < 3600 || expiresIn > 30 * 24 * 3600)) return refuse(400, 'A link lasts an hour to thirty days, or until it is turned off.');
          if (maxUses !== undefined && (maxUses < 1 || maxUses > ORG_ROWS)) return refuse(400, 'A link may be used 1 to 50 times, or without a limit.');
          if (live.length >= 10) return refuse(409, 'This organization has as many invite links as it can. Turn one off first.');
          const link = linkTo(org, me, expiresIn === undefined ? null : Date.now() + expiresIn * 1000, maxUses ?? null);
          return json(201, { link: linkJson(link) });
        }
        if (method === 'DELETE' && orgLinks[2] !== undefined) {
          const link = [...links.values()].find((l) => l.orgId === org.id && l.id === decodeURIComponent(orgLinks[2]!));
          if (!link) return refuse(404, 'That invite link has expired or was turned off.');
          links.delete(link.code);
          return json(200, { dropped: true });
        }
      }
      const join = /^joins\/([^/]+)$/.exec(path);
      if (join) {
        const link = links.get(decodeURIComponent(join[1]!));
        const org = link && working(link) ? orgs.get(link.orgId) : undefined;
        if (!link || !org) return refuse(404, 'That invite link has expired or was turned off.');
        const had = rowOf(org, me);
        if (method === 'GET') return json(200, { org: { id: org.id, name: org.name, hue: org.hue, members: joined(org).length }, by: link.by, member: had?.state === 'member' });
        if (method === 'POST') {
          if (had?.state === 'member') return json(200, { org: orgJson(org, had) });
          if (had?.state !== 'invited' && [...org.rows.values()].filter((r) => r.state !== 'declined').length >= ORG_ROWS) return refuse(409, 'The organization is full.');
          const row: Row = { handle: me, role: 'member', state: 'member', since: Date.now(), invitedBy: had?.invitedBy ?? link.by };
          org.rows.set(lower(me), row);
          link.uses += 1;
          const notice = pendingInvite(org.id);
          if (notice) touch(notice, { state: 'accepted' });
          return json(200, { org: orgJson(org, row) });
        }
      }
      const invite = /^orgs\/([^/]+)\/invite$/.exec(path);
      if (invite && method === 'POST') {
        const found = inOrg(decodeURIComponent(invite[1]!), ['invited']);
        if (!found) return refuse(404, 'You were not invited.');
        const { org, row } = found;
        const notice = pendingInvite(org.id);
        if (body.accept === true) {
          row.state = 'member';
          row.since = Date.now();
          if (notice) touch(notice, { state: 'accepted' });
          return json(200, { org: orgJson(org, row) });
        }
        row.state = 'declined';
        row.since = Date.now();
        if (notice) touch(notice, { state: 'declined' });
        return json(200, { declined: true });
      }

      if (method === 'GET' && path === 'notifications') {
        const since = Number(url.searchParams.get('since') ?? 0);
        const limit = Math.min(200, Math.max(1, Number(url.searchParams.get('limit') ?? 100)));
        const newer = [...feed.values()].filter((n) => n.rev > since).sort((a, b) => a.rev - b.rev);
        const items = newer.slice(0, limit);
        const more = newer.length > items.length;
        // The cursor is the last row given when there is more to come, and the account's head when there is not.
        return json(200, { rev: more ? items[items.length - 1]!.rev : counter, items, more });
      }
      if (method === 'POST' && path === 'notifications') {
        const id = String(body.id ?? '');
        if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) return refuse(400, 'That is not an id.');
        if (!isSelfKind(body.kind)) return refuse(400, 'Only your own kinds can be posted.');
        if (typeof body.blob !== 'string' || !body.blob || body.blob.length > 8 * 1024) return refuse(400, 'A notification’s blob is up to 8 KB.');
        // An id this account already has: the same answer, and nothing written (a retry after a lost answer).
        const had = feed.get(id);
        if (had) return json(200, { rev: had.rev });
        const made = fed({ id, kind: body.kind, blob: body.blob });
        return json(200, { rev: made.rev });
      }
      if (method === 'POST' && path === 'notifications/read') {
        const ids = Array.isArray(body.ids) ? new Set(body.ids.map(String)) : null;
        const before = typeof body.before === 'number' ? body.before : Number.POSITIVE_INFINITY;
        for (const item of [...feed.values()]) {
          const wanted = body.all === true ? item.rev <= before : (ids?.has(item.id) ?? false);
          if (wanted && item.readAt === null) touch(item, { readAt: Date.now() });
        }
        return json(200, { rev: counter });
      }
      const row = /^notifications\/([^/]+)$/.exec(path);
      if (row && method === 'PUT') {
        const item = feed.get(decodeURIComponent(row[1]!));
        if (!item) return refuse(404, 'No such notification.');
        const change: Partial<Notification> = {};
        if (body.read === true && item.readAt === null) change.readAt = Date.now();
        if (body.read === false) change.readAt = null;
        if (typeof body.hidden === 'boolean') change.hidden = body.hidden;
        const next = Object.keys(change).length ? touch(item, change) : item;
        return json(200, { rev: next.rev });
      }
      return refuse(404, `No route ${method} ${path}`);
    }

    const file = /^recordings\/([^/]+)$/.exec(path);
    if (file) {
      const id = file[1]!;
      const had = files.get(id);
      if (method === 'HEAD') {
        if (!head) throw new TypeError('Failed to fetch');
        return had ? new Response(null, { status: 200, headers: { 'x-glyph-rev': String(had.rev) } }) : new Response(null, { status: 404 });
      }
      if (method === 'GET') return had ? new Response(had.bytes, { status: 200, headers: { 'x-glyph-rev': String(had.rev) } }) : refuse(404, 'No recording by that id.');
      if (method === 'PUT') {
        const base = Number(url.searchParams.get('base') ?? 0);
        if (had && had.rev !== base) return json(409, { rev: had.rev });
        const rev = nextRev();
        files.set(id, { rev, bytes: new Uint8Array(init?.body as Bytes) });
        return json(200, { rev });
      }
    }
    return refuse(404, `No route ${method} ${path}`);
  };

  /** The account key the service made for a seeded account; a test asking for any other has made a mistake. */
  const keyOf = (): CryptoKey => {
    if (!account?.key) throw new Error('The fake service holds no account key: only an account it was seeded with has one.');
    return account.key;
  };

  return {
    fetcher,
    calls,
    /** The feed as stored: each note's revision and sealed blob, or its deletion marker. */
    notes,
    /** The recordings and pictures as stored, sealed, by their file id. */
    files,
    /** The seeded account's key, for a test that seals or opens as a device of that account would. */
    get accountKey(): CryptoKey {
      return keyOf();
    },
    /** A live token for the account, as a device that signed in earlier holds one. */
    signedIn(): string {
      if (!account) throw new Error('The fake service holds no account to sign in to.');
      return token();
    },
    /** Another device writing a note, sealed as the app seals it. Answers the note's new revision. */
    async deviceWrites(written: Note, extra: Partial<NotePayload> = {}): Promise<number> {
      const rev = nextRev();
      notes.set(written.id, { rev, deleted: false, blob: await seal(keyOf(), { v: 1, note: written, ...extra }, `note:${written.id}`) });
      return rev;
    },
    /** What the account holds for a note, opened: the payload a client wrote, or null for none or a deletion. */
    async stored(id: string): Promise<NotePayload | null> {
      const item = notes.get(id);
      if (!item?.blob) return null;
      return open<NotePayload>(keyOf(), item.blob, `note:${id}`);
    },
    /** Every token the service has handed out stops working at once, as a week passing would do. */
    expireAllTokens(): void {
      tokens.clear();
    },
    /** Whether the account is still there: false after a signup that never came, or after it was deleted. */
    hasAccount(): boolean {
      return account !== null;
    },
    /** How many recovery codes the account has left unspent. */
    codesLeft(): number {
      return account?.recovery.size ?? 0;
    },
    /** The account's notifications as stored, by id: each row at the revision it was last written. */
    feed,
    /** The organizations as stored, by id, with their rows by handle. */
    orgs,
    /** The handles that resolve for an invitation without being the account. */
    peers,
    /** A peer's colour and encryption public key, as their own devices would have set them (docs/SHARED.md). */
    peerColour(handle: string, hue: string | null): void {
      if (hue === null) peerHues.delete(lower(handle));
      else peerHues.set(lower(handle), hue);
    },
    peerKey(handle: string, pub: string | null): void {
      if (pub === null) peerKeys.delete(lower(handle));
      else peerKeys.set(lower(handle), pub);
    },
    /** A team's notes as stored, by id: each row's revision, blob and writer; and its logs by note. */
    teamNotes(orgId: string): Map<string, TeamRow> {
      return orgs.get(orgId)?.notes ?? new Map();
    },
    teamUpdates(orgId: string, noteId: string): { seq: number; blob: string; by: string }[] {
      return orgs.get(orgId)?.updates?.get(noteId) ?? [];
    },
    teamFiles(orgId: string): Map<string, { rev: number; bytes: Bytes }> {
      return orgs.get(orgId)?.files ?? new Map();
    },
    /** The organization key's state as stored: the generation in force and each member's wraps by generation. */
    keysOf(orgId: string): { generation: number; wraps: Record<string, Record<number, string>> } {
      const org = orgs.get(orgId);
      const wraps: Record<string, Record<number, string>> = {};
      for (const [handle, theirs] of org?.wraps ?? []) wraps[handle] = Object.fromEntries(theirs);
      return { generation: org?.generation ?? 0, wraps };
    },
    /** The account's registered encryption key pair, as stored. */
    get encryption(): { pub: string; sealed: string } | null {
      return account?.encryption ?? null;
    },
    /** A row the service wrote into the account's feed - another account's doing - at a new revision. Answers it. */
    notifies(row: Partial<Notification> & { kind: Kind }): Notification {
      return fed(row);
    },
    /** An organization `by` (a peer) made and invited the account to: the invitation lands in the feed. Answers the organization's id. */
    invited(name: string, by: string = peers[0] ?? 'sam'): string {
      return inviteAccount(name, by).id;
    },
    /** Invite links as stored, by code. */
    links,
    /** An organization a peer made, with an invite link to it the account has been sent: answers the code. */
    peerLink(name: string, by: string = peers[0] ?? 'sam', terms: { expiresAt?: number | null; maxUses?: number | null } = {}): string {
      const org: StoredOrg = { id: shortId(), name, hue: null, createdAt: Date.now(), rows: new Map() };
      org.rows.set(lower(by), { handle: by, role: 'owner', state: 'member', since: org.createdAt, invitedBy: null });
      orgs.set(org.id, org);
      return linkTo(org, by, terms.expiresAt ?? null, terms.maxUses ?? null).code;
    },
    /** The account's row in an organization, as the service holds it; null when it has none. */
    rowIn(orgId: string): { role: Role; state: 'member' | 'invited' | 'declined' } | null {
      const org = orgs.get(orgId);
      const row = org && account ? rowOf(org, account.handle) : null;
      return row ? { role: row.role, state: row.state } : null;
    },
  };
}

/** The service's own type, for a test that keeps one across its cases. */
export type FakeService = Awaited<ReturnType<typeof fakeService>>;
