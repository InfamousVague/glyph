import { addToLane, lanesOf } from '../core/boards.ts';
import { frontMatterEnd } from '../core/frontMatter.ts';
import { listLead } from '../core/itemSyntax.ts';
import { capitalise } from '../core/text.ts';
import { appendBlock, appendBody } from './appendBody.ts';
import { itemText, runsOf, semanticListKind, type Run } from './listAppend.ts';

/**
 * Where a take's words go inside the note they are for, and the note as it reads with them there: what the recorder's
 * page draws as the words are said, what Done writes, and what the better words write later, so the three agree.
 *
 * Matt: "when it's found that note, it should look through the note and see what different things I could be talking
 * about adding to. Like if there's a list already." So a note that keeps lists takes the words as items of the one they
 * fit: the only list; the list under a heading that shares their words ("call an electrician" under Electrical, not
 * under Kitchen for sharing "fix"); a to-do list when a to-do was said or the title says to-dos; otherwise the first
 * to-do list with something still to do, or the last list. A note with none starts one when its title says what it
 * holds (House TODOs, Groceries), and otherwise the words go on its end as they always did.
 *
 * Three pure steps: `placingFor` decides the kind of place from the note and what was said, `itemsOf` reads the take's
 * markdown as items, and `placeTake` writes them in. `placeTake` depends only on its arguments, so the page, Done and
 * the better words, handed the same note, words and placing, write the same text.
 */

/** A lane of a board, by name, for "add … to Doing" said on the board's own Speak (core/boards.ts). */
export type Placing =
  | { kind: 'end' }
  | {
      kind: 'lists';
      /** A to-do was said, or the title says to-dos: only the to-do lists count, and a new list is one. */
      task: boolean;
      /** A heading said for it ("under Electrical"): the list under that heading. */
      heading: string | null;
      /** The note has no list yet: the one to start, or null for none (the words go at the end). */
      fresh: 'task' | 'bullet' | null;
    }
  | { kind: 'lane'; lane: string };

/** The end of the note, byte for byte what `appendBody` writes. */
export const END: Placing = { kind: 'end' };

/** What a command said about the words it sent: a to-do or task, or a paragraph. */
export interface Said {
  task?: boolean;
  paragraph?: boolean;
}

/**
 * The kind of place `base` has for a take's words.
 *
 * - A move ("move this to …") or "as a paragraph": the end.
 * - A note's own Speak: the end, as it always was, unless its title says what it holds (House TODOs, Groceries), when
 *   what is said is its items.
 * - Otherwise the note's lists, when it has any, or a new one when its title or the command says what kind.
 */
export function placingFor(base: string, { said = {}, heading = null, lane = null, move = false, own = false }: { said?: Said; heading?: string | null; lane?: string | null; move?: boolean; own?: boolean } = {}): Placing {
  if (move || said.paragraph) return END;
  if (lane && lanesOf(base).some((candidate) => candidate.name === lane)) return { kind: 'lane', lane };
  const kind = semanticListKind(base);
  if (own && !kind && !heading) return END;
  const task = Boolean(said.task) || kind === 'task';
  if (runsOf(base.split('\n')).length) return { kind: 'lists', task, heading, fresh: null };
  const fresh = task ? 'task' : kind === 'bullet' ? 'bullet' : null;
  return fresh ? { kind: 'lists', task, heading, fresh } : END;
}

// ---- the take as items ------------------------------------------------------------------------

export interface TakeItem {
  text: string;
  /** Lines under it: a sentence that carries it on ("because the switch sparks"). */
  more: string[];
}

