import * as Y from 'yjs';
import { canvasOf, parseCanvas, withCanvas, type Canvas, type CanvasComment, type CanvasEdge, type CanvasNode } from '../../canvas/jsonCanvas.ts';
import type { TeamDoc } from './doc.ts';
import { applyTextDiff } from './textDiff.ts';

/**
 * A team canvas as a structure the members' edits merge in (docs/SHARED.md, S9): beside the note's words - the
 * JSON the library and Obsidian read - the same Yjs document holds the canvas as types, `canvas-nodes` a map of
 * node id to a map of the node's fields (a card's words a `Y.Text`), `canvas-edges` the same for the lines, and
 * `canvas-order` the node ids in their z-order. Two members moving different cards, or typing in the same one, both
 * keep what they did; the same field set twice at once takes one of them, whole, never a splice of both numbers,
 * which is what merging the JSON as words would have made. The types are the document's own named roots, so two
 * devices seeding the structure at once from the same JSON write the same keys into the same maps, and neither
 * loses the other's; a card both seeded keeps one device's copy, which is the same card.
 *
 * Once seeded, the types are the canvas, and the note's words are read from them (core/team/doc.ts `words`:
 * the front matter from the document's text, the JSON from the types), never written into the shared text: two
 * members' JSON written as text at once merges into a splice that is no JSON at all, where the same two changes to
 * the types merge into a canvas. The view edits by handing back the whole canvas (canvas/CanvasView.tsx
 * `onChange`): `apply` works out what changed and writes only that. Words that reach the note without the view -
 * typed by hand in the JSON view, written by Claude or the Mac's folder - are read into the types as a change when a
 * pass reconciles them (`reconcileCanvas`).
 */

/** A change made by this adapter: the types and the words together. The text's own `follow` leaves these alone. */
export const CANVAS = Symbol('team: the canvas adapter');

export interface TeamCanvas {
  /** The canvas as the types hold it now. */
  canvas(): Canvas;
  /** The view's next canvas written into the types and the words, as one change. */
  apply(next: Canvas): void;
  /** Told the canvas after every change to the types, this device's or another's. */
  onChange(listener: (canvas: Canvas) => void): () => void;
}

type Fields = Y.Map<unknown>;

const adapters = new WeakMap<Y.Doc, TeamCanvas | null>();

/** The fields of a node or an edge that are words, kept as a `Y.Text` so typing in one card by two members merges. */
const WORDS = new Set(['text']);

/**
 * The adapter for a team note's document, made once per document: null for a note that is not a canvas (its words
 * are not one, and the types are empty).
 */
export function teamCanvas(doc: Pick<TeamDoc, 'doc' | 'text'>): TeamCanvas | null {
  const held = adapters.get(doc.doc);
  if (held !== undefined) return held;
  const made = make(doc);
  adapters.set(doc.doc, made);
  return made;
}

/** The document's own named roots that hold the structure: shared by name, never made twice. */
interface Roots {
  nodes: Y.Map<Fields>;
  edges: Y.Map<Fields>;
  order: Y.Array<string>;
  /** The threads (S9), by id: a map of the thread's fields, its replies an array both members' replies land in. */
  comments: Y.Map<Fields>;
  meta: Y.Map<unknown>;
}

function rootsOf(doc: Y.Doc): Roots {
  return {
    nodes: doc.getMap<Fields>('canvas-nodes'),
    edges: doc.getMap<Fields>('canvas-edges'),
    order: doc.getArray<string>('canvas-order'),
    comments: doc.getMap<Fields>('canvas-comments'),
    meta: doc.getMap<unknown>('canvas-meta'),
  };
}

