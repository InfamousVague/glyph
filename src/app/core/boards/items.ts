import { ANCHOR_NAME, COUNTER, anchorSpan, listLead, taskBox, withoutAnchor, withoutBookmark } from '../itemSyntax.ts';

/**
 * The items a board points at: a list item read as a card's item - its anchor, its words, its box - the anchor made
 * for one that has none, and the anchor pointed at from the words, `[[#^ask-sam]]`.
 *
 * How the line is spelled is core/itemSyntax.ts; what its parts mean to a board is here. Any list item that ends
 * with an anchor is an item - a bullet, a number or a to-do, all the same - and a card IS its item, so every card's
 * words and box are read through these (docs/BOARDS.md).
 */

export interface Item {
  /** The anchor that names it. */
  id: string;
  /** The words, without the list marker, the tick box or the anchor. */
  text: string;
  /** Ticked, unticked, or null for an item with no box at all: a bullet or a numbered step. */
  done: boolean | null;
  /** Which line of the note it is on, counting from 1. */
  line: number;
}

/** A list item pulled apart: whether it has a box, its words, and the anchor naming it. */
interface Parsed {
  done: boolean | null;
  text: string;
  id: string | null;
}

/**
 * A list item read the way core/itemSyntax.ts spells it. The words are what is left between the lead and the anchor:
 * a choice's box is not part of what the item says, and not a tick either; the bookmark is a place in the note, not
 * something the item says, so no card, title or anchor has it; and a mark or counter written after the anchor stays
 * with the words it belongs to.
 */
function parse(line: string): Parsed | null {
  const lead = listLead(line);
  if (!lead) return null;
  const rest = line.slice(lead.wordsAt);
  const span = anchorSpan(rest);
  return {
    done: lead.done,
    text: withoutBookmark(withoutAnchor(rest, span)).trim(),
    id: span?.id ?? null,
  };
}

/** `[[#^ask-sam]]`: an item in this note, pointed at from anywhere in it. */
const REF = new RegExp(String.raw`\[\[#\^(${ANCHOR_NAME})\]\]`, 'g');

/** Every anchored item in the note, the first of a repeated anchor winning. */
export function itemsIn(doc: string): Item[] {
  const items: Item[] = [];
  const seen = new Set<string>();
  doc.split('\n').forEach((line, index) => {
    const item = itemOnLine(line);
    if (!item || seen.has(item.id)) return;
    seen.add(item.id);
    items.push({ ...item, line: index + 1 });
  });
  return items;
}

/** The item a line is, if it is a list item with an anchor. */
export function itemOnLine(line: string): Item | null {
  const found = parse(line);
  return found?.id ? { id: found.id, text: found.text, done: found.done, line: 0 } : null;
}

/** Whether a line is a list item at all: what can be given an anchor and put on a board. */
export function isItemLine(line: string): boolean {
  const found = parse(line);
  return Boolean(found && (found.text || found.id));
}

/** The words of a list item, box and anchor off, or null where the line is not one. */
export function itemWords(line: string): string | null {
  return parse(line)?.text ?? null;
}

/**
 * That line with its box ticked or cleared: the one character between the brackets, and nothing else about the line
 * touched. An item with no box is left alone, since there is nothing to tick and writing a box is the person's to do.
 */
export function setItemDone(line: string, done: boolean): string {
  const box = taskBox(line);
  if (!box) return line;
  return `${line.slice(0, box.at + 1)}${done ? 'x' : ' '}${line.slice(box.at + 2)}`;
}

/** That line given an anchor, or left as it is when it has one already. */
export function withAnchor(line: string, id: string): string {
  return itemOnLine(line) ? line : `${line.replace(/\s+$/, '')} ^${id}`;
}

/** Every counter in an item's words (editor/counters.ts): a count kept on the item, never part of its name. */
const COUNTERS = new RegExp(COUNTER, 'g');

/**
 * Words that say nothing about which item this is: an anchor made of "add-ability-to" names two different items
 * the same way, and is the name someone then has to point at.
 */
const FILLER = new Set(
  'a an the to of in on at by for from with into onto and or but nor so is are was were be been being it its this that these those as up out'.split(
    ' ',
  ),
);

/**
 * An anchor made from an item's words: its first three words that carry meaning, lower case, and not one the note
 * already uses. "Add ability to auto-tag notes" is `add-ability-auto`, not `add-ability-to`; words that are all
 * filler ("To do") keep them rather than come out empty.
 */
export function anchorFor(text: string, taken: readonly string[]): string {
  const words = withoutBookmark(
    text
      // A link is named by its words, not by where it points: [notion](https://…) anchors as "notion", never as a URL.
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
      // A counter is a count kept on the item, and the bookmark a place in the note: neither is part of its name.
      .replace(COUNTERS, ' '),
  )
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .split('-')
    .filter(Boolean);
  const telling = words.filter((word) => !FILLER.has(word));
  const base = (telling.length ? telling : words).slice(0, 3).join('-') || 'item';
  if (!taken.includes(base)) return base;
  for (let n = 2; ; n += 1) {
    const tried = `${base}-${n}`;
    if (!taken.includes(tried)) return tried;
  }
}

/**
 * Where an anchor is pointed at from: `[[#^ask-sam]]`, anywhere in a line, counting positions from `offset`.
 *
 * This is the anchor used as prose rather than as a card, and it is why the anchor is worth having on every kind of
 * item: "the copy is waiting on [[#^ask-sam]]" reads as words anywhere, and in Glyph it is a way back to the line.
 */
export interface ItemRef {
  from: number;
  to: number;
  id: string;
}

export function refsIn(text: string, offset = 0): ItemRef[] {
  const found: ItemRef[] = [];
  REF.lastIndex = 0;
  for (let match = REF.exec(text); match; match = REF.exec(text)) {
    found.push({ from: offset + match.index, to: offset + match.index + match[0].length, id: match[1] ?? '' });
  }
  return found;
}

/** The item an anchor names, wherever it is in the note, or null. */
export function itemAt(doc: string, id: string): Item | null {
  return itemsIn(doc).find((item) => item.id === id) ?? null;
}

/** An anchor written as a pointer to it, for anything that offers to write one. */
export function refFor(id: string): string {
  return `[[#^${id}]]`;
}

/**
 * An item's words as a card says them: links by their own words, not by where they point, a pointer at another item
 * by its anchor, and the marks that would be drawn as bold or code taken off. The note keeps every character; this
 * is only what the card shows.
 */
export function cardText(text: string): string {
  return withoutBookmark(text)
    .replace(REF, '^$1')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/<((?:https?|mailto):[^>]+)>/g, '$1')
    .replace(/[*_`~]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}
