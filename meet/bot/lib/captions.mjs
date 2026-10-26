/**
 * Meet's captions, turned into a speaker timeline.
 *
 * What the page gives (meet.mjs reads it twice a second) is the captions region as it stands: a short list of blocks,
 * each a speaker's display name over what they are saying. Blocks grow as the person talks, get revised (Meet corrects
 * a word or two once it hears the rest of the sentence), scroll off the top as new ones arrive at the bottom, and a
 * long monologue can lose its head while it keeps growing at the tail. Nothing in the DOM says "this phrase is
 * finished", so this decides it:
 *
 *   - a block is matched to the one it was a moment ago by position from the bottom, speaker and words in common
 *     (`align`), so a block that scrolled off, or one revised in place, is not taken for a new one;
 *   - a block's words are written out once it has not changed for `quietMs` (2 s), or as soon as a newer block is
 *     below it (somebody else started talking, or the same person after a pause);
 *   - a block that grows again after it was written out gives only its new words (`newWords`), so a pause in the
 *     middle of a long turn makes two lines and no repeats;
 *   - revisions to words already written out are let go: a line, once out, is not taken back.
 *
 * A line is `{ at, speaker, text }`, `at` in ms since the recording started: when the phrase was first seen.
 */

/** A block's raw text, `name\ntext`, as a speaker and what they said; null for a block that is only Meet's furniture. */
export function parseBlock(raw) {
  const lines = String(raw ?? '')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !NOISE.test(line) && !ICONS.has(line));
  if (!lines.length) return null;
  return { speaker: lines[0], text: lines.slice(1).join(' ') };
}

/** Icon ligatures and buttons that can sit inside the captions region beside the blocks. */
const NOISE = /^(arrow_downward|jump to bottom|settings|format_size|close|more_vert)$/i;

/**
 * Material Symbols ligatures Meet can draw inside a caption block, beside or in place of the avatar: the icon's glyph
 * is drawn from the word, so the block's text has the word in it, on a line of its own above the name. Matt's
 * engineering standup (2026-10-26) had a speaker read as `groups`, the people icon. Matched exactly and in lower case,
 * as a ligature is written, so a person who says "Groups." is still heard. The device drops the same words as a
 * speaker's name (lib/meet/speakers.dart `captionIcons`) for captions kept before this.
 */
export const ICONS = new Set([
  'groups',
  'group',
  'group_add',
  'person',
  'people',
  'account_circle',
  'meeting_room',
  'devices',
  'co_present',
  'present_to_all',
  'frame_person',
  'mic',
  'mic_off',
  'keep',
  'keep_off',
  'push_pin',
  'more_horiz',
  'closed_caption',
]);

