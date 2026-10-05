import { ApiError, call, notYet } from '../account/api.ts';
import { failureText } from '../failure.ts';
import { imageNames } from '../imageRefs.ts';
import type { Note } from '../store.ts';
import { fromBase64Url, open, openBytes, seal, sealBytes, toBase64Url, type Bytes } from '../sync/crypto.ts';
import { fetchFile, fetchVersionsOf, fileId, resendFile, sendFile, sendVersionsOf, turnedKey, type FilesContext, type LocalFiles, type LocalNotes, type SyncState } from '../sync/notes.ts';
import { adoptTeamDoc, dropTeamDoc, teamDoc, type TeamDoc } from './doc.ts';

import { KeyTurned } from '../sync/notes.ts';

export { KeyTurned };
import type { TeamDocStore } from './docs.ts';

/**
 * A team's notes kept the same on every member's devices (docs/SHARED.md, S1, S4, S5): the organization channel,
 * run after the account's own sync in every full pass (core/sync/engine.ts), once for each organization the person
 * has joined and holds the key of (core/orgs/orgKeys.ts).
 *
 * The document of record is the CRDT (core/team/doc.ts). The organization's row for a note carries a snapshot of the
 * document - its state, and the note's words and particulars as they stood - and the log beside it carries every
 * update since, so a pass is:
 *
 * 1. **Pull** every row written since the cursor: a deletion takes the note and its document; a row is adopted into
 *    the document held here (merged, never doubled), its words written to the note, the note filed in the
 *    organization's workspace, and its files - the versions file merged, the pictures - fetched where this device
 *    lacks them. A note this device had of its own before the team did keeps its words: they are reconciled into the
 *    document as a change, so the team gets them.
 * 2. **Updates** since each document's seq, applied, and the words written to the note when they changed.
 * 3. **Push**: words that reached a note without the editor are reconciled into its document; the updates made here
 *    are posted to the log; a note new to the team, or one whose particulars changed, or one whose document has gone
 *    `SNAPSHOT_EVERY` updates past its last snapshot, is put as a row - with its versions file and pictures sent
 *    first - and a row that lost the race is merged and put again. A note no longer here, or no longer filed in the
 *    organization's workspace, is deleted from the team.
 *
 * Two members who edited apart merge by the CRDT: nothing here keeps a copy. A note's send that fails is counted and
 * the pass goes on, as the account's sync does; a lapsed session ends it.
 */

export interface TeamSyncState {
  /** The last revision of the organization's feed this device has read. */
  cursor: number;
  /** Per note: the row's revision last seen, and the note's particulars then (`particulars`). */
  notes: Record<string, { rev: number; mark: string }>;
  /** Per file, as the account's sync keeps them (core/sync/notes.ts `SyncState.files`). */
  files: SyncState['files'];
}

export function emptyTeamState(): TeamSyncState {
  return { cursor: 0, notes: {}, files: {} };
}

export interface TeamSyncContext {
  token: string;
  orgId: string;
  /** The organization key (core/orgs/orgKeys.ts). */
  key: CryptoKey;
  notes: LocalNotes;
  files: LocalFiles;
  docs: TeamDocStore;
  state: TeamSyncState;
  save(state: TeamSyncState): void;
  fetcher?: typeof fetch;
  now?: () => number;
  /** Whether a note on this device is filed in this organization's workspace. */
  isTeamNote(id: string): boolean;
  /** A note from the team, filed in the organization's workspace on this device. */
  file(id: string): void;
  /** The key's generation (docs/SHARED.md, S11), named on every write so one under a turned key is refused, not kept. */
  generation?: number;
  /** The key at an older generation, for a row or an update sealed before a turn and not re-sealed yet; null for none. */
  olderKey?: (generation: number) => Promise<CryptoKey | null>;
}

/** A row's blob, opened: the note as it stood, the document's whole state then, the seq it covered, and the files. */
interface TeamPayload {
  v: 1;
  note: Note;
  state: string;
  seq: number;
  images?: string[];
  versions?: string;
}

