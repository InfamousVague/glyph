import type { EditorState, Line, Text } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';

/**
 * The lines an extension looks at: the ones on screen, which is all a view plugin's decorations may cover, and the
 * ones the selection touches, where marks are shown as written so they can be edited; and, for what reads the whole
 * note, the ones outside fenced code. Each is walked here the one way, so the decorators that draw from them agree
 * on which lines they are.
 */

/** Calls `visit` with every line inside the view's visible ranges, in order. */
export function forEachVisibleLine(view: EditorView, visit: (line: Line) => void): void {
  const { doc } = view.state;
  for (const { from, to } of view.visibleRanges) {
    let line = doc.lineAt(from);
    for (;;) {
      visit(line);
      if (line.to >= to || line.number >= doc.lines) break;
      line = doc.line(line.number + 1);
    }
  }
}

/** A line that opens or closes fenced code: three backticks or three tildes. */
const FENCE = /^\s*(```|~~~)/;

/**
 * Calls `visit` with every line of `doc` outside fenced code, in order; the fence lines themselves are skipped too. A
 * fence closes on the marker it opened with, so a `~~~` inside a ``` block is the block's words.
 */
export function forEachLineOutsideFences(doc: Text, visit: (line: Line) => void): void {
  let fence: string | null = null;
  for (let n = 1; n <= doc.lines; n += 1) {
    const line = doc.line(n);
    const marker = FENCE.exec(line.text)?.[1];
    if (marker) {
      fence = fence === null ? marker : fence === marker ? null : fence;
      continue;
    }
    if (!fence) visit(line);
  }
}

/** The numbers of the lines the selection touches, every range and every line between its ends. */
export function selectedLines(state: EditorState): Set<number> {
  const lines = new Set<number>();
  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;
    for (let n = first; n <= last; n += 1) lines.add(n);
  }
  return lines;
}
