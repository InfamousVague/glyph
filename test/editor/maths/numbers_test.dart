// Equation numbers: the rows of `align`, `gather`, `equation` and `alignat` are numbered at the right of their
// line, as KaTeX numbers them, less a row that says `\nonumber` or `\notag` or has a `\tag` of its own; the
// starred forms have only the tags they are given. What number: counted through the note from its top, so that
// it is the formula's place in the note and nothing else (KaTeX counts what is in the page, and the web editor
// draws only the lines near the screen: lib/editor/maths/maths.dart says so where it counts). And the cost: a
// number is part of what a formula's widget is, so a formula is made again for its number only when a numbered
// formula above it came or went.
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

String block(String tex) => '\$\$\n$tex\n\$\$\n\n';

/// The formulas the note draws, in its order.
List<MathsWidget> widgetsOf(EditorState state) {
  final out = <MathsWidget>[];
  drawnMathsIn(state).between(0, state.doc.length, (from, to, value) {
    final widget = value.widget;
    if (widget is MathsWidget) out.add(widget);
    return null;
  });
  return out;
}

void main() {
  setUpAll(loadAppFonts);

  test('which rows take a number, and which a tag of their own', () {
    final align = formulaOf(r'\begin{align} a &= b \\ c &= d \nonumber \\ e &= f \tag{x} \\ g \notag \\ h \end{align}', true);
    expect(align.failed, isNull);
    expect(align.rowNumbered, <bool>[true, false, false, false, true]);
    expect(align.rowTags!.map((tag) => tag != null), <bool>[false, false, true, false, false]);
    expect(align.numbered, 2);
    // A last `\\` with nothing after it is no row, and takes no number.
    expect(formulaOf(r'\begin{gather} a \\ b \\ \end{gather}', true).rowNumbered, <bool>[true, true]);
    expect(formulaOf(r'\begin{equation} a \end{equation}', true).numbered, 1);
    expect(formulaOf(r'\begin{alignat}{2} a &= b \\ c &= d \end{alignat}', true).numbered, 2);
    // The starred forms: no numbers, and only the tags they are given.
    for (final name in <String>['align*', 'gather*', 'equation*']) {
      final starred = formulaOf('\\begin{$name} a \\\\ b \\end{$name}', true);
      expect(starred.failed, isNull, reason: name);
      expect(starred.numbered, 0, reason: name);
      expect(starred.rowTags, isNull, reason: name);
    }
    final tagged = formulaOf(r'\begin{align*} a \tag{1} \\ b \end{align*}', true);
    expect(tagged.numbered, 0);
    expect(tagged.rowTags!.map((tag) => tag != null), <bool>[true, false]);
    // The ones that are part of a formula have neither.
    expect(formulaOf(r'\begin{aligned} a \\ b \end{aligned}', true).rowTags, isNull);
    expect(formulaOf(r'x = \begin{split} a \\ b \end{split}', true).rowTags, isNull);
    // And in a line of text they are refused, as KaTeX refuses them.
    expect(formulaOf(r'\begin{align} a \end{align}', false).failed, '{align} can be used only in display mode.');
    expect(formulaOf(r'\begin{gather*} a \end{gather*}', false).failed, '{gather*} can be used only in display mode.');
    expect(formulaOf(r'\begin{aligned} a \end{aligned}', false).failed, isNull);
  });

  group('counted through the note', () {
    final note =
        'Words.\n\n${block(r'\begin{equation} a \end{equation}')}'
        '${block(r'\begin{align} b \\ c \nonumber \\ d \end{align}')}'
        '${block('x^2')}'
        'A line with \$y\$ in it, and \$\$\\begin{gather} e \\end{gather}\$\$ which is in a line and takes none.\n\n'
        '\$\$\\begin{gather} f \\end{gather}\$\$\n\n'
        '${block(r'\begin{align*} g \end{align*}')}'
        '${block(r'\begin{alignat}{1} h \\ i \end{alignat}')}'
        'End.\n';

    EditorView viewOf(String doc) {
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions()));
      addTearDown(view.destroy);
      return view;
    }

    test('each formula knows the number of its first numbered row', () {
      final view = viewOf(note);
      expect(widgetsOf(view.state).map((widget) => widget.first), <int>[1, 2, 0, 0, 0, 4, 0, 5]);
      // The caret in a formula shows its source, and the ones below keep their numbers.
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(note.indexOf(r'\begin{align}') + 3)));
      expect(widgetsOf(view.state).map((widget) => widget.first), <int>[1, 0, 0, 0, 4, 0, 5]);
    });

    test('a formula is made again for its number only when a numbered formula above it comes or goes', () {
      final view = viewOf(note);
      var before = widgetsOf(view.state);
      // How many of the formulas now drawn are not the formulas that were.
      int remade() {
        final after = widgetsOf(view.state);
        final made = after.where((widget) => !before.any(widget.eq)).length;
        before = after;
        return made;
      }

      MathsStats.reset();
      // Words typed: none, and no formula read.
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 2, insert: 'x')));
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.toString().indexOf('End.'), insert: 'y')));
      expect(remade(), 0);
      // A formula that takes no number put in above them all: itself.
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: block('k'))));
      expect(remade(), 1);
      expect(widgetsOf(view.state).map((widget) => widget.first), <int>[0, 1, 2, 0, 0, 0, 4, 0, 5]);
      // A numbered one put in after the second: itself, and the two numbered ones below it. Not the two above,
      // and not the four that take no number.
      final at = view.state.doc.toString().indexOf(block('x^2'));
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: block(r'\begin{equation} z \end{equation}'))));
      expect(remade(), 3);
      expect(widgetsOf(view.state).map((widget) => widget.first), <int>[0, 1, 2, 4, 0, 0, 0, 5, 0, 6]);
      // Taken out again: the two below it.
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, to: at + block(r'\begin{equation} z \end{equation}').length)));
      expect(remade(), 2);
      // The first numbered formula changed, and not how many numbers it takes: itself, and none below it.
      final inFirst = view.state.doc.toString().indexOf(r' a \end{equation}');
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: inFirst, to: inFirst + r' a \end{equation}'.length, insert: r' a \end{equation} % one')));
      expect(remade(), 1, reason: 'a formula changed and no number with it');
      // Counting read the two new formulas that have a numbering environment's name in them, once each. The
      // third new one has none, and is not read until it is drawn.
      expect(MathsStats.read, 2);
    });
  });

  testWidgets('each number stands at the right of its row\'s line', (tester) async {
    final note =
        '${block(r'\begin{align} a &= b + c \\ d &= \frac{e}{f} \nonumber \\ g &= h \tag{x} \\ i &= j \end{align}')}'
        'Words between.\n\n'
        '${block(r'\begin{equation} E = mc^2 \end{equation}')}'
        '${block(r'\begin{gather*} x \\ y \end{gather*}')}';
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: note, extensions: noteExtensions()));
    addTearDown(view.destroy);
    await pumpApp(
      tester,
      size: const Size(390, 560),
      prefs: const AppPreferences(theme: 'light'),
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
    expect(tester.takeException(), isNull);
    final drawn = find.byType(DrawnMaths);
    expect(drawn, findsNWidgets(3));
    List<Rect> boxes(int formula) => <Rect>[for (final element in find.descendant(of: drawn.at(formula), matching: find.byType(Math)).evaluate()) tester.getRect(find.byWidget(element.widget))];
    // The first: its formula, then (1), (x) and (2), each lower than the one before, all ending at one edge.
    final first = boxes(0);
    expect(first, hasLength(4));
    expect(first[1].center.dy < first[2].center.dy && first[2].center.dy < first[3].center.dy, isTrue);
    expect(first[1].top, greaterThanOrEqualTo(first[0].top - 1));
    expect(first[3].bottom, lessThanOrEqualTo(first[0].bottom + 1));
    expect(first[2].right, closeTo(first[1].right, 0.01));
    expect(first[3].right, closeTo(first[1].right, 0.01));
    // The formula in the middle of the line, the numbers at its far side.
    expect(first[1].right, greaterThan(first[0].right));
    expect(first[1].right, greaterThan(300));
    // The second takes the next number, at the same edge; the starred one has none.
    final second = boxes(1);
    expect(second, hasLength(2));
    expect(second[1].right, closeTo(first[1].right, 0.01));
    expect(boxes(2), hasLength(1));
    await shot(tester, 'maths-numbers');
  });
}
