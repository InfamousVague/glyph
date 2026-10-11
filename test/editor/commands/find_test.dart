// Find and replace (lib/editor/commands/find.dart): `src/app/editor/find.test.ts`, case for case. What the web
// reads off the page (the marks' classes) is the view's; everything else is the state's and is here.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/find.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/history.dart';
import 'package:ghost_md/editor/state/state.dart';

import 'support.dart';

void main() {
  group('find and replace', () {
    test('finds every match, case forgiven, never overlapping', () {
      expect(<int>[for (final m in matchesIn('Friday, friday, FRIDAY', 'friday')) m.from], <int>[0, 8, 16]);
      expect(<int>[for (final m in matchesIn('aaaa', 'aa')) m.from], <int>[0, 2]);
      expect(matchesIn('anything', ''), isEmpty);
    });

    test('makes the first match after the caret current, and keeps finding as the words change', () {
      final state = EditorState.create(doc: 'milk, eggs, milk, bread, milk', extensions: findExtension());
      final found = state.update(TransactionSpec(effects: setFind.of((query: 'milk', near: 7)))).state;
      expect(findOf(found).matches.length, 3);
      expect(findOf(found).current, 1);
      // One replaced by hand: the search follows, one fewer.
      final edited = found.update(const TransactionSpec(changes: ChangeSpec(from: 0, to: 4, insert: 'oat'))).state;
      expect(findOf(edited).matches.length, 2);
    });

    test('replaces every match in one change', () {
      final state = EditorState.create(doc: 'milk, eggs, milk', extensions: findExtension());
      final found = state.update(TransactionSpec(effects: setFind.of((query: 'milk', near: null)))).state;
      final changes = <ChangeSpec>[for (final m in findOf(found).matches) ChangeSpec(from: m.from, to: m.to, insert: 'oat milk')];
      final replaced = found.update(TransactionSpec(changes: changes)).state;
      expect(replaced.doc.toString(), 'oat milk, eggs, oat milk');
    });
  });

  group('the find bar’s commands on a note', () {
    // What the find bar drives: a search, the arrows, Replace, Replace all and Done.
    const doc = 'milk, eggs, Milk, bread, milk';

    TestView open([int caret = 0]) => TestView.of(doc, caret, null, <Extension>[findExtension(), history()]);
    int? current(TestView on) => currentMatch(on.state)?.from;

    test('marks every match and makes the first one at or after the caret current', () {
      final on = open(7);
      on.dispatch(search(on.state, 'milk'));
      expect(findOf(on.state).matches, hasLength(3));
      expect(current(on), 12);
      // The web counts two `cm-findMatch` and reads "Milk" in `cm-findCurrent`: the same, from the state.
      final match = currentMatch(on.state)!;
      expect(on.state.sliceDoc(match.from, match.to), 'Milk');
    });

    test('steps through the matches either way, wrapping round at each end', () {
      final on = open();
      on.dispatch(search(on.state, 'milk'));
      expect(current(on), 0);
      on.dispatch(step(on.state, -1));
      expect(current(on), 25);
      on.dispatch(step(on.state, 1));
      expect(current(on), 0);
      on.dispatch(step(on.state, 1));
      on.dispatch(step(on.state, 1));
      on.dispatch(step(on.state, 1));
      expect(current(on), 0);
    });

    test('replaces the current match and moves on to the next', () {
      final on = open(7);
      on.dispatch(search(on.state, 'milk'));
      replaceOne(on.state, 'oat milk').forEach(on.dispatch);
      expect(on.text, 'milk, eggs, oat milk, bread, milk');
      // Past what was just written, so its own "milk" is not found and replaced again.
      expect(current(on), on.text.lastIndexOf('milk'));
    });

    test('replaces them all as one change, one undo taking it back, and says how many', () {
      final on = open();
      on.dispatch(search(on.state, 'milk'));
      final all = replaceAll(on.state, 'oats');
      on.dispatch(all.tr);
      expect(all.count, 3);
      expect(all.tr!.isUserEvent('input.replace.all'), isTrue);
      expect(on.text, 'oats, eggs, oats, bread, oats');
      on.undo_();
      expect(on.text, doc);
      on.dispatch(search(on.state, 'cheese'));
      final none = replaceAll(on.state, 'x');
      expect(none.count, 0);
      expect(none.tr, isNull);
      expect(step(on.state, 1), isNull);
      expect(replaceOne(on.state, 'x'), isEmpty);
      expect(on.text, doc);
    });

    test('ends with no marks and the current match selected, so the note picks up where the search left it', () {
      final on = open();
      on.dispatch(search(on.state, 'bread'));
      on.dispatch(endSearch(on.state));
      expect(findOf(on.state).matches, isEmpty);
      expect(on.selected, 'bread');
    });

    test('is empty in a note that cannot be searched', () {
      // Not in the web's file: `findOf` on a state without the field.
      expect(findOf(EditorState.create(doc: doc)).current, -1);
    });
  });
}
