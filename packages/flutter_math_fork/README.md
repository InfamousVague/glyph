# flutter_math_fork, as Ghost.md keeps it

This is [flutter_math_fork](https://pub.dev/packages/flutter_math_fork) 0.7.4 (Apache 2.0, see `LICENSE`; the
parser and the layout are ported from KaTeX, MIT, and each file says so), with the eighteen changes named below. The app
reads it by path (`pubspec.yaml`: `flutter_math_fork: path: packages/flutter_math_fork`) and draws a note's
formulas with it (`lib/editor/maths`).

It is kept here, and not taken from pub.dev, because the changes are inside its layout and its parser, where
nothing outside the package can reach. The web editor draws the same formulas with KaTeX 0.16; a formula must
take the room there that it takes here, or a note's lines sit at other heights in the two apps. Each change was
found by setting the same formula in both and comparing its height above and depth below the baseline
(`tool/maths_fixtures.mjs` asks KaTeX, `test/editor/maths/katex_test.dart` asks this package), and each makes
this package do what KaTeX's source does at the place named.

What is here of the published package: `lib/` (the code and the KaTeX faces), `LICENSE`, `CHANGELOG.md`,
`pubspec.yaml`, and its README as `UPSTREAM.md`. Its `doc/`, `example/` and `test/` are left out: its tests
compare against golden pictures drawn before these changes. `analysis_options.yaml` is ours and quiets the lints
the published code does not pass, so the app's analysis says nothing of it.

## The changes

Each is marked where it is made: `Changed from 0.7.4 (README.md, N)`.

1. **A cramped style was read as uncramped and the other way about** (`lib/src/ast/style.dart`).
   `MathStyleExt.cramped` answered `index.isEven`; the styles are listed `display, displayCramped, text,
   textCramped, …`, so the cramped ones are the odd ones. And `MathStyleDiff` listed `sub` before `sup` while the
   tables it indexes are written superscript first. The two together gave a superscript the lower place of a
   cramped one and gave everything under a root or a fraction bar the higher place: `x^2` stood 0.05em too low,
   `\sqrt{x^2}` too high. KaTeX: `Style.js` (`sup`, `sub`, `cramp`).
2. **A root's rule and its clearance** (`lib/src/ast/nodes/sqrt.dart`). The height of a root is the body's, the
   clearance, and the rule twice (the rule and as much again above it), and the surd hangs from there; an index
   that stands higher than that lifts the whole. It had the rule once and measured the surd from the wrong edge.
   KaTeX: `functions/sqrt.js`.
3. **The brackets of `\binom` and `\choose`** (`lib/src/ast/nodes/left_right.dart`, `genfrac.dart`). A fraction's
   own delimiters are of a fixed size by style (`delim1` in display, `delim2` otherwise) and not stretched to
   what they hold as `\left( \right)` are. KaTeX: `functions/genfrac.js`.
4. **A brace over or under, and its label** (`nodes/over.dart`, `nodes/under.dart`, `nodes/accent_under.dart`,
   `horiz_brace.dart`). The label of `\underbrace{…}_{c}` stands 0.2em from the brace with no big-operator
   spacing around it, and a brace under has 0.1em below it. KaTeX: `functions/horizBrace.js`.
5. **Rows of `cases` and `aligned`** (`render/layout/eqn_array.dart`, `parser/tex/environments/eqn_array.dart`).
   The extra space between rows (`\jot`) is between rows and not after the last, and `cases` is stretched by 1.2
   as an array is. KaTeX: `environments/array.js`.
6. **`align`, `align*`, `split`, `gather`, `gather*`, `equation`, `equation*`, `alignat`, `alignat*`** are read
   (`parser/tex/environments/eqn_array.dart`), each as its `-ed` form is: the published package knew `aligned`,
   `gathered` and `alignedat` only and failed on the rest. No equation numbers are drawn (KaTeX draws them for
   the unstarred forms; see "What still differs").
7. **What follows `\operatorname{…}`** is read as any atom is (`operator_name.dart`), as after `\sin`. It asked
   for a group and could not read `\operatorname{argmax}_\theta \, x`.
8. **`\def` and `\gdef`** (`parser/tex/macros.dart`), with parameters `#1…#9`. `\newcommand` was there already
   and now, with this, so are the definitions KaTeX's own macros make with `\def`. KaTeX: `macros.js`.
9. **A line over or under** (`nodes/accent.dart`, `nodes/accent_under.dart`). `\overline` has three rule
   thicknesses between it and what it covers and one above; `\underline` the same below. They were the other
   way about. KaTeX: `functions/overline.js`, `functions/underline.js`.
10. **`\left.` and `\right.`** take the room of a null delimiter in width only (`nodes/left_right.dart`); it was
    a box as tall as the font and made `\left\{ \frac{a}{b} \right.` taller than its fraction.
11. **`\cancel`, `\bcancel`, `\xcancel`** (`enclose.dart`, `nodes/enclosure.dart`). The stroke is drawn over what
    it strikes and adds nothing to its height (it added 0.2em above and below); the two names that were
    misspelt in the table now strike the right way. KaTeX: `functions/enclose.js`.
12. **A labelled arrow** (`nodes/stretchy_op.dart`). `\xrightarrow{f}` sits on the maths axis (it sat an x-height
    up), and its label is lifted clear of it by 0.111em, a label with a descender by its depth. KaTeX:
    `functions/arrow.js`.