interface TeamFeedItem {
  id: string;
  rev: number;
  deleted: boolean;
  blob: string | null;
  by: string | null;
  updatedAt: number;
}

interface UpdateItem {
  seq: number;
  blob: string;
  by: string | null;
  at: number;
}

export interface TeamOutcome {
  /** Notes written or removed on this device. */
  changed: number;
  /** Notes whose send failed this pass, and the first reason. */
  unsent: number;
  reason: string | null;
}

/** How many updates past its last snapshot a document may go before a pass puts a new one and cuts the log. */
export const SNAPSHOT_EVERY = 200;
/** Updates in one post (server/src/org_notes.rs `UPDATES_PER_POST`). */
const POST_AT_MOST = 100;

/**
 * A note's particulars, for telling whether its row needs putting again: everything but the words, which the
 * document carries, and `updatedAt`, which every keystroke moves.
 */
export function particulars(note: Note): string {
  return JSON.stringify([note.createdAt, note.source, Boolean(note.starred), note.archivedAt ?? null, note.path ?? null, note.recordingMs ?? null]);
}

const noteContext = (orgId: string, id: string) => `org:${orgId}:note:${id}`;
const updateContext = (orgId: string, id: string) => `org:${orgId}:note:${id}:update`;

function filesOf(ctx: TeamSyncContext): FilesContext {
  return { token: ctx.token, key: ctx.key, files: ctx.files, fetcher: ctx.fetcher, filesRoute: `orgs/${encodeURIComponent(ctx.orgId)}/files`, state: ctx.state, ...(ctx.generation ? { generation: ctx.generation } : {}) };
}

function route(ctx: TeamSyncContext, tail: string): string {
  return `orgs/${encodeURIComponent(ctx.orgId)}/${tail}`;
}

/** The call's options; a body names the key's generation it is sealed under (S11). */
function options(ctx: TeamSyncContext, body?: Record<string, unknown>) {
  return { token: ctx.token, fetcher: ctx.fetcher, ...(body === undefined ? {} : { body: ctx.generation ? { ...body, generation: ctx.generation } : body }) };
}

/**
 * Sealed bytes opened under the key in force, or, failing that, under the generations before it (S11): a row or an
 * update sealed before a turn by a device that had not yet heard of it, or not yet re-sealed. Answers what opened
 * and whether an older key did it, so a row read that way is put again under the key in force.
 */
async function opened<T>(ctx: TeamSyncContext, open: (key: CryptoKey) => Promise<T>): Promise<{ value: T; older: boolean }> {
  try {
    return { value: await open(ctx.key), older: false };
  } catch (failure) {
    if (!ctx.olderKey || !ctx.generation) throw failure;
    for (let generation = ctx.generation - 1; generation >= 1; generation -= 1) {
      const key = await ctx.olderKey(generation);
      if (!key) continue;
      try {
        return { value: await open(key), older: true };
      } catch {
        // Not that one either.
      }
    }
    throw failure;
  }
}

/** The note's words from the document, written to the note here when they differ. */
async function writeWords(ctx: TeamSyncContext, id: string, words: string, outcome: TeamOutcome): Promise<void> {
  const local = await ctx.notes.get(id);
  if (!local || local.body === words) return;
  await ctx.notes.apply({ ...local, body: words, updatedAt: (ctx.now ?? Date.now)() });
  outcome.changed += 1;
}

// --- pull ------------------------------------------------------------------------------

