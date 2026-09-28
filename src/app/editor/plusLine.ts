import type { EditorState, Line } from '@codemirror/state';
import { frontMatterEnd } from '../core/frontMatter.ts';
import { lineWords } from '../core/itemSyntax.ts';
import { inFence } from './lines.ts';

/**
 * Which line the + beside the line is drawn on, if any (editor/insertPlus.ts draws it): the pure half, so every rule
 * is a test (editor/plusLine.test.ts).
 *
 * Matt chose the rule: "EMPTY LINES ONLY, on every platform, Mac hover included". An empty line is one with no words
 * (core/itemSyntax.ts `lineWords`): blank, or only a list's, a to-do's or a quote's lead. The first letter typed makes
 * the line one with words, and the + goes. So it never sits beside a sentence being written, and a note being read
 * with the caret in a paragraph shows nothing.
 *
 * And only where adding to the note makes sense: a view that can be edited and has the focus (or has handed it to the
 * + or its list), one caret and no selection (a selection belongs to press and hold), a note the screen says is being
 * written (not a notebook's index or a canvas, no AI run writing into it), and a line outside the front matter and
 * outside fenced code, where a picture or a place would be words of the block.
 */

export interface PlusContext {
  /** The view has focus, or the + or its list has. */
  focused: boolean;
  /** The view can be typed in. */
  editable: boolean;
  /** The screen allows it: a note of words, shown, with nothing writing into it (editor/NoteScreen.tsx). */
  allowed: boolean;
}

/** How many lines front matter can run to (core/frontMatter.ts reads no further). */
const FRONT_MATTER_LINES = 40;

/** Whether line `number` is inside the note's front matter. */
function inFrontMatter(state: EditorState, number: number): boolean {
  const doc = state.doc;
  const first = Array.from({ length: Math.min(FRONT_MATTER_LINES, doc.lines) }, (_, i) => doc.line(i + 1).text);
  return number <= frontMatterEnd(first);
}

/** The caret's line when the + belongs beside it, or null. */
export function plusLine(state: EditorState, { focused, editable, allowed }: PlusContext): Line | null {
  if (!focused || !editable || !allowed) return null;
  const { ranges, main } = state.selection;
  if (ranges.length !== 1 || !main.empty) return null;
  const line = state.doc.lineAt(main.head);
  if (lineWords(line.text)) return null;
  if (inFrontMatter(state, line.number) || inFence(state.doc, line.number)) return null;
  return line;
}
