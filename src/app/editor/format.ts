import { EditorSelection, Transaction, type ChangeSpec, type EditorState } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';

/**
 * What the formatting bar writes.
 *
 * The delimiters are the kit's, exactly: `**`, `_`, backtick, `~~`, and the
 * four block prefixes from `@glacier/logic`'s `rich-text.ts`. That is not
 * politeness, it is correctness - the bar writes characters and the
 * highlighter reads them, and if the two ever disagree the app types a mark
 * that does not render. Underscore for italic (not `*`) also keeps `*` free to
 * mean bold's half, which is what a person typing expects.
 *
 * Every edit goes through `state.changeByRange`, so a multi-cursor selection
 * behaves and the caret lands somewhere sensible afterwards: with a selection,
 * around the wrapped text; with none, BETWEEN the delimiters, so pressing Bold
 * and typing produces bold text instead of leaving the caret stranded past the
 * markers.
 *
 * Transactions are annotated `input.format` so `feel.ts` can tell a deliberate
 * bar press (which already got its own tap tick from the button) from a mark
 * the person typed by hand (which is the thing worth announcing).
 */

export type Mark = 'bold' | 'italic' | 'code' | 'strike';
export type Block = 'heading' | 'quote' | 'bullet' | 'number';

const MARK_DELIMITERS: Record<Mark, string> = {
  bold: '**',
  italic: '_',
  code: '`',
  strike: '~~',
};

const BLOCK_PREFIXES: Record<Block, string> = {
  heading: '# ',
  quote: '> ',
  bullet: '- ',
  number: '1. ',
};

/** A prefix matcher per block form, loose enough to spot what is already there. */
const BLOCK_PATTERNS: Record<Block, RegExp> = {
  heading: /^#{1,6}\s+/,
  quote: /^>\s+/,
  bullet: /^[-*+]\s+/,
  number: /^\d+[.)]\s+/,
};

const format = Transaction.userEvent.of('input.format');

/**
 * Wrap or unwrap the selection.
 *
 * Toggling recognises two shapes, because a selection lands either way: the
 * delimiters sitting just OUTSIDE it (the word was selected and is being
 * un-bolded) or INSIDE it (the whole `**word**` was selected). Both unwrap.
 */
export function toggleMark(view: EditorView, mark: Mark): void {
  const delimiter = MARK_DELIMITERS[mark];
  const width = delimiter.length;

  view.dispatch(
    view.state.changeByRange((range) => {
      const { from, to } = range;
      const doc = view.state.doc;
      const outsideBefore = doc.sliceString(Math.max(0, from - width), from);
      const outsideAfter = doc.sliceString(to, Math.min(doc.length, to + width));

      if (outsideBefore === delimiter && outsideAfter === delimiter) {
        return {
          changes: [
            { from: from - width, to: from },
            { from: to, to: to + width },
          ],
          range: EditorSelection.range(from - width, to - width),
        };
      }

      const selected = doc.sliceString(from, to);
      if (selected.length >= width * 2 && selected.startsWith(delimiter) && selected.endsWith(delimiter)) {
        return {
          changes: [
            { from, to: from + width },
            { from: to - width, to },
          ],
          range: EditorSelection.range(from, to - width * 2),
        };
      }

      return {
        changes: [
          { from, insert: delimiter },
          { from: to, insert: delimiter },
        ],
        range: range.empty
          ? EditorSelection.cursor(from + width)
          : EditorSelection.range(from + width, to + width),
      };
    }),
    { annotations: format },
  );
}

/** Which lines a range touches, as line numbers. */
function linesOf(state: EditorState, from: number, to: number): number[] {
  const first = state.doc.lineAt(from).number;
  const last = state.doc.lineAt(to).number;
  const out: number[] = [];
  for (let n = first; n <= last; n += 1) out.push(n);
  return out;
}

/**
 * Apply or remove a block form on every line the selection touches.
 *
 * Applied when ANY touched line lacks the prefix, removed only when every one
 * of them already has it - so dragging across a half-formatted list completes
 * it rather than clearing the half that was done.
 */
export function toggleBlock(view: EditorView, block: Block): void {
  const { state } = view;
  const pattern = BLOCK_PATTERNS[block];
  const prefix = BLOCK_PREFIXES[block];
  const main = state.selection.main;
  const numbers = linesOf(state, main.from, main.to);
  const lines = numbers.map((n) => state.doc.line(n));
  const removing = lines.every((line) => pattern.test(line.text));

  const changes: ChangeSpec[] = [];
  for (const line of lines) {
    const match = pattern.exec(line.text);
    if (removing && match) {
      changes.push({ from: line.from, to: line.from + match[0].length });
    } else if (!removing && !match) {
      // A numbered list counts up rather than repeating "1."; anything else
      // uses the same prefix on every line.
      const insert =
        block === 'number' ? `${numbers.indexOf(line.number) + 1}. ` : prefix;
      changes.push({ from: line.from, insert });
    }
  }
  if (!changes.length) return;
  view.dispatch(state.update({ changes, annotations: format }));
}

/** Which inline marks surround the caret right now, for the bar's pressed state. */
export function activeMarks(state: EditorState): Mark[] {
  const { from, to } = state.selection.main;
  const doc = state.doc;
  const out: Mark[] = [];
  for (const mark of Object.keys(MARK_DELIMITERS) as Mark[]) {
    const delimiter = MARK_DELIMITERS[mark];
    const width = delimiter.length;
    const before = doc.sliceString(Math.max(0, from - width), from);
    const after = doc.sliceString(to, Math.min(doc.length, to + width));
    if (before === delimiter && after === delimiter) out.push(mark);
  }
  return out;
}

/** Which block form the caret's line is in, if any. */
export function activeBlock(state: EditorState): Block | null {
  const text = state.doc.lineAt(state.selection.main.head).text;
  for (const block of Object.keys(BLOCK_PATTERNS) as Block[]) {
    if (BLOCK_PATTERNS[block].test(text)) return block;
  }
  return null;
}