/** A sentence that carries the one before it on, rather than being a thing of its own. */
const CONTINUES = /^(?:because|'cause|cause|so|but|which|since|i think|i guess|apparently|that's|it's|they're|he's|she's)\b/i;
/** Words a person joins items with, which are not the item. */
const JOINER = /^(?:and also|oh and|and|also|plus)[,\s]+/i;
/** A sentence this long is a thought, not a thing to do. */
const LONG_WORDS = 30;
/** A block that is not words to list: a heading, a fence, a table, a quote, a rule, a voice memo's mark. */
const NOT_ITEMS = /^(?:#{1,6}\s|```|~~~|\||>|---\s*$|\*\*\*\s*$|!\[)/;
/** Where one sentence ends and the next begins. */
const SENTENCE = /(?<=[.!?…])\s+(?=["'“(]?[\p{Lu}\p{N}])/u;

/**
 * The take's markdown (capture/markdown.ts `renderNote`, untitled) as items: each list line one, each sentence of a
 * paragraph one, with a sentence that carries the last one on ("Because the switch sparks.") under it, and anything
 * that is not words to list - a heading, a table, a fenced block, a voice memo, a thought over thirty words said first
 * - kept to go after the lists, at the end.
 */
export function itemsOf(markdown: string): { items: TakeItem[]; after: string[] } {
  const items: TakeItem[] = [];
  const after: string[] = [];
  for (const block of markdown.split(/\n{2,}/)) {
    const lines = block.split('\n').filter((line) => line.trim());
    if (!lines.length) continue;
    if (NOT_ITEMS.test(lines[0]!.trimStart())) {
      after.push(lines.join('\n'));
      continue;
    }
    if (listLead(lines[0]!)) {
      for (const line of lines) {
        const lead = listLead(line);
        if (lead && !lead.indent) items.push({ text: line.slice(lead.wordsAt), more: [] });
        else if (items.length) items.at(-1)!.more.push(lead ? line.slice(lead.wordsAt) : line.trim());
        else items.push({ text: line.trim(), more: [] });
      }
      continue;
    }
    for (const sentence of lines.join(' ').split(SENTENCE)) {
      const text = sentence.trim();
      if (!text) continue;
      const long = text.split(/\s+/).length > LONG_WORDS;
      if ((CONTINUES.test(text) || long) && items.length) items.at(-1)!.more.push(text);
      else if (long) after.push(text);
      else items.push({ text: text.replace(JOINER, ''), more: [] });
    }
  }
  return { items: items.filter((item) => itemText(item.text)), after };
}

// ---- which list ---------------------------------------------------------------------------------

/** Words that say nothing of which list: the small ones, and the verbs a thing to do starts with. */
const QUIET = new Set(
  'the and for with that this from into onto about have has was were are its our your their them then than just also need needs should will would could can call book buy email send pick make check clean take find sort look ring text order tell remember finish write read bring sure want'.split(
    ' ',
  ),
);

/** A text's stems: the first six letters of each word of four or more that says something. */
function stems(text: string): Set<string> {
  return new Set(
    text
      .toLowerCase()
      .replace(/\]\([^)]*\)/g, ' ')
      .split(/[^\p{L}\p{N}]+/u)
      .filter((word) => word.length >= 4 && !QUIET.has(word))
      .map((word) => word.slice(0, 6)),
  );
}

/** For each line, the heading it sits under, fence-aware, never the note's own title (its first line, as a heading). */
function headingsAbove(lines: readonly string[]): (string | null)[] {
  const out: (string | null)[] = [];
  const start = frontMatterEnd(lines);
  let current: string | null = null;
  let fence: string | null = null;
  let titled = false;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i] ?? '';
    out.push(current);
    if (i < start) continue;
    const marker = /^\s*(`{3,}|~{3,})/.exec(line)?.[1] ?? null;
    if (marker) {
      if (!fence) fence = marker.charAt(0);
      else if (marker.charAt(0) === fence) fence = null;
      continue;
    }
    if (fence || !line.trim()) continue;
    const heading = /^#{1,6}\s+(.+?)\s*#*\s*$/.exec(line);
    if (heading && !titled && /^#\s/.test(line)) {
      titled = true;
      continue;
    }
    titled = true;
    if (heading) current = heading[1]!;
  }
  return out;
}

/** A list's heading as its words go: the heading above it, or the "Label:" line just above it. */
function headingOf(lines: readonly string[], run: Run, above: readonly (string | null)[]): string | null {
  for (let i = run.first - 1; i >= 0; i -= 1) {
    const line = (lines[i] ?? '').trim();
    if (!line) continue;
    if (/:\s*$/.test(line) && !listLead(line)) return line.replace(/:\s*$/, '');
    break;
  }
  return above[run.first] ?? null;
}

/** How well `text` fits a list: its heading's stems count twice, its items' once. */
function fit(text: string, heading: string | null, items: string): number {
  const wanted = stems(text);
  const titled = stems(heading ?? '');
  const listed = stems(items);
  let score = 0;
  for (const stem of wanted) score += (titled.has(stem) ? 2 : 0) + (listed.has(stem) ? 1 : 0);
  return score;
}

// ---- writing them in ------------------------------------------------------------------------------

export interface Placed {
  /** The note with the take's words in it. */
  body: string;
  /** The pieces of text put in, each as it was written: for Undo to find and take out again. */
  blocks: string[];
  /** Where they went, in words ("under Electrical", "in its to-do list"), or null for the end of the note. */
  spot: string | null;
}

/** An item as a line of `run`'s list, numbered `n` when the list is numbered. */
function lineIn(run: Run, text: string, n: number): string {
  const box = run.style.task ? '[ ] ' : '';
  return run.style.kind === 'number' ? `${run.indent}${n}${run.style.delimiter} ${box}${text}` : `${run.indent}${run.style.mark} ${box}${text}`;
}

/** An item's line and the lines under it. */
function itemLines(first: string, item: TakeItem, under: string): string[] {
  return [first, ...item.more.map((line) => `${under}${capitalise(line.trim())}`)];
}

/**
 * `base` with the take's `markdown` in it, where `placing` says: at the end (`appendBody`), in a lane of the note's
 * board, or as items of its lists, each item in the list it fits and the rest after them at the end.
 */
export function placeTake(base: string, markdown: string, placing: Placing): Placed {
  if (placing.kind === 'end') return { body: appendBody(base, markdown), blocks: markdown.trim() ? [markdown] : [], spot: null };
  if (!markdown.trim()) return { body: base, blocks: [], spot: null };
  const { items, after } = itemsOf(markdown);
  let body = base;
  const blocks: string[] = [];
  let spot: string | null = null;

  if (placing.kind === 'lane') {
    for (const item of items) {
      const lane = lanesOf(body).find((candidate) => candidate.name === placing.lane);
      const added = lane ? addToLane(body, lane, itemText(item.text)) : null;
      if (!added) continue;
      body = added.body;
      blocks.push(added.line);
    }
    spot = `in ${placing.lane}`;
  } else if (items.length) {
    const lines = body.split('\n');
    const all = runsOf(lines);
    const runs = placing.task && all.some((run) => run.style.task) ? all.filter((run) => run.style.task) : all;
    if (!runs.length) {
      const box = (placing.fresh ?? (placing.task ? 'task' : 'bullet')) === 'task' ? '- [ ] ' : '- ';
      const block = items.flatMap((item) => itemLines(`${box}${itemText(item.text)}`, item, '  ')).join('\n');
      body = appendBlock(body, block);
      blocks.push(block);
      spot = box === '- [ ] ' ? 'in a new to-do list' : 'in a new list';
    } else {
      const above = headingsAbove(lines);
      const lists = runs.map((run) => ({ run, heading: headingOf(lines, run, above), items: lines.slice(run.first, run.last + 1).join(' ') }));
      const scoreOf = (text: string, index: number) => fit(text, lists[index]!.heading, lists[index]!.items);
      const bestFor = (text: string) => {
        let best = -1;
        let top = 0;
        lists.forEach((_, index) => {
          const score = scoreOf(text, index);
          if (score > top) {
            top = score;
            best = index;
          }
        });
        return { index: best, score: top };
      };
      const named = placing.heading ? lists.findIndex((list) => list.heading !== null && fit(placing.heading!, list.heading, '') > 0) : -1;
      const first = items[0]!.text;
      let current = named >= 0 ? named : bestFor(first).index;
      if (current < 0) {
        // Nothing to go by: the first to-do list with something still to do, or the last list, where items always went.
        const open = lists.findIndex((list) => list.run.style.task && lines.slice(list.run.first, list.run.last + 1).some((line) => listLead(line)?.done === false));
        current = open >= 0 ? open : lists.length - 1;
      }
      const firstList = lists[current]!;
      spot = firstList.heading ? `under ${firstList.heading}` : firstList.run.style.task ? 'in its to-do list' : 'in its list';
      const into = new Map<number, TakeItem[]>();
      items.forEach((item, i) => {
        if (i > 0) {
          // Related things said together stay together; one that plainly fits another list goes there.
          const other = bestFor(item.text);
          if (other.index >= 0 && other.index !== current && other.score >= 2 && other.score > scoreOf(item.text, current)) current = other.index;
        }
        into.set(current, [...(into.get(current) ?? []), item]);
      });
      // From the last list up, so the lines of the ones above keep their places.
      const order = [...into.keys()].sort((a, b) => lists[b]!.run.last - lists[a]!.run.last);
      const next = [...lines];
      const written = new Map<number, string>();
      for (const index of order) {
        const run = lists[index]!.run;
        let n = run.style.kind === 'number' ? run.style.next : 0;
        const under = `${run.indent}${run.style.kind === 'number' ? '   ' : '  '}`;
        const added = into.get(index)!.flatMap((item) => itemLines(lineIn(run, itemText(item.text), n++), item, under));
        next.splice(run.last + 1, 0, ...added);
        written.set(index, added.join('\n'));
      }
      body = next.join('\n');
      for (const index of [...into.keys()]) blocks.push(written.get(index)!);
    }
  }
  for (const block of after) {
    body = appendBlock(body, block);
    blocks.push(block);
  }
  return { body, blocks, spot };
}
