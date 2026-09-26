import { frontMatterEnd } from '../core/frontMatter.ts';
import { noteTitle } from '../core/noteTitle.ts';
import { listLead, type ListLead } from '../core/itemSyntax.ts';
import { capitalise } from '../core/text.ts';
import { appendBlock } from './appendBody.ts';
import { titleKind } from './noteFind.ts';
import { enumeration } from './spoken/lists.ts';

/**
 * "New item for AttackFM": putting spoken items into a note's list, not at the
 * bottom of the note.
 *
 * A note's list is the last run of list lines in it (a to-do, a bullet or a
 * numbered line, with any indented lines that continue them). New items go on
 * the end of that run in the run's own style: a numbered list the next number,
 * a bullet list its own bullet, and a to-do list a box after either, at the
 * run's indent. A note with no list gets one at its end, as to-dos when the
 * command said "task" or "to-do". Pure, so every shape of note is a test.
 */

export interface Run {
  /** Index of the run's first and last line. */
  first: number;
  last: number;
  indent: string;
  /**
   * How the run's last top-level item is marked: its bullet or its next number, and whether it is a to-do. A `* [ ]`
   * list grows by `* [ ]` lines and a `1. [ ]` list by numbered to-dos, as every reader of the grammar
   * (core/itemSyntax.ts) takes them for to-dos too.
   */
  style: { kind: 'bullet'; mark: string; task: boolean } | { kind: 'number'; next: number; delimiter: string; task: boolean };
}

/**
 * Every list in `lines`, in order, from the end of the note's front matter (core/frontMatter.ts): a key's value is
 * never a list to put words in. A block that rule counts as front matter holds keys alone, never a list line, so this
 * is a guard for a looser rule later rather than one a note can reach today.
 */
