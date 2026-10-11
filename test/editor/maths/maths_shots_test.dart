// Maths in a note as it is drawn: formulas in a line and in a heading, a block on lines of its own, one alone on
// its line, and one that cannot be read; and the sizes and ink the web gives them (mathsDrawn.ts's theme over
// KaTeX's stylesheet): in a line 1.05 of the line's type in the line's ink, set apart KaTeX's own 1.21.
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
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

const String note = r'''
## Energy, $E = mc^2$

The roots are $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$, where $a \neq 0$, and it costs $5 or $6.

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

> A quote with $\alpha + \beta$ in it.

$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$

One that cannot be read: $\frac{a$ here.
''';

/// The formulas drawn, in the note's order: each one's own drawing (the first `Math` under it; the others are
/// its pieces, for a line it does not fit).
List<Math> formulas(WidgetTester tester) => <Math>[
  // (A formula in a line is a widget for each of its pieces; a formula is counted at its first.)
  for (final element in find.byType(DrawnMaths).evaluate().where((element) => ((element.widget as DrawnMaths).piece ?? 0) == 0))
    if (find.descendant(of: find.byWidget(element.widget), matching: find.byType(Math)).evaluate().isNotEmpty)
      find.descendant(of: find.byWidget(element.widget), matching: find.byType(Math)).evaluate().first.widget as Math,
];

void main() {
  setUpAll(loadAppFonts);

  Future<EditorView> draw(WidgetTester tester, AppPreferences prefs) async {
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: note, extensions: noteExtensions()));
    addTearDown(view.destroy);
    await pumpApp(
      tester,
      size: const Size(390, 560),
      prefs: prefs,
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(alignment: Alignment.topLeft, child: SingleChildScrollView(child: EditorColumn(view: view))),
        ),
      ),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
    return view;
  }

  testWidgets('each formula is set at the web\'s size in its line\'s ink', (tester) async {
    final view = await draw(tester, const AppPreferences(theme: 'light'));
    final look = view.look!;
    final body = look.env.body, ink = look.env.t.color('glacier-text');
    final drawn = formulas(tester);
    expect(find.byType(DrawnMaths).evaluate().where((element) => ((element.widget as DrawnMaths).piece ?? 0) == 0), hasLength(7));
    expect(drawn, hasLength(6), reason: 'every one but the one that cannot be read');
    // In the heading: 1.05 of the note's size, not the heading's. The heading's size is the highlighter's class
    // on its words, and the highlighter's marks are inside every other decoration (`Prec.high`), so they are not
    // round a widget another extension puts in the line: on the web the formula's span is the line's child, and
    // takes the line's size and ink. The same goes for a quote's quieter ink.
    expect(drawn[0].options!.fontSize, closeTo(body * 1.05, 0.01));
    expect(drawn[0].options!.color, ink);
    // In a line of the note: 1.05 of the body, in the note's ink.
    expect(drawn[1].options!.fontSize, closeTo(body * 1.05, 0.01));
    expect(drawn[1].options!.color, ink);
    expect(drawn[2].options!.fontSize, closeTo(body * 1.05, 0.01));
    // On lines of its own: KaTeX's 1.21em of the note's size.
    expect(drawn[3].options!.fontSize, closeTo(body * 1.21, 0.01));
    expect(drawn[3].options!.color, ink);
    expect(drawn[4].options!.fontSize, closeTo(body * 1.05, 0.01));
    // Alone on its line: set apart, at 1.21 of its line.
    expect(drawn[5].options!.fontSize, closeTo(body * 1.21, 0.01));
    await shot(tester, 'maths-light');
  });

  testWidgets('a letter typed, and the caret onto a formula\'s line and off it, read no formula again', (tester) async {
    final view = await draw(tester, const AppPreferences(theme: 'light'));
    MathsStats.reset();
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: note.indexOf('The roots') + 3, insert: 'x')));
    await tester.pump();
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(note.indexOf('The roots') + 4)));
    await tester.pump();
    expect(formulas(tester), hasLength(4));
    view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
    await tester.pump();
    expect(formulas(tester), hasLength(5), reason: 'the caret is on the heading\'s line now');
    expect(MathsStats.read, 0, reason: 'each formula was read once, when it was first drawn');
    // The binding's own switch for shadows, which drawing the app turned on.
    debugDisableShadows = true;
  });

  testWidgets('on the dark page', (tester) async {
    await draw(tester, const AppPreferences(theme: 'dark'));
    await shot(tester, 'maths-dark');
  });

  testWidgets('the caret on a formula\'s line shows what was typed', (tester) async {
    final view = await draw(tester, const AppPreferences(theme: 'light'));
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(note.indexOf('The roots') + 4)));
    await tester.pump();
    expect(formulas(tester), hasLength(4), reason: 'the two on the caret\'s line are their source');
    await shot(tester, 'maths-caret');
  });
}
