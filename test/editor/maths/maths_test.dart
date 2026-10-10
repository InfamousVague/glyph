// Maths drawn as its formula (lib/editor/maths), off the caret's line: src/app/editor/mathsDrawn.test.ts, case for
// case, and then what the web's test cannot count and this can: what a keystroke and a move of the caret cost.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/maths/formula.dart';
import 'package:ghost_md/editor/maths/maths.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

/// A view of `doc`, not focused, so every formula in it is drawn.
EditorView viewOf(String doc, {bool readOnly = false}) {
  final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(readOnly: readOnly)));
  addTearDown(view.destroy);
  return view;
}

/// The formulas drawn in the view: where each is, and what it is.
List<(int from, int to, MathsWidget widget, bool block)> drawn(EditorView view) {
  final out = <(int, int, MathsWidget, bool)>[];
  drawnMathsIn(view.state).between(0, view.state.doc.length, (from, to, value) {
    final widget = value.widget;
    if (widget is MathsWidget) out.add((from, to, widget, value is PointDecoration && value.block));
    return null;
  });
  return out;
}

void main() {
  // A view asks the painting layer for its caches as it is made.
  TestWidgetsFlutterBinding.ensureInitialized();
  group('maths, drawn', () {
    test('draws a formula in a line as the formula, its dollar signs gone', () {
      final found = drawn(viewOf(r'when $x^2 + y$ holds'));
      expect(found, hasLength(1));
      final (from, to, widget, block) = found.single;
      expect((from, to), (5, 14));
      expect(widget.tex, 'x^2 + y');
      expect(widget.source, r'$x^2 + y$');
      expect(widget.display, isFalse);
      expect(block, isFalse);
      // The raised 2 is the reader's own: the formula is read, not passed over.
      expect(formulaOf(widget.tex, false).tree, isNotNull);
    });

    test('draws a formula on lines of its own, and one alone on its line, set apart', () {
      const doc = 'Words\n\n\$\$\n\\frac{a}{b}\n\$\$\n\nMore';
      final found = drawn(viewOf(doc));
      expect(found, hasLength(1));
      final (from, to, widget, block) = found.single;
      expect(doc.substring(from, to), '\$\$\n\\frac{a}{b}\n\$\$');
      expect(widget.tex, r'\frac{a}{b}');
      expect(widget.display, isTrue);
      expect(block, isTrue, reason: 'a block between the lines');
      expect(formulaOf(widget.tex, true).tree, isNotNull);

      final alone = drawn(viewOf(r'$$a + b$$')).single;
      expect(alone.$3.display, isTrue);
      expect(alone.$4, isFalse, reason: 'in its line, set as a formula of its own');
      // In a sentence it stays in the line.
      expect(drawn(viewOf(r'so $$a + b$$ it is')).single.$3.display, isFalse);
    });

    test('leaves prices, code and a dollar after a backslash as they are', () {
      expect(drawn(viewOf('It costs \$5, or \$6 with tax.\n\n`\$x\$` in code\n\n```\n\$y\$\n```\n\nA \\\$3 coffee')), isEmpty);
      // A `$$` pair inside a fence is code; and the note's own front matter is its settings.
      expect(drawn(viewOf('```\n\$\$\nx\n\$\$\n```\n')), isEmpty);
      expect(drawn(viewOf('---\ntitle: \$x\$\n---\n\nand \$y\$ here')).single.$3.tex, 'y');
    });

    test('keeps a formula the reader cannot read as it was typed, saying what is wrong', () {
      final widget = drawn(viewOf(r'broken $\frac{a$ here')).single.$3;
      expect(widget.source, r'$\frac{a$');
      final read = formulaOf(widget.tex, false);
      expect(read.tree, isNull);
      expect(read.failed, isNotEmpty);
    });

    test('shows what was typed on the caret\'s line in a focused view', () {
      final view = viewOf('when \$x^2\$ holds\n\nand \$y\$ too');
      expect(drawn(view), hasLength(2));
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(2)));
      final found = drawn(view);
      expect(found, hasLength(1), reason: 'the first line is as typed');
      expect(found.single.$3.tex, 'y');
      // The caret into the block: its lines are there to edit; out again and it is drawn.
      final block = viewOf('A\n\n\$\$\nx\n\$\$\n\nB');
      block.setFocused(true);
      block.dispatch(TransactionSpec(selection: EditorSelection.single(5)));
      expect(drawn(block), isEmpty);
      block.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      expect(drawn(block), hasLength(1));
      block.setFocused(false);
      block.dispatch(TransactionSpec(selection: EditorSelection.single(5)));
      expect(drawn(block), hasLength(1), reason: 'a view nobody is typing in draws every one');
    });

    test('a press opens a formula only where the note can be changed', () {
      expect(drawn(viewOf(r'a $x$ b')).single.$3.opens, isTrue);
      expect(drawn(viewOf(r'a $x$ b', readOnly: true)).single.$3.opens, isFalse);
    });
  });

  group('what it costs', () {
    test('a letter typed reads no formula again, and a move of the caret off the maths builds nothing', () {
      final view = viewOf('Words first.\n\nwhen \$x^2 + y\$ holds\n\n\$\$\n\\frac{a}{b}\n\$\$\n\nWords last, and \$z\$.\n');
      expect(drawn(view), hasLength(3));
      // Each read once, as it is first drawn; asked for again, it is the one kept.
      for (final (_, _, widget, _) in drawn(view)) {
        formulaOf(widget.tex, widget.display);
      }
      MathsStats.reset();
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 3, insert: 'x')));
      for (final (_, _, widget, _) in drawn(view)) {
        formulaOf(widget.tex, widget.display);
      }
      expect(MathsStats.read, 0);
      // And each is the formula it was, though it moved: nothing of its line is built again for the letter.
      final moved = drawn(view);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'y')));
      final after = drawn(view);
      for (var i = 0; i < moved.length; i++) {
        expect(after[i].$1, moved[i].$1 + 1);
        expect(after[i].$3.compare(moved[i].$3), isTrue);
      }

      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(1)));
      final before = drawnMathsIn(view.state);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(6)));
      expect(identical(drawnMathsIn(view.state), before), isTrue, reason: 'the caret moved along a line with no maths');
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.toString().indexOf('when') + 1)));
      expect(identical(drawnMathsIn(view.state), before), isFalse, reason: 'the caret came onto a line with maths');
      expect(drawn(view), hasLength(2));
    });

    test('a note with no dollar sign in it has nothing to build', () {
      final view = viewOf('Plain words.\n\nMore of them.\n');
      final none = drawnMathsIn(view.state);
      expect(none.isEmpty, isTrue);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x')));
      expect(identical(drawnMathsIn(view.state), none), isTrue);
    });
  });
}