export function runsOf(lines: readonly string[]): Run[] {
  const runs: Run[] = [];
  let i = frontMatterEnd(lines);
  let fence: string | null = null;
  while (i < lines.length) {
    const line = lines[i] ?? '';
    const marker = /^\s*(`{3,}|~{3,})/.exec(line)?.[1] ?? null;
    if (marker) {
      if (!fence) fence = marker.charAt(0);
      else if (marker.charAt(0) === fence) fence = null;
      i += 1;
      continue;
    }
    if (fence) {
      i += 1;
      continue;
    }
    const head = listLead(line);
    if (!head) {
      i += 1;
      continue;
    }
    const indent = head.indent;
    const first = i;
    let last = i;
    let style: Run['style'] = styleOf(head);
    i += 1;
    while (i < lines.length) {
      const line = lines[i] ?? '';
      const item = listLead(line);
      if (item && item.indent.length >= indent.length) {
        if (item.indent.length === indent.length) style = styleOf(item);
        last = i;
        i += 1;
      } else if (line.trim() && /^\s+/.test(line) && (/^\s*/.exec(line)?.[0].length ?? 0) > indent.length) {
        // An indented line under an item continues it.
        last = i;
        i += 1;
      } else {
        break;
      }
    }
    runs.push({ first, last, indent, style });
  }
  return runs;
}

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

/** A note's list, with the words that say what goes in it: its heading and its items. */
export interface ListOf {
  run: Run;
  heading: string | null;
  items: string;
}

/** The lists of `lines` (`runsOf`, or some of them), each with its heading and its items' words. */
export function listsOf(lines: readonly string[], runs: readonly Run[]): ListOf[] {
  const above = headingsAbove(lines);
  return runs.map((run) => ({ run, heading: headingOf(lines, run, above), items: lines.slice(run.first, run.last + 1).join(' ') }));
}

/** How well `text` fits a list: the stems it shares with the list's heading count twice, with its items once. */
export function fitOf(text: string, list: { heading: string | null; items: string }): number {
  const wanted = stems(text);
  const titled = stems(list.heading ?? '');
  const listed = stems(list.items);
  let score = 0;
  for (const stem of wanted) score += (titled.has(stem) ? 2 : 0) + (listed.has(stem) ? 1 : 0);
  return score;
}

/** The list `text` fits best, the first of any tied, and how well: -1 when it fits none of them. */
export function bestList(lists: readonly ListOf[], text: string): { index: number; score: number } {
  let index = -1;
  let score = 0;
  lists.forEach((list, i) => {
    const fit = fitOf(text, list);
    if (fit > score) {
      score = fit;
      index = i;
    }
  });
  return { index, score };
}

/** Where words that fit no list go: the first to-do list with something still to do, or the last list. */
export function restingList(lines: readonly string[], lists: readonly ListOf[]): number {
  const open = lists.findIndex((list) => list.run.style.task && lines.slice(list.run.first, list.run.last + 1).some((line) => listLead(line)?.done === false));
  return open >= 0 ? open : lists.length - 1;
}

/**
 * The list that `text` belongs in, when a note has more than one: the one whose heading (or "Label:" line) and items
 * share the most with it, the heading counting double (`bestList`); with nothing to go by, `restingList`. The same
 * choice the live reader's words make (place.ts), so a command read at Done puts a thing where one said live would.
 */
function runFor(lines: readonly string[], runs: readonly Run[], text: string | undefined): Run | null {
  if (!runs.length) return null;
  const lists = listsOf(lines, runs);
  const best = text && runs.length > 1 ? bestList(lists, text).index : -1;
  return runs[best >= 0 ? best : restingList(lines, lists)]!;
}

export function styleOf(lead: ListLead): Run['style'] {
  const task = lead.done !== null;
  // A number's marker is its digits and then its `.` or `)`; a bullet's is the one character.
  if (/\d/.test(lead.marker)) return { kind: 'number', next: Number.parseInt(lead.marker, 10) + 1, delimiter: lead.marker.slice(-1), task };
  return { kind: 'bullet', mark: lead.marker, task };
}

/**
 * One item's text as a list line: first letter up, no closing full stop. A stop the model's words carried in escaped
 * (instructionMutation.ts `literalMarkdown` writes `\.`) goes with its backslash, which alone would end the line.
 */
export function itemText(text: string): string {
  const trimmed = text.trim().replace(/(?:\\?[\s.,;:])+$/, '');
  return capitalise(trimmed);
}

/**
 * `body` with `items` on the end of its last list, or of the list `near`
 * belongs in when it has several. `asTasks` shapes a list that has to be
 * started (a note with no list yet). Answers the new body and
 * the lines added, for showing them land.
 */
export function appendToList(
  body: string,
  items: readonly string[],
  { asTasks = false, near }: { asTasks?: boolean; near?: string } = {},
): { body: string; added: string[] } {
  const texts = items.map(itemText).filter(Boolean);
  if (!texts.length) return { body, added: [] };
  const lines = body.split('\n');
  const run = runFor(lines, runsOf(lines), near);

  if (!run) {
    const added = texts.map((text) => `${asTasks ? '- [ ] ' : '- '}${text}`);
    return { body: appendBlock(body, added.join('\n')), added };
  }

  let number = run.style.kind === 'number' ? run.style.next : 0;
  const box = run.style.task ? '[ ] ' : '';
  const added = texts.map((text) =>
    run.style.kind === 'number' ? `${run.indent}${number++}${run.style.delimiter} ${box}${text}` : `${run.indent}${run.style.mark} ${box}${text}`,
  );
  const next = [...lines.slice(0, run.last + 1), ...added, ...lines.slice(run.last + 1)];
  return { body: next.join('\n'), added };
}

/**
 * The lines of `body` just above the last `added.length` lines ending at the last of `added`, blank ones left out: the
 * list as it was before `appendToList` put the items on its end, for showing them land under it.
 */
export function linesAbove(body: string, added: readonly string[], keep = 2): string[] {
  const lines = body.split('\n');
  const end = lines.lastIndexOf(added[added.length - 1] ?? '');
  const start = end - added.length + 1;
  return lines.slice(Math.max(0, start - keep), Math.max(0, start)).filter((line) => line.trim());
}

/** What a spoken note starts with that is not the note: "that", "to", "saying". */
const LEAD_IN = /^\s*(?:(?:that\s+says|which\s+says|that\s+reads|to\s+say|saying)\s+)?(?:(?:that|to)\s+(?=\p{L}))?/iu;

/** A thing to do or a short point, rather than a paragraph: short, and one or two sentences. */
function itemShaped(text: string): boolean {
  const words = text.split(/\s+/).filter(Boolean).length;
  const sentences = text.split(/[.!?]+\s+/).filter((part) => part.trim()).length;
  return words <= 30 && sentences <= 2;
}

/**
 * Title-owned defaults when a list has no items yet, from the note's title as the list reads it (after its front
 * matter): a to-do title ("Todo", "House TODOs", "Chores") takes to-dos, a list title ("Groceries", "Packing list")
 * bullets (noteFind.ts `titleKind`). Only a title of a few words: a note that opens with a sentence about shopping is
 * not a shopping list.
 */
export function semanticListKind(body: string): 'task' | 'bullet' | null {
  const title = noteTitle(body);
  if (!title || title.split(/\s+/).length > 4) return null;
  return titleKind(title);
}

/**
 * "Leave a note on the page for AttackFM that says the login is broken on
 * Android": `text` put where it belongs in `body`. A note with a list takes it
 * as a new item of that list (the list it fits, when there are several), since
 * a note of lists is a note of items; a long thought, or a note with no list,
 * takes it as its own paragraph at the end. Answers the new body, the lines
 * added and which it was.
 */
export function leaveNote(body: string, text: string, { asParagraph = false } = {}): { body: string; added: string[]; into: 'list' | 'paragraph' } {
  const words = text.replace(LEAD_IN, '').replace(/^["“]+|["”]+$/g, '').trim();
  if (!words) return { body, added: [], into: 'paragraph' };
  const lines = body.split('\n');
  // A short thing, on a note of lists, is an item; asked for as a paragraph (`placeWords`' "paragraph"), it is one, list or no list.
  if (!asParagraph && runsOf(lines).length && itemShaped(words)) {
    return { ...appendToList(body, [words], { near: words }), into: 'list' };
  }
  const sentence = capitalise(words);
  const line = /[.!?…]$/.test(sentence) ? sentence : `${sentence}.`;
  return { body: appendBlock(body, line), added: [line], into: 'paragraph' };
}

export interface Placing {
  /** "leave": where it fits; "item": a list item; "paragraph": its own paragraph, whatever the note holds. */
  how: 'leave' | 'item' | 'paragraph';
  task: boolean;
  many: boolean;
  near?: string;
  /** Items already told apart by the command: each is one item, commas and all. */
  items?: readonly string[];
}

/**
 * Spoken words put into a note the way a command asked: "leave" where they fit
 * (`leaveNote`), "item" as list items, split on commas or "and" when there are
 * several. What the recorder shows before asking, and what it does after a yes,
 * are both this, so the preview is the result.
 */
export function placeWords(body: string, spoken: string, { how, task, many, near, items: told }: Placing): { body: string; added: string[]; into: 'list' | 'paragraph' } {
  const semantic = semanticListKind(body);
  if (how === 'item' && told?.length) return { ...appendToList(body, told, { asTasks: task || semantic === 'task', near }), into: 'list' };
  if (how === 'paragraph') return leaveNote(body, spoken, { asParagraph: true });
  if (how === 'leave' && !semantic) return leaveNote(body, spoken);
  // Several said one after another arrive joined with commas: each is an item, two as much as five.
  const explicit = many && /,/.test(spoken) ? spoken.split(/\s*,\s*/).filter(Boolean) : null;
  const listed = explicit ?? (many || /,/.test(spoken) ? enumeration(`Items: ${spoken}`)?.items : null);
  const items = listed?.length ? listed : [spoken];
  return { ...appendToList(body, items, { asTasks: task || semantic === 'task', near }), into: 'list' };
}

export type InstructionArea = 'bugs' | 'tasks' | 'list' | 'notes' | null;

/**
 * Places an inferred append inside an explicitly named Markdown section. Only
 * the section slice is rewritten; front matter, other headings, tables, HTML,
 * and fenced code stay byte-for-byte unchanged.
 */
export function placeInstruction(
  body: string,
  content: string,
  area: InstructionArea,
): { body: string; added: string[]; into: 'list' | 'paragraph' } {
  if (!area) {
    const semantic = semanticListKind(body);
    if (semantic) return { ...appendToList(body, [content], { asTasks: semantic === 'task', near: content }), into: 'list' };
    return leaveNote(body, content);
  }
  if (area === 'notes') return leaveNote(body, content);
  const lines = body.split('\n');
  const wanted = area === 'list' ? /\b(?:list|items?)\b/i : area === 'bugs' ? /\b(?:bugs?|issues?|defects?)\b/i : /\b(?:tasks?|to-?dos?|actions?)\b/i;
  let fence: string | null = null;
  let heading = -1;
  let level = 7;
  let end = lines.length;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i] ?? '';
    const marker = /^\s*(`{3,}|~{3,})/.exec(line)?.[1] ?? null;
    if (marker) {
      if (!fence) fence = marker.charAt(0);
      else if (marker.charAt(0) === fence) fence = null;
      continue;
    }
    if (fence) continue;
    const match = /^(#{1,6})\s+(.+?)\s*$/.exec(line);
    if (!match) continue;
    const currentLevel = match[1]?.length ?? 7;
    if (heading < 0 && wanted.test(match[2] ?? '')) {
      heading = i;
      level = currentLevel;
    } else if (heading >= 0 && currentLevel <= level) {
      end = i;
      break;
    }
  }
  if (heading < 0) return { ...appendToList(body, [content], { asTasks: area === 'tasks', near: area }), into: 'list' };
  const section = lines.slice(heading + 1, end).join('\n');
  const placed = appendToList(section, [content], { asTasks: area === 'tasks', near: area });
  const replacement = placed.body.split('\n');
  const next = [...lines.slice(0, heading + 1), ...replacement, ...lines.slice(end)];
  return { body: next.join('\n'), added: placed.added, into: 'list' };
}