function make(doc: Pick<TeamDoc, 'doc' | 'text'>): TeamCanvas | null {
  const roots = rootsOf(doc.doc);
  if (!roots.meta.get('seeded')) {
    const words = canvasOf(doc.text.toString());
    if (!words) return null;
    doc.doc.transact(() => {
      write(roots, words);
      roots.meta.set('seeded', 1);
    }, CANVAS);
  }
  let shown: Canvas | null = null;
  const listeners = new Set<(canvas: Canvas) => void>();
  const self: TeamCanvas = {
    canvas() {
      if (!shown) shown = read(roots);
      return shown;
    },
    apply(next) {
      doc.doc.transact(() => write(roots, next), CANVAS);
    },
    onChange(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
  const changed = (transaction: Y.Transaction) => {
    shown = null;
    if (transaction.origin === CANVAS && listeners.size === 0) return;
    const canvas = self.canvas();
    listeners.forEach((listener) => listener(canvas));
  };
  // One telling per transaction, however many of the roots it touched.
  let told: Y.Transaction | null = null;
  const onDeep = (_events: unknown, transaction: Y.Transaction) => {
    if (told === transaction) return;
    told = transaction;
    changed(transaction);
  };
  roots.nodes.observeDeep(onDeep);
  roots.edges.observeDeep(onDeep);
  roots.comments.observeDeep(onDeep);
  roots.order.observe((_event, transaction) => onDeep(undefined, transaction));
  return self;
}

function same(a: Canvas, b: Canvas): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

/**
 * The note's words as the types say them: the front matter as the document's text has it, then the canvas the
 * types hold, as the spec writes it. What core/team/doc.ts answers for `words` once the canvas is seeded.
 */
export function canvasWords(ydoc: Y.Doc, text: string): string {
  return withCanvas(text, read(rootsOf(ydoc)));
}

/**
 * Words that reached the note without the view - a hand edit of the JSON, Claude, the Mac's folder - read into the
 * types as a change (`reconcile` in core/team/doc.ts, for a seeded canvas). True when something changed; words that
 * are not a canvas change nothing.
 */
export function reconcileCanvas(ydoc: Y.Doc, words: string): boolean {
  const canvas = canvasOf(words);
  if (!canvas) return false;
  const roots = rootsOf(ydoc);
  if (same(canvas, read(roots))) return false;
  ydoc.transact(() => write(roots, canvas), CANVAS);
  return true;
}

/** The types as a canvas: the nodes in their order, the edges and the threads by id, each read leniently as the JSON would be. */
function read({ nodes, edges, order, comments }: Roots): Canvas {
  const ids: string[] = [];
  const seen = new Set<string>();
  for (const id of order.toArray()) {
    if (!seen.has(id) && nodes.has(id)) {
      seen.add(id);
      ids.push(id);
    }
  }
  for (const id of [...nodes.keys()].sort()) if (!seen.has(id)) ids.push(id);
  const plain = (fields: Fields): Record<string, unknown> => {
    const out: Record<string, unknown> = {};
    for (const [key, value] of fields.entries()) out[key] = value instanceof Y.Text ? value.toString() : value;
    return out;
  };
  const thread = (id: string): Record<string, unknown> => {
    const fields = comments.get(id)!;
    const replies = fields.get('replies');
    return { id, ...plain(fields), replies: replies instanceof Y.Array ? replies.toArray() : [] };
  };
  const raw = {
    nodes: ids.map((id) => ({ id, ...plain(nodes.get(id)!) })),
    edges: [...edges.keys()].sort().map((id) => ({ id, ...plain(edges.get(id)!) })),
    comments: [...comments.keys()].sort().map(thread),
  };
  return parseCanvas(JSON.stringify(raw)) ?? { nodes: [], edges: [] };
}

/** `next` written into the types: only what differs from what they hold. Inside a transaction. */
function write({ nodes, edges, order, comments }: Roots, next: Canvas): void {
  writeAll(nodes, next.nodes);
  writeAll(edges, next.edges);
  writeThreads(comments, next.comments ?? []);
  const wanted = next.nodes.map((node) => node.id);
  const had = order.toArray();
  const keep = new Set(wanted);
  // Gone, or doubled by two devices putting the same id in at once: taken out, from the end so the indexes hold.
  const seenHere = new Set<string>();
  for (let i = had.length - 1; i >= 0; i -= 1) {
    const id = had[i]!;
    if (!keep.has(id) || seenHere.has(id)) order.delete(i, 1);
    seenHere.add(id);
  }
  const now = order.toArray();
  if (now.length === wanted.length && now.every((id, i) => id === wanted[i])) return;
  // New ids put in where they belong; an order that still differs is rewritten whole (a card sent to the back).
  const present = new Set(now);
  wanted.forEach((id, i) => {
    if (!present.has(id)) order.insert(Math.min(i, order.length), [id]);
  });
  const after = order.toArray();
  if (after.length === wanted.length && after.every((id, i) => id === wanted[i])) return;
  order.delete(0, order.length);
  order.insert(0, wanted);
}

/**
 * The threads: each a map of its fields, with `replies` an array only ever added to, so two members replying at
 * once both land; `resolved` set and taken off as the thread closes and reopens.
 */
function writeThreads(into: Y.Map<Fields>, threads: readonly CanvasComment[]): void {
  const wanted = new Set(threads.map((thread) => thread.id));
  for (const id of [...into.keys()]) if (!wanted.has(id)) into.delete(id);
  for (const thread of threads) {
    const fields = into.get(thread.id) ?? new Y.Map<unknown>();
    if (!into.has(thread.id)) into.set(thread.id, fields);
    const { replies, resolved, ...rest } = thread;
    writeFields(fields, rest as unknown as Record<string, unknown>);
    let held = fields.get('replies');
    if (!(held instanceof Y.Array)) {
      held = new Y.Array<unknown>();
      fields.set('replies', held);
    }
    const list = held as Y.Array<unknown>;
    if (replies.length > list.length) list.push(replies.slice(list.length).map((reply) => ({ ...reply })));
    if (resolved) {
      const was = fields.get('resolved') as { by?: string; at?: string } | undefined;
      if (was?.by !== resolved.by || was?.at !== resolved.at) fields.set('resolved', { ...resolved });
    } else if (fields.has('resolved')) fields.delete('resolved');
  }
}

function writeAll(into: Y.Map<Fields>, items: readonly (CanvasNode | CanvasEdge)[]): void {
  const wanted = new Set(items.map((item) => item.id));
  for (const id of [...into.keys()]) if (!wanted.has(id)) into.delete(id);
  for (const item of items) {
    const fields = into.get(item.id) ?? new Y.Map<unknown>();
    if (!into.has(item.id)) into.set(item.id, fields);
    writeFields(fields, item as unknown as Record<string, unknown>);
  }
}

function writeFields(fields: Fields, item: Record<string, unknown>): void {
  for (const key of [...fields.keys()]) if (key !== 'id' && key !== 'replies' && key !== 'resolved' && item[key] === undefined) fields.delete(key);
  for (const [key, value] of Object.entries(item)) {
    if (key === 'id' || value === undefined) continue;
    const held = fields.get(key);
    if (WORDS.has(key) && typeof value === 'string') {
      if (held instanceof Y.Text) {
        const was = held.toString();
        if (was !== value) applyTextDiff(held, was, value);
      } else {
        const text = new Y.Text();
        fields.set(key, text);
        text.insert(0, value);
      }
      continue;
    }
    if (held !== value) fields.set(key, value);
  }
}

/** Whether a document's types hold a canvas yet: seeded here, or arrived from another device. */
export function hasTeamCanvas(doc: Y.Doc): boolean {
  return Boolean(doc.getMap<unknown>('canvas-meta').get('seeded'));
}
