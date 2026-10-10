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

/**
 * The pieces the formulas above are made of, one at a time: where a formula's height is not KaTeX's, the piece
 * that is off says which rule it is.
 */
const PARTS = [
  ['x^2', false], ['x^2', true], ['x_i', false], ['x_i^2', false], ['x^{y^2}', false], ['e^{-x^2}', true],
  ['\\sqrt{x}', false], ['\\sqrt{x}', true], ['\\sqrt{\\pi}', true], ['\\sqrt{x^2}', false], ['\\sqrt[3]{x}', false], ['\\sqrt{\\frac{a}{b}}', true],
  ['\\frac{\\sqrt{\\pi}}{2}', true], ['\\frac{1}{x}', true], ['\\frac{1}{1 + \\frac{1}{x}}', true],
  ['\\binom{n}{k}', true], ['\\binom{n}{k}', false], ['{n \\choose k}', false], ['\\left(\\frac{a}{b}\\right)', true], ['\\left(x\\right)', false], ['\\left\\{\\frac{a}{b}\\right.', true],
  ['\\underbrace{a + b}', true], ['\\underbrace{a + b}_{c}', true], ['\\overbrace{1 + 2}', true], ['\\overbrace{1 + 2}^{3}', true], ['\\underline{x}', false], ['\\overline{z}', false],
  ['\\xrightarrow{f}', true], ['\\xrightarrow[g]{f}', true], ['\\xleftarrow{abc}', false], ['\\substack{a \\\\ b}', true],
  ['\\begin{cases} a \\\\ b \\end{cases}', true], ['\\begin{cases} a & b \\\\ c & d \\\\ e & f \\end{cases}', true], ['\\begin{matrix} a \\\\ b \\end{matrix}', true], ['\\begin{bmatrix} a & b \\\\ c & d \\\\ e & f \\end{bmatrix}', true],
  ['\\begin{aligned} a &= b \\end{aligned}', true], ['\\begin{aligned} a &= b \\\\ c &= d \\\\ e &= f \\end{aligned}', true], ['\\begin{array}{cc} a & b \\\\ c & d \\end{array}', true],
  ['\\hat{x}', false], ['\\vec{v}', false], ['\\widehat{abc}', false], ['\\bar{x}^2', false], ['\\dot{x}', false],
  ['\\sum_{i=1}^n', true], ['\\sum_{i=1}^n', false], ['\\int_0^1', true], ['\\lim_{x\\to 0}', true], ['\\prod_{p}', true],
  ['\\operatorname{argmax}_\\theta', false], ['\\operatorname{sin} x', false], ['\\operatorname*{argmax}_\\theta x', true],
  ['\\lim_{x\\to 0} x', false], ['\\max_i x_i', false], ['\\operatorname*{argmax}_\\theta x', false], ['\\lim\\limits_{x\\to 0} x', false], ['\\max\\nolimits_i x_i', true], ['\\sup_{x}^{2} x', true],
  ['\\mathbb{R}', false], ['\\mathcal{L}', false], ['\\mathfrak{g}', false], ['\\text{abc}', false], ['\\boxed{z}', false], ['\\cancel{x}', false],
  ['a \\tag{1}', true], ['\\def\\x{y}\\x', false], ['\\newcommand{\\z}{w}\\z', false], ['\\begin{align} a &= b \\end{align}', true], ['\\begin{gather} a \\\\ b \\end{gather}', true], ['\\begin{alignat}{2} a &= b \\end{alignat}', true],
  ['\\stackrel{a}{=}', false], ['\\overset{a}{b}', false], ['\\underset{a}{b}', false], ['\\not=', false], ['\\ldots', false], ['\\dfrac{1}{2}', false], ['\\tfrac{1}{2}', true],
  ['\\Big( x \\Big)', false], ['\\bigg\\{ x \\bigg\\}', false], ['\\lvert x \\rvert', false], ['\\| v \\|', false], ['\\langle a, b \\rangle', false],
];

/**
 * The reach of the reader: one line for each family of commands KaTeX has, said the plainest way. Only whether
 * each is read is compared, so that what the port's reader cannot read is a list a test holds.
 */
