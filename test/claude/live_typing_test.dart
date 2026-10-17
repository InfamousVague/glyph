// Claude typing into an open note (lib/claude/live_typing.dart) at the pace of lib/claude/typing_pacer.dart: the
// words go in a word at a time as the frames come, the caret and the scrolling go with the words let in, Stop and a
// closed note let the rest out at once, the person's typing meanwhile moves Claude along, and the note ends with
// exactly what Claude wrote.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/live_typing.dart';
import 'package:ghost_md/claude/typing_pacer.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart' show WispKind, wisp;
import 'package:ghost_md/editor/view/editor_view.dart';

const Duration _frame = Duration(milliseconds: 16);

/// What Claude writes in these tests: about 330 letters, more than a reader's pace types in the two seconds a
/// stream may run ahead.
final String _words = List<String>.generate(30, (i) => 'word$i and').join(' ');

/// A note's editor with Claude's caret field, and every change Claude made in it.
({EditorView view, List<Transaction> typed, List<int> scrolled}) _note(String doc) {
  final typed = <Transaction>[];
  final scrolled = <int>[];
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: Extension.list(<Extension>[
        claudeTyping,
        EditorViewLike.updateListener.of((update) {
          for (final tr in update.transactions) {
            if (tr.isUserEvent('claude.type') && tr.docChanged) typed.add(tr);
            for (final effect in tr.effects) {
              final target = EditorViewLike.scrollIntoViewEffect.cast(effect);
              if (target != null) scrolled.add(target.value.range.head);
            }
          }
        }),
      ]),
    ),
  );
  addTearDown(view.destroy);
  return (view: view, typed: typed, scrolled: scrolled);
}

Future<void> _frames(WidgetTester tester, Duration total) async {
  for (var gone = Duration.zero; gone < total; gone += _frame) {
    await tester.pump(_frame);
  }
}

void main() {
  group('Claude typing at a reader\'s pace', () {
    testWidgets('puts the words in a word at a time as the frames come, the caret and the scrolling with them', (tester) async {
      final note = _note('# Plan\n');
      var smoky = true;
      final typer = NoteTyper(note.view, follow: () => true, smoke: () => smoky, open: () => true);
      typer.begin(note.view.state.doc.length);
      // The whole of it handed over at once, as a burst from the stream.
      typer.type(_words);
      await _frames(tester, const Duration(milliseconds: 500));
      final doc = note.view.state.doc.toString();
      final inSoFar = doc.length - '# Plan\n'.length;
      // Some, not all, and whole words only.
      expect(inSoFar, greaterThan(0));
      expect(inSoFar, lessThan(_words.length));
      expect(doc, '# Plan\n${_words.substring(0, inSoFar)}');
      expect(_words[inSoFar - 1], ' ');
      // Claude's caret, and the scrolling, are at the end of what was let in, not of what the stream gave.
      expect(claudeCaretOf(note.view.state), doc.length);
      expect(note.scrolled.last, doc.length);
      // Every change is Claude's, out of the light smoke, a word or so at a time.
      expect(note.typed.every((tr) => tr.annotation(wisp) == WispKind.typed), isTrue);
      expect(note.typed.length, greaterThan(5));
      smoky = false;
      // Within the two seconds it may fall behind, all of it is in.
      await _frames(tester, pacerMostBehind + const Duration(milliseconds: 300));
      expect(note.view.state.doc.toString(), '# Plan\n$_words');
      expect(claudeCaretOf(note.view.state), note.view.state.doc.length);
      expect(note.typed.last.annotation(wisp), isNull);
      await typer.end();
    });

    testWidgets('ends with exactly what Claude wrote, however the stream cut it, the last word let go as the call ends', (tester) async {
      final note = _note('');
      final typer = NoteTyper(note.view, follow: () => false, smoke: () => false, open: () => true);
      typer.begin(0);
      final words = 'Ünïcode 🎉 words,\n\n- [ ] a task\n- and a link https://example.com/a/very/long/path/with/no/spaces/at/all ending';
      for (var i = 0; i < words.length; i += 7) {
        typer.type(words.substring(i, i + 7 > words.length ? words.length : i + 7));
        await tester.pump(_frame);
      }
      var ended = false;
      typer.end().then((_) => ended = true);
      await _frames(tester, const Duration(seconds: 3));
      expect(ended, isTrue);
      expect(note.view.state.doc.toString(), words);
      expect(typer.whole, isTrue);
    });

    testWidgets('puts the rest in at once on Stop', (tester) async {
      final note = _note('');
      final typer = NoteTyper(note.view, follow: () => true, smoke: () => true, open: () => true);
      typer.begin(0);
      typer.type(_words);
      await _frames(tester, const Duration(milliseconds: 200));
      expect(note.view.state.doc.length, lessThan(_words.length));
      typer.flush();
      expect(note.view.state.doc.toString(), _words);
      expect(claudeCaretOf(note.view.state), _words.length);
      await typer.drained();
    });

    testWidgets('keeps what is left for the tool to write behind the note when it is closed under Claude', (tester) async {
      final note = _note('');
      var open = true;
      final typer = NoteTyper(note.view, follow: () => true, smoke: () => true, open: () => open);
      typer.begin(0);
      typer.type(_words);
      await _frames(tester, const Duration(milliseconds: 300));
      final typed = note.view.state.doc.toString();
      expect(typed.length, lessThan(_words.length));
      open = false;
      // Within a quarter second of the frames the typer sees it, and lets the rest go at once.
      await _frames(tester, const Duration(milliseconds: 320));
      expect(typer.whole, isFalse);
      expect(note.view.state.doc.toString().length, lessThan(_words.length));
      final there = note.view.state.doc.toString();
      expect(there + typer.left, _words);
      expect(typer.lastAt, there.length);
      await typer.drained();
    });

    testWidgets('goes on where Claude was when the person types above it while it types', (tester) async {
      final note = _note('Top\n');
      final typer = NoteTyper(note.view, follow: () => true, smoke: () => false, open: () => true);
      typer.begin(note.view.state.doc.length);
      typer.type(_words);
      await _frames(tester, const Duration(milliseconds: 400));
      note.view.dispatch(const TransactionSpec(changes: Change(from: 0, insert: 'Mine. '), userEvent: 'input.type'));
      await _frames(tester, const Duration(milliseconds: 400));
      note.view.dispatch(const TransactionSpec(changes: Change(from: 0, insert: 'More. '), userEvent: 'input.type'));
      final ending = typer.end();
      await _frames(tester, const Duration(seconds: 3));
      await ending;
      expect(note.view.state.doc.toString(), 'More. Mine. Top\n$_words');
    });
  });
}
