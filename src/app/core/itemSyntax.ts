/**
 * A list item's grammar, read here and nowhere else: what opens an item, the boxes it may carry, and what may end its
 * line after its words.
 *
 *   - [ ] Ship the pricing page §§ [notion](https://…) [3/8] ^ship-page
 *
 *   `-`             the marker: `-`, `*` or `+`, or a number with `.` or `)`
 *   `[ ]`           a to-do's box, `[ ]`, `[x]` or `[X]`; or, after a bullet, a choice's `( )` (editor/choices.ts)
 *   `§§`            the bookmark, where the reader left off (editor/bookmarkLine.ts)
 *   `[notion](…)`   the mark: what the item is linked to (core/itemLinks.ts)
 *   `[3/8]`         a counter (editor/counters.ts)
 *   `^ship-page`    the anchor: the item's name, which a board points at (core/boards.ts)
 *
 * Why a module of its own: the grammar used to be written out wherever a line was read, about twenty-five times, and
 * the copies disagreed. Notion was offered `* [x] Done thing` to send, titled "[x] Done thing", because
 * core/itemLinks.ts took a box only after `- `; a numbered to-do never followed its Notion task, because
 * editor/doneSync.ts took only a bullet and one space; a spoken item added to a `* [ ]` list came in without a box,
 * because capture/listAppend.ts saw the list as bullets. Each of them was right about the lines its author thought
 * of. One grammar means a line is a to-do everywhere or nowhere: what ticks, what syncs Done, what a board draws as a
 * card, what the recorder appends to and what is sent as a task's title all read the same line the same way.
 *
 * The atoms are regex sources with no groups of their own, so they compose into a larger pattern without renumbering
 * it; the patterns and helpers built from them are the questions the call sites actually ask. What the parts MEAN -
 * a card, a sent task, a lane - is left to the modules that own those things. Pure, so every shape of line is a test
 * (core/itemSyntax.test.ts).
 */

// ---- the atoms -----------------------------------------------------------------------------------

/** A bullet: `-`, `*` or `+`. */
export const BULLET = '[-*+]';
/** A numbered item's number and its `.` or `)`: `1.`, `12)`. */
export const NUMBER = String.raw`\d+[.)]`;
/** What opens a list item: a bullet or a number. */
export const MARKER = `(?:${BULLET}|${NUMBER})`;
/**
 * A to-do's box: `[ ]`, `[x]` or `[X]`, standing as a word - whitespace or the end of the line after it. That is the
 * box the editor draws (lezer's task list wants a space after the `]`), so `- [x](https://…)` stays a link whose words
 * are "x", and `- [ ]foo` stays words: neither has a box to tick, and nothing here pretends it has.
 */
export const BOX = String.raw`\[[ xX]\](?=\s|$)`;
/** A choice's round box, `( )` or `(x)`, standing as a word. Only a bullet takes one: a number and a box are a to-do. */
export const CHOICE = String.raw`\([ xX]\)(?=\s|$)`;
/** An anchor's name: lower case, the shape a person can type and read (docs/BOARDS.md). */
export const ANCHOR_NAME = '[a-z0-9][a-z0-9_-]*';
/** The anchor as written: a caret, then its name. */
export const ANCHOR = String.raw`\^${ANCHOR_NAME}`;
/** A mark's name: the lowercase id of what the item is linked to, `notion` or `github`. */
export const MARK_NAME = '[a-z][a-z0-9-]*';
/** A mark's address. */
export const MARK_URL = String.raw`https?:\/\/[^\s)]+`;
/** An item's mark: a link whose words are one lowercase name, `[notion](https://…)`. */
export const MARK = String.raw`\[${MARK_NAME}\]\(${MARK_URL}\)`;
/** A counter: a count and a goal, up to four digits each, `[3/8]`. */
export const COUNTER = String.raw`\[\d{1,4}\/\d{1,4}\]`;
/** A counter standing in words (editor/counters.ts): not a link's words `[3/8](…)`, a picture's `![3/8]`, or a footnote's. */
export const COUNTER_IN_WORDS = String.raw`(?<![!\]\w])${COUNTER}(?!\()`;
/** The bookmark's two signs, as they are written into a line. */
export const BOOKMARK_SIGNS = '§§';
/** The bookmark standing as a word: its two signs with whitespace or the end of the line after them. */
export const BOOKMARK = `${BOOKMARK_SIGNS}(?=\\s|$)`;
/**
 * What may follow an item's mark at the end of its line: a board's anchor and counters, in any order (core/itemLinks.ts).
 * Written after the mark, or typed after it later, they leave the mark the item's mark.
 */
export const ITEM_TAIL = `${ANCHOR}|${COUNTER}`;

// ---- what opens an item --------------------------------------------------------------------------

/** The indent, the marker and the spaces after it. Groups: the indent, the marker. */
const OPEN = new RegExp(String.raw`^(\s*)(${MARKER})\s+`);
/** A to-do's box where an item's words would start, and at most one space after it. */
const BOX_FIRST = new RegExp(String.raw`^${BOX}\s?`);
/** A choice's box where a bullet's words would start, and at most one space after it. */
const CHOICE_FIRST = new RegExp(String.raw`^${CHOICE}\s?`);
const IS_BULLET = new RegExp(`^${BULLET}$`);

