// Sums (lib/editor/items/sums.dart, the arithmetic lib/core/sums.dart's): `src/app/editor/sums.test.ts`, case for
// case. test/core/sums_test.dart holds the web's `core/sums.test.ts` and the module's own examples, none of them
// these four cases, though a few of their sums are worked there too (`2 ^ 3 ^ 2`, `200 * 15%`, and the three that
// cannot be done). The last group is not the web's: it holds the editor's half, where an answer is drawn.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/sums.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sums', () {
    test('works arithmetic out in the usual order', () {
      expect(answer('450 + 120 * 2'), '690');
      expect(answer('(450 + 120) * 2'), '1140');
      expect(answer('2 ^ 3 ^ 2'), '512');
      expect(answer('-3 + 10 / 4'), '-0.5'.replaceFirst('-', '−'));
      expect(answer('10 × 3 ÷ 4'), '7.5');
      expect(answer('200 * 15%'), '30');
    });

    test('gives a currency sign and thousands back', () {
      expect(answer(r'$1,200 / 3'), r'$400');
      expect(answer('£10 / 3'), '£3.33');
      expect(answer('1,000 + 250'), '1,250');
    });

    test('answers nothing for a lone number, words, or a sum that cannot be done', () {
      expect(answer('450'), isNull);
      expect(answer('rent + food'), isNull);
      expect(answer('1 / 0'), isNull);
      expect(answer('(1 + 2'), isNull);
      expect(answer('1 +'), isNull);
    });

    test('is a line starting with = and a space, in a list or quote too, and not a heading underline', () {
      expect(sumOnLine('= 1 + 1'), (answer: '2'));
      expect(sumOnLine('- = 2 * 3'), (answer: '6'));
      expect(sumOnLine('> = 9 - 4'), (answer: '5'));
      expect(sumOnLine('==='), isNull);
      expect(sumOnLine('x = 1 + 1'), isNull);
    });
  });

  group('a sum in a note (not in the web’s tests)', () {
    /// The answers drawn: each one's line (from 1), where it stands, and what it says.
    List<({int line, int at, String text})> answers(EditorView view) {
      final found = <({int line, int at, String text})>[];
      for (final set in view.decorations) {
        set.between(0, view.state.doc.length, (from, to, value) {
          final widget = value.widget;
          if (widget is AnswerWidget) found.add((line: view.state.doc.lineAt(from).number, at: from, text: widget.text));
          return null;
        });
      }
      return found..sort((a, b) => a.at - b.at);
    }

    test('answers after its line, never in code, and follows the sum as it is written', () {
      final view = EditorView(
        wholeDocument: true,
        state: EditorState.create(doc: '= 450 + 120 * 2\n- = \$1,200 / 3\nrent = 1 + 1\n\n```\n= 1 + 1\n```', extensions: noteExtensions(more: <Extension>[sums()])),
      );
      addTearDown(view.destroy);
      expect(answers(view), <({int line, int at, String text})>[
        (line: 1, at: view.state.doc.line(1).to, text: '690'),
        (line: 2, at: view.state.doc.line(2).to, text: r'$400'),
      ]);
      // Nothing is written into the note.
      expect(view.state.doc.line(1).text, '= 450 + 120 * 2');
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.line(1).to, insert: ' + 10')));
      expect(answers(view).first, (line: 1, at: view.state.doc.line(1).to, text: '700'));
    });
  });
}
