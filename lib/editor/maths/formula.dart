/// A formula read, once: what `katex.renderToString(tex, {displayMode, throwOnError: true, output: 'htmlAndMathml',
/// strict: 'ignore'})` is to `src/app/editor/mathsDrawn.ts`, which keeps its answers by what they say and how
/// they are set (`drawn`, four hundred of them) so that scrolling past a formula reads nothing again.
///
/// The reader is `flutter_math_fork` 0.7 (Apache 2.0), a port of KaTeX's parser and layout to Dart with KaTeX's
/// own faces: the same TeX, the same boxes, by the same tables of the faces' sizes. What it reads is a tree;
/// what the tree is drawn as depends on a size and an ink, and the package keeps what it built for the last
/// options it was asked with, so the options a formula is drawn with are kept too ([optionsFor]): the same
/// formula at the same size in the same ink is built once.
library;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_math_fork/ast.dart' show MathOptions, MathStyle, SyntaxTree, SyntaxTreeTexStyleBreakExt;
import 'package:flutter_math_fork/flutter_math.dart' show ParseException, Strict, TexParserSettings;
import 'package:flutter_math_fork/tex.dart' show TexParser;

/// What a formula is drawn as: its tree, or what is wrong with it.
class Formula {
  Formula._(this.tex, this.display, this.tree, this.failed);

  final String tex;
  final bool display;
  final SyntaxTree? tree;

  /// What the reader said, when it could not read the formula.
  final String? failed;

  /// The formula in the pieces a line may be broken between: after a relation or an operator at its top level,
  /// as TeX breaks a formula in a paragraph and KaTeX lets a browser (each piece is a `.base` of its markup).
  late final List<SyntaxTree> parts = tree == null ? const <SyntaxTree>[] : tree!.texBreak().parts;

  /// Whether a drawing on screen holds this reading ([takeFormula]).
  bool _taken = false;
}

/// The work done, counted, for a test to hold the editor to.
abstract final class MathsStats {
  /// Formulas read (parsed) from their TeX.
  static int read = 0;

  static void reset() => read = 0;
}

/// The readings kept, by what each says and how it is set. More than one of the same where the same formula
/// stands in more than one place at once: the reader's tree keeps the one drawing it built (and names its rows
/// with keys only one place on screen may hold), so each place on screen needs a tree of its own.
final Map<String, List<Formula>> _read = <String, List<Formula>>{};
int _kept = 0;

Formula _parse(String tex, bool display) {
  MathsStats.read++;
  try {
    // `strict: 'ignore'`: what LaTeX would not take and KaTeX can is drawn without a word.
    return Formula._(tex, display, SyntaxTree(greenRoot: TexParser(tex, TexParserSettings(displayMode: display, strict: Strict.ignore)).parse()), null);
  } on ParseException catch (error) {
    return Formula._(tex, display, null, error.message);
  } on Object catch (error) {
    return Formula._(tex, display, null, '$error');
  }
}

List<Formula> _readings(String tex, bool display) {
  final key = '${display ? 'D' : 'I'}$tex';
  var list = _read[key];
  if (list == null) {
    // `if (drawn.size > 400) drawn.clear()`, less the ones on screen.
    if (_kept > 400) {
      _read.removeWhere((_, readings) {
        readings.removeWhere((reading) => !reading._taken);
        return readings.isEmpty;
      });
      _kept = _read.values.fold(0, (sum, readings) => sum + readings.length);
    }
    list = _read[key] = <Formula>[_parse(tex, display)];
    _kept++;
  }
  return list;
}

/// The formula `tex` (without its dollar signs), set on lines of its own (`display`) or in a line: whether it
/// can be read, and what is wrong with it if not. For whoever only asks; to draw it, [takeFormula].
Formula formulaOf(String tex, bool display) => _readings(tex, display).first;

/// A reading of the formula for one place on screen to draw, its own until it is given back
/// ([releaseFormula]). A formula scrolled away and back, or typed past, is read once; the same formula in two
/// places at once is read twice.
Formula takeFormula(String tex, bool display) {
  final readings = _readings(tex, display);
  // One that cannot be read has nothing to draw, and is anyone's.
  if (readings.first.tree == null) return readings.first;
  for (final reading in readings) {
    if (!reading._taken) return reading.._taken = true;
  }
  final more = _parse(tex, display).._taken = true;
  readings.add(more);
  _kept++;
  return more;
}

/// Gives a reading back, for the next place that draws the same formula.
void releaseFormula(Formula formula) => formula._taken = false;

final Map<(bool, double, int), MathOptions> _options = <(bool, double, int), MathOptions>{};

/// The options a formula is drawn with: on lines of its own or in a line, at `size` (the formula's own em, in
/// logical pixels), in `color`. The same three give the same object, which is what the package's trees keep
/// their built boxes by.
MathOptions optionsFor({required bool display, required double size, required Color color}) {
  if (_options.length > 64) _options.clear();
  return _options[(display, size, color.toARGB32())] ??= MathOptions(style: display ? MathStyle.display : MathStyle.text, fontSize: size, color: color);
}
