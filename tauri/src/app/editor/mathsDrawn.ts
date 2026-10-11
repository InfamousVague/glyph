import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, WidgetType, type DecorationSet } from '@codemirror/view';
import { FRONT_MATTER_LINES, frontMatterEnd } from '../core/frontMatter.ts';
import { mathsIn } from '../core/maths.ts';
import { caretIn, focusMoved, openOnPress, trackFocus } from './drawnBlock.ts';

/**
 * Maths drawn as the formula it is (Matt, of the Academy's lesson: "should the maths be formatted any special way or
 * do something?", then "yes" to drawing it): `$x^2 + y$` in a line as a formula, a raised 2 and all, and a `$$` block
 * on lines of its own as a formula set in the middle of the page. KaTeX draws them.
 *
 * KaTeX came into the app with Mermaid, which draws the maths in a diagram with it, so drawing a note's maths adds its
 * stylesheet and its fonts and nothing else. It is imported the first time a note has a formula, as a diagram's
 * library is (editor/mermaid.ts), so opening the app is no slower; and since the over-the-air update brings every file
 * down to the phone, it draws offline.
 *
 * The caret on a formula's line shows what was typed, to edit, as a heading's hashes and a definition's colon come
 * back there; a view with no caret - the Formatted view, the Academy's preview, a note not focused - draws every one.
 * A formula KaTeX cannot read stays as it was typed, set as code, with what is wrong said on a long press. Where the
 * maths is found is core/maths.ts, Pandoc's rule, so two prices on a line stay prices; a `$` in code is code.
 */

type Katex = typeof import('katex')['default'];

let loading: Promise<Katex> | null = null;

/** KaTeX and its stylesheet, fetched once, the first time a formula is drawn. */
function library(): Promise<Katex> {
  loading ??= Promise.all([import('katex'), import('katex/dist/katex.min.css')]).then(([module]) => module.default);
  return loading;
}

/** What a formula is drawn as: its markup, or what is wrong with it. */
type Drawn = { html: string } | { failed: string };

/** Formulas drawn already, by what they say and how they are set: scrolling past one draws nothing again. */
const drawn = new Map<string, Drawn>();

function keyOf(tex: string, display: boolean): string {
  return `${display ? 'D' : 'I'}${tex}`;
}

function render(katex: Katex, tex: string, display: boolean): Drawn {
  try {
    return { html: katex.renderToString(tex, { displayMode: display, throwOnError: true, output: 'htmlAndMathml', strict: 'ignore' }) };
  } catch (error) {
    return { failed: error instanceof Error ? error.message.replace(/^KaTeX parse error:\s*/, '') : String(error) };
  }
}

/** A formula drawn, from the cache at once or once KaTeX has come. */
function draw(tex: string, display: boolean): Drawn | Promise<Drawn> {
  const key = keyOf(tex, display);
  const known = drawn.get(key);
  if (known) return known;
  return library().then((katex) => {
    const made = render(katex, tex, display);
    if (drawn.size > 400) drawn.clear();
    drawn.set(key, made);
    return made;
  });
}

class MathsWidget extends WidgetType {
  constructor(
    /** The formula, without its dollar signs. */
    readonly tex: string,
    /** What was typed, dollar signs and all: shown until it is drawn, and if it never is. */
    readonly source: string,
    readonly display: boolean,
    /** Where a press puts the caret, to edit it. */
    readonly at: number,
  ) {
    super();
  }

  eq(other: MathsWidget): boolean {
    return other.tex === this.tex && other.display === this.display && other.at === this.at;
  }

  get estimatedHeight(): number {
    return this.display ? 64 : -1;
  }

  toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement(this.display ? 'div' : 'span');
    wrap.className = this.display ? 'cm-mathsBlock' : 'cm-mathsInline';
    const show = (made: Drawn) => {
      if ('html' in made) {
        wrap.innerHTML = made.html;
        wrap.dataset.drawn = '';
        wrap.removeAttribute('title');
        return;
      }
      wrap.textContent = this.source;
      wrap.dataset.failed = '';
      wrap.title = `This formula could not be drawn: ${made.failed}`;
    };
    const made = draw(this.tex, this.display);
    if (made instanceof Promise) {
      wrap.textContent = this.source;
      void made.then((done) => {
        if (!wrap.isConnected) return;
        show(done);
        view.requestMeasure();
      });
    } else show(made);
    openOnPress(view, wrap, this.at);
    return wrap;
  }

  ignoreEvent(event: Event): boolean {
    // A press is ours, to open the formula for editing; a wide display formula scrolled sideways is the formula's.
    return event.type !== 'mousedown';
  }
}

