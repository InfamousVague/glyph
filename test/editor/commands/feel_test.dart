// What the hand is allowed to say: `src/app/editor/feel.test.ts`, case for case.
//
// These run without a Taptic Engine, which is the entire reason `feelOf` is a pure function separate from the
// firing. Every case types the LAST character of a construct into a document that already holds the rest, because
// that is the moment the app claims to recognise and the only one worth a taptic.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/feel.dart';
import 'package:ghost_md/editor/commands/syntax_tree.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/syntax/language.dart';

// The web's cases parse with `markdown({base: markdownLanguage})`, plain GFM: so do these.
EditorState stateOf(String doc) => EditorState.create(doc: doc, extensions: commandParser.of(markdownLanguage));

/// Type `insert` at the end of `before` and return the resulting transaction.
Transaction type(String before, String insert) => stateOf(before).update(
  TransactionSpec(
    changes: ChangeSpec(from: before.length, insert: insert),
    selection: EditorSelection.single(before.length + insert.length),
    userEvent: 'input.type',
  ),
);

void main() {
  group('feelOf', () {
    test('ticks when a bold mark closes', () {
      expect(feelOf(type('**bold*', '*')), FeelKind.mark);
    });

    test('ticks when italic, code and strikethrough close', () {
      expect(feelOf(type('_soft', '_')), FeelKind.mark);
      expect(feelOf(type('`code', '`')), FeelKind.mark);
      expect(feelOf(type('~~gone~', '~')), FeelKind.mark);
    });

    test('says nothing for the OPENING half of a mark', () {
      expect(feelOf(type('a *', '*')), isNull);
    });

    test('says nothing for ordinary characters', () {
      expect(feelOf(type('hello worl', 'd')), isNull);
    });

    // The marker character, not the space after it. The grammar promotes the line as soon as the `#` lands - which
    // is also when it visibly grows - so waiting for the space would put the buzz a character behind the eye.
    test('is heavier for a heading than for other blocks', () {
      expect(feelOf(type('', '#')), FeelKind.heading);
      expect(feelOf(type('', '>')), FeelKind.block);
      expect(feelOf(type('', '-')), FeelKind.block);
      expect(feelOf(type('--', '-')), FeelKind.block);
      expect(feelOf(type('``', '`')), FeelKind.block);
    });

    test('does not re-announce a block that was already there', () {
      // The space after "#" does not make a second heading, and neither does typing the heading's actual text.
      expect(feelOf(type('#', ' ')), isNull);
      expect(feelOf(type('# Titl', 'e')), isNull);
    });

    // The case a regex cannot get right, and the reason this is a tree comparison: inside a fenced code block `**`
    // is two asterisks, no mark is created, and a text-matching implementation would buzz anyway.
    test('stays silent inside a fenced code block', () {
      expect(feelOf(type('```\n**bold*', '*')), isNull);
    });

    test('stays silent while an IME is composing', () {
      const before = '**bold*';
      final tr = stateOf(before).update(
        const TransactionSpec(changes: ChangeSpec(from: before.length, insert: '*'), userEvent: 'input.type.compose'),
      );
      expect(feelOf(tr), isNull);
    });

    test('says nothing for a transaction that changed no text', () {
      expect(feelOf(stateOf('**bold**').update(TransactionSpec(selection: EditorSelection.single(2)))), isNull);
    });

    // Enter in a list: the markdown keymap writes the newline and the next marker in one insert, a to-do's box too,
    // in a quote or not. Texture rather than news, but still felt.
    test('feels a list continuing itself onto the next line', () {
      Transaction continued(String before, String insert) =>
          stateOf(before).update(TransactionSpec(changes: ChangeSpec(from: before.length, insert: insert), userEvent: 'input'));
      expect(feelOf(continued('- milk', '\n- ')), FeelKind.continued);
      expect(feelOf(continued('1. milk', '\n2. ')), FeelKind.continued);
      expect(feelOf(continued('- [ ] milk', '\n- [ ] ')), FeelKind.continued);
      expect(feelOf(continued('> - milk', '\n> - ')), FeelKind.continued);
      // A plain newline, or a line of words after it, is not a list continuing.
      expect(feelOf(continued('- milk', '\n')), isNull);
      expect(feelOf(continued('- milk', '\neggs')), isNull);
    });

    test('reads the app’s own parser the same way when the state names none', () {
      // Not in the web's file: the default parser (no Setext headings, the app's) answers the same for these.
      Transaction plain(String before, String insert) => EditorState.create(doc: before).update(
        TransactionSpec(
          changes: ChangeSpec(from: before.length, insert: insert),
          selection: EditorSelection.single(before.length + insert.length),
          userEvent: 'input.type',
        ),
      );
      expect(feelOf(plain('**bold*', '*')), FeelKind.mark);
      expect(feelOf(plain('', '#')), FeelKind.heading);
      expect(feelOf(plain('Para\n--', '-')), FeelKind.block);
    });
  });

  group('what each is felt as', () {
    test('a mark closing as a tick, a heading heavier, any other block light, and a list continuing as the lightest', () {
      final calls = <String>[];
      void feel(Transaction tr) => feelTransaction(tr, fireFelt: calls.add, fireMicroTick: () => calls.add('tick'));
      feel(type('**bold*', '*'));
      feel(type('', '#'));
      feel(type('', '>'));
      feel(stateOf('- milk').update(const TransactionSpec(changes: ChangeSpec(from: 6, insert: '\n- '), userEvent: 'input')));
      feel(type('hello worl', 'd'));
      expect(calls, <String>['selection', 'medium', 'light', 'tick']);
    });
  });
}