async function takeRow(ctx: TeamSyncContext, item: TeamFeedItem, local: Note | undefined, outcome: TeamOutcome): Promise<void> {
  if (item.deleted || !item.blob) {
    if (local) {
      await ctx.notes.remove(item.id);
      outcome.changed += 1;
    }
    await dropTeamDoc(item.id, ctx.docs);
    delete ctx.state.notes[item.id];
    return;
  }
  const { value: payload, older } = await opened(ctx, (key) => open<TeamPayload>(key, item.blob!, noteContext(ctx.orgId, item.id)));
  const held = await teamDoc(item.id, ctx.docs);
  // Words typed here since the document was last written are a change of this device's, reconciled before the row's
  // state comes in, so the merge is the CRDT's and nothing typed is written over.
  if (held && local) held.reconcile(local.body);
  const doc = await adoptTeamDoc(item.id, ctx.docs, fromBase64Url(payload.state), payload.seq);
  // This device's own words, from before the team had the note: a change for the team, not words to lose.
  if (!held && local && local.body !== doc.words()) doc.reconcile(local.body);
  const files = filesOf(ctx);
  if (payload.versions) await fetchVersionsOf(files, item.id, payload.versions);
  for (const name of payload.images ?? []) {
    const id = fileId('image', name);
    if (!id || ctx.state.files[id]) continue;
    if (await ctx.files.read('image', name)) continue;
    await fetchFile(files, 'image', name);
  }
  const theirs: Note = { ...payload.note, id: item.id, body: doc.words() };
  if (!local || local.body !== theirs.body || particulars(local) !== particulars(theirs)) {
    await ctx.notes.apply(theirs);
    outcome.changed += 1;
  }
  ctx.file(item.id);
  ctx.state.notes[item.id] = { rev: item.rev, mark: particulars(theirs) };
  // Read under a generation before the turn: put again under the one in force, so every member can read it.
  if (older) await putRow(ctx, (await ctx.notes.get(item.id)) ?? theirs, doc, outcome);
}

async function pull(ctx: TeamSyncContext, outcome: TeamOutcome): Promise<void> {
  for (;;) {
    const page = await call<{ rev: number; items: TeamFeedItem[]; more: boolean }>('GET', route(ctx, `notes?since=${ctx.state.cursor}`), options(ctx));
    if (page.items.length) {
      const here = new Map((await ctx.notes.list()).map((note) => [note.id, note]));
      for (const item of page.items) {
        if (ctx.state.notes[item.id]?.rev === item.rev) continue;
        await takeRow(ctx, item, here.get(item.id), outcome);
      }
    }
    ctx.state.cursor = Math.max(ctx.state.cursor, page.rev);
    ctx.save(ctx.state);
    if (!page.more) return;
  }
}

// --- updates ---------------------------------------------------------------------------

/** The log since the document's seq, applied; the words written when they changed. */
async function takeUpdates(ctx: TeamSyncContext, doc: TeamDoc, outcome: TeamOutcome): Promise<void> {
  for (;;) {
    let page: { seq: number; items: UpdateItem[]; more: boolean };
    try {
      page = await call('GET', route(ctx, `notes/${encodeURIComponent(doc.noteId)}/updates?since=${doc.seq}`), options(ctx));
    } catch (failure) {
      // The row is gone (deleted by another member, not yet pulled here): the next pull takes it.
      if (failure instanceof ApiError && failure.status === 404) return;
      throw failure;
    }
    if (page.items.length) {
      const updates: Uint8Array[] = [];
      for (const item of page.items) {
        try {
          updates.push((await opened(ctx, (key) => openBytes(key, fromBase64Url(item.blob), updateContext(ctx.orgId, doc.noteId)))).value);
        } catch {
          // An update that will not open - sealed under a generation this device lacks - is passed over; the row's
          // next snapshot carries what it did.
        }
      }
      const words = doc.applyRemote(updates, page.items[page.items.length - 1]!.seq);
      if (words !== null) await writeWords(ctx, doc.noteId, words, outcome);
    } else {
      doc.seq = Math.max(doc.seq, page.seq);
    }
    if (!page.more) return;
  }
}

// --- push ------------------------------------------------------------------------------

