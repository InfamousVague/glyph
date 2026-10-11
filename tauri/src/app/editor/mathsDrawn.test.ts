import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { describe, expect, it } from 'vitest';
import { glyphMarkdown } from './language.ts';
import { drawnMaths } from './mathsDrawn.ts';

/* Maths drawn as its formula (editor/mathsDrawn.ts), by KaTeX, off the caret's line. */

/** A view of `doc`, not focused, so every formula in it is drawn; and its content once KaTeX has had its turn. */
async function drawn(doc: string) {
  const view = new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown([], []), drawnMaths()] }), parent: document.body });
  // KaTeX is fetched the first time; a turn or two of the loop and it is there.
  for (let i = 0; i < 50 && view.contentDOM.querySelector('.cm-mathsInline:not([data-drawn]):not([data-failed]), .cm-mathsBlock:not([data-drawn]):not([data-failed])'); i += 1) {
    await new Promise((done) => setTimeout(done, 20));
  }
  return { view, dom: view.contentDOM, done: () => view.destroy() };
}

describe('maths, drawn', () => {
  it('draws a formula in a line as the formula, its dollar signs gone', async () => {
    const { dom, done } = await drawn('when $x^2 + y$ holds');
    const formula = dom.querySelector('.cm-mathsInline');
    expect(formula?.hasAttribute('data-drawn')).toBe(true);
    expect(formula?.querySelector('.katex')).toBeTruthy();
    // The raised 2 is KaTeX's superscript, and the words around it are the line's own.
    expect(formula?.querySelector('.msupsub')).toBeTruthy();
    expect(dom.textContent).toContain('when');
    expect(dom.textContent).toContain('holds');
    done();
  });

  it('draws a formula on lines of its own, and one alone on its line, set apart', async () => {
    const block = await drawn('Words\n\n$$\n\\frac{a}{b}\n$$\n\nMore');
    expect(block.dom.querySelector('.cm-mathsBlock[data-drawn] .katex-display')).toBeTruthy();
    block.done();
    const alone = await drawn('$$a + b$$');
    expect(alone.dom.querySelector('.cm-mathsBlock[data-drawn]')).toBeTruthy();
    alone.done();
  });

  it('leaves prices, code and a dollar after a backslash as they are', async () => {
    const { dom, done } = await drawn('It costs $5, or $6 with tax.\n\n`$x$` in code\n\n```\n$y$\n```\n\nA \\$3 coffee');
    expect(dom.querySelector('.cm-mathsInline, .cm-mathsBlock')).toBeNull();
    done();
  });

  it('keeps a formula KaTeX cannot read as it was typed, saying what is wrong', async () => {
    const { dom, done } = await drawn('broken $\\frac{a$ here');
    const formula = dom.querySelector('.cm-mathsInline');
    expect(formula?.hasAttribute('data-failed')).toBe(true);
    expect(formula?.textContent).toBe('$\\frac{a$');
    expect(formula?.getAttribute('title')).toMatch(/could not be drawn/);
    done();
  });

  it('shows what was typed on the caret’s line in a focused view', async () => {
    const { view, dom, done } = await drawn('when $x^2$ holds\n\nand $y$ too');
    view.focus();
    // Focus arrives as an effect, a moment after; a selection on the first line then shows its formula as typed.
    await new Promise((settled) => setTimeout(settled, 30));
    view.dispatch({ selection: { anchor: 2 } });
    const lines = [...dom.querySelectorAll('.cm-line')];
    if (view.hasFocus) {
      expect(lines[0]?.querySelector('.cm-mathsInline')).toBeNull();
      expect(lines[0]?.textContent).toBe('when $x^2$ holds');
    }
    // The other line's formula is drawn either way.
    expect(lines[2]?.querySelector('.cm-mathsInline')).toBeTruthy();
    done();
  });
});
