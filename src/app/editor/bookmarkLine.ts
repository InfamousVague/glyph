import { StateEffect, StateField, type EditorState, type Extension, type Text, type TransactionSpec } from '@codemirror/state';
import { Decoration, EditorView, WidgetType, type DecorationSet } from '@codemirror/view';
import { wordsEnd } from '../core/boards.ts';

/**
 * The bookmark, written in the note (Matt: "we should show the bookmark in markdown as a physical symbol combo thats
 * rarely used. i should be able to tap bookmark again to update the position as well right now its stuck").
 *
 * It is two section signs at the end of the bookmarked line's words:
 *
 *   The deposit is four hundred. §§
 *   - [ ] Ship the pricing page §§ [notion](…) ^pricing-page
 *
 * `§§` is almost never typed, reads as a mark anywhere the note is opened, and travels with the note - to another
 * device, into a sync, into a copy - where a bookmark kept beside the note did not. A note holds one: putting it on a
 * line takes it off every other. On a list item it goes before the item's mark, counters and anchor, which have to
 * stay last (core/boards.ts `wordsEnd`), and it is never part of what the item says.
 *
 * Drawn as a small ribbon in place of the two signs, and a line down the bookmarked line's leading edge, so scrolling
 * past it shows where it is. The signs come back as text while the caret is right at them, to be edited like anything.
 *
 * A bookmark from before this, kept on the device (editor/notePlace.ts), is still shown, with `showBookmark`, until
 * the button next puts one in the note.
 */

export const BOOKMARK = '§§';
/** The mark and the space before it, wherever it sits on a line. */
const MARK = /[ \t]*§§(?=\s|$)/g;

/** The line (from 1) holding the note's bookmark, or null. */
export function bookmarkLineIn(doc: Text | string): number | null {
  const text = typeof doc === 'string' ? doc : doc.toString();
  const at = text.search(/§§(?=\s|$)/);
  if (at < 0) return null;
  return text.slice(0, at).split('\n').length;
}

/** A line's text with the bookmark taken out. */
export function withoutBookmark(line: string): string {
  return line.replace(MARK, '');
}

/**
 * The changes that put the bookmark on line `number` (from 1), taking it off everywhere else; with null, only taking
 * it off. One transaction, so it is one undo.
 */
export function placeBookmark(state: EditorState, number: number | null): TransactionSpec {
  const changes: { from: number; to: number; insert?: string }[] = [];
  const { doc } = state;
  for (let n = 1; n <= doc.lines; n += 1) {
    const line = doc.line(n);
    for (const found of line.text.matchAll(MARK)) changes.push({ from: line.from + found.index, to: line.from + found.index + found[0].length });
  }
  if (number !== null && number >= 1 && number <= doc.lines) {
    const line = doc.line(number);
    const clean = withoutBookmark(line.text);
    // The words end before a list item's mark, counters and anchor; elsewhere, at the end of the line.
    const end = wordsEnd(clean);
    // Positions in the clean line map onto the real one because the marks taken out all sit at or after the words' end.
    const at = line.from + Math.min(end, line.text.length);
    const before = clean.slice(0, end);
    changes.push({ from: at, to: at, insert: `${before && !/\s$/.test(before) ? ' ' : ''}${BOOKMARK}` });
  }
  return { changes, userEvent: 'input.bookmark' };
}

/** A bookmark kept on the device, shown until the note carries its own: the position, or null. */
export const showBookmark = StateEffect.define<number | null>();

const ribbon = Decoration.line({ class: 'cm-bookmarked', attributes: { 'data-bookmark': 'The bookmark in this note' } });

class RibbonWidget extends WidgetType {
  eq(): boolean {
    return true;
  }
  toDOM(): HTMLElement {
    const mark = document.createElement('span');
    mark.className = 'cm-bookmarkMark';
    mark.setAttribute('aria-label', 'Bookmark');
    mark.title = 'Bookmark';
    return mark;
  }
}

const hidden = Decoration.replace({ widget: new RibbonWidget() });

interface Marks {
  /** The device's own bookmark, for a note without one written in. */
  kept: number | null;
  decorations: DecorationSet;
}

