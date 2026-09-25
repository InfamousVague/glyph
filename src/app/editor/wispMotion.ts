import { Annotation, Facet, StateEffect, StateField, type EditorState, type Transaction } from '@codemirror/state';
import { prefersStill } from '../core/motion.ts';
import { motionScale } from '../core/preferences.ts';

/**
 * What is in motion in a note's words, and when: the half of the Wisp treatment that decides, with none of the
 * drawing (editor/wispArrivals.ts draws it).
 *
 * A transaction carrying the `wisp` annotation - the recorder writing what it heard, or rewriting a pending phrase -
 * sets the letters it really added arriving and the text it really took away leaving, diffed so a phrase firming up
 * moves one letter. With typing on, the person's own letters and backspaces do too, and a paste only its first
 * letters. `revealWisp` fades a stretch already there in, as a note opens. Everything in motion is held in one field,
 * mapped through every change, with the moment each piece starts and how long it lasts at the chosen pace
 * (Settings > Animations), until the drawing says it has settled. With reduced motion asked for, nothing is set in
 * motion at all.
 *
 * The user events are load-bearing: a board's own edits (`input.board`) are not typing, and a tapped box's letter
 * (`input.toggle`, `input.choice`) dissolves where it stands rather than arriving.
 */

export type WispKind = 'heard' | 'rewrite';

/** Put on a transaction that writes what was heard, or rewrites a pending phrase. */
export const wisp = Annotation.define<{ kind: WispKind }>();

/** Whether typed and deleted text moves too. */
export const typing = Facet.define<boolean, boolean>({ combine: (values) => values.some(Boolean) });

/**
 * Text deleted by hand leaves quickly, and quicker still in a run of backspaces (Matt: "if the item is being
 * backspaced make the animation quicker"): the smoke is a trace of what went, not something to wait for. A single
 * letter leaves no trace at all, because it read as a stutter while typing.
 */
const DELETE_MS = 140;
const DELETE_RUN_MS = 85;
/** Backspaces closer together than this are one run. */
const DELETE_RUN_GAP_MS = 350;
let lastDeleteAt = 0;

function deleteMs(now: number): number {
  const run = now - lastDeleteAt < DELETE_RUN_GAP_MS;
  lastDeleteAt = now;
  return run ? DELETE_RUN_MS : DELETE_MS;
}

/** A paste animates no more letters than this: past it the pool would only settle the first ones early. */
const PASTE_MAX = 40;

/** A letter that arrived, or the text that left, still in motion. */
export interface Moving {
  id: number;
  /** Arriving: the letter's range in the document. Leaving: an empty range at the point it left. */
  from: number;
  to: number;
  /** The text, for a ghost of what left; empty for an arrival. */
  gone: string;
  /** performance.now() at which its motion starts; later than now for letters still waiting their turn. */
  at: number;
  /** A tapped box's letter (`- [x]`, `- ( )`): it dissolves where it stands, without the throw or the lift. */
  box?: boolean;

  dur: number;
}

/**
 * Letters a phrase types in at, ms; the whole phrase never waits longer than the cap. The words follow each other
 * quickly (Matt: "the text needs to fade in way faster"), but each keeps its full arc: shortening that made the smoke
 * end before it read ("it seems shortening the animation was wrong").
 */
const STAGGER_MS = 8;
/** However long a word, the next one never waits longer than this behind it. */
const WORD_MAX_MS = 62;
const STAGGER_CAP_MS = 1350;
/**
 * Quicker again, another quarter off (Matt: "the fade in wisp effect needs to be boosted by 33% speed", then "speed
 * up the wisp animation on text"): arc, jitter and stagger together, so the words still arrive in order.
 */
const IN_MS = 350;
const IN_JITTER_MS = 100;
const OUT_MS = 380;

/** Letters done moving, by id: the drawing says so, and this lets them go (editor/wispArrivals.ts). */
export const settle = StateEffect.define<readonly number[]>();

/**
 * Fades a stretch of text that is already there in from smoke, a line at a time and quickly: the note opening (Matt:
 * "the text on notes should quickly fade in with the wisp"). One filter a line, so a screenful fits the pool.
 */
export const revealWisp = StateEffect.define<{ from: number; to: number }>();

/** The opening reveal: each piece this far behind the one before, the whole never longer than the cap; and its arc. */
const REVEAL_STEP_MS = 10;
const REVEAL_CAP_MS = 290;
const REVEAL_MS = 260;
/**
 * A piece of the reveal is a few words, never more than this many characters: short enough to sit on one row. A
 * whole paragraph as one piece was one filter the width of the page and several rows deep, redrawn every frame (Matt:
 * "loading the second row of text is still super laggy").
 */
const REVEAL_PIECE_CHARS = 24;
/** Pieces the opening reveal animates: about a screen; anything further down is already set when scrolled to. */
const REVEAL_PIECES = 48;

function revealing(state: EditorState, from: number, to: number, now: number): Moving[] {
  const moving: Moving[] = [];
  let line = state.doc.lineAt(Math.max(0, Math.min(from, state.doc.length)));
  const end = Math.min(to, state.doc.length);
  while (moving.length < REVEAL_PIECES) {
    const text = line.text;
    const words = /\S+/g;
    let piece: { from: number; to: number } | null = null;
    const flush = () => {
      if (!piece) return;
      moving.push({ id: nextId++, from: line.from + piece.from, to: line.from + piece.to, gone: '', at: now + Math.min(moving.length * REVEAL_STEP_MS, REVEAL_CAP_MS), dur: REVEAL_MS + Math.random() * IN_JITTER_MS });
      piece = null;
    };
    for (let word = words.exec(text); word && moving.length < REVEAL_PIECES; word = words.exec(text)) {
      const wordEnd = word.index + word[0].length;
      if (piece && wordEnd - piece.from > REVEAL_PIECE_CHARS) flush();
      if (piece) piece.to = wordEnd;
      else piece = { from: word.index, to: wordEnd };
    }
    flush();
    if (line.to >= end || line.number >= state.doc.lines) break;
    line = state.doc.line(line.number + 1);
  }
  return moving;
}

