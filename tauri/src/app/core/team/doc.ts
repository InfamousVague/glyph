import * as Y from 'yjs';
import { frontMatterEnd } from '../frontMatter.ts';
import { REMOTE } from '../live/session.ts';
import { canvasWords, hasTeamCanvas, reconcileCanvas } from './canvas.ts';
import type { TeamDocRecord, TeamDocStore } from './docs.ts';
import { applyTextDiff } from './textDiff.ts';

export { applyTextDiff, LOCAL } from './textDiff.ts';

/**
 * A team note's document on this device (docs/SHARED.md, S5): one Yjs document per note, held while the app runs,
 * its text in `body`, what the editor binds to (editor/liveBinding.ts) and what the organization channel syncs
 * (core/team/sync.ts). Every change made here becomes an update the next pass posts to the note's log; every update
 * the log holds is applied here; the note's words in the library are the document's text, written as it changes.
 *
 * Words that reach the note without the editor - a capture appending to it, a journal entry, Claude through the
 * connector - are reconciled into the document as a change (`reconcile`): the lines that differ go and the new ones
 * come, in one transaction, so a change made anywhere merges with the team's rather than overwriting it.
 *
 * A canvas (docs/SHARED.md, S9; core/team/canvas.ts), once its structure is seeded, is its types: `words` reads
 * the JSON from them under the text's front matter, `reconcile` reads words into them, and the text's own JSON is
 * left as it was, since JSON written as text by two members at once merges into no JSON at all.
 */


export interface TeamDoc {
  readonly noteId: string;
  readonly doc: Y.Doc;
  readonly text: Y.Text;
  /** The last seq of the note's log applied here, and the seq the organization's row covered when last put or read. */
  seq: number;
  snapshotSeq: number;
  /** The document's words now. */
  words(): string;
  /** `words` brought into the document as one change, where they differ from it. True when something changed. */
  reconcile(words: string): boolean;
  /** Updates from the log or the organization's row, applied; the words after, when they changed. */
  applyRemote(updates: readonly Uint8Array[], seq?: number): string | null;
  /** The updates made here that the service has not been given yet, in order. */
  pending(): Uint8Array[];
  /** The first `count` pending updates are with the service now. */
  posted(count: number): void;
  /** The whole document, for the organization's row. */
  snapshot(): Uint8Array;
  /** Kept to the store now, rather than a moment from now. */
  flush(): Promise<void>;
  /** Told when the words change by an update from elsewhere, or by a reconcile. */
  onWords(listener: (words: string) => void): () => void;
}

const docs = new Map<string, Promise<TeamDoc>>();

/** The field a note's words live in, as the live session names it (core/live/session.ts). */
const FIELD = 'body';

/** How long a change rests before the document is kept to the store. */
const KEEP_AFTER_MS = 400;

