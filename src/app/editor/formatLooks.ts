import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
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
}

/** The styled stretches in `range`: the words of every node in `looks`, delimiters aside, and not a lifting look's node the selection touches while `atCaret`. */
export function styledRanges(state: EditorState, looks: ReadonlyMap<string, StyleLook>, range: { from: number; to: number }, atCaret = false): Styled[] {
  const found: Styled[] = [];
  syntaxTree(state).iterate({
    from: range.from,
    to: range.to,
    enter(node) {
      const look = looks.get(node.name);
      if (!look) return undefined;
      if (look.clearAtCaret && atCaret && state.selection.ranges.some((r) => r.to >= node.from && r.from <= node.to)) return false;
      const from = node.from + look.length;
      const to = node.to - look.length;
      if (to > from) found.push({ from, to, css: look.css });
      return false;
    },
  });
  return found;
}

export function formatLooks(formats: readonly InlineFormat[]): Extension {
  const looks = new Map<string, StyleLook>();
  for (const format of formats) {
    if (format.look.kind === 'style') looks.set(format.name, { length: format.delimiter.length, css: format.look.css, clearAtCaret: format.look.clearAtCaret });
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
  return ViewPlugin.fromClass(
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
  );
}