/** The updates made here, posted in order; the document's seq follows them when nobody else wrote in between. */
async function postPending(ctx: TeamSyncContext, note: Note, doc: TeamDoc, outcome: TeamOutcome): Promise<void> {
  for (;;) {
    const pending = doc.pending().slice(0, POST_AT_MOST);
    if (!pending.length) return;
    const blobs: string[] = [];
    for (const update of pending) blobs.push(toBase64Url(await sealBytes(ctx.key, update as Bytes, updateContext(ctx.orgId, doc.noteId))));
    let seq: number;
    try {
      ({ seq } = await call<{ seq: number }>('POST', route(ctx, `notes/${encodeURIComponent(doc.noteId)}/updates`), options(ctx, { blobs })));
    } catch (failure) {
      const turned = turnedKey(failure);
      if (turned) throw turned;
      // The log is as long as the service keeps one (S11): a snapshot cuts it, and carries these updates with it.
      if (failure instanceof ApiError && failure.status === 409 && (failure.body as { error?: unknown } | null)?.error === 'snapshot') {
        await putRow(ctx, note, doc, outcome);
        continue;
      }
      throw failure;
    }
    doc.posted(pending.length);
    // Exactly these went on at the end of the log: nothing of the team's between, so there is nothing to read back.
    if (seq - pending.length === doc.seq) doc.seq = seq;
  }
}

/** The note's row put: a snapshot of the document, its particulars, and its files sent first. */
async function putRow(ctx: TeamSyncContext, note: Note, doc: TeamDoc, outcome: TeamOutcome, retry = true): Promise<void> {
  const known = ctx.state.notes[note.id];
  const files = filesOf(ctx);
  const sent: Pick<TeamPayload, 'images' | 'versions'> = {};
  const versions = await sendVersionsOf(files, note.id);
  if (versions) sent.versions = versions;
  const images = imageNames(note.body);
  if (images.length) {
    sent.images = images;
    for (const name of images) {
      const id = fileId('image', name);
      if (!id || ctx.state.files[id]) continue;
      const bytes = await ctx.files.read('image', name);
      if (bytes) await sendFile(files, 'image', name, bytes);
    }
  }
  const covered = doc.pending().length;
  const payload: TeamPayload = { v: 1, note: { ...note, body: doc.words() }, state: toBase64Url(doc.snapshot()), seq: doc.seq, ...sent };
  const blob = await seal(ctx.key, payload, noteContext(ctx.orgId, note.id));
  try {
    const { rev } = await call<{ rev: number }>('PUT', route(ctx, `notes/${encodeURIComponent(note.id)}`), options(ctx, { base: known?.rev ?? 0, blob, upTo: doc.seq }));
    ctx.state.notes[note.id] = { rev, mark: particulars(note) };
    doc.snapshotSeq = doc.seq;
    // The snapshot carried the updates pending when it was taken; what was typed since is still pending.
    doc.posted(covered);
    await doc.flush();
  } catch (failure) {
    const turned = turnedKey(failure);
    if (turned) throw turned;
    if (!(failure instanceof ApiError) || failure.status !== 409 || !failure.body) throw failure;
    // Another member put the row first: theirs merged into the document here, and this one put again from their revision.
    const winner = failure.body as TeamFeedItem;
    const local = (await ctx.notes.get(note.id)) ?? note;
    await takeRow(ctx, winner, local, outcome);
    if (retry) await putRow(ctx, (await ctx.notes.get(note.id)) ?? note, doc, outcome, false);
  }
}

async function pushOne(ctx: TeamSyncContext, note: Note, outcome: TeamOutcome): Promise<void> {
  const doc = (await teamDoc(note.id, ctx.docs, note.body))!;
  doc.reconcile(note.body);
  const known = ctx.state.notes[note.id];
  if (known) await postPending(ctx, note, doc, outcome);
  const due = !known || known.mark !== particulars(note) || doc.seq - doc.snapshotSeq >= SNAPSHOT_EVERY || (ctx.files.owed?.() ?? []).includes(note.id);
  if (due) await putRow(ctx, note, doc, outcome);
  else await doc.flush();
}

async function counted(ctx: TeamSyncContext, outcome: TeamOutcome, work: () => Promise<void>): Promise<void> {
  try {
    await work();
  } catch (failure) {
    if ((failure instanceof ApiError && failure.status === 401) || failure instanceof KeyTurned) throw failure;
    outcome.unsent += 1;
    outcome.reason ??= failureText(failure);
  }
}