function make(noteId: string, store: TeamDocStore, record: TeamDocRecord | null, seedWords: string | null): TeamDoc {
  const doc = new Y.Doc();
  const text = doc.getText(FIELD);
  let pending: Uint8Array[] = record ? [...record.pending] : [];
  if (record) Y.applyUpdate(doc, record.state, REMOTE);
  else if (seedWords) text.insert(0, seedWords);
  // A document seeded here from the note's words is itself a change the service has not seen: the whole of it.
  if (!record && seedWords) pending = [Y.encodeStateAsUpdate(doc)];
  const listeners = new Set<(words: string) => void>();
  let keep: ReturnType<typeof setTimeout> | null = null;
  let keeping: Promise<void> = Promise.resolve();
  const words = () => (hasTeamCanvas(doc) ? canvasWords(doc, text.toString()) : text.toString());
  const self: TeamDoc = {
    noteId,
    doc,
    text,
    seq: record?.seq ?? 0,
    snapshotSeq: record?.snapshotSeq ?? 0,
    words,
    reconcile(given) {
      const now = words();
      if (now === given) return false;
      if (hasTeamCanvas(doc)) {
        // The canvas into its types, and only the front matter - the name, the tags - into the text.
        const changed = reconcileCanvas(doc, given);
        const was = text.toString();
        const front = frontMatterOf(given);
        const had = frontMatterOf(was);
        if (front !== had) applyTextDiff(text, was, front + was.slice(had.length));
        if (!changed && front === had) return false;
      } else {
        applyTextDiff(text, now, given);
      }
      listeners.forEach((listener) => listener(words()));
      return true;
    },
    applyRemote(updates, seq) {
      const before = words();
      doc.transact(() => {
        for (const update of updates) Y.applyUpdate(doc, update, REMOTE);
      }, REMOTE);
      if (seq !== undefined) self.seq = Math.max(self.seq, seq);
      soon();
      const after = words();
      if (after === before) return null;
      listeners.forEach((listener) => listener(after));
      return after;
    },
    pending: () => [...pending],
    posted(count) {
      pending = pending.slice(count);
      soon();
    },
    snapshot: () => Y.encodeStateAsUpdate(doc),
    flush() {
      if (keep) {
        clearTimeout(keep);
        keep = null;
      }
      keeping = keeping.then(() => store.write(noteId, { state: Y.encodeStateAsUpdate(doc), seq: self.seq, snapshotSeq: self.snapshotSeq, pending: [...pending] }));
      return keeping;
    },
    onWords(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
  const soon = () => {
    if (keep) clearTimeout(keep);
    keep = setTimeout(() => void self.flush(), KEEP_AFTER_MS);
  };
  doc.on('update', (update: Uint8Array, origin: unknown) => {
    if (origin === REMOTE) return;
    pending.push(update);
    soon();
  });
  // Seeded here: kept at once, so a page closed before the first pass still has the words pending for the team.
  if (!record && seedWords) soon();
  return self;
}

/** A body's front matter block with its closing line, or nothing where it has none. */
function frontMatterOf(body: string): string {
  const lines = body.split('\n');
  const end = frontMatterEnd(lines);
  return end ? `${lines.slice(0, end).join('\n')}\n` : '';
}


/**
 * Note `noteId`'s document: the one held, else the one kept in the store, else - with `seedWords` - a new one with
 * those words, the whole of them pending for the service. Null when there is none and nothing to seed with.
 */
export function teamDoc(noteId: string, store: TeamDocStore, seedWords: string | null = null): Promise<TeamDoc | null> {
  const held = docs.get(noteId);
  if (held) return held;
  const made = (async () => {
    const record = await store.read(noteId);
    if (!record && seedWords === null) return null;
    return make(noteId, store, record, seedWords);
  })();
  docs.set(
    noteId,
    made.then((doc) => {
      if (!doc) docs.delete(noteId);
      return doc as TeamDoc;
    }),
  );
  return made;
}

/** The document adopted from the organization's row: its state applied over whatever this device holds. */
export async function adoptTeamDoc(noteId: string, store: TeamDocStore, state: Uint8Array, seq: number): Promise<TeamDoc> {
  const held = await teamDoc(noteId, store);
  if (held) {
    held.applyRemote([state], seq);
    held.snapshotSeq = Math.max(held.snapshotSeq, seq);
    return held;
  }
  const doc = make(noteId, store, { state, seq, snapshotSeq: seq, pending: [] }, null);
  docs.set(noteId, Promise.resolve(doc));
  await doc.flush();
  return doc;
}

/** The document let go: the note is gone, or no longer the team's. */
export async function dropTeamDoc(noteId: string, store: TeamDocStore): Promise<void> {
  const held = docs.get(noteId);
  docs.delete(noteId);
  const doc = held ? await held.catch(() => null) : null;
  doc?.doc.destroy();
  await store.remove(noteId);
}

/** Every document held, for the pass and the tests. */
export function heldTeamDocs(): string[] {
  return [...docs.keys()];
}

/** Forgotten without touching the store: signing out, and between tests. */
export function forgetTeamDocs(): void {
  docs.clear();
}
