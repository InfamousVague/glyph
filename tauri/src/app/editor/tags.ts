import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { forEachVisibleLine } from './lines.ts';
import { inQuietText } from './syntax.ts';
import { blankMatches } from '../core/blanks.ts';
import { tagsIn } from '../core/tags.ts';

/**
 * Tags drawn: a small quiet chip on each, the `#` kept (Matt: "add ability to make tags on list items"). What a tag is
 * is core/tags.ts, which a query reads too (docs/DESIGN.md §156); here is only where one is drawn. Nothing inside
 * code, an address, front matter, HTML, a comment or maths is a tag, which is the parser's to say.
 */

const chip = Decoration.mark({ class: 'cm-tag' });

function decorate(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  // Nothing inside code, an address, front matter, HTML, a comment or maths is a tag.
  forEachVisibleLine(view, (line) => {
    // A `#word` inside a blank's question is not a chip: the question reads as one quiet phrase (docs/DESIGN.md §145).
    const blanks = line.text.includes('{?') ? blankMatches(line.text, line.from) : [];
    for (const tag of tagsIn(line.text, line.from)) if (!inQuietText(view.state, tag.from) && !blanks.some((b) => tag.from > b.from && tag.from < b.to)) builder.add(tag.from, tag.to, chip);
  });
  return builder.finish();
}

const theme = EditorView.baseTheme({
  '.cm-tag': {
    padding: '0 0.3em',
    borderRadius: '0.35em',
    background: 'color-mix(in srgb, currentColor 9%, transparent)',
    color: 'var(--app-ink-2, inherit)',
    fontSize: '0.92em',
    whiteSpace: 'nowrap',
  },
});

export function tags(): Extension {
  return [
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;
        constructor(view: EditorView) {
          this.decorations = decorate(view);
        }
        update(update: ViewUpdate) {
          if (update.docChanged || update.viewportChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) this.decorations = decorate(update.view);
        }
      },
      { decorations: (plugin) => plugin.decorations },
    ),
    theme,
  ];
}
