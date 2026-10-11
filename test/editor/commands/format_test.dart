// What the formatting bar writes, checked against what the highlighter reads: `src/app/editor/format.test.ts`,
// case for case.
//
// The bar is the one place in the app that puts markdown syntax into the document on the user's behalf, so a drift
// between its delimiters and the grammar's would produce text that looks like a mark and renders as plain.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/format.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/history.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/syntax/language.dart';

import 'support.dart';

void main() {
  group('toggleMark', () {
    test('wraps a selection and keeps it selected', () {
      final view = TestView.of('make this bold', 10, 14);
      view.dispatch(toggleMark(view.state, Mark.bold));
      expect(view.text, 'make this **bold**');
      expect(view.selected, 'bold');
    });

    test('puts the caret BETWEEN the delimiters when nothing is selected', () {
      // Otherwise pressing Bold and typing produces text after the markers, and the person has to notice and move
      // the caret back.
      final view = TestView.of('', 0);
      view.dispatch(toggleMark(view.state, Mark.bold));
      expect(view.text, '****');
      expect(view.head, 2);
    });

    test('unwraps when the delimiters sit just outside the selection', () {
      final view = TestView.of('**bold**', 2, 6);
      view.dispatch(toggleMark(view.state, Mark.bold));
      expect(view.text, 'bold');
    });

    test('unwraps when the delimiters are inside the selection', () {
      final view = TestView.of('**bold**', 0, 8);
      view.dispatch(toggleMark(view.state, Mark.bold));
      expect(view.text, 'bold');
    });

    test('uses the kit delimiters, so what the bar writes is what the grammar reads', () {
      const cases = <(Mark, String)>[(Mark.bold, '**x**'), (Mark.italic, '_x_'), (Mark.code, '`x`'), (Mark.strike, '~~x~~')];
      for (final (mark, expected) in cases) {
        final view = TestView.of('x', 0, 1);
        view.dispatch(toggleMark(view.state, mark));
        expect(view.text, expected);
      }
    });

    test('is a bar press to the haptics, and wraps every range of a selection', () {
      // Not in the web's file: the annotation feel.dart reads, and changeByRange's promise.
      final state = EditorState.create(
        doc: 'one two',
        selection: EditorSelection.create(<SelectionRange>[EditorSelection.range(0, 3), EditorSelection.range(4, 7)]),
        extensions: EditorState.allowMultipleSelections.of(true),
      );
      final tr = toggleWrap(state, '==');
      expect(tr.isUserEvent('input.format'), isTrue);
      expect(tr.state.doc.toString(), '==one== ==two==');
      expect(<String>[for (final r in tr.state.selection.ranges) tr.state.sliceDoc(r.from, r.to)], <String>['one', 'two']);
    });
  });

  group('toggleBlock', () {
    test('prefixes the caret line', () {
      final view = TestView.of('a line', 3);
      view.dispatch(toggleBlock(view.state, Block.quote));
      expect(view.text, '> a line');
    });

    test('removes the prefix when every touched line has one', () {
      final view = TestView.of('- one\n- two', 0, 11);
      view.dispatch(toggleBlock(view.state, Block.bullet));
      expect(view.text, 'one\ntwo');
    });

    test('completes a half-formatted run rather than clearing it', () {
      final view = TestView.of('- one\ntwo', 0, 9);
      view.dispatch(toggleBlock(view.state, Block.bullet));
      expect(view.text, '- one\n- two');
    });

    test('numbers an ordered list rather than repeating 1.', () {
      final view = TestView.of('one\ntwo\nthree', 0, 13);
      view.dispatch(toggleBlock(view.state, Block.number));
      expect(view.text, '1. one\n2. two\n3. three');
    });

    test('recognises a heading of any level as already-a-heading', () {
      final view = TestView.of('### deep', 4);
      expect(activeBlock(view.state), Block.heading);
      view.dispatch(toggleBlock(view.state, Block.heading));
      expect(view.text, 'deep');
    });
  });

  group("Style's table and rule", () {
    // The node names a doc parses to: the app's own parser, or plain GFM as Obsidian and GitHub read the file.
    List<String> parsed(String doc, {bool plain = false}) => nodeNames((plain ? markdownLanguage : glyphMarkdown()).parse(doc));
    // The node holding `needle`, innermost first, as the app's parser reads `doc`.
    List<String> around(String doc, String needle) => chainAt(doc, doc.indexOf(needle) + 1);

    test('puts a blank line between a table and the words after it, so they are not a row', () {
      final view = TestView.of('Para\n\nnext words', 5);
      view.dispatch(insertTable(view.state));
      final doc = view.text;
      expect(doc, 'Para\n\n| Column | Column |\n| --- | --- |\n| Cell | Cell |\n\nnext words');
      expect(around(doc, 'next words'), isNot(contains('TableRow')));
      // Without the blank line the same words are a row: the check can fail.
      expect(around('Para\n| Column | Column |\n| --- | --- |\n| Cell | Cell |\nnext words', 'next words'), contains('TableRow'));
    });

    test('keeps the rule under a paragraph from making it a heading where other apps read the file', () {
      final view = TestView.of('Para\n', 5);
      view.dispatch(insertRule(view.state));
      expect(view.text, 'Para\n\n---');
      expect(parsed(view.text, plain: true), isNot(contains('SetextHeading2')));
      // Plain GFM reads the unmended form as a heading, which is what the blank line is for.
      expect(parsed('Para\n---', plain: true), contains('SetextHeading2'));
    });

    test('takes an empty list item’s line', () {
      final view = TestView.of('- a\n- ', 6);
      view.dispatch(insertTable(view.state));
      expect(view.text, '- a\n\n| Column | Column |\n| --- | --- |\n| Cell | Cell |');
      expect(view.selected, 'Column');
    });

    test('is one step to undo', () {
      final view = TestView.of('Words', 5, null, <Extension>[history()]);
      view.dispatch(insertRule(view.state));
      view.undo_();
      expect(view.text, 'Words');
    });

    test('keeps what is typed over its seed straight after a step of its own', () {
      final view = TestView.of('Words\n', 6, null, <Extension>[history()]);
      view.dispatch(insertTable(view.state));
      final from = view.state.selection.main.from, to = view.state.selection.main.to;
      view.dispatch(
        TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: 'Name'), selection: EditorSelection.single(from + 4), userEvent: 'input.type'),
      );
      view.undo_();
      expect(view.text, 'Words\n\n| Column | Column |\n| --- | --- |\n| Cell | Cell |');
    });
  });

  group('activeMarks', () {
    test('reports the mark surrounding the caret', () {
      final view = TestView.of('**bold**', 2, 6);
      expect(activeMarks(view.state), contains(Mark.bold));
    });

    test('reports nothing in plain text', () {
      expect(activeMarks(TestView.of('plain', 2).state), isEmpty);
    });
  });

  // The web's file has no cases for these five; they are what the press-and-hold menu's other rows write.
  group('the menu’s other rows', () {
    test('a link goes around the selected words, the caret where the address goes', () {
      final view = TestView.of('see docs here', 4, 8);
      final tr = insertLink(view.state);
      view.dispatch(tr);
      expect(view.text, 'see [docs](https://) here');
      expect(view.head, 'see [docs](https://'.length);
      expect(tr.isUserEvent('input.format'), isTrue);
    });

    test('delete takes the selection, or the caret’s line with its break', () {
      var view = TestView.of('one two', 0, 4);
      view.dispatch(deleteSelection(view.state));
      expect(view.text, 'two');
      view = TestView.of('one\ntwo\nthree', 5);
      final tr = deleteSelection(view.state);
      view.dispatch(tr);
      expect(view.text, 'one\nthree');
      expect(view.head, 4);
      expect(tr.isUserEvent('delete.selection'), isTrue);
      expect(tr.scrollIntoView, isTrue);
      view = TestView.of('one\ntwo', 5);
      view.dispatch(deleteSelection(view.state));
      expect(view.text, 'one\n');
    });

    test('duplicate writes the selection after itself, or the line under itself', () {
      var view = TestView.of('ab cd', 0, 2);
      view.dispatch(duplicateSelection(view.state));
      expect(view.text, 'abab cd');
      expect(view.selected, 'ab');
      expect(view.state.selection.main.from, 2);
      view = TestView.of('one\ntwo', 1);
      view.dispatch(duplicateSelection(view.state));
      expect(view.text, 'one\none\ntwo');
      expect(view.head, 5);
    });

    test('lines move up and down with their selection, and stop at either end', () {
      var view = TestView.of('a\nbb\nccc', 3);
      view.dispatch(moveLines(view.state, -1));
      expect(view.text, 'bb\na\nccc');
      expect(view.head, 1);
      view.dispatch(moveLines(view.state, 1));
      expect(view.text, 'a\nbb\nccc');
      expect(view.head, 3);
      expect(moveLines(TestView.of('a\nb', 0).state, -1), isNull);
      expect(moveLines(TestView.of('a\nb', 3).state, 1), isNull);
      view = TestView.of('a\nb\nc\nd', 2, 5);
      view.dispatch(moveLines(view.state, 1));
      expect(view.text, 'a\nd\nb\nc');
      expect(view.selected, 'b\nc');
    });

    test('the bar’s pressed state reads any delimiter, a plugin’s too', () {
      expect(activeWraps(TestView.of('==hi==', 2, 4).state, <String>['**', '==']), <String>['==']);
      expect(activeBlock(TestView.of('- [ ] milk', 3).state), Block.task);
      expect(activeBlock(TestView.of('1. [ ] milk', 3).state), Block.number);
      expect(activeBlock(TestView.of('plain', 3).state), isNull);
    });
  });
}
