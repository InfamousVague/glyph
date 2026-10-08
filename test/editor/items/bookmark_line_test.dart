// The bookmark written in the note (lib/editor/items/bookmark_line.dart): `src/app/editor/bookmarkLine.test.ts`,
// case for case.
//
// What is asked differently: the ribboned lines are the lines given the `cm-bookmarked` line decoration;
// `markedWords` takes the state here, where the page's took the view.
//
// Left out, as the Dart file's header says: the ribbon is the kit's own bookmark icon, so there is no path copied
// from lucide to hold to the button's ("is the same shape as the Bookmark button draws") and no lucide classes on an
// `<svg>` ("wears lucide’s classes…"). In their place the last group checks the signs are drawn as the ribbon widget.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/bookmark_line.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

final String doc = <String>['# Launch week', '', '- [ ] Write the *pricing* page ^pricing-page', '', '   ', 'A line of ordinary words that runs on well past the room a toast has'].join('\n');

EditorView editor([String? text]) {
  final view = EditorView(wholeDocument: true, state: EditorState.create(doc: text ?? doc, extensions: bookmarkRibbon()));
  addTearDown(view.destroy);
  return view;
}

/// The line decorations of the bookmark: each one's line (from 1) and its classes.
List<({int line, List<String> classes})> ribbons(EditorView on) {
  final found = <({int line, List<String> classes})>[];
  for (final set in on.decorations) {
    set.between(0, on.state.doc.length, (from, to, value) {
      final classes = (value.spec.className ?? '').split(' ');
      if (value is LineDecoration && classes.contains('cm-bookmarked')) found.add((line: on.state.doc.lineAt(from).number, classes: classes));
      return null;
    });
  }
  return found;
}

/// Which lines carry the ribbon, counting from 1.
List<int> ribboned(EditorView on) => <int>[for (final ribbon in ribbons(on)) ribbon.line];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the bookmark shown in the note', () {
    test('marks nothing until a place is given, then the line that place is on', () {
      final on = editor();
      expect(ribboned(on), isEmpty);
      on.dispatch(TransactionSpec(effects: showBookmark.of(on.state.doc.line(3).from + 4)));
      expect(ribboned(on), <int>[3]);
    });

    test('comes off again, and holds a place past the end of the note', () {
      final on = editor();
      on.dispatch(TransactionSpec(effects: showBookmark.of(on.state.doc.line(3).from)));
      on.dispatch(TransactionSpec(effects: showBookmark.of(null)));
      expect(ribboned(on), isEmpty);
      on.dispatch(TransactionSpec(effects: showBookmark.of(9999)));
      expect(ribboned(on), <int>[6]);
    });

    test('stays on its words when the note is typed into above them', () {
      final on = editor();
      on.dispatch(TransactionSpec(effects: showBookmark.of(on.state.doc.line(3).from)));
      on.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'A first line\n')));
      expect(ribboned(on), <int>[4]);
    });
  });

  group('the words a bookmark sits on', () {
    test('says them without the marks that shape them', () {
      final on = editor();
      expect(markedWords(on.state, on.state.doc.line(1).from), 'Launch week');
      expect(markedWords(on.state, on.state.doc.line(3).from), 'Write the pricing page');
    });

    test('looks past blank lines, and cuts a long line short', () {
      final on = editor();
      expect(markedWords(on.state, on.state.doc.line(4).from), 'A line of ordinary words that…');
      expect(markedWords(editor('   \n\n').state, 0), isNull);
    });

    test('takes any list item’s box off, and its anchor wherever the item keeps it (core/itemSyntax.ts)', () {
      final on = editor('1. [ ] Book the cabin\n- ( ) Tent ^tent\n- [ ] Pack ^pack [3/8]');
      expect(markedWords(on.state, on.state.doc.line(1).from), 'Book the cabin');
      expect(markedWords(on.state, on.state.doc.line(2).from), 'Tent');
      expect(markedWords(on.state, on.state.doc.line(3).from), 'Pack [3/8]');
    });
  });

  group('a place on a blank line', () {
    test('ribbons the next line that has words, so the mark is where the words are', () {
      final on = editor();
      on.dispatch(TransactionSpec(effects: showBookmark.of(on.state.doc.line(2).from)));
      expect(ribboned(on), <int>[3]);
      expect(markedWords(on.state, on.state.doc.line(2).from), 'Write the pricing page');
    });

    // `- ` and `- [ ] ` were always passed over; the rest were kept before core/itemSyntax.ts, and said back as "[ ]"
    // or "^a".
    test('passes over a list item with no words yet, whatever its box, to the next line that has words', () {
      for (final empty in <String>['- ', '- [ ] ', '- [ ]', '* [x]', '1. [ ]', '1. [ ] ', '- ( )', '- ^a', '- [ ] ^a']) {
        final state = EditorState.create(doc: '$empty\nThe next words');
        expect(markedLine(state, 0), 2, reason: '"$empty"');
      }
      final on = editor('- [ ]\nThe next words');
      expect(markedWords(on.state, 0), 'The next words');
      // With nothing after it that has words, the place stays where it was.
      expect(markedLine(EditorState.create(doc: '- [ ]\n\n'), 0), 1);
    });
  });

  group('the bookmark written in the note', () {
    String put(String doc, int? line) {
      final state = EditorState.create(doc: doc);
      return state.update(placeBookmark(state, line)).state.doc.toString();
    }

    test('goes at the end of a line, and before a list item’s mark, counter and anchor', () {
      expect(put('The deposit is four hundred.', 1), 'The deposit is four hundred. §§');
      expect(put('- [ ] Ship it [notion](https://notion.so/a) ^ship-it', 1), '- [ ] Ship it §§ [notion](https://notion.so/a) ^ship-it');
      expect(put('- Water [3/8]', 1), '- Water §§ [3/8]');
    });

    test('moves from wherever it was, keeping one, and comes off with null', () {
      const doc = 'One line §§\nTwo line\n- [ ] Three §§ ^three';
      expect(put(doc, 2), 'One line\nTwo line §§\n- [ ] Three ^three');
      expect(put(doc, 3), 'One line\nTwo line\n- [ ] Three §§ ^three');
      expect(put(doc, null), 'One line\nTwo line\n- [ ] Three ^three');
      expect(bookmarkLineIn('a\nb §§\nc'), 2);
      expect(bookmarkLineIn('a § b'), isNull);
    });
  });

  group('the bookmark drawn on the page', () {
    // In place of the two cases about lucide's path and classes: the signs, and the space before them, are drawn as
    // the one ribbon widget, whose icon is the kit's.
    test('is the ribbon in place of its signs', () {
      final view = editor('Marked here §§');
      final drawn = <({int from, int to})>[];
      for (final set in view.decorations) {
        set.between(0, view.state.doc.length, (from, to, value) {
          if (value.widget is RibbonWidget) drawn.add((from: from, to: to));
          return null;
        });
      }
      expect(drawn, <({int from, int to})>[(from: 'Marked here'.length, to: 'Marked here §§'.length)]);
    });

    test('sits in a line wearing the gold, which ink.css works out against that line’s own paper', () {
      final view = editor('Marked here §§');
      expect(ribbons(view).single.line, 1);
      expect(ribbons(view).single.classes, contains('app-gold'));
    });
  });
}
