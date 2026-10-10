// What KaTeX makes of a set of formulas, for the port's drawing of them to be held against
// (lib/editor/maths, test/editor/maths/katex_test.dart).
//
//   node tool/maths_fixtures.mjs
//
// Everything is read from ../glyph and nothing is written there: its node_modules for KaTeX 0.16, called as
// src/app/editor/mathsDrawn.ts calls it (`displayMode`, `throwOnError: true`, `output: 'htmlAndMathml'`,
// `strict: 'ignore'`). There is no browser here, so no width and no picture: what KaTeX itself works out is each
// formula's height above its baseline and its depth below, in ems of the formula's own type, which it writes into
// the markup as struts. Those two numbers, and whether the formula can be read at all and what KaTeX says when it
// cannot, go to test/editor/maths/fixtures/katex.json.
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const GLYPH = '/Users/matt/Development/Apps/glyph/';
const OUT = new URL('../test/editor/maths/fixtures/', import.meta.url).pathname;
const require = createRequire(`${GLYPH}package.json`);
const katex = require('katex');
const version = JSON.parse(readFileSync(`${GLYPH}node_modules/katex/package.json`, 'utf8')).version;

// The call in mathsDrawn.ts, checked against the file so that a change there is a change here.
const source = readFileSync(`${GLYPH}src/app/editor/mathsDrawn.ts`, 'utf8');
if (!source.includes("katex.renderToString(tex, { displayMode: display, throwOnError: true, output: 'htmlAndMathml', strict: 'ignore' })")) {
  throw new Error("mathsDrawn.ts's call to KaTeX has moved");
}

/** The formulas: ordinary ones first, then harder, then ones one or other cannot read. `display` is a `$$` block. */
const FORMULAS = [
  ['x^2 + y', false],
  ['E = mc^2', false],
  ['a_1 + a_2 = a_{n+1}', false],
  ['\\alpha\\beta\\gamma \\le \\Omega \\neq \\emptyset', false],
  ['\\frac{a}{b}', false],
  ['\\frac{a}{b}', true],
  ['\\sqrt{x^2 + y^2}', false],
  ['x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}', true],
  ['\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}', true],
  ['\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}', false],
  ['\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}', true],
  ['\\lim_{x \\to 0} \\frac{\\sin x}{x} = 1', true],
  ['\\binom{n}{k} = \\frac{n!}{k!(n-k)!}', true],
  ['\\vec{v} \\cdot \\hat{n} = \\|v\\|\\cos\\theta', false],
  ['\\mathbb{R}^n \\to \\mathcal{L}(\\mathfrak{g})', false],
  ['\\overline{z} + \\underbrace{a + b}_{c}', true],
  ['\\left( \\frac{\\partial f}{\\partial x} \\right)_{y}', true],
  ['\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}', true],
  ['f(x) = \\begin{cases} x^2 & x \\ge 0 \\\\ -x & \\text{otherwise} \\end{cases}', true],
  ['\\begin{aligned} a &= b + c \\\\ &= d \\end{aligned}', true],
  ['\\prod_{p \\text{ prime}} \\frac{1}{1 - p^{-s}}', true],
  ['\\sqrt[3]{\\frac{1}{1 + \\frac{1}{x}}}', true],
  ['\\color{red}{x} + \\textcolor{blue}{y} + \\boxed{z}', false],
  ['\\mathbf{A}\\mathrm{d}x + \\operatorname{argmax}_\\theta \\, \\hat{\\theta}', false],
  ['\\xrightarrow{f} \\overbrace{1 + 2}^{3} \\substack{a \\\\ b}', true],
  ['\\dfrac{1}{2} + \\tfrac{1}{2} + {n \\choose k}', false],
  ['\\begin{align} a &= b \\\\ c &= d \\end{align}', true],
  ['\\cancel{x} + \\tag{1}', true],
  ['\\def\\x{y}\\x + \\newcommand{\\z}{w}\\z', false],
  ['\\underline{x} \\, \\widehat{abc} \\, \\not= \\, \\ldots', false],
  ['\\frac{a', false],
  ['\\unknowncommand{x}', false],
  ['x^', false],
  ['\\begin{matrix} a & b', true],
];

function measure(html) {
  // Each base box KaTeX lays out starts with a strut: its whole height, and how far below the baseline it reaches.
  let height = 0, depth = 0;
  for (const strut of html.matchAll(/class="strut" style="height:([\d.]+)em;(?:vertical-align:(-?[\d.]+)em;)?"/g)) {
    const whole = Number(strut[1]), below = strut[2] ? -Number(strut[2]) : 0;
    height = Math.max(height, whole - below);
    depth = Math.max(depth, below);
  }
  return { height: Math.round(height * 1e4) / 1e4, depth: Math.round(depth * 1e4) / 1e4 };
}

const out = FORMULAS.map(([tex, display]) => {
  try {
    const html = katex.renderToString(tex, { displayMode: display, throwOnError: true, output: 'htmlAndMathml', strict: 'ignore' });
    return { tex, display, ok: true, ...measure(html.slice(html.indexOf('class="katex-html"'))) };
  } catch (error) {
    // What mathsDrawn.ts says on a long press: KaTeX's words, less its name.
    return { tex, display, ok: false, error: (error instanceof Error ? error.message : String(error)).replace(/^KaTeX parse error:\s*/, '') };
  }
});

mkdirSync(OUT, { recursive: true });
writeFileSync(`${OUT}katex.json`, `${JSON.stringify({ katex: version, formulas: out }, null, 1)}\n`);
console.log(`KaTeX ${version}: ${out.filter((f) => f.ok).length} read, ${out.filter((f) => !f.ok).length} not`);
for (const f of out) console.log(f.ok ? `  ${f.height} ${f.depth}` : `  ✗ ${f.error}`, f.display ? '$$' : '$', f.tex);
