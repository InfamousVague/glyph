// A formula in a line may be broken after a relation or an operator, where it is wider than its line. It is laid
// out in its pieces from the first frame, never whole and then again (lib/editor/maths/maths.dart), which is
// right only if the pieces side by side are the formula as it is set whole: here each formula is set both ways
// and measured, and a formula wider than its page is in rows the first time it is drawn.
import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart' show Math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/maths/formula.dart';
import 'package:ghost_md/editor/maths/maths.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  /// The widths of `widgets` in a row, each as wide as it likes.
  Future<List<double>> widths(WidgetTester tester, List<Widget> widgets) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: widgets),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    return <double>[for (final element in find.byType(Math).evaluate()) element.size!.width];
  }

  testWidgets('the pieces of a formula, side by side, are the formula', (tester) async {
    const em = 100.0;
    final options = optionsFor(display: false, size: em, color: const Color(0xff000000));
    for (final tex in <String>[
      'a + b',
      'a = b',
      'x = -b',
      r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
      r'a + b - c \times d \div e = f \le g \ne h',
      r'f(x) = \sin x + \cos(y) - \left(\frac{1}{2}\right)',
      r'a \in A \cup B \subset C',
      r'\sum_{i=1}^n i = \frac{n(n+1)}{2}',
      r'x, y \mapsto x + y',
      r'a +{} b = {} + c',
      r'\alpha\beta + \gamma\,\delta = \mathbf{A}x + {\color{red} y + z}',
      'a = b = c = d = e',
      'a + (b + c) + [d = e]',
    ]) {
      // Two readings: the whole and its pieces share the drawing the reader keeps, and cannot both be on screen
      // from one.
      final whole = takeFormula(tex, false), broken = takeFormula(tex, false);
      expect(identical(whole, broken), isFalse);
      final one = await widths(tester, <Widget>[Math(ast: whole.tree, options: options)]);
      final pieces = await widths(tester, <Widget>[for (final part in broken.parts) Math(ast: part, options: options)]);
      expect(pieces.fold<double>(0, (sum, width) => sum + width), closeTo(one.single, 0.01), reason: '$tex, in ${pieces.length} pieces: $pieces');
      releaseFormula(whole);
      releaseFormula(broken);
    }
    // The ones above are broken at all: the test is of something.
    expect(formulaOf('a + b', false).parts, hasLength(2));
    expect(formulaOf(r'a + b - c \times d \div e = f \le g \ne h', false).parts.length, greaterThan(6));
  });

  testWidgets('a formula wider than its line is in rows from the first frame', (tester) async {
    const note = r'$a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 + a_9 + a_{10} + a_{11} + a_{12} + a_{13} + a_{14} + a_{15} + a_{16} = b_1 + b_2 + b_3 + b_4$' '\n\n' r'$x + y$' '\n';
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: note, extensions: noteExtensions()));
    addTearDown(view.destroy);
    await pumpApp(
      tester,
      size: const Size(390, 560),
      prefs: const AppPreferences(theme: 'light'),
      home: Align(alignment: Alignment.topLeft, child: SingleChildScrollView(child: EditorColumn(view: view))),
    );
    expect(tester.takeException(), isNull);
    final drawn = find.byType(DrawnMaths);
    expect(drawn, findsNWidgets(2));
    final wide = tester.getSize(drawn.first), short = tester.getSize(drawn.last);
    // In pieces, each a `Math` of its own, and more than one row of them: at least twice the height of a formula
    // on one row, and no wider than the page.
    expect(find.descendant(of: drawn.first, matching: find.byType(Math)), findsNWidgets(formulaOf(note.substring(1, note.indexOf(r'$', 1)), false).parts.length));
    expect(wide.height, greaterThan(short.height * 1.9));
    expect(wide.width, lessThanOrEqualTo(390));
    // And it is so at once: another frame moves nothing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(drawn.first), wide);
    // `pumpApp` lets shadows be drawn, and a test must leave them as it found them.
    debugDisableShadows = true;
  });
}
