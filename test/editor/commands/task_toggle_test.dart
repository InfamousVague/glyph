// Tapping a to-do's box (lib/editor/commands/task_toggle.dart): `src/app/editor/taskToggle.test.ts`, case for case.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/task_toggle.dart';
import 'package:ghost_md/editor/state/state.dart';

void main() {
  group('tapping a to-do box', () {
    test('finds the box on a to-do line, bulleted, numbered or indented, and nothing on other lines', () {
      final state = EditorState.create(doc: '- [ ] milk\n  * [x] eggs\n3. [X] bread\n- plain\n[ ] not a list');
      int line(int n) => state.doc.line(n).from;
      expect(boxAt(state, line(1)), (from: 2, to: 5, done: false));
      expect(boxAt(state, line(2) + 4)!.from, line(2) + 4);
      expect(boxAt(state, line(2) + 4)!.done, isTrue);
      expect(boxAt(state, line(3))!.from, line(3) + 3);
      expect(boxAt(state, line(3))!.done, isTrue);
      expect(boxAt(state, line(4)), isNull);
      expect(boxAt(state, line(5)), isNull);
    });

    test('finds no box where the editor draws none: brackets glued to the words, or a link whose words are "x"', () {
      // A tap on either used to write into the brackets, turning `[x](…)`'s words into a space.
      final state = EditorState.create(doc: '- [ ]milk\n- [x](https://example.com/x)\n- [ ]');
      int line(int n) => state.doc.line(n).from;
      expect(boxAt(state, line(1)), isNull);
      expect(boxAt(state, line(2)), isNull);
      // An empty to-do is still one, while its words are being typed.
      expect(boxAt(state, line(3))!.from, line(3) + 2);
      expect(boxAt(state, line(3))!.done, isFalse);
    });

    test('ticks an empty box and clears a ticked one, touching nothing else, as one edit', () {
      var state = EditorState.create(doc: '- [ ] milk [notion](https://notion.so/x) ^milk');
      final tr = toggleBox(state, boxAt(state, 0)!);
      expect(tr.isUserEvent('input'), isTrue);
      state = tr.state;
      expect(state.doc.toString(), '- [x] milk [notion](https://notion.so/x) ^milk');
      state = toggleBox(state, boxAt(state, 0)!).state;
      expect(state.doc.toString(), '- [ ] milk [notion](https://notion.so/x) ^milk');
      final upper = EditorState.create(doc: '- [X] done');
      expect(toggleBox(upper, boxAt(upper, 0)!).state.doc.toString(), '- [ ] done');
    });
  });

  group('a box that is also a card', () {
    final note = <String>['```board', 'To do: milk, eggs', 'Done: bread', '```', '', '- [ ] Milk ^milk', '- [ ] Eggs ^eggs', '- [x] Bread ^bread', ''].join('\n');
    String tick(String doc, int line) {
      final state = EditorState.create(doc: doc);
      return toggleBox(state, boxAt(state, state.doc.line(line).from)!).state.doc.toString();
    }

    test('moves its card to Done when the box is ticked in the list, as one edit', () {
      final after = tick(note, 6);
      expect(after, contains('To do: eggs\nDone: bread, milk'));
      expect(after, contains('- [x] Milk ^milk'));
    });

    test('takes the card out of Done when the box is cleared, back to the first lane', () {
      final after = tick(note, 8);
      expect(after, contains('To do: milk, eggs, bread\nDone:'));
      expect(after, contains('- [ ] Bread ^bread'));
    });

    test('settles cards that had drifted at the same time, and leaves a board with no Done lane alone', () {
      // The note Matt had: ticked items still sitting in To do, drawn in Done but not written there.
      final drifted = <String>['```board', 'To do: milk, eggs', 'Done:', '```', '', '- [ ] Milk ^milk', '- [x] Eggs ^eggs', ''].join('\n');
      expect(tick(drifted, 6), contains('To do:\nDone: milk, eggs'));
      final noDone = <String>['```board', 'To do: milk', 'Next: eggs', '```', '', '- [ ] Milk ^milk', '- [x] Eggs ^eggs', ''].join('\n');
      expect(tick(noDone, 6), contains('To do: milk\nNext: eggs'));
    });

    test('leaves the fence alone for an item that is not on a board', () {
      final plain = <String>['```board', 'To do: milk', 'Done:', '```', '', '- [ ] Milk ^milk', '- [ ] Loose ^loose', ''].join('\n');
      expect(tick(plain, 7), contains('To do: milk\nDone:'));
    });
  });

  group('a box that is not a card yet', () {
    test('joins its list’s board in Done, anchor and all, as one edit', () {
      final note = <String>['```board', 'To do: milk', 'Done:', '```', '', '- [ ] Milk ^milk', '- [ ] Bread', ''].join('\n');
      final state = EditorState.create(doc: note);
      final after = toggleBox(state, boxAt(state, state.doc.line(7).from)!).state.doc.toString();
      // The line gains its name, the box is ticked, and the card lands in Done: one tap, one undo.
      expect(after, contains('- [x] Bread ^bread'));
      expect(after, contains('To do: milk\nDone: bread'));
    });

    test('leaves an item alone when its list has nothing on a board', () {
      final note = <String>['```board', 'To do: milk', 'Done:', '```', '', '- [ ] Milk ^milk', '', '## Later', '', '- [ ] Bread', ''].join('\n');
      final state = EditorState.create(doc: note);
      final after = toggleBox(state, boxAt(state, state.doc.line(10).from)!).state.doc.toString();
      expect(after, contains('- [x] Bread'));
      expect(after, isNot(contains('^bread')));
      expect(after, contains('To do: milk\nDone:'));
    });
  });
}