async function push(ctx: TeamSyncContext, outcome: TeamOutcome): Promise<void> {
  const here = (await ctx.notes.list()).filter((note) => ctx.isTeamNote(note.id));
  const present = new Set<string>();
  for (const note of here) {
    present.add(note.id);
    await counted(ctx, outcome, () => pushOne(ctx, note, outcome));
  }
  // Gone from here, or taken out of the organization's workspace: gone from the team.
  for (const id of Object.keys(ctx.state.notes)) {
    if (present.has(id)) continue;
    await counted(ctx, outcome, async () => {
      const known = ctx.state.notes[id]!;
      try {
        await call('DELETE', route(ctx, `notes/${encodeURIComponent(id)}`), options(ctx, { base: known.rev }));
      } catch (failure) {
        if (!(failure instanceof ApiError) || failure.status !== 409 || !failure.body) throw failure;
        const winner = failure.body as TeamFeedItem;
        if (!winner.deleted) await call('DELETE', route(ctx, `notes/${encodeURIComponent(id)}`), options(ctx, { base: winner.rev }));
      }
      delete ctx.state.notes[id];
      await dropTeamDoc(id, ctx.docs);
    });
  }
  ctx.save(ctx.state);
}

/**
 * Each live note's log head, in one read, so only the logs that moved are fetched; null from a service without the
 * route yet, which means every log is looked at as before.
 */
async function heads(ctx: TeamSyncContext): Promise<Record<string, number> | null> {
  try {
    const { heads } = await call<{ heads: Record<string, number> }>('GET', route(ctx, 'heads'), options(ctx));
    return heads;
  } catch (failure) {
    if (notYet(failure)) return null;
    throw failure;
  }
}

/** One whole sync of a team's notes: what changed elsewhere first, then the logs that moved, then what changed here. */
/**
 * Every team note put again under the key in force, after a turn (docs/SHARED.md, S11; core/orgs/orgKeys.ts
 * `turnOrgKey`): the row with the document's whole state, its log cut to it, its versions file and its pictures sent
 * again sealed afresh. Run by the engine right after the turn, on the device that made it, with the team's notes
 * pulled first under the old key so nothing a member wrote is left behind. The service refuses what is still
 * sealed under the old generation, so a device that slept through the turn re-seals its own next.
 */
export async function resealTeamNotes(ctx: TeamSyncContext): Promise<TeamOutcome> {
  const outcome: TeamOutcome = { changed: 0, unsent: 0, reason: null };
  const files = filesOf(ctx);
  for (const id of Object.keys(ctx.state.notes)) {
    const note = await ctx.notes.get(id);
    const doc = await teamDoc(id, ctx.docs);
    if (!note || !doc) continue;
    await counted(ctx, outcome, async () => {
      for (const name of imageNames(note.body)) {
        const bytes = await ctx.files.read('image', name);
        if (bytes) await resendFile(files, 'image', name, bytes);
      }
      // The versions file goes with the row, sent again since its digest is forgotten here.
      const versions = fileId('versions', id);
      if (versions && ctx.state.files[versions]) ctx.state.files[versions] = { rev: ctx.state.files[versions]!.rev };
      await putRow(ctx, note, doc, outcome);
    });
  }
  ctx.save(ctx.state);
  return outcome;
}

export async function syncTeamNotes(ctx: TeamSyncContext): Promise<TeamOutcome> {
  const outcome: TeamOutcome = { changed: 0, unsent: 0, reason: null };
  await pull(ctx, outcome);
  const team = (await ctx.notes.list()).filter((each) => ctx.isTeamNote(each.id));
  const moved = team.length ? await heads(ctx) : null;
  for (const note of team) {
    const doc = await teamDoc(note.id, ctx.docs);
    if (!doc || !ctx.state.notes[note.id]) continue;
    // Words that reached the note without the editor go into the document first, so what the log brings merges with them.
    doc.reconcile(note.body);
    // A log that has not moved past what this device applied is not read: one request for the organization, not one a note.
    if (moved && (moved[note.id] ?? 0) <= doc.seq) continue;
    await counted(ctx, outcome, () => takeUpdates(ctx, doc, outcome));
  }
  await push(ctx, outcome);
  ctx.save(ctx.state);
  return outcome;
}
