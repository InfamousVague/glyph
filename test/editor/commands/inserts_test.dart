// Where the things the + beside the line adds go (lib/editor/commands/inserts.dart), read back with the app's own
// parser: a thing drawn on a line of its own never lands inside the list, quote or table above it, a block never
// takes the next line of words as its own, words go where the caret is with the spaces a sentence needs, and every
// insert is one Undo. `src/app/editor/inserts.test.ts`, case for case; what the web tests of the page (focus
// taken back, the spy on dispatch, `afterComposition`) is said where it is left out.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/inserts.dart';
import 'package:ghost_md/editor/commands/syntax_tree.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/history.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/syntax/tree.dart';

import 'support.dart';

const String picture = '![](image/x.jpg)';
const String place = '[Cais](geo:38.7057,-9.1446)';

EditorState stateOf(String doc, [int? caret, bool withHistory = true]) => EditorState.create(
  doc: doc,
  selection: EditorSelection.single(caret ?? doc.length),
  extensions: Extension.list(<Extension>[if (withHistory) history(), insertSpots]),
);

TestView viewOf(String doc, [int? caret]) => TestView(stateOf(doc, caret));

/// The doc after a plan, and where the caret went.
({String doc, int caret, String selected}) after(EditorState state, Plan plan) {
  final next = state.update(TransactionSpec(changes: plan.changes, selection: plan.editorSelection)).state;
  final main = next.selection.main;
  return (doc: next.doc.toString(), caret: main.head, selected: next.sliceDoc(main.from, main.to));
}

/// The top-level block holding `needle`, and every block around it, as the app's parser reads the doc.
List<String> blocksAround(String doc, String needle) => chainAt(doc, doc.indexOf(needle) + 1);

void outsideBlocks(String doc, String needle) {
  final chain = blocksAround(doc, needle);
  expect(chain, isNot(contains('ListItem')), reason: '$doc: ${chain.join(' < ')}');
  expect(chain, isNot(contains('Blockquote')));
  expect(chain, isNot(contains('Table')));
  expect(chain, contains('Paragraph'));
}

/// Reserves a place on a view, as the web's `reserveSpot(view)` does in one call.
int reserve(TestView view, [int? pos]) {
  final kept = reserveSpot(view.state, pos);
  view.dispatch(kept.tr);
  return kept.spot;
}

/// The web's `insertLineAt(view, ...)`: the line, then a kept place at its start.
int insertLine(TestView view, int spot, String text, {String? userEvent, bool fresh = true, bool apart = false}) {
  final landed = insertLineAt(view.state, spot, text, userEvent: userEvent, fresh: fresh, apart: apart);
  view.dispatch(landed.tr);
  return reserve(view, landed.lineStart);
}

