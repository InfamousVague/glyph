// Which line the + beside the line is drawn on (lib/editor/plus/plus_line.dart): the caret's line when it has no
// words (Matt: "EMPTY LINES ONLY, on every platform"), and only where adding to the note makes sense. The cases of
// ../glyph/src/app/editor/plusLine.test.ts, one for one.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/plus/plus_line.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';

int? lineOf(String doc, {int? anchor, int? head, bool focused = true, bool editable = true, bool allowed = true}) {
  final at = anchor ?? doc.length;
  final state = EditorState.create(doc: doc, selection: EditorSelection.single(at, head ?? at));
  return plusLine(state, PlusContext(focused: focused, editable: editable, allowed: allowed))?.number;
}

void main() {
  group('the line the + is drawn on', () {
    test('is the caret’s line when it has no words', () {
      expect(lineOf('Lunch at the harbour\n'), 2);
      expect(lineOf(''), 1);
    });

    test('is an empty item, to-do, choice or quote line: a lead is not words', () {
      for (final lead in ['- ', '- [ ] ', '3. ', '- ( ) ', '> ', '> - [ ] ']) {
        expect(lineOf('Para\n$lead'), 2, reason: lead);
      }
    });

    test('is never a line with words, whatever the caret is doing on it', () {
      expect(lineOf('Lunch at the harbour'), isNull);
      expect(lineOf('Lunch at the harbour', anchor: 0), isNull);
      expect(lineOf('- [ ] milk'), isNull);
      expect(lineOf('# '), isNull);
    });

    test('is never on a selection, which belongs to press and hold, nor beside one of several carets', () {
      // The head on the empty line: it is the selection that says no, not words.
      expect(lineOf('a\n\nb', anchor: 0, head: 2), isNull);
      expect(lineOf('a\n\nb', anchor: 2, head: 2), 2);
      final carets = EditorState.create(
        doc: '\n\n',
        selection: EditorSelection.create([EditorSelection.cursor(0), EditorSelection.cursor(2)]),
        extensions: EditorState.allowMultipleSelections.of(true),
      );
      expect(plusLine(carets, const PlusContext(focused: true, editable: true, allowed: true)), isNull);
    });

    test('is never in a view that has lost focus, cannot be edited, or is not a note being written', () {
      expect(lineOf('', anchor: 0, focused: false), isNull);
      expect(lineOf('', anchor: 0, editable: false), isNull);
      expect(lineOf('', anchor: 0, allowed: false), isNull);
    });

    test('is never in the front matter or a block of code', () {
      const front = '---\ntitle: Trip\n\n---\n\nWords';
      expect(lineOf(front, anchor: front.indexOf('\n\n---') + 1), isNull);
      expect(lineOf(front, anchor: front.length - 'Words'.length - 1), 5);
      const fence = 'Before\n```\n\n```\nAfter\n';
      expect(lineOf(fence, anchor: 'Before\n```\n'.length), isNull);
      expect(lineOf(fence), 6);
    });
  });
}
