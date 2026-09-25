/**
 * How tall a drawn block was, remembered by what it shows: in memory while the app is open, and across launches.
 *
 * A block widget is drawn after the note is laid out - a board once its cards are measured (editor/boards/height.ts),
 * a diagram once mermaid has drawn it (editor/mermaid.ts) - and until then the editor counts it at the widget's
 * `estimatedHeight`. Counted as one line, it grew by a screenful as it came into view, the editor moved the note to
 * keep its place, and on a phone that move stops a fling dead (Matt: "scrolling past boards is glitchy and stops
 * scroll momentum"). So the height each one was drawn at is kept, and a note opened again knows it before drawing.
 *
 * Kept newest last, the oldest let go past a cap, and written half a second after the last change so a board settling
 * through several sizes is one write. Each kind of block keeps the storage key, the cap and the rounding it has always
 * had: a build rolled back over the air reads what the newer one wrote. The key is named where the block is, in the
 * `store` it hands over, because that is where core/reset.test.ts looks to prove a reset can find it.
 */

export interface HeightMemory {
  /** The height `face` was last drawn at, or null for one never drawn (or not remembered). */
  known(face: string): number | null;
  /** Remembers `height` for `face`, rounded the memory's way. */
  keep(face: string, height: number): void;
}

/** Where a memory is kept: what storage holds under its key, as JSON, and writing the pairs back there. */
export interface HeightStore {
  read(): unknown;
  write(pairs: [string, number][]): void;
}

/** Writes wait this long after the last change, so a block settling through several heights is one write. */
const SAVE_AFTER_MS = 500;

/**
 * A memory kept in `store`, holding at most `kept` blocks, each height passed through `round` first. The store is read
 * the first time the memory is asked, not when it is made.
 */
export function heightMemory(store: HeightStore, kept: number, round: (height: number) => number): HeightMemory {
  let heights: Map<string, number> | null = null;
  let saving = 0;

  const all = (): Map<string, number> => {
    if (heights) return heights;
    heights = new Map();
    // No storage, or something other than pairs in it: blocks are guessed at until they are drawn.
    const stored = store.read();
    for (const entry of Array.isArray(stored) ? stored : []) {
      if (Array.isArray(entry) && typeof entry[0] === 'string' && typeof entry[1] === 'number') heights.set(entry[0], entry[1]);
    }
    return heights;
  };

  return {
    known: (face) => all().get(shortKey(face)) ?? null,
    keep(face, height) {
      const held = all();
      const name = shortKey(face);
      const px = round(height);
      if (held.get(name) === px) return;
      // Newest last, so the oldest are the first let go.
      held.delete(name);
      held.set(name, px);
      for (const old of held.keys()) {
        if (held.size <= kept) break;
        held.delete(old);
      }
      if (saving || typeof window === 'undefined') return;
      saving = window.setTimeout(() => {
        saving = 0;
        // Not kept: remembered for as long as the app is open.
        store.write([...held]);
      }, SAVE_AFTER_MS);
    },
  };
}

/** A short name for what a block shows: its length and an FNV-1a hash, since the face itself can be every card's words. */
function shortKey(face: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < face.length; i += 1) {
    hash ^= face.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return `${face.length.toString(36)}.${(hash >>> 0).toString(36)}`;
}