/** The opening of a list item, pulled apart. */
export interface ListLead {
  /** The whitespace before the marker. */
  indent: string;
  /** The marker as written: `-`, `*`, `+`, `1.`, `2)`. */
  marker: string;
  /** A to-do's box, ticked or not; null for an item with none - a bullet, a numbered step or a choice. */
  done: boolean | null;
  /** A choice's round box, picked or not; null for an item with none. */
  picked: boolean | null;
  /** Where the box or the choice opens in the line, its `[` or `(`; -1 when there is neither. */
  boxAt: number;
  /** Where the item's words start: past the marker, the box or the choice, and the one space after it. */
  wordsAt: number;
}

/** A line's list lead, or null when the line is not a list item. */
export function listLead(line: string): ListLead | null {
  const open = OPEN.exec(line);
  if (!open) return null;
  const marker = open[2] ?? '';
  const at = open[0].length;
  const rest = line.slice(at);
  const box = BOX_FIRST.exec(rest);
  // A choice is only a choice after a bullet: `1. ( ) Pick` is a numbered step whose words start with brackets.
  const choice = box || !IS_BULLET.test(marker) ? null : CHOICE_FIRST.exec(rest);
  const found = box ?? choice;
  return {
    indent: open[1] ?? '',
    marker,
    done: box ? rest[1] !== ' ' : null,
    picked: choice ? rest[1] !== ' ' : null,
    boxAt: found ? at : -1,
    wordsAt: at + (found?.[0].length ?? 0),
  };
}

/** A to-do's box on a line: where its `[` is and whether it is ticked; null for a line that is not a to-do. */
export function taskBox(line: string): { at: number; done: boolean } | null {
  const lead = listLead(line);
  return lead?.done != null ? { at: lead.boxAt, done: lead.done } : null;
}

/**
 * A line with its list lead taken off - indent, marker, and a to-do's box or a choice's - as a line is said back to a
 * person: "Added “Buy milk”", not "Added “- [ ] Buy milk”". A line that is not a list item comes back as it is.
 */
export function withoutLead(line: string): string {
  const lead = listLead(line);
  return lead ? line.slice(lead.wordsAt) : line;
}

// ---- what ends an item's line --------------------------------------------------------------------

/**
 * The anchor that names an item: a caret with whitespace before it (or nothing before it at all, on an item whose
 * words have not been written yet) and the end of the line after it. That is what leaves `E = mc^2^` and `foo ^2^`
 * the superscripts they are: a closing caret means the line does not end there.
 *
 * The things allowed after it are an item's mark and counters, which a person typing at the end of the line puts
 * there. The anchor goes last, but a mark used to be added after it when an item was sent to Notion, and those lines
 * must still be found: the card showed its anchor and nothing else (Matt: "the last two items show up weird on the
 * board as only their label no title").
 */
const TAIL = new RegExp(String.raw`(?<!\S)(${ANCHOR})(?:\s+(?:${MARK}|${COUNTER}))*\s*$`);

/** Where the anchor naming an item sits in `text`: its caret at `from`, its name ending at `to`; or null for none. */
export function anchorSpan(text: string): { id: string; from: number; to: number } | null {
  const found = TAIL.exec(text);
  const anchor = found?.[1];
  if (!found || !anchor) return null;
  return { id: anchor.slice(1), from: found.index, to: found.index + anchor.length };
}

/**
 * `text` without the anchor naming it, and the one space before it: `- [ ] Ship it ^ship` is `- [ ] Ship it`, and a
 * mark or counter written after the anchor stays, in its place. Text with no anchor comes back as it is.
 */
export function withoutAnchor(text: string, span = anchorSpan(text)): string {
  if (!span) return text;
  return `${text.slice(0, Math.max(0, span.from - 1))}${text.slice(span.to)}`.replace(/\s+$/, '');
}

/** The bookmark and the whitespace before it, wherever it stands in a line. */
const BOOKMARK_SPACED = new RegExp(String.raw`\s*${BOOKMARK}`, 'g');

/** A line's text with the bookmark taken out: it is a place in the note, never something the line says. */
export function withoutBookmark(text: string): string {
  return text.replace(BOOKMARK_SPACED, '');
}

/** What may end an item's line after its words: its anchor, a mark, a counter, the bookmark. */
const LINE_TAIL = new RegExp(String.raw`\s+(?:${ANCHOR}|${MARK}|${COUNTER}|${BOOKMARK})$`);

/**
 * Where a list item's words end in its line: before its bookmark, mark, counters and anchor. The caret goes here when
 * a card or a pointer takes the note to the item, so what is typed next goes on the words and not into the anchor that
 * names them. A line that is not an item ends where its text does.
 */
export function wordsEnd(line: string): number {
  let rest = line.replace(/\s+$/, '');
  const lead = listLead(line);
  if (!lead) return rest.length;
  for (let found = LINE_TAIL.exec(rest); found; found = LINE_TAIL.exec(rest)) rest = rest.slice(0, found.index);
  return Math.max(lead.wordsAt, rest.length);
}

/** What may follow an item's mark to the end of its line: nothing, or a board's anchor and counters. */
export const AFTER_MARK = new RegExp(String.raw`^(?:\s+(?:${ITEM_TAIL}))*\s*$`);

// ---- what a tick means on a board ------------------------------------------------------------------

/**
 * Whether a board's column is its Done lane, the one a ticked item belongs in: a name that starts or ends with the
 * word, "Done" or "All done" or "Done this week". The other half of what a box means, so it is read here with the box.
 */
export function isDoneName(name: string): boolean {
  return /^done\b|\bdone$/i.test(name.trim());
}
