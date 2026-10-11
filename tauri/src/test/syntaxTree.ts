import { ensureSyntaxTree } from '@codemirror/language';
import type { EditorView } from '@codemirror/view';

/**
 * The whole of a test editor's note parsed, and every extension told so, before anything is asserted about what the
 * parse decides - a heading's line, a hidden mark, a counter in code, a drawn table.
 *
 * CodeMirror parses on a time budget: a new state gets about twenty milliseconds, and the rest arrives from a worker
 * a moment later. On an idle machine a test's few lines are parsed well inside it; under a loaded run they were not,
 * and the Formatted view left a quote's `>` showing because the parse had not reached its line. So the parse is run
 * to the end here, with a budget no machine misses, and an empty transaction hands the finished tree to the view's
 * state - which only takes it up on its next transaction - so every plugin that redraws on a new tree redraws.
 */
export function parseWhole(view: EditorView): EditorView {
  ensureSyntaxTree(view.state, view.state.doc.length, 10_000);
  view.dispatch({});
  return view;
}