13. **Limits by style** (`nodes/style_limits.dart`, new; `op.dart`, `operator_name.dart`). `\lim_{x \to 0}`,
    `\max_i` and `\operatorname*{argmax}_\theta` take what is written under them as a limit in display style and
    as a subscript in a line of text; `\limits` and `\nolimits` say otherwise. The published package decided as
    it read the formula, always for limits ("in accordance with UnicodeMath, and … different from KaTeX", its
    comment said), so a limit in a sentence made the line taller. KaTeX: `functions/op.js`,
    `functions/operatorname.js`, `functions/supsub.js`.

14. **A broken formula's pieces keep their spacing** (`lib/src/ast/syntax_tree.dart`, `lib/src/ast/tex_break.dart`).
    `texBreak` cuts a row after each relation and operator, for a formula too wide for its line. Each piece
    was then spaced as a row of its own: the operator a piece ends with ("a +", cut before "b") was taken for a
    sign with nothing to its right and lost the space before it, and the space after it, which lay between two
    pieces, was nobody's. A piece is now told the kind of atom that stood before it and after it
    (`EquationRowNode.precededBy`, `followedBy`), is spaced as it was in the row, and keeps the space after
    its last atom, as each `.base` of KaTeX's markup keeps its own. The pieces set side by side are the row,
    to the pixel, which is what lets the app lay a formula out in its pieces from the first frame.

15. **`\mathstrut` and `\underbar`** (`parser/tex/macros.dart`): two of KaTeX's own macros that were left out.

16. **Boxes measured otherwise than by what is in them** (`lib/src/ast/nodes/box.dart`, new;
    `parser/tex/functions/katex_base/box.dart`, new). `\smash` and `\smash[t]`, `\smash[b]` (no height, no
    depth); `\mathllap`, `\mathrlap`, `\mathclap` (no width); `\vcenter` (the middle on the axis); `\hbox`;
    `\mathchoice` (one of four by the style it is built in); `\pmb` (drawn twice a hair apart, as KaTeX's
    `text-shadow` draws it). And the commands KaTeX draws only for a page it trusts, which a note is not:
    `\href`, `\url`, `\includegraphics`, `\htmlClass`, `\htmlId`, `\htmlStyle`, `\htmlData` are the command's own
    name in KaTeX's error red and nothing of what they were given, as on the web. (A link with a `%` in it is
    not read: the reader takes the `%` for a comment's start.) KaTeX: `functions/smash.js`, `lap.js`,
    `vcenter.js`, `hbox.js`, `mathchoice.js`, `pmb.js`, `Parser.formatUnsupportedCmd`.
17. **More of TeX's and KaTeX's macros** (`parser/tex/macros.dart`): `\let`, and `\global` and `\long` before a
    definition; `\llap`, `\rlap`, `\clap`; `\varlimsup`, `\varliminf`, `\varinjlim`, `\varprojlim`; `\aa`, `\AA`.
18. **The starred matrices** (`parser/tex/environments/array.dart`): `matrix*`, `pmatrix*`, `bmatrix*`, `Bmatrix*`,
    `vmatrix*`, `Vmatrix*`, with `[l]`, `[c]` or `[r]` for how their columns are set. And `Vmatrix` has its
    double bars: the published package gave it `vmatrix`'s single ones.

`\tag{…}` is not a change here: the package's macros already keep a tag aside (`\df@tag`), and the app reads it
from there and sets it at the right of the formula (`lib/editor/maths/formula.dart`, `maths.dart`).

## What still differs from KaTeX

`test/editor/maths/katex_test.dart` holds thirty-four formulas and a hundred and nine pieces of them to KaTeX's heights
and depths, to a hundredth of an em, and all agree. What that does not say:

- **Equation numbers.** KaTeX numbers the rows of `align`, `gather`, `equation` and `alignat` at the right
  (`(1)`, `(2)`, counted down the page by a CSS counter); nothing is drawn here. The starred forms and `aligned`
  have none in either. A formula's own `\tag{…}` is drawn.
- **Widths, and the shape of a glyph.** There is no browser on either side of the comparison, so only what the
  two layouts work out is compared: how far above and below its baseline a formula reaches.
- **What KaTeX reads and this reader does not.** Of eighty-three families of KaTeX's commands, each tried the
  plainest way, seven are not read (the test holds the list): `\phase` and `\angl`; `\edef`; `\set` and `\Set`;
  the `CD` environment; `\copyright`, `\textregistered` and `\minuso`. A formula that uses one is shown as its
  source, in the note's error ink, as KaTeX shows what it cannot read. `\phase`, `\angl` and the circled
  letters each want a way of drawing in `lib/src/ast/nodes` (an angle, a border on two sides, a ring round a
  letter); `\edef` wants the expander asked to expand a definition's words as it is made; `\set` wants KaTeX's
  `\bra@set`, which reads its braces with `|` meaning something else; `CD` is a parser of its own
  (`environments/cd.js`).

## Taking a newer one

Copy the new `lib/` over this one, then make the eighteen changes again: `git log -p -- packages/flutter_math_fork`
shows each, and `diff -r` against the published 0.7.4 in the pub cache is the whole of them (about four hundred
lines). `test/editor/maths/katex_test.dart` then says which of them the new version still needs.