let nextId = 1;

/** The common prefix and suffix of `a` and `b`, as lengths, never overlapping. */
export function commonEnds(a: string, b: string): { prefix: number; suffix: number } {
  const shortest = Math.min(a.length, b.length);
  let prefix = 0;
  while (prefix < shortest && a[prefix] === b[prefix]) prefix += 1;
  let suffix = 0;
  while (suffix < shortest - prefix && a[a.length - 1 - suffix] === b[b.length - 1 - suffix]) suffix += 1;
  return { prefix, suffix };
}

/** What a wisp transaction sets in motion: the letters it really added, and the text it really took away. */
function movingIn(tr: Transaction, now: number, cap = Number.POSITIVE_INFINITY, outMs = OUT_MS, singleLetters = true, box?: boolean): Moving[] {
  const moving: Moving[] = [];
  let wait = 0;
  let letters = 0;
  tr.changes.iterChanges((fromA, toA, fromB, _toB, inserted) => {
    const removed = tr.startState.doc.sliceString(fromA, toA);
    const added = inserted.toString();
    const { prefix, suffix } = commonEnds(removed, added);
    const gone = removed.slice(prefix, removed.length - suffix);
    // A letter backspaced by hand just goes: a trace of smoke on each was a stutter under the fingers (Matt:
    // "deleting characters should be instant and not glitchy when typing"). A word or a selection taken out at once
    // still smokes, and so does a letter a rewrite takes back while the words are being heard, which is not typing.
    if (gone.trim() && (singleLetters || gone.trim().length > 1)) moving.push({ id: nextId++, from: fromB + prefix, to: fromB + prefix, gone, at: now, dur: outMs, box });
    // A word at a time, one filter each, in turn at the pace its letters would type: a letter per filter made a long
    // phrase bend sixty at once, the phone fell behind, and the rest arrived all together (Matt: "it still animates
    // one line or so and then rapidly finishes"). A single typed letter is its own word, so typing is unchanged.
    const end = added.length - suffix;
    let i = prefix;
    while (i < end && letters < cap) {
      while (i < end && !(added[i] ?? '').trim()) i += 1;
      if (i >= end) break;
      let j = i;
      while (j < end && (added[j] ?? '').trim() && letters < cap) {
        j += 1;
        letters += 1;
      }
      moving.push({ id: nextId++, from: fromB + i, to: fromB + j, gone: '', at: now + Math.min(wait, STAGGER_CAP_MS), dur: IN_MS + Math.random() * IN_JITTER_MS, box });
      wait += Math.min(WORD_MAX_MS, (j - i + 1) * STAGGER_MS);
      i = j;
    }
  });
  return moving;
}

/** Motion set at the chosen pace (Settings > Animations): each piece's wait and its arc stretched or shortened alike. */
function paced(list: Moving[], now: number): Moving[] {
  const scale = motionScale();
  if (scale === 1) return list;
  return list.map((m) => ({ ...m, at: now + (m.at - now) * scale, dur: m.dur * scale }));
}

/** Everything in motion, mapped through every change, until the frame loop says it has settled. */
export const wispState = StateField.define<readonly Moving[]>({
  create: () => [],
  update(moving, tr) {
    let next = moving;
    if (tr.docChanged) {
      next = next.flatMap((m) => {
        const from = tr.changes.mapPos(m.from, m.gone ? -1 : 1);
        const to = tr.changes.mapPos(m.to, -1);
        // A word the change took away entirely is done moving.
        if (!m.gone && to <= from) return [];
        return [{ ...m, from, to }];
      });
    }
    for (const effect of tr.effects) {
      if (effect.is(revealWisp) && !prefersStill()) {
        const now = performance.now();
        next = [...next, ...paced(revealing(tr.state, effect.value.from, effect.value.to, now), now)];
      }
      if (effect.is(settle)) {
        const done = new Set(effect.value);
        next = next.filter((m) => !done.has(m.id));
      }
    }
    if (!tr.docChanged || prefersStill()) return next;
    if (tr.annotation(wisp)) {
      const now = performance.now();
      return [...next, ...paced(movingIn(tr, now), now)];
    }
    // A board's own edits are not typing (editor/boards.ts): a card ticked, moved or added rewrites the item's box and
    // the fence under the drawing, and none of that is a letter someone wrote.
    if (tr.isUserEvent('input.board')) return next;
    if (tr.state.facet(typing) && (tr.isUserEvent('input') || tr.isUserEvent('delete'))) {
      const now = performance.now();
      const deleting = tr.isUserEvent('delete');
      // A tapped box turns one letter between two that stay put: it dissolves where it stands.
      const box = tr.isUserEvent('input.toggle') || tr.isUserEvent('input.choice');
      return [...next, ...paced(movingIn(tr, now, tr.isUserEvent('input.paste') ? PASTE_MAX : Number.POSITIVE_INFINITY, deleting ? deleteMs(now) : OUT_MS, !deleting, box), now)];
    }
    return next;
  },
});

/** The letters and ghosts in motion right now, for a test or a caller wondering whether to wait. */
export function moving(state: EditorState): readonly Moving[] {
  return state.field(wispState, false) ?? [];
}
