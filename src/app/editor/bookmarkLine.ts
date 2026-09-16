import { StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, type DecorationSet } from '@codemirror/view';

/**
 * Where the bookmark is, drawn in the note (Matt: "add a way to track where the bookmark is placed").
 *
 * The bookmark itself lives outside the document (editor/notePlace.ts): it is a place on the page, not anything
 * written in the words. So nothing marks it while reading, and the only sign the note has one is the filled button in
 * the header. This puts a ribbon down the leading edge of the bookmarked line, so scrolling past it shows where it
 * was put, and the note says for itself what the button would take you back to.
 *
 * The mark is set from the screen with `showBookmark`, and rides along with edits above it like any other range.
 */

/** Put the ribbon on the line holding this position, or take it off with null. */
export const showBookmark = StateEffect.define<number | null>();

const ribbon = Decoration.line({ class: 'cm-bookmarked', attributes: { 'data-bookmark': 'The bookmark in this note' } });

const bookmarkField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(marks, tr) {
    let at: number | null | undefined;
    for (const effect of tr.effects) if (effect.is(showBookmark)) at = effect.value;
    if (at === undefined) return tr.docChanged ? marks.map(tr.changes) : marks;
    if (at === null) return Decoration.none;
    return Decoration.set([ribbon.range(tr.state.doc.line(markedLine(tr.state, at)).from)]);
  },
  provide: (field) => EditorView.decorations.from(field),
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
});

/** How much of the bookmarked line is said back, so the words fit a toast. */
const SAY = 32;
/** Lines looked at from the bookmark before giving up on finding words: a place can land on a blank line. */
const LOOK = 5;

/** The words on a line, without the marks that make them a heading, a bullet or a to-do. */
function wordsOn(state: EditorState, number: number): string {
  return state.doc
    .line(number)
    .text.replace(/^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|>\s+|\d+[.)]\s+)/, '')
    .replace(/[*_`~]/g, '')
    .replace(/\s+\^[a-z0-9][a-z0-9_-]*$/, '')
    .trim();
}

/**
 * Which line the bookmark is shown on: the one the place is on, or the next with words on it. A place is where the
 * page was scrolled to, which is often the blank line between two paragraphs, and a ribbon down a blank line marks
 * nothing a person can see.
 */
function markedLine(state: EditorState, pos: number): number {
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