/** Code, where a dollar sign is a dollar sign: a fence, a code span, an indented block. */
const CODE = new Set(['FencedCode', 'CodeBlock', 'InlineCode', 'CodeText']);

function inCode(state: EditorState, at: number): boolean {
  for (let node: ReturnType<ReturnType<typeof syntaxTree>['resolveInner']> | null = syntaxTree(state).resolveInner(at, 1); node; node = node.parent) {
    if (CODE.has(node.name)) return true;
  }
  return false;
}

/** A line that is `$$` and nothing else: the edge of a formula on lines of its own. */
const EDGE = /^\s*\$\$\s*$/;

function build(state: EditorState): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const doc = state.doc;
  // The note's own front matter is its settings, never maths.
  const head = Array.from({ length: Math.min(doc.lines, FRONT_MATTER_LINES) }, (_, i) => doc.line(i + 1).text);
  for (let n = frontMatterEnd(head) + 1; n <= doc.lines; n += 1) {
    const line = doc.line(n);
    if (!line.text.includes('$')) continue;
    // A formula on lines of its own, between two lines of `$$`.
    if (EDGE.test(line.text) && !inCode(state, line.from)) {
      let end = -1;
      for (let m = n + 1; m <= doc.lines; m += 1) {
        if (EDGE.test(doc.line(m).text)) {
          end = m;
          break;
        }
      }
      if (end > n + 1) {
        const last = doc.line(end);
        const tex = doc.sliceString(doc.line(n + 1).from, doc.line(end - 1).to);
        if (tex.trim() && !caretIn(state, line.from, last.to)) {
          builder.add(line.from, last.to, Decoration.replace({ widget: new MathsWidget(tex, doc.sliceString(line.from, last.to), true, line.from + line.text.length), block: true }));
        }
        n = end;
        continue;
      }
    }
    // The caret on the line: what was typed, to edit.
    if (caretIn(state, line.from, line.to)) continue;
    for (const maths of mathsIn(line.text, line.from)) {
      if (inCode(state, maths.from)) continue;
      const source = doc.sliceString(maths.from, maths.to);
      const wide = source.startsWith('$$');
      const tex = source.slice(wide ? 2 : 1, wide ? -2 : -1);
      if (!tex.trim()) continue;
      // `$$…$$` alone on its line is set as a formula of its own; inside a sentence, it stays in the line.
      const alone = wide && line.text.trim() === source;
      builder.add(maths.from, maths.to, Decoration.replace({ widget: new MathsWidget(tex, source, alone, maths.from) }));
    }
  }
  return builder.finish();
}

const mathsField = StateField.define<DecorationSet>({
  create: build,
  update(decorations, tr) {
    if (tr.docChanged || tr.selection || focusMoved(tr) || tr.reconfigured) return build(tr.state);
    return decorations;
  },
  provide: (field) => EditorView.decorations.from(field),
});

const theme = EditorView.baseTheme({
  // In a line: the formula in the line's own ink, a touch larger, as KaTeX's type runs small beside a sans face.
  '.cm-mathsInline': { fontSize: '1.05em', cursor: 'text' },
  '.cm-mathsInline .katex': { fontSize: '1em' },
  // On lines of its own: in the middle of the page, scrolling sideways rather than running off it.
  '.cm-mathsBlock': {
    display: 'block',
    padding: '0.4em var(--app-gutter, 1rem)',
    overflowX: 'auto',
    overflowY: 'hidden',
    textAlign: 'center',
    textIndent: '0',
    cursor: 'text',
  },
  '.cm-mathsBlock .katex-display': { margin: '0' },
  // Not drawn yet, or not drawable: as it was typed, set as code, as a formula read before it was drawn.
  '.cm-mathsInline:not([data-drawn]), .cm-mathsBlock:not([data-drawn])': {
    fontFamily: 'var(--glacier-font-mono)',
    fontSize: '0.92em',
    whiteSpace: 'pre-wrap',
    color: 'var(--app-ink-2, var(--glacier-text))',
  },
  '.cm-mathsInline[data-failed], .cm-mathsBlock[data-failed]': { textDecoration: 'underline dotted', textUnderlineOffset: '0.25em' },
});

/** Every formula in the note drawn, off the caret's line. */
export function drawnMaths(): Extension {
  return [trackFocus, mathsField, theme];
}
