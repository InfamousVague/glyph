// The port's formulas against KaTeX's own, formula for formula: tool/maths_fixtures.mjs ran KaTeX 0.16 as
// src/app/editor/mathsDrawn.ts runs it over thirty-four formulas, ordinary to hard, and wrote down whether each
// could be read and, for the ones that could, how far its box reaches above and below its baseline, in ems of
// the formula's own type (fixtures/katex.json). Here each is read and laid out by the port's reader
// (flutter_math_fork, with KaTeX's own faces loaded) and measured the same way.
//
// There is no browser on either side, so widths and the look of a glyph are not compared: only what the two
// layouts work out, which is where one would stand a fraction of a line off the other.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart' show Math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/maths/formula.dart';

import '../../support/render.dart';

/// Notes where its child's baseline is, which a box may only be asked while it is being laid out.
class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderProbe();
}

class _RenderProbe extends RenderProxyBox {
  double baseline = 0;

  @override
  void performLayout() {
    super.performLayout();
    baseline = child!.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ?? child!.size.height;
  }
}

void main() {
  setUpAll(loadAppFonts);

  final fixture = jsonDecode(File('test/editor/maths/fixtures/katex.json').readAsStringSync()) as Map<String, dynamic>;
  final formulas = (fixture['formulas'] as List).cast<Map<String, dynamic>>();

  testWidgets('${formulas.length} formulas: read where KaTeX ${fixture['katex']} reads them, and as tall', (tester) async {
    // An em of a hundred pixels: a hundredth of an em is a pixel.
    const em = 100.0;
    // For each formula that differs, how: `unread` (KaTeX reads it, the port does not), `neither`, or which of
    // its height and depth is more than a hundredth of an em from KaTeX's. And the same in words, to read.
    final differs = <String, String>{};
    final report = <String>[];
    for (final formula in formulas) {
      final tex = formula['tex'] as String, display = formula['display'] as bool, ok = formula['ok'] as bool;
      final name = '${display ? r'$$' : r'$'} $tex';
      final read = formulaOf(tex, display);
      if (read.tree == null) {
        differs[name] = ok ? 'unread' : 'neither';
        report.add(ok ? '$name: not read here (${read.failed}), read by KaTeX' : '$name: read by neither; here "${read.failed}", KaTeX "${formula['error']}"');
        continue;
      }
      if (!ok) {
        differs[name] = 'read here only';
        report.add('$name: read here, not by KaTeX (${formula['error']})');
        continue;
      }
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          // As wide and as tall as it likes: at this size a formula is wider than a test's screen.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: _Probe(child: Math(ast: read.tree, options: optionsFor(display: display, size: em, color: const Color(0xff000000)))),
            ),
          ),
        ),
      );
      final box = tester.renderObject<_RenderProbe>(find.byType(_Probe));
      final height = box.baseline / em, depth = (box.size.height - box.baseline) / em;
      final wantHeight = (formula['height'] as num).toDouble(), wantDepth = (formula['depth'] as num).toDouble();
      final off = <String>[
        if ((height - wantHeight).abs() > 0.011) 'height',
        if ((depth - wantDepth).abs() > 0.011) 'depth',
      ];
      if (off.isNotEmpty) {
        differs[name] = off.join(' ');
        report.add('$name: height ${height.toStringAsFixed(2)} (KaTeX ${wantHeight.toStringAsFixed(2)}), depth ${depth.toStringAsFixed(2)} (KaTeX ${wantDepth.toStringAsFixed(2)})');
      }
    }
    // ignore: avoid_print
    print('${formulas.length - differs.length} of ${formulas.length} as KaTeX has them; the others:\n${report.join('\n')}');
    // What is known to differ, said here so that it is held: anything else is a failure, and so is one of these
    // coming right without being taken off the list.
    expect(differs, _known);
  });
}

/// Where the port's reader is not KaTeX 0.16, formula by formula (the numbers are in the test's own output).
///
/// The first four are one fault: `flutter_math_fork` 0.7.4 reads a style's crampedness the wrong way round
/// (`MathStyleExt.cramped` in its lib/src/ast/style.dart answers `index.isEven`, and the cramped styles are the
/// odd ones), so a superscript is set at the height TeX gives one under a root or a fraction's bar, 0.074 em
/// lower in a line of text, and an accent's own style is never cramped. The others are layouts the package has
/// of its own (the rows of `cases` and `aligned`, `\binom`'s brackets, a brace's depth, an arrow's height), and
/// four things it does not read: `\operatorname` before a subscript and a space, the `align` environment,
/// `\tag`, and `\def` and `\newcommand`.
const Map<String, String> _known = <String, String>{
  r'$ x^2 + y': 'height',
  r'$ E = mc^2': 'height',
  r'$ \sqrt{x^2 + y^2}': 'depth',
  r'$$ \int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}': 'height',
  r'$$ \binom{n}{k} = \frac{n!}{k!(n-k)!}': 'height depth',
  r'$$ \overline{z} + \underbrace{a + b}_{c}': 'depth',
  r'$$ f(x) = \begin{cases} x^2 & x \ge 0 \\ -x & \text{otherwise} \end{cases}': 'height depth',
  r'$$ \begin{aligned} a &= b + c \\ &= d \end{aligned}': 'height depth',
  r'$$ \sqrt[3]{\frac{1}{1 + \frac{1}{x}}}': 'height',
  r'$ \mathbf{A}\mathrm{d}x + \operatorname{argmax}_\theta \, \hat{\theta}': 'unread',
  r'$$ \xrightarrow{f} \overbrace{1 + 2}^{3} \substack{a \\ b}': 'height',
  r'$$ \begin{align} a &= b \\ c &= d \end{align}': 'unread',
  r'$$ \cancel{x} + \tag{1}': 'unread',
  r'$ \def\x{y}\x + \newcommand{\z}{w}\z': 'unread',
  r'$ \frac{a': 'neither',
  r'$ \unknowncommand{x}': 'neither',
  r'$ x^': 'neither',
  r'$$ \begin{matrix} a & b': 'neither',
};