/** The words of a text, each with the key it is compared by: lower case, no punctuation. Pure punctuation is dropped. */
export function tokens(text) {
  return String(text ?? '')
    .split(/\s+/)
    .map((raw) => ({ raw, key: raw.toLowerCase().replace(/[^\p{L}\p{N}']+/gu, '') }))
    .filter((token) => token.key);
}

/**
 * Whether `a` (a block a moment ago) and `b` (now) are the same block: one is empty (a block that has just appeared),
 * they start with the same few words, `b` starts where `a` ended (Meet trimmed the head of a long turn), or most of
 * the shorter one's words are in the longer one (a few words were revised).
 */
export function similar(a, b) {
  const x = tokens(a).map((t) => t.key);
  const y = tokens(b).map((t) => t.key);
  if (!x.length || !y.length) return true;
  let prefix = 0;
  while (prefix < x.length && prefix < y.length && x[prefix] === y[prefix]) prefix++;
  if (prefix >= Math.min(3, x.length, y.length)) return true;
  for (let size = Math.min(x.length, y.length); size >= 3; size--) {
    if (x.slice(-size).every((word, i) => y[i] === word)) return true;
  }
  const [short, long] = x.length <= y.length ? [x, y] : [y, x];
  const bag = new Map();
  for (const word of long) bag.set(word, (bag.get(word) ?? 0) + 1);
  let hits = 0;
  for (const word of short) {
    if (bag.get(word)) {
      hits++;
      bag.set(word, bag.get(word) - 1);
    }
  }
  return hits / short.length >= 0.6;
}

/**
 * Where the words of `current` that were not yet written out begin, given the keys already written (`written`).
 *
 *   - `current` still starts with them: everything after.
 *   - It does not (revised, or the head was trimmed): after the last place the written text's last few words (2 to 6)
 *     appear in it.
 *   - Neither, and it has grown well past them: after as many words as were written (a rough cut beats a lost phrase).
 *   - Otherwise: nothing new, it was a revision of words already out.
 */
export function newWordsFrom(written, current) {
  const keys = current.map((t) => t.key);
  if (!written.length) return 0;
  if (written.length <= keys.length && written.every((key, i) => keys[i] === key)) return written.length;
  for (let size = Math.min(6, written.length); size >= 2; size--) {
    const tail = written.slice(-size);
    for (let end = keys.length; end >= size; end--) {
      if (tail.every((key, i) => keys[end - size + i] === key)) return end;
    }
  }
  if (keys.length > written.length + 3) return written.length;
  return keys.length;
}

/**
 * How many of the blocks seen last time (`before`) have scrolled off the top, given the blocks now (`after`): the
 * smallest offset at which every block that is in both lines up by speaker and text. When none does, all of them have
 * gone (the whole region was replaced).
 */
export function align(before, after) {
  for (let offset = 0; offset < before.length; offset++) {
    const overlap = Math.min(before.length - offset, after.length);
    let matches = true;
    for (let i = 0; i < overlap && matches; i++) {
      const old = before[offset + i];
      matches = old.speaker === after[i].speaker && similar(old.text, after[i].text);
    }
    if (matches) return offset;
  }
  return before.length;
}

export class CaptionTimeline {
  /** `quietMs`: how long a block must stay unchanged to count as finished. */
  constructor({ quietMs = 2000, dedupeMs = 30000 } = {}) {
    this.quietMs = quietMs;
    this.dedupeMs = dedupeMs;
    /** The blocks on screen at the last update, top to bottom. */
    this.blocks = [];
    /** The last lines written, for de-duplication. */
    this.recent = [];
  }

  /**
   * The region as it stands at `at` (ms since the start): an array of blocks' raw texts, or of `{speaker, text}`.
   * Returns the lines finished by this update, in order.
   */
  update(snapshot, at) {
    const now = (snapshot ?? [])
      .map((block) => (typeof block === 'string' ? parseBlock(block) : block))
      .filter(Boolean);
    const out = [];
    const gone = align(this.blocks, now);
    for (const block of this.blocks.slice(0, gone)) this.#finish(block, out);
    this.blocks = this.blocks.slice(gone);
    now.forEach((seen, i) => {
      const block = this.blocks[i];
      if (!block) {
        this.blocks.push({ speaker: seen.speaker, text: seen.text, changedAt: at, since: at, pending: true, written: [] });
        return;
      }
      if (block.text === seen.text) return;
      if (!block.pending) {
        block.pending = true;
        block.since = at;
      }
      block.text = seen.text;
      block.changedAt = at;
    });
    // Blocks no longer on screen beyond the end (the region shrank from the bottom: a redraw) are finished too.
    for (const block of this.blocks.slice(now.length)) this.#finish(block, out);
    this.blocks = this.blocks.slice(0, now.length);
    this.blocks.forEach((block, i) => {
      if (!block.pending) return;
      if (i < this.blocks.length - 1 || at - block.changedAt >= this.quietMs) this.#finish(block, out);
    });
    return out;
  }

  /** Everything still pending, written out: the call is over. */
  flush() {
    const out = [];
    for (const block of this.blocks) this.#finish(block, out);
    this.blocks = [];
    return out;
  }

  #finish(block, out) {
    if (!block.pending) return;
    block.pending = false;
    const words = tokens(block.text);
    const from = newWordsFrom(block.written, words);
    block.written = words.map((t) => t.key);
    if (from >= words.length) return;
    const line = { at: block.since, speaker: block.speaker, text: words.slice(from).map((t) => t.raw).join(' ') };
    const key = `${line.speaker}\n${tokens(line.text).map((t) => t.key).join(' ')}`;
    this.recent = this.recent.filter((r) => line.at - r.at <= this.dedupeMs);
    if (this.recent.some((r) => r.key === key)) return;
    this.recent.push({ key, at: line.at });
    out.push(line);
  }
}
