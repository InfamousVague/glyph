// The port's formulas against KaTeX's own, formula for formula: tool/maths_fixtures.mjs ran KaTeX 0.16 as
// src/app/editor/mathsDrawn.ts runs it over thirty-four formulas, ordinary to hard, and over the pieces they are
// made of one at a time, and wrote down whether each could be read and, for the ones that could, how far its box
// reaches above and below its baseline, in ems of the formula's own type (fixtures/katex.json). Here each is
// read and laid out by the port's reader (packages/flutter_math_fork, with KaTeX's own faces loaded) and
// measured the same way.
//
// They agree, all of them, to a hundredth of an em. They did not with the package as published: its README
// names the places it was changed, each found by a line of this test's output.
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
  final parts = (fixture['parts'] as List).cast<Map<String, dynamic>>();
  final reach = (fixture['reach'] as List).cast<Map<String, dynamic>>();

  /// For each formula of `list` that differs, how: `unread` (KaTeX reads it, the port does not), `read here
  /// only`, or which of its height and depth is more than a hundredth of an em from KaTeX's. And the same in
  /// words, to read, with the ones neither reads, which is agreeing.
  Future<(Map<String, String>, List<String>)> compare(WidgetTester tester, List<Map<String, dynamic>> list) async {
    // An em of a hundred pixels: a hundredth of an em is a pixel.
    const em = 100.0;
    final differs = <String, String>{};
    final report = <String>[];
    for (final formula in list) {
      final tex = formula['tex'] as String, display = formula['display'] as bool, ok = formula['ok'] as bool;
      final name = '${display ? r'$$' : r'$'} $tex';
      final read = formulaOf(tex, display);
      if (read.tree == null) {
        if (ok) differs[name] = 'unread';
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
              child: _Probe(
                // A tagged formula is as tall as the taller of it and its tag, on one baseline.
                child: read.tag == null
                    ? Math(ast: read.tree, options: optionsFor(display: display, size: em, color: const Color(0xff000000)))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Math(ast: read.tree, options: optionsFor(display: display, size: em, color: const Color(0xff000000))),
                          Math(ast: read.tag, options: optionsFor(display: display, size: em, color: const Color(0xff000000))),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
      final error = tester.takeException();
      if (error != null) {
        differs[name] = 'not laid out';
        report.add('$name: not laid out here ($error)');
        continue;
      }
      final box = tester.renderObject<_RenderProbe>(find.byType(_Probe));
      final height = box.baseline / em, depth = (box.size.height - box.baseline) / em;
      final wantHeight = (formula['height'] as num).toDouble(), wantDepth = (formula['depth'] as num).toDouble();
      final off = <String>[
        if ((height - wantHeight).abs() > 0.011) 'height',
        if ((depth - wantDepth).abs() > 0.011) 'depth',
      ];
      if (off.isNotEmpty) {
        differs[name] = off.join(' ');
        report.add('$name: height ${height.toStringAsFixed(4)} (KaTeX ${wantHeight.toStringAsFixed(4)}), depth ${depth.toStringAsFixed(4)} (KaTeX ${wantDepth.toStringAsFixed(4)})');
      }
    }
    return (differs, report);
  }

  testWidgets('${formulas.length} formulas: read where KaTeX ${fixture['katex']} reads them, and as tall', (tester) async {
    final (differs, report) = await compare(tester, formulas);
    // ignore: avoid_print
    print('${formulas.length - differs.length} of ${formulas.length} as KaTeX has them\n${report.join('\n')}');
    expect(differs, isEmpty);
    // The seven that are not formulas are read by neither, and the four the published package could not read
    // are read: a name before a subscript and a space, `align`, `\tag`, `\def` and `\newcommand`.
    expect(formulas.where((formula) => formula['ok'] == false).length, 7);
    // Three of them are environments that stand only as a displayed formula: refused in a line, in KaTeX's words.
    for (final formula in formulas.where((formula) => (formula['error'] as String?)?.contains('display mode') ?? false)) {
      expect(formulaOf(formula['tex'] as String, false).failed, formula['error'], reason: formula['tex'] as String);
    }
    expect(formulas.where((formula) => (formula['error'] as String?)?.contains('display mode') ?? false), hasLength(3));
    for (final tex in <String>[r'\mathbf{A}\mathrm{d}x + \operatorname{argmax}_\theta \, \hat{\theta}', r'\begin{align} a &= b \\ c &= d \end{align}', r'\cancel{x} + \tag{1}', r'\def\x{y}\x + \newcommand{\z}{w}\z']) {
      expect(formulas.any((formula) => formula['tex'] == tex), isTrue, reason: tex);
      expect(formulaOf(tex, tex.contains('align') || tex.contains('tag')).tree, isNotNull, reason: tex);
    }
  });

  testWidgets('${parts.length} pieces of them, one at a time', (tester) async {
    final (differs, report) = await compare(tester, parts);
    // ignore: avoid_print
    print('${parts.length - differs.length} of ${parts.length} pieces as KaTeX has them\n${report.join('\n')}');
    expect(differs, isEmpty);
  });

  test('${reach.length} families of the commands KaTeX has: which of them the reader cannot read is this list', () {
    final unread = <String>[
      for (final formula in reach)
        if (formula['ok'] == true && formulaOf(formula['tex'] as String, true).tree == null) formula['tex'] as String,
    ];
    // ignore: avoid_print
    print('${reach.length - unread.length} of ${reach.length} families read; not:\n${unread.map((tex) => '$tex: ${formulaOf(tex, true).failed}').join('\n')}');
    expect(reach.where((formula) => formula['ok'] != true), isEmpty, reason: 'each line is one KaTeX reads');
    expect(unread, _unread);
  });
}

/// What KaTeX reads and the port's reader does not, of the families in the fixture: a formula with one of these
/// is shown as its source, in the error's ink. Held here so that the list is known, and so that one coming
/// right is taken off it.
const List<String> _unread = <String>[
  // Two marks: an angle under and beside, and the actuary's.
  r'\phase{x}',
  r'\angl{n}',
  // A definition whose words are worked out as it is made.
  r'\edef\a{b}\a',
  // A set with a bar in it that grows with the braces.
  r'\Set{x | y}',
  r'\set{x}',
  // A diagram of arrows.
  r'\begin{CD} A @>a>> B \end{CD}',
  // A letter in a circle.
  r'\degree \copyright \textregistered \minuso',
];