const REACH = [
  '\\smash{x}', '\\vcenter{x}', '\\hbox{x}', '\\verb|x|', '\\mathchoice{a}{b}{c}{d}', '\\phase{x}', '\\angl{n}', '\\href{http://a.example}{x}', '\\url{http://a.example}', '\\includegraphics{a.png}',
  '\\htmlClass{a}{x}', '\\let\\a=b \\a', '\\global\\def\\a{b}\\a', '\\edef\\a{b}\\a', '\\pmb{x}', '\\Set{x | y}', '\\set{x}', '\\underbar{x}', '\\mathstrut x',
  '\\mathclap{x}', '\\mathllap{x}', '\\mathrlap{x}', 'x \\tag*{a}', '\\begin{matrix*}[r] a \\\\ b \\end{matrix*}', '\\begin{CD} A @>a>> B \\end{CD}', '\\varinjlim x', '\\bra{x} \\ket{y} \\braket{x|y}',
  '\\textcolor{red}{x}', '\\color{blue} x', '\\colorbox{yellow}{x}', '\\fcolorbox{red}{yellow}{x}', '\\boxed{x}', '\\cancel{x} \\bcancel{x} \\xcancel{x} \\sout{x}', '\\not\\in', '\\kern1em x \\mkern2mu y \\hskip1em z',
  '\\rule{1em}{2pt}', '\\raisebox{1em}{x}', '\\overbrace{x} \\underbrace{y}', '\\xrightarrow[a]{b} \\xleftarrow{c} \\xLeftrightarrow{d}', '\\genfrac{(}{)}{0pt}{}{a}{b}', '\\cfrac{1}{1 + \\cfrac{1}{x}}',
  '\\dbinom{n}{k} \\tbinom{n}{k}', '{a \\over b} {a \\atop b} {a \\brace b} {a \\brack b}', '\\mathbb{R} \\mathscr{L} \\mathcal{F} \\mathfrak{g} \\mathsf{x} \\mathtt{y} \\mathit{z}', '\\boldsymbol{\\alpha} \\bm{x} \\mathbf{y}',
  '\\text{a $x$ b} \\textbf{c} \\textit{d} \\texttt{e} \\textrm{f} \\textsf{g}', '\\newcommand{\\a}[1]{#1} \\renewcommand{\\a}{c} \\providecommand{\\b}{d} \\a\\b', '\\sum\\limits_a^b \\int\\nolimits_a^b',
  '\\displaystyle x \\textstyle y \\scriptstyle z \\scriptscriptstyle w', '\\big( \\Big[ \\bigg\\{ \\Bigg| \\bigl< \\bigr>', '\\left\\lVert x \\middle| y \\right\\rVert', '\\widetilde{ab} \\widehat{cd} \\overrightarrow{ef} \\overleftarrow{gh} \\utilde{ij}',
  '\\tiny a \\small b \\large c \\Huge d', '\\liminf_x \\limsup_x \\arg\\max \\operatorname*{a}_b', '\\begin{array}{c|c} a & b \\\\ \\hline c & d \\\\ \\hdashline e & f \\end{array}',
  '\\begin{pmatrix} a \\end{pmatrix} \\begin{Bmatrix} a \\end{Bmatrix} \\begin{vmatrix} a \\end{vmatrix} \\begin{Vmatrix} a \\end{Vmatrix} \\begin{smallmatrix} a \\end{smallmatrix}',
  '\\begin{dcases} a \\end{dcases} \\begin{rcases} a \\end{rcases} \\begin{drcases} a \\end{drcases}', '\\begin{gathered} a \\\\ b \\end{gathered} \\begin{alignedat}{2} a &= b \\end{alignedat} \\begin{split} a &= b \\end{split}',
  '\\begin{gather} a \\\\ b \\end{gather}', '\\begin{equation} a \\end{equation}', '\\begin{alignat}{2} a &= b \\end{alignat}', '\\begin{subarray}{l} a \\\\ b \\end{subarray}', '\\begin{darray}{c} a \\end{darray}',
  '\\quad \\qquad \\, \\: \\; \\! \\enspace \\hspace{1em} \\nobreak \\allowbreak', 'a \\bmod b \\pmod{c} \\pod{d} \\mod{e}', '\\iff \\implies \\impliedby', '\\imath \\jmath', '\\text{\\aa \\AA \\ss \\o \\O \\i \\j}',
  '\\vdots \\ddots \\cdots \\ldots \\dots', '\\mathop{x} \\mathbin{y} \\mathrel{z} \\mathopen{(} \\mathclose{)} \\mathpunct{,} \\mathord{a} \\mathinner{b}', '\\llap{a} \\rlap{b} \\clap{c}',
  '\\phantom{a} \\hphantom{b} \\vphantom{c}', '\\TeX \\LaTeX \\KaTeX', '\\char"41', '\\degree \\copyright \\textregistered \\minuso', '\\begingroup x \\endgroup', '\\relax x', 'x \\newline y', '\\overline{x} \\underline{y}',
  '\\stackrel{a}{b} \\overset{a}{b} \\underset{a}{b} \\substack{a \\\\ b}', '\\oint \\iint \\iiint \\coprod \\bigoplus \\bigotimes', '\\lfloor x \\rfloor \\lceil y \\rceil \\ulcorner z \\urcorner', '\\dot{x} \\ddot{y} \\acute{z} \\grave{a} \\check{b} \\breve{c} \\mathring{d}',
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

const read = ([tex, display]) => {
  try {
    const html = katex.renderToString(tex, { displayMode: display, throwOnError: true, output: 'htmlAndMathml', strict: 'ignore' });
    return { tex, display, ok: true, ...measure(html.slice(html.indexOf('class="katex-html"'))) };
  } catch (error) {
    // What mathsDrawn.ts says on a long press: KaTeX's words, less its name.
    return { tex, display, ok: false, error: (error instanceof Error ? error.message : String(error)).replace(/^KaTeX parse error:\s*/, '') };
  }
};
const out = FORMULAS.map(read);
const parts = PARTS.map(read);
// Set apart, as a formula on lines of its own is: the environments want it.
const reach = REACH.map((tex) => read([tex, true])).map(({ tex, ok, error }) => (ok ? { tex, ok } : { tex, ok, error }));

mkdirSync(OUT, { recursive: true });
writeFileSync(`${OUT}katex.json`, `${JSON.stringify({ katex: version, formulas: out, parts, reach }, null, 1)}\n`);
console.log(`KaTeX ${version}: ${out.filter((f) => f.ok).length} read, ${out.filter((f) => !f.ok).length} not`);
console.log(`reach: ${reach.filter((f) => f.ok).length} of ${reach.length} read by KaTeX; not: ${reach.filter((f) => !f.ok).map((f) => f.tex).join('  ')}`);
for (const f of [...out, ...parts]) console.log(f.ok ? `  ${f.height} ${f.depth}` : `  ✗ ${f.error}`, f.display ? '$$' : '$', f.tex);
