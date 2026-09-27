import { syntaxTree } from '@codemirror/language';
import { Facet, Prec, RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import type { SyntaxNode } from '@lezer/common';
import type { InlineFormat } from '../plugins/types.ts';

/**
 * The look of a plugin formatting whose look is a style (plugins/types.ts
 * `FormatLook` 'style'): the words between the delimiters carry the plugin's
 * CSS, as one inline mark, and the delimiters stay dimmed marks. Nothing is
 * hidden or moved (docs/DESIGN.md §3.2). Smoke looks are wispFormat.ts.
 *
 * A view plugin over the visible lines, redrawn when the document, the
 * viewport or the parse changes, and when the caret moves if any look lifts
 * at the caret (a redaction's bar, so the words under it can be edited); a
 * plugin's CSS is trusted the way its settings pane is, and it reaches only
 * its own words.
 *
 * A look inside a look is drawn inside it: a bar in a highlight is a bar on
 * the wash. The one exception is a look that hides its words (`clearAtCaret`,
 * the bar): nothing inside it is drawn, or a highlight in a bar would wash
 * the ink and show the words through it. While the bar is lifted, what is
 * under it is drawn as it is. `coveringLooks` names those looks for the rest
 * of the editor, so links.ts leaves an address under a bar whole rather than
 * drawing its short form beside the bar.
 *
 * The look's span sits inside the highlighter's, so it takes the size of the
 * words it is on: a redaction in a heading is a bar as tall as the heading,
 * where an outer span was a bar the body's height with the heading's letters
 * showing over it (measured, docs/DESIGN.md §131). CodeMirror nests the
 * decorations of higher precedence inside, and the tree highlighter's are
 * `Prec.high`, so these are `Prec.highest`.
 */

interface Styled {
  from: number;
  to: number;
  css: string;
}

export interface StyleLook {
  length: number;
  css: string;
  clearAtCaret?: boolean;
  /** A name in brackets after the mark, as extra CSS for those words (plugins/types.ts `InlineFormat.tint`). */
  tint?: (name: string) => string | null;
}

/** `(green)` straight after a mark: the name a tint is asked about. */
const TINT = /^\(([^)\n]+)\)/;

/** The names of the nodes whose look hides its words (a redaction): what sits under one is not drawn, by anything. */
export const coveringLooks = Facet.define<string>();

/** Whether `node` sits inside a node whose look hides its words. */
export function underCover(node: SyntaxNode, covering: readonly string[]): boolean {
  if (!covering.length) return false;
  for (let above = node.parent; above; above = above.parent) if (covering.includes(above.name)) return true;
  return false;
}

/**
 * The styled stretches in `range`: the words of every node in `looks`, delimiters aside, and not a lifting look's node
 * the selection touches while `atCaret`. A look's words inside another look's are listed after it, in document order,
 * as a range set wants them; none inside a look that hides its words, unless it is lifted.
 */
export function styledRanges(state: EditorState, looks: ReadonlyMap<string, StyleLook>, range: { from: number; to: number }, atCaret = false): Styled[] {
  const found: Styled[] = [];
  syntaxTree(state).iterate({
    from: range.from,
    to: range.to,
    enter(node) {
      const look = looks.get(node.name);
      if (!look) return undefined;
      // Lifted: the words are drawn as they are, and so is any look inside them.
      if (look.clearAtCaret && atCaret && state.selection.ranges.some((r) => r.to >= node.from && r.from <= node.to)) return undefined;
      const from = node.from + look.length;
      const to = node.to - look.length;
      if (to <= from) return false;
      // A name in brackets straight after the mark, where this mark takes one: `==the key==(green)`. A name it does
      // not know is left to editor/markNotes.ts, which reads the same brackets as a note.
      const after = look.tint ? TINT.exec(state.sliceDoc(node.to, Math.min(node.to + 40, state.doc.length))) : null;
      const tint = after ? look.tint?.(after[1] ?? '') : null;
      found.push({ from, to, css: tint ? `${look.css}${tint}` : look.css });
      // A look inside these words is drawn inside this one; under a bar, nothing is.
      return look.clearAtCaret ? false : undefined;
    },
  });
  return found;
}

export function formatLooks(formats: readonly InlineFormat[]): Extension {
  const looks = new Map<string, StyleLook>();
  for (const format of formats) {
    if (format.look.kind === 'style')
      looks.set(format.name, { length: format.delimiter.length, css: format.look.css, clearAtCaret: format.look.clearAtCaret, tint: format.tint });
  }
  if (!looks.size) return [];
  const lifts = [...looks.values()].some((look) => look.clearAtCaret);
  const marks = new Map<string, Decoration>();
  const markFor = (css: string) => {
    let mark = marks.get(css);
    if (!mark) {
      mark = Decoration.mark({ class: 'cm-formatLook', attributes: { style: css } });
      marks.set(css, mark);
    }
    return mark;
  };
  const build = (view: EditorView): DecorationSet => {
    const builder = new RangeSetBuilder<Decoration>();
    const first = view.visibleRanges[0];
    const last = view.visibleRanges[view.visibleRanges.length - 1];
    if (!first || !last) return Decoration.none;
    const atCaret = view.state.facet(EditorView.editable) && view.hasFocus;
    for (const styled of styledRanges(view.state, looks, { from: first.from, to: last.to }, atCaret)) builder.add(styled.from, styled.to, markFor(styled.css));
    return builder.finish();
  };
  return [
    [...looks].filter(([, look]) => look.clearAtCaret).map(([name]) => coveringLooks.of(name)),
    Prec.highest(
      ViewPlugin.fromClass(
        class {
          decorations: DecorationSet;

          constructor(readonly view: EditorView) {
            this.decorations = build(view);
          }

          update(update: ViewUpdate) {
            const moved = lifts && (update.selectionSet || update.focusChanged);
            if (moved || update.docChanged || update.viewportChanged || syntaxTree(update.state) !== syntaxTree(update.startState)) this.decorations = build(update.view);
          }
        },
        { decorations: (plugin) => plugin.decorations },
      ),
    ),
  ];
}
