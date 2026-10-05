import * as Y from 'yjs';
import { canvasOf, parseCanvas, withCanvas, type Canvas, type CanvasEdge, type CanvasNode } from '../../canvas/jsonCanvas.ts';
import { REMOTE } from '../live/session.ts';
import { applyTextDiff, type TeamDoc } from './doc.ts';

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
 * The view edits by handing back the whole canvas (canvas/CanvasView.tsx `onChange`): `apply` works out what
 * changed and writes only that into the types, and the note's words in the same transaction, so the JSON follows
 * on this device and on the others as part of the same change. Words changed without the types - typed by hand
 * in the JSON view, written by Claude or the Mac's folder, reconciled by a pass - are read back into the types
 * (`follow`); words that arrive from another device are not, since a merge of two members' JSON edits can land
 * between them, and the types already carry what each meant. The next change here writes the JSON whole again.
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
  meta: Y.Map<unknown>;
}

function rootsOf(doc: Y.Doc): Roots {
  return { nodes: doc.getMap<Fields>('canvas-nodes'), edges: doc.getMap<Fields>('canvas-edges'), order: doc.getArray<string>('canvas-order'), meta: doc.getMap<unknown>('canvas-meta') };
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
      doc.doc.transact(() => {
        write(roots, next);
        const was = doc.text.toString();
        const now = withCanvas(was, next);
        if (now !== was) applyTextDiff(doc.text, was, now);
      }, CANVAS);
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
  roots.order.observe((_event, transaction) => onDeep(undefined, transaction));
  // Words changed on this device without the types: read back into them, after the change that made them.
  doc.text.observe((event) => {
    if (event.transaction.origin === CANVAS || event.transaction.origin === REMOTE) return;
    queueMicrotask(() => {
      const words = canvasOf(doc.text.toString());
      if (!words || same(words, self.canvas())) return;
      doc.doc.transact(() => write(roots, words), CANVAS);
    });
  });
  return self;
}

function same(a: Canvas, b: Canvas): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

/** The types as a canvas: the nodes in their order, the edges by id, each read leniently as the JSON would be. */
function read({ nodes, edges, order }: Roots): Canvas {
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
  const raw = {
    nodes: ids.map((id) => ({ id, ...plain(nodes.get(id)!) })),
    edges: [...edges.keys()].sort().map((id) => ({ id, ...plain(edges.get(id)!) })),
  };
  return parseCanvas(JSON.stringify(raw)) ?? { nodes: [], edges: [] };
}

/** `next` written into the types: only what differs from what they hold. Inside a transaction. */
function write({ nodes, edges, order }: Roots, next: Canvas): void {
  writeAll(nodes, next.nodes);
  writeAll(edges, next.edges);
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
  for (const key of [...fields.keys()]) if (key !== 'id' && item[key] === undefined) fields.delete(key);
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
