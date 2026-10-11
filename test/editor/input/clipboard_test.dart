// What a copy takes and how a paste goes in (lib/editor/input/clipboard.dart): @codemirror/view input.ts
// `copiedRange` and `doPaste`, which CodeMirror's own tests hold in a browser (test/webtest-... has none for the
// clipboard, so these are read off the source): docs/PARITY.md, Differs 31.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/input/clipboard.dart';

EditorState state(String doc, List<SelectionRange> ranges) =>
    EditorState.create(doc: doc, selection: EditorSelection.create(ranges), extensions: EditorState.allowMultipleSelections.of(true));

EditorState pasted(EditorState from, String text) => from.update(pasteOf(from, text)).state;

void main() {
  setUp(() => lastLinewiseCopy = null);

  group('copiedRange', () {
    test('takes the selected words, each range joined by a line break', () {
      final copied = copiedRange(state('one two three', [EditorSelection.range(0, 3), EditorSelection.range(8, 13)]));
      expect(copied.text, 'one\nthree');
      expect(copied.ranges, [(from: 0, to: 3), (from: 8, to: 13)]);
      expect(copied.linewise, isFalse);
    });

    test('with nothing selected takes the caret’s line, and the break after it for a cut', () {
      final copied = copiedRange(state('one\ntwo\nthree', [EditorSelection.cursor(5)]));
      expect(copied.text, 'two');
      expect(copied.ranges, [(from: 4, to: 8)]);
      expect(copied.linewise, isTrue);
    });

    test('the last line has no break to take, and an empty note is an empty line', () {
      expect(copiedRange(state('one\ntwo', [EditorSelection.cursor(7)])).ranges, [(from: 4, to: 7)]);
      final empty = copiedRange(state('', [EditorSelection.cursor(0)]));
      expect((empty.text, empty.linewise), ('', true));
      expect(empty.ranges, [(from: 0, to: 0)]);
    });

    test('two carets on one line take it once, and carets on two lines take both', () {
      expect(copiedRange(state('one\ntwo', [EditorSelection.cursor(0), EditorSelection.cursor(2)])).text, 'one');
      final both = copiedRange(state('one\ntwo\nthree', [EditorSelection.cursor(1), EditorSelection.cursor(9)]));
      expect(both.text, 'one\nthree');
      expect(both.ranges, [(from: 0, to: 4), (from: 8, to: 13)]);
    });

    test('an empty range beside a selected one is passed over', () {
      final copied = copiedRange(state('one\ntwo', [EditorSelection.cursor(1), EditorSelection.range(4, 7)]));
      expect((copied.text, copied.linewise), ('two', false));
    });
  });

  group('copyOf', () {
    test('remembers a line copied whole, and forgets it at the next copy of a selection', () {
      final line = state('one\ntwo', [EditorSelection.cursor(5)]);
      expect(copyOf(line, cut: false).text, 'two');
      expect(lastLinewiseCopy, 'two');
      expect(copyOf(state('one\ntwo', [EditorSelection.range(0, 3)]), cut: false).text, 'one');
      expect(lastLinewiseCopy, isNull);
    });

    test('a cut is one delete.cut of what was taken, and none in a note that cannot be changed', () {
      final line = state('one\ntwo\nthree', [EditorSelection.cursor(5)]);
      final taken = copyOf(line, cut: true);
      final tr = line.update(taken.cut!);
      expect(tr.state.doc.toString(), 'one\nthree');
      expect(tr.isUserEvent('delete.cut'), isTrue);
      expect(tr.state.selection.main.head, 4);
      final locked = EditorState.create(doc: 'one\ntwo', selection: EditorSelection.single(5), extensions: EditorState.readOnlyFacet.of(true));
      final kept = copyOf(locked, cut: true);
      expect((kept.text, kept.cut), ('two', null));
    });

    test('a copy without cut makes no edit', () {
      expect(copyOf(state('one', [EditorSelection.cursor(1)]), cut: false).cut, isNull);
    });
  });

  group('pasteOf', () {
    test('a line copied whole goes in above the caret’s line, the caret staying in its own', () {
      copyOf(state('one\ntwo', [EditorSelection.cursor(5)]), cut: false);
      final after = pasted(state('alpha\nbeta', [EditorSelection.cursor(8)]), 'two');
      expect(after.doc.toString(), 'alpha\ntwo\nbeta');
      expect(after.selection.main.head, 12);
    });

    test('the same words over a selection, or other words, replace the selection as ever', () {
      copyOf(state('one\ntwo', [EditorSelection.cursor(5)]), cut: false);
      expect(pasted(state('alpha beta', [EditorSelection.range(0, 5)]), 'two').doc.toString(), 'two beta');
      final other = pasted(state('alpha', [EditorSelection.cursor(5)]), ' and');
      expect(other.doc.toString(), 'alpha and');
      expect(other.selection.main.head, 9);
    });

    test('with no line remembered the words go in at the caret', () {
      expect(pasted(state('alpha\nbeta', [EditorSelection.cursor(8)]), 'two').doc.toString(), 'alpha\nbetwota');
    });

    test('as many lines as carets go one to each', () {
      final after = pasted(state('a\nb', [EditorSelection.cursor(1), EditorSelection.cursor(3)]), '1\n2');
      expect(after.doc.toString(), 'a1\nb2');
      expect(after.selection.ranges.map((r) => r.head), [2, 5]);
    });

    test('lines copied whole from two carets go back one above each caret’s line', () {
      copyOf(state('one\ntwo', [EditorSelection.cursor(1), EditorSelection.cursor(5)]), cut: false);
      expect(lastLinewiseCopy, 'one\ntwo');
      final after = pasted(state('a\nb', [EditorSelection.cursor(0), EditorSelection.cursor(2)]), 'one\ntwo');
      expect(after.doc.toString(), 'one\na\ntwo\nb');
    });

    test('several lines pasted at one caret go in whole', () {
      final after = pasted(state('ab', [EditorSelection.cursor(1)]), '1\n2');
      expect(after.doc.toString(), 'a1\n2b');
      expect(after.selection.main.head, 4);
    });
  });
}