function decorate(state: EditorState, kept: number | null): DecorationSet {
  const written = bookmarkLineIn(state.doc);
  const number = written ?? (kept === null ? null : markedLine(state, kept));
  if (number === null) return Decoration.none;
  const line = state.doc.line(number);
  const ranges = [ribbon.range(line.from)];
  const found = written !== null ? /[ \t]*§§(?=\s|$)/.exec(line.text) : null;
  if (found) {
    const from = line.from + found.index;
    const to = from + found[0].length;
    // The signs as text only while the caret is at them, so they can be edited; a caret elsewhere on the line leaves the ribbon.
    const editing = state.selection.ranges.some((range) => range.from <= to && range.to >= from + found[0].length - BOOKMARK.length);
    if (!editing) ranges.push(hidden.range(from, to));
  }
  return Decoration.set(ranges, true);
}

const bookmarkField = StateField.define<Marks>({
  create: (state) => ({ kept: null, decorations: decorate(state, null) }),
  update(value, tr) {
    let kept = value.kept === null ? null : tr.changes.mapPos(value.kept);
    let touched = false;
    for (const effect of tr.effects) {
      if (effect.is(showBookmark)) {
        kept = effect.value;
        touched = true;
      }
    }
    if (!touched && !tr.docChanged && !tr.selection) return value;
    return { kept, decorations: decorate(tr.state, kept) };
  },
  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
});

const bookmarkTheme = EditorView.baseTheme({
  '.cm-bookmarked': {
    position: 'relative',
    // The words themselves are untouched: a breath of tint behind the line, and the ribbon in the margin the line
    // already leaves before its first letter, which is the only room there is (the note runs to the page's edge).
    borderRadius: '0.25em',
    background: 'color-mix(in oklch, currentColor 5%, transparent)',
  },
  '.cm-bookmarked::before': {
    content: '""',
    position: 'absolute',
    insetInlineStart: '0.4em',
    insetBlock: '0.1em',
    inlineSize: '3px',
    borderRadius: '2px',
    background: 'currentColor',
    opacity: '0.7',
  },
  // A small ribbon where the two signs are: a notched tab, in the line's own ink.
  '.cm-bookmarkMark': {
    display: 'inline-block',
    inlineSize: '0.5em',
    blockSize: '0.75em',
    marginInlineStart: '0.35em',
    verticalAlign: '-0.05em',
    background: 'currentColor',
    opacity: '0.75',
    clipPath: 'polygon(0 0, 100% 0, 100% 100%, 50% 72%, 0 100%)',
  },
});

/** How much of the bookmarked line is said back, so the words fit a toast. */
const SAY = 32;
/** Lines looked at from the bookmark before giving up on finding words: a place can land on a blank line. */
const LOOK = 5;

/** The words on a line, without the marks that make them a heading, a bullet or a to-do, or the bookmark. */
function wordsOn(state: EditorState, number: number): string {
  return withoutBookmark(state.doc.line(number).text)
    .replace(/^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|>\s+|\d+[.)]\s+)/, '')
    .replace(/[*_`~]/g, '')
    .replace(/\s+\^[a-z0-9][a-z0-9_-]*$/, '')
    .trim();
}

/**
 * Which line a place stands for: the one it is on, or the next with words on it. A place is often the blank line
 * between two paragraphs, and a bookmark on a blank line marks nothing a person can see.
 */
export function markedLine(state: EditorState, pos: number): number {
  const first = state.doc.lineAt(Math.max(0, Math.min(pos, state.doc.length))).number;
  for (let number = first; number < Math.min(first + LOOK, state.doc.lines + 1); number += 1) if (wordsOn(state, number)) return number;
  return first;
}

/**
 * The words the bookmark sits on, said the way they read. Null where there is nothing to say, so the message can
 * leave the place out rather than quote an empty line.
 */
export function markedWords(view: EditorView, pos: number): string | null {
  const words = wordsOn(view.state, markedLine(view.state, pos));
  if (!words) return null;
  if (words.length <= SAY) return words;
  // Cut at a space rather than through a word, so the quote reads as words and not as a broken one.
  const cut = words.slice(0, SAY);
  const space = cut.lastIndexOf(' ');
  return `${(space > SAY / 2 ? cut.slice(0, space) : cut).trimEnd()}…`;
}

/** The bookmarked line, shown as one. */
export function bookmarkRibbon(): Extension {
  return [bookmarkField, bookmarkTheme];
}
