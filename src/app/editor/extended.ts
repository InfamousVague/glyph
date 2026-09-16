import { RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view';

/**
 * The extended markdown Glyph draws but had no look for.
 *
 * The language already parses more than the app drew (editor/language.ts takes GFM plus subscript, superscript and
 * emoji): `x^2^` and `H~2~O` were plain words with their marks showing, and a GitHub callout - a quote whose first
 * line is `[!NOTE]` - was an ordinary quote. Both are ordinary markdown anywhere else, so a note written in Glyph
 * reads the same in GitHub, Obsidian or a plain text editor, which is the whole point of the format.
 *
 * Nothing is hidden, as everywhere else in the editor: the marks stay, and the words between them take the look.
 */

/** The words of a raised or lowered run, by node name: the highlighter gives both the same tag. */
const SCRIPTS: Record<string, string | undefined> = { Superscript: 'cm-sup', Subscript: 'cm-sub' };

/** A callout's kind, as GitHub writes it: `> [!NOTE]` on the quote's first line. */
export const CALLOUT = /^\s*>\s*\[!(note|tip|important|warning|caution)\]\s*(.*)$/i;

/** The kind of callout a blockquote is, or null for an ordinary quote. */
export function calloutKind(firstLine: string): string | null {
  const found = CALLOUT.exec(firstLine);
  return found ? (found[1] ?? '').toLowerCase() : null;
}

function decorate(state: EditorState, from: number, to: number): DecorationSet {
  const marks: { from: number; to: number; deco: Decoration }[] = [];
  syntaxTree(state).iterate({
    from,
    to,
    enter(node) {
      const script = SCRIPTS[node.name];
      if (script) {
        // The words, the delimiters aside: `^` and `~` are one character each.
        const words = { from: node.from + 1, to: node.to - 1 };
        if (words.to > words.from) marks.push({ ...words, deco: Decoration.mark({ class: script }) });
        return false;
      }
      if (node.name !== 'Blockquote') return undefined;
      const first = state.doc.lineAt(node.from);
      const kind = calloutKind(first.text);
      if (!kind) return undefined;
      // `[!NOTE]` is a link label to the parser, and was drawn as one: underlined, in the link's ink. It is the
      // callout's name, so it is drawn as a name.
      const at = first.text.indexOf('[!');
      const shut = first.text.indexOf(']', at);
      if (at >= 0 && shut > at) marks.push({ from: first.from + at, to: first.from + shut + 1, deco: Decoration.mark({ class: 'cm-calloutName' }) });
      const last = state.doc.lineAt(Math.max(node.from, node.to - 1));
      for (let n = first.number; n <= last.number; n += 1) {
        const line = state.doc.line(n);
        marks.push({
          from: line.from,
          to: line.from,
          deco: Decoration.line({ class: n === first.number ? 'cm-callout cm-calloutTop' : 'cm-callout', attributes: { 'data-callout': kind } }),
        });
      }
      return undefined;
    },
  });
  // A line decoration and a mark can start at the same place; the line one must be added first.
  marks.sort((a, b) => a.from - b.from || (a.to === a.from ? -1 : 1) - (b.to === b.from ? -1 : 1));
  const builder = new RangeSetBuilder<Decoration>();
  for (const mark of marks) builder.add(mark.from, mark.to, mark.deco);
  return builder.finish();
}

const theme = EditorView.baseTheme({
  '.cm-sup': { verticalAlign: 'super', fontSize: '0.75em', lineHeight: '1' },
  '.cm-sub': { verticalAlign: 'sub', fontSize: '0.75em', lineHeight: '1' },
  /*
   * A callout is the quote it already is, with its own band of ink down the side and a tinted ground, so the eye
   * takes it as an aside rather than a quotation. The kinds differ only in weight of tint: Glyph is ink and paper,
   * and a wall of coloured boxes is not what a note should look like.
   */
  '.cm-callout': {
    background: 'color-mix(in oklch, currentColor 4%, transparent)',
    borderInlineStart: '3px solid color-mix(in oklch, currentColor 35%, transparent)',
    paddingInlineStart: '0.6em',
  },
  '.cm-callout[data-callout="warning"], .cm-callout[data-callout="caution"]': {
    background: 'color-mix(in oklch, currentColor 7%, transparent)',
    borderInlineStartColor: 'color-mix(in oklch, currentColor 60%, transparent)',
  },
  // The underline belongs to the link span inside, so the name's own children are cleared too.
  '.cm-calloutName, .cm-calloutName *': {
    textDecoration: 'none',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    fontSize: '0.82em',
    letterSpacing: '0.08em',
  },
  '.cm-calloutTop': { fontWeight: 'var(--glacier-font-weight-semibold, 600)', paddingBlockStart: '0.25em', borderStartStartRadius: '0.4em' },
  '.cm-callout:not(.cm-calloutTop):last-of-type': { paddingBlockEnd: '0.25em' },
});

/** Superscript, subscript and callouts, drawn as what they are. */
export function extendedMarkdown(): Extension {
  return [
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;

        constructor(readonly view: EditorView) {
          this.decorations = this.build(view);
        }

        update(update: ViewUpdate) {
          if (update.docChanged || update.viewportChanged) this.decorations = this.build(update.view);
        }

        private build(view: EditorView): DecorationSet {
          const { from, to } = view.viewport;
          return decorate(view.state, from, to);
        }
      },
      { decorations: (value) => value.decorations },
    ),
    theme,
  ];
}
