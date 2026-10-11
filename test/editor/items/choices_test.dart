// Choices (lib/editor/items/choices.dart): `src/app/editor/choices.test.ts`, case for case. Nothing is left out;
// the taps on a round box are `boxTaps.test.ts`'s (box_taps_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/choices.dart';

EditorState state(String text) => EditorState.create(doc: text);

void main() {
  group('choices', () {
    test('reads a round box on a bullet, and nothing else', () {
      final s = state('- ( ) Tent\n* (x) Cabin\n- (X) Hotel\n- ( x ) no\n1. ( ) no\n- [ ] a to-do');
      expect(choiceOn(s.doc, 1), const Choice(line: 1, from: 2, picked: false, indent: 0));
      expect(choiceOn(s.doc, 2)?.picked, isTrue);
      expect(choiceOn(s.doc, 3)?.picked, isTrue);
      expect(<int>[4, 5, 6].map((n) => choiceOn(s.doc, n)), <Choice?>[null, null, null]);
    });

    test('reads a choice however it is spaced after its bullet, as a to-do’s box is (core/itemSyntax.ts)', () {
      final s = state('-  ( ) Two spaces\n*\t(x) A tab\n  - ( ) Indented\n- ( )\n- ( )Glued');
      expect(choiceOn(s.doc, 1), const Choice(line: 1, from: 3, picked: false, indent: 0));
      expect(choiceOn(s.doc, 2)?.from, s.doc.line(2).from + 2);
      expect(choiceOn(s.doc, 2)?.picked, isTrue);
      expect(choiceOn(s.doc, 3)?.from, s.doc.line(3).from + 4);
      expect(choiceOn(s.doc, 3)?.indent, 2);
      // One with no words yet is a choice too; brackets glued to words are words.
      expect(choiceOn(s.doc, 4)?.from, s.doc.line(4).from + 2);
      expect(choiceOn(s.doc, 4)?.picked, isFalse);
      expect(choiceOn(s.doc, 5), isNull);
      // And the tap writes inside the brackets wherever they are.
      expect(pick(s, 1)!.state.doc.line(1).text, '-  (x) Two spaces');
    });

    test('groups the choices next to each other at one indent, with lines under a choice inside the group', () {
      final s = state('Stay?\n- ( ) Tent\n  cheap\n- ( ) Cabin\n  - ( ) Small\n  - ( ) Big\n- ( ) Hotel\n\n- ( ) Other group');
      expect(groupOf(s.doc, 2).map((c) => c.line), <int>[2, 4, 7]);
      expect(groupOf(s.doc, 5).map((c) => c.line), <int>[5, 6]);
      expect(groupOf(s.doc, 9).map((c) => c.line), <int>[9]);
    });

    test('picks one and clears the rest, and a picked one tapped again is cleared', () {
      var s = state('- (x) Tent\n- ( ) Cabin\n- ( ) Hotel');
      s = pick(s, 2)!.state;
      expect(s.doc.toString(), '- ( ) Tent\n- (x) Cabin\n- ( ) Hotel');
      s = pick(s, 2)!.state;
      expect(s.doc.toString(), '- ( ) Tent\n- ( ) Cabin\n- ( ) Hotel');
      expect(pick(s, 1)!.isUserEvent('input'), isTrue);
    });
  });
}