void main() {
  group('a line that gives way', () {
    test('is one with nothing on it but a lead', () {
      for (final line in <String>['', '  ', '- ', '- [ ] ', '3. ', '> ', '- ( ) ']) {
        expect(givesWay(line), isTrue, reason: line);
      }
    });

    test('is never one with words, a bookmark or an anchor, which an insert would lose', () {
      for (final line in <String>['words', '- [ ] milk', '- §§', '- [ ] ^anchor']) {
        expect(givesWay(line), isFalse, reason: line);
      }
    });
  });

  group('a thing on a line of its own', () {
    test('takes an empty line under a paragraph, and leaves the caret on a fresh line after it', () {
      final state = stateOf('Trip\n\nMore', 5);
      final out = after(state, ownLinePlan(state, 5, picture));
      expect(out.doc, 'Trip\n$picture\n\nMore');
      expect(out.caret, 'Trip\n$picture\n'.length);
    });

    test('goes under a line with words, never splitting it', () {
      final state = stateOf('Book the cabin by Friday', 8);
      expect(after(state, ownLinePlan(state, 8, picture)).doc, 'Book the cabin by Friday\n$picture\n');
    });

    test('takes an empty to-do under an item whole, with a blank line so it is not the list’s', () {
      const doc = '- [ ] milk\n- [ ] ';
      final state = stateOf(doc);
      final out = after(state, ownLinePlan(state, doc.length, picture)).doc;
      expect(out, '- [ ] milk\n\n$picture\n');
      outsideBlocks(out, picture);
    });

    test('takes an empty middle item, ending the list there and starting it again after', () {
      const doc = '- a\n- \n- b';
      final state = stateOf(doc, 6);
      final out = after(state, ownLinePlan(state, 6, picture)).doc;
      expect(out, '- a\n\n$picture\n\n- b');
      outsideBlocks(out, picture);
    });

    test('goes under a to-do with words outside it', () {
      const doc = '- [ ] buy milk';
      final state = stateOf(doc, 4);
      final out = after(state, ownLinePlan(state, 4, place)).doc;
      expect(out, '- [ ] buy milk\n\n$place\n');
      outsideBlocks(out, place);
    });

    test('goes under a quote outside it', () {
      const doc = '> quote';
      final state = stateOf(doc);
      final out = after(state, ownLinePlan(state, doc.length, place)).doc;
      outsideBlocks(out, place);
    });

    test('takes an empty quote line, outside the quote', () {
      const doc = '> quote\n> ';
      final state = stateOf(doc);
      final out = after(state, ownLinePlan(state, doc.length, place)).doc;
      expect(out, '> quote\n\n$place\n');
      outsideBlocks(out, place);
    });

    test('on the empty line under a table is not a row of it', () {
      const doc = '| a | b |\n| --- | --- |\n| c | d |\n';
      final state = stateOf(doc);
      final out = after(state, ownLinePlan(state, doc.length, picture)).doc;
      outsideBlocks(out, picture);
    });

    test('keeps apart from a paragraph above when it is a link, a place, so no reader runs it into the sentence', () {
      const doc = 'Lunch at the harbour\n';
      final state = stateOf(doc);
      final out = after(state, ownLinePlan(state, doc.length, place, apart: true));
      expect(out.doc, 'Lunch at the harbour\n\n$place\n');
      expect(out.caret, out.doc.length);
      final tree = syntaxTree(stateOf(out.doc));
      SyntaxNode? node = tree.resolveInner(out.doc.indexOf(place) + 1, 1);
      while (node != null && node.name != 'Paragraph') {
        node = node.parent;
      }
      expect(node?.from, out.doc.indexOf(place));
      // Under a line of words that the caret is on, too; and a picture keeps to the line under the words.
      final words = stateOf('Lunch', 2);
      expect(after(words, ownLinePlan(words, 2, place, apart: true)).doc, 'Lunch\n\n$place\n');
      expect(after(state, ownLinePlan(state, doc.length, picture)).doc, 'Lunch at the harbour\n$picture\n');
    });

    test('keeps out of a list item whose words run on to a line of their own', () {
      // The second line has no lead: only the parser says it is still the item's.
      const doc = '- milk\nand eggs\n';
      final state = stateOf(doc);
      final out = after(state, ownLinePlan(state, doc.length, picture)).doc;
      expect(out, '- milk\nand eggs\n\n$picture\n');
      outsideBlocks(out, picture);
    });

    test('keeps a bookmarked or anchored empty item, and goes under it', () {
      const doc = '- [ ] ^anchor';
      final state = stateOf(doc);
      expect(after(state, ownLinePlan(state, doc.length, picture)).doc, '- [ ] ^anchor\n\n$picture\n');
    });
  });

  group('a block', () {
    const table = '| Column | Column |\n| --- | --- |\n| Cell | Cell |';

    test('before a line of words leaves a blank line, so the words are not a row', () {
      const doc = 'Para\n\nnext words';
      final state = stateOf(doc, 5);
      final out = after(state, blockPlan(state, 5, table, const BlockSelect.at(2, 8)));
      expect(out.doc, 'Para\n\n$table\n\nnext words');
      expect(out.selected, 'Column');
      final chain = blocksAround(out.doc, 'next words');
      expect(chain, isNot(contains('TableRow')));
      expect(chain, contains('Paragraph'));
    });

    test('under a paragraph on the next line gets a blank line before it, for other readers', () {
      const doc = 'Para\n';
      final state = stateOf(doc);
      expect(after(state, blockPlan(state, doc.length, '---', const BlockSelect.at(3))).doc, 'Para\n\n---');
    });

    test('takes an empty list item whole', () {
      const doc = '- a\n- ';
      final state = stateOf(doc);
      final out = after(state, blockPlan(state, doc.length, table, const BlockSelect.at(2, 8))).doc;
      expect(out, '- a\n\n$table');
    });

    test('after a line of words goes after it, a blank line first', () {
      const doc = 'Words here';
      final state = stateOf(doc, 3);
      expect(after(state, blockPlan(state, 3, '---', const BlockSelect.at(3))).doc, 'Words here\n\n---');
    });

    test('can leave the caret on a fresh line after it', () {
      const doc = 'A\n\n\nB';
      final state = stateOf(doc, 3);
      final out = after(state, blockPlan(state, 3, '---', const BlockSelect.after()));
      expect(out.doc, 'A\n\n---\n\nB');
      expect(out.caret, 'A\n\n---\n'.length);
    });
  });

  group('words at the caret', () {
    test('are spaced from the words either side', () {
      final state = stateOf('Met atthe harbour', 6);
      expect(after(state, wordsPlan(state, 6, '[[Lisbon]]')).doc, 'Met at [[Lisbon]] the harbour');
    });

    test('take a space after closing punctuation, and none on an empty line', () {
      var state = stateOf('Done.', 5);
      expect(after(state, wordsPlan(state, 5, '14:05')).doc, 'Done. 14:05');
      state = stateOf('- ', 2);
      expect(after(state, wordsPlan(state, 2, '14:05')).doc, '- 14:05');
    });

    test('leave the caret after them, or where the seed says', () {
      var state = stateOf('', 0);
      expect(after(state, wordsPlan(state, 0, '28 Sep 2026, 14:05')).caret, 18);
      state = stateOf('', 0);
      expect(after(state, wordsPlan(state, 0, '#tag', (from: 1, to: 4))).selected, 'tag');
    });
  });

  group('a to-do, and the other items', () {
    ({String doc, int caret, String selected}) todo(String doc, [int? caret]) {
      final state = stateOf(doc, caret);
      return after(state, itemPlan(state, caret ?? doc.length, ItemKind.todo));
    }

    test('turns an empty item’s lead into a to-do’s, keeping its indent and marker', () {
      expect(todo('- ').doc, '- [ ] ');
      expect(todo('3. ').doc, '3. [ ] ');
      expect(todo('  - ').doc, '  - [ ] ');
      expect(todo('- ( ) ').doc, '- [ ] ');
    });

    test('writes nothing on an empty to-do, and never a second box', () {
      final out = todo('- [ ] ');
      expect(out.doc, '- [ ] ');
      expect(out.caret, 6);
    });

    test('keeps a quote around it, and takes the indent of the item above on an empty line', () {
      expect(todo('> ').doc, '> - [ ] ');
      expect(todo('  - milk\n').doc, '  - milk\n  - [ ] ');
      expect(todo('').doc, '- [ ] ');
    });

    test('under a line of words starts a new item, keeping the quote and the indent', () {
      expect(todo('Para', 2).doc, 'Para\n- [ ] ');
      expect(todo('> quote', 3).doc, '> quote\n> - [ ] ');
      expect(todo('  - milk', 5).doc, '  - milk\n  - [ ] ');
    });

    test('makes a choice only after a bullet', () {
      final state = stateOf('3. ');
      expect(after(state, itemPlan(state, 3, ItemKind.choice)).doc, '- ( ) ');
    });

    test('numbers a new step after the one above', () {
      final state = stateOf('1. one\n2. two\n');
      expect(after(state, itemPlan(state, state.doc.length, ItemKind.number)).doc, '1. one\n2. two\n3. ');
    });

    test('turns an empty to-do into a plain item for a bulleted list', () {
      final state = stateOf('- [ ] ');
      expect(after(state, itemPlan(state, 6, ItemKind.bullet)).doc, '- ');
    });
  });

  group('a line’s form', () {
    String form(String doc, LineForm kind) {
      final state = stateOf(doc);
      return after(state, formPlan(state, doc.length, kind)).doc;
    }

    test('writes a heading, a quote and a sum on an empty line', () {
      expect(form('', LineForm.heading), '## ');
      expect(form('', LineForm.quote), '> ');
      expect(form('', LineForm.sum), '= ');
    });

    test('leaves an empty quote line a quote, and never nests another in it', () {
      expect(form('> ', LineForm.quote), '> ');
      expect(form('>', LineForm.quote), '>');
    });

    test('keeps a quote around a heading, and a list’s lead before a sum', () {
      expect(form('> ', LineForm.heading), '> ## ');
      expect(form('- ', LineForm.sum), '- = ');
      expect(form('- ', LineForm.heading), '## ');
    });
  });

  group('a footnote', () {
    test('puts the next number at the caret and its line at the end of the note, the caret there', () {
      const doc = 'Four hundred[^1]\n\nThen\n\n[^1]: Sam said so.';
      final state = stateOf(doc, 'Four hundred[^1]\n\nThen'.length);
      final out = after(state, footnotePlan(state, state.selection.main.head));
      expect(out.doc, 'Four hundred[^1]\n\nThen [^2]\n\n[^1]: Sam said so.\n[^2]: ');
      expect(out.caret, out.doc.length);
    });

    test('starts at 1, closing the words just above an empty line, with a blank line before its words', () {
      final state = stateOf('Words\n', 6);
      expect(after(state, footnotePlan(state, 6)).doc, 'Words[^1]\n\n[^1]: ');
      final apart = stateOf('Words\n\n', 7);
      expect(after(apart, footnotePlan(apart, 7)).doc, 'Words\n\n[^1]\n\n[^1]: ');
    });
  });

  group('one Undo for each', () {
    test('takes back the whole insert, and nothing typed before it', () {
      final view = viewOf('Typed');
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 5, insert: ' more'), userEvent: 'input.type'));
      final doc = view.text;
      view.dispatch(
        applyPlan(view.state, blockPlan(view.state, doc.length, '| Column | Column |\n| --- | --- |\n| Cell | Cell |', const BlockSelect.at(2, 8))),
      );
      view.undo_();
      expect(view.text, doc);
    });

    test('keeps what is typed straight after it a step of its own', () {
      final view = viewOf('Para\n');
      view.dispatch(applyPlan(view.state, itemPlan(view.state, view.state.doc.length, ItemKind.todo)));
      final end = view.state.doc.length;
      view.dispatch(
        TransactionSpec(changes: ChangeSpec(from: end, insert: 'milk'), selection: EditorSelection.single(end + 4), userEvent: 'input.type'),
      );
      view.undo_();
      expect(view.text, 'Para\n- [ ] ');
      view.undo_();
      expect(view.text, 'Para\n');
    });

    test('is the +’s own event, and scrolls only while the note has focus', () {
      // Not a case of the web's file: `apply`'s annotations, which the view and feel.dart read.
      final state = stateOf('Para\n');
      final plan = itemPlan(state, state.doc.length, ItemKind.todo);
      final quiet = applyPlan(state, plan);
      expect(quiet.isUserEvent('input.plus'), isTrue);
      expect(quiet.annotation(isolateHistory), 'full');
      expect(quiet.scrollIntoView, isFalse);
      expect(applyPlan(state, plan, hasFocus: true, userEvent: 'input.plus.drawn').scrollIntoView, isTrue);
    });
  });

  group('a line that arrives later', () {
    test('lands where the caret was when it was asked for, however the note changed', () {
      final view = viewOf('Lunch at the harbour\n', 21);
      final spot = reserve(view);
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'Day two\n')));
      insertLine(view, spot, place, userEvent: 'input.plus.drawn');
      expect(view.text, 'Day two\nLunch at the harbour\n$place\n');
      view.dispatch(releaseSpot(view.state, spot));
      expect(spotAt(view.state, spot), isNull);
    });

    test('leaves the caret alone once the person has moved on', () {
      final view = viewOf('One\n\nTwo', 4);
      final spot = reserve(view);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(1)));
      insertLine(view, spot, place, userEvent: 'input.plus.drawn');
      expect(view.head, 1);
    });

    test('with a stale focus token: no scroll, and a caret left on the line carried past it', () {
      // The web's case also holds that focus is not taken back, which is the view's to do with `fresh`.
      final view = viewOf('One\n\n', 5);
      final token = FocusToken()..moved(insideNote: false);
      final spot = reserve(view);
      final landed = insertLineAt(view.state, spot, place, userEvent: 'input.plus.drawn', fresh: token.fresh());
      view.dispatch(landed.tr);
      expect(view.text, 'One\n\n$place\n');
      // Left at the line's start, the first letter typed on coming back would go in front of the place and break it.
      expect(view.head, 'One\n\n$place\n'.length);
      expect(landed.tr.scrollIntoView, isFalse);
    });

    test('with a stale focus token leaves a caret the person put elsewhere where it is', () {
      final view = viewOf('One\n\nTwo', 4);
      final token = FocusToken()..moved(insideNote: false);
      final spot = reserve(view);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(3)));
      insertLine(view, spot, place, userEvent: 'input.plus.drawn', fresh: token.fresh(), apart: true);
      expect(view.head, 3);
    });

    test('counts a focus inside the note as the note’s, and one anywhere else as somewhere else', () {
      final token = FocusToken();
      token.moved(insideNote: true);
      expect(token.fresh(), isTrue);
      token.moved(insideNote: false);
      expect(token.fresh(), isFalse);
    });

    test('with a fresh token: the caret after it, scrolled to', () {
      // The web's case also holds that focus comes back once when the view had lost it: the view's.
      final view = viewOf('One\n\n', 5);
      final token = FocusToken();
      final spot = reserve(view);
      final landed = insertLineAt(view.state, spot, place, userEvent: 'input.plus.drawn', fresh: token.fresh());
      view.dispatch(landed.tr);
      expect(view.head, 'One\n\n$place\n'.length);
      expect(landed.tr.scrollIntoView, isTrue);
      expect(landed.lineStart, 'One\n\n'.length);
    });
  });

  group('a place’s name that comes late', () {
    const coords = '[38.7057, -9.1446](geo:38.7057,-9.1446)';
    const named = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';

    /// The place written with its coordinates, as the + writes it when no name came in time.
    ({TestView view, int spot, int depth}) written() {
      final view = viewOf('Lunch at the harbour\n', 21);
      final spot = reserve(view);
      final landed = insertLine(view, spot, coords, userEvent: 'input.plus.drawn');
      view.dispatch(releaseSpot(view.state, spot));
      return (view: view, spot: landed, depth: undoDepth(view.state));
    }

    bool name(TestView view, int spot, int depth) {
      final tr = nameLater(view.state, spot, depth, coords, named);
      view.dispatch(tr);
      return tr != null;
    }

    test('is written when nothing came between, and undoes in two clean steps', () {
      final w = written();
      expect(name(w.view, w.spot, w.depth), isTrue);
      expect(w.view.text, 'Lunch at the harbour\n$named\n');
      w.view.undo_();
      expect(w.view.text, 'Lunch at the harbour\n$coords\n');
      w.view.undo_();
      expect(w.view.text, 'Lunch at the harbour\n');
    });

    test('is written after a caret move, which is not a change', () {
      final w = written();
      w.view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      expect(name(w.view, w.spot, w.depth), isTrue);
    });

    test('is not written once the person typed, and the first Undo takes back the typing', () {
      final w = written();
      final end = w.view.state.doc.length;
      w.view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: 'Grilled sardines'), userEvent: 'input.type'));
      expect(name(w.view, w.spot, w.depth), isFalse);
      w.view.undo_();
      expect(w.view.text, 'Lunch at the harbour\n$coords\n');
    });

    test('is not written while an Undo waits to be redone', () {
      final w = written();
      final end = w.view.state.doc.length;
      w.view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: 'x'), userEvent: 'input.type'));
      w.view.undo_();
      expect(name(w.view, w.spot, w.depth), isFalse);
      w.view.redo_();
      expect(w.view.text, 'Lunch at the harbour\n$coords\nx');
    });

    test('keeps what is typed straight after it a step of its own', () {
      final w = written();
      expect(name(w.view, w.spot, w.depth), isTrue);
      // Right against the name, where CodeMirror would otherwise take the two as one change.
      final end = w.view.state.doc.length - 1;
      w.view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: ' at noon'), userEvent: 'input.type'));
      w.view.undo_();
      expect(w.view.text, 'Lunch at the harbour\n$named\n');
    });

    test('is never written into a note whose undo is not the editor’s own, as a note live on two devices is', () {
      final view = TestView(stateOf('Lunch at the harbour\n', 21, false));
      final landed = insertLine(view, reserve(view), coords, userEvent: 'input.plus.drawn');
      expect(name(view, landed, 0), isFalse);
      expect(view.text, 'Lunch at the harbour\n$coords\n');
    });

    test('is not written over a line that changed', () {
      final w = written();
      final at = w.view.text.indexOf('38.7057,');
      w.view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, to: at + 1, insert: '4')));
      expect(name(w.view, w.spot, undoDepth(w.view.state)), isFalse);
    });
  });

  // `afterComposition`'s two cases wait on the view's composition: the input layer's (lib/editor/input).
}
