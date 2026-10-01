import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { sumOnLine } from '../core/sums.ts';
import { forEachVisibleLine } from './lines.ts';

/**
 * Sums (Matt picked them from the list of new formats): a line that starts with `=` works itself out.
 *
 *   = 450 + 120 * 2          → 690
 *   - = $1,200 / 3           → $400
 *
 * The answer is drawn after the line in quiet ink and is never written into the note, so the note reads the same
 * anywhere and a changed number is answered at once. Only arithmetic: numbers, `+ - * /`, `^` for powers, `%` after
 * a number for a percent, and brackets. A currency sign or thousands commas come back on the answer. Anything else - a word, a
 * sum that can't be done - draws nothing.
 *
 * The arithmetic is core/sums.ts's since 2026-09-30, where a query's totals read it too (docs/DESIGN.md §158); it is
 * said again from here for the callers that have always found it here.
 */

export { answer, sumOnLine } from '../core/sums.ts';

class AnswerWidget extends WidgetType {
  constructor(readonly text: string) {
    super();
  }
  eq(other: AnswerWidget): boolean {
    return other.text === this.text;
  }
  toDOM(): HTMLElement {
    const span = document.createElement('span');
    span.className = 'cm-sumAnswer';
    span.textContent = this.text;
    span.setAttribute('aria-label', `equals ${this.text}`);
    return span;
  }
}

function decorate(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const tree = syntaxTree(view.state);
  forEachVisibleLine(view, (line) => {
    const sum = sumOnLine(line.text);
    const inCode = sum ? /Code|FrontMatter|Comment|Math/.test(tree.resolveInner(line.from, 1).name) : false;
    if (sum && !inCode) builder.add(line.to, line.to, Decoration.widget({ widget: new AnswerWidget(sum.answer), side: 1 }));
  });
  return builder.finish();
}

const theme = EditorView.baseTheme({
  '.cm-sumAnswer': {
    marginInlineStart: '0.6em',
    color: 'var(--app-ink-3, currentColor)',
    fontVariantNumeric: 'tabular-nums',
    whiteSpace: 'nowrap',
    userSelect: 'none',
  },
  '.cm-sumAnswer::before': {
    content: '"→ "',
  },
});

export function sums(): Extension {
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
      { decorations: (value) => value.decorations },
    ),
    theme,
  ];
}
