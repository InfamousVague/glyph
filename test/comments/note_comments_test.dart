// The note's comments on its screen (lib/comments/ui/note_comments.dart): the cases of "comments on the note" in
// `src/app/editor/NoteScreen.test.tsx`, in its order, held on the piece itself: a real editor with the comments
// drawn in it, the [ScreenComments] a desk makes, and its sheet. Where each way in is put on the screen (the band,
// the bar, More) is the screen's and the desk's (test/root/comments_test.dart).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/comments/ask.dart';
import 'package:ghost_md/comments/colours.dart';
import 'package:ghost_md/comments/ui/note_comments.dart';
import 'package:ghost_md/comments/ui/sheet.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/editor/comments/comments.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/format_looks.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/marks.dart';
import 'package:glacier/glacier.dart';

import '../sidebar/support.dart';
import '../support/render.dart';

final RegExp anchor = RegExp(r'\[\^(c[0-9a-z]{4})\]');

/// A note on a screen with its comments: the editor, what was said, and the comments themselves.
class Desk {
  Desk(this.view, this.comments, this.said);
  final EditorView view;
  final ScreenComments comments;
  final List<String> said;

  String get doc => view.state.doc.toString();
}

Future<Desk> pumpNote(WidgetTester tester, String doc, {bool readOnly = false, CommentAsks? asks, CommentColours? colours}) async {
  final said = <String>[];
  late final EditorView view;
  final comments = ScreenComments(noteId: 'n1', view: () => view, say: said.add, colours: () => colours ?? commentColours(orgId: null), asks: asks);
  view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(formats: marks, readOnly: readOnly, more: <Extension>[history(), formatLooks(marks), noteComments(() => comments.hooks)]),
    ),
  );
  addTearDown(view.destroy);
  addTearDown(comments.dispose);
  view.focusRequest = () => view.setFocused(true);
  await pumpPage(
    tester,
    BackScope(
      child: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('app-paper'),
          child: Stack(
            children: [
              Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view)))),
              ListenableBuilder(listenable: comments, builder: (context, _) => comments.sheet(context) ?? const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return Desk(view, comments, said);
}

/// Writes `words` in the open sheet's field and sends them with the button called `send`.
Future<void> write(WidgetTester tester, String words, String send) async {
  await tester.enterText(find.byType(EditableText), words);
  await tester.pump();
  await tester.tap(find.byWidgetPredicate((widget) => widget is GlacierPressable && widget.semanticLabel == send));
  await tester.pump();
  await tester.pump();
}

List<String> saidOn(WidgetTester tester, Finder under) => [for (final element in find.descendant(of: under, matching: find.byType(RichText)).evaluate()) (element.widget as RichText).text.toPlainText()];

void main() {
  setUpAll(loadAppFonts);

  final sheet = find.byType(CommentSheet);

  group('comments on the note (docs/SHARED.md, S8)', () {
    testWidgets('starts one on the caret’s line, writes it as one change, and one undo takes it back', (tester) async {
      final desk = await pumpNote(tester, '# Plan\n\nBook the barn');
      desk.view.dispatch(TransactionSpec(selection: EditorSelection.single(desk.view.state.doc.length)));
      desk.comments.start();
      await tester.pump();
      await settle(tester);
      expect(desk.comments.page, const NewPage(null));
      expect(find.bySemanticsLabel('New comment'), findsWidgets);
      await write(tester, 'Which barn?', 'Add comment');
      expect(desk.comments.page, isNull);
      expect(sheet, findsNothing);
      final id = anchor.firstMatch(desk.doc)!.group(1)!;
      // By `me`, with no account on this device, at a time to the second in UTC.
      expect(desk.doc, matches(RegExp('^# Plan\\n\\nBook the barn\\[\\^$id\\]\\n\\n```comments\\n$id me \\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ\\nWhich barn\\?\\n```\\n\$')));
      // Drawn: the round where the anchor is, the fence as its list.
      expect(find.bySemanticsLabel('Comment by You'), findsOneWidget);
      expect(saidOn(tester, find.byType(DrawnComments)), contains('Which barn?'));
      undo(desk.view);
      await tester.pump();
      expect(desk.doc, '# Plan\n\nBook the barn');
      await away(tester);
    });

    testWidgets('starts one round the selection the band held, the words quoted in the card', (tester) async {
      final desk = await pumpNote(tester, '# Plan\n\nBook the barn for Saturday');
      final from = desk.doc.indexOf('the barn');
      desk.comments.start((from: from, to: from + 'the barn'.length));
      await tester.pump();
      await settle(tester);
      expect(desk.comments.page, const NewPage('the barn'));
      expect(saidOn(tester, sheet), contains('the barn'));
      await write(tester, 'Which one?', 'Add comment');
      expect(desk.view.state.doc.line(3).text, matches(RegExp(r'^Book ==the barn==\[\^c[0-9a-z]{4}\] for Saturday$')));
      await away(tester);
    });

    testWidgets('quotes the first line of a selection over several, with an ellipsis', (tester) async {
      final desk = await pumpNote(tester, 'One line\nand another');
      desk.comments.start((from: 0, to: desk.doc.length));
      await tester.pump();
      expect(desk.comments.page, const NewPage('One line…'));
      await away(tester);
    });

    testWidgets('opens the card from the round, and replies, resolves, reopens and deletes through it', (tester) async {
      const body = '# Plan\n\nThe ==venue==[^c1] is booked.\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall or the barn?\n```\n';
      final desk = await pumpNote(tester, body);
      await tester.tap(find.bySemanticsLabel('Comment by sam'));
      await tester.pump();
      await settle(tester);
      expect(desk.comments.page, const ThreadPage('c1'));
      expect(find.bySemanticsLabel('Comment thread'), findsWidgets);
      expect(saidOn(tester, sheet), containsAllInOrder(['venue', 'The hall or the barn?']));
      await write(tester, 'The hall.', 'Send reply');
      expect(desk.doc, matches(RegExp(r'The hall or the barn\?\n {2}me \S+Z\n {2}The hall\.\n```')));
      expect(saidOn(tester, sheet), contains('The hall.'));
      await tester.tap(find.descendant(of: sheet, matching: find.text('Resolve')));
      await tester.pump();
      await tester.pump();
      expect(desk.doc, matches(RegExp(r'\n {2}resolved me \S+Z\n```')));
      expect(saidOn(tester, sheet).join('\n'), contains('Resolved by You'));
      await tester.tap(find.descendant(of: sheet, matching: find.text('Reopen')));
      await tester.pump();
      await tester.pump();
      expect(desk.doc, isNot(contains('resolved')));
      await tester.ensureVisible(find.descendant(of: sheet, matching: find.text('Delete thread')));
      await tester.tap(find.descendant(of: sheet, matching: find.text('Delete thread')));
      await tester.pump();
      // Asked once more before it goes.
      expect(desk.doc, contains('```comments'));
      await tester.tap(find.descendant(of: sheet, matching: find.text('Delete it? Press again')));
      await tester.pump();
      await tester.pump();
      expect(desk.doc, '# Plan\n\nThe venue is booked.\n');
      expect(sheet, findsNothing);
      expect(desk.said, [commentDeleted]);
      // Undo puts it back, as the toast says.
      undo(desk.view);
      expect(desk.doc, contains('```comments\nc1 sam'));
      await away(tester);
    });

    testWidgets('says how many there are and how many are open, and the list opens a thread', (tester) async {
      const body = '# Plan[^c2]\n\nThe ==venue==[^c1]\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall?\nc2 sam 2026-10-04T19:01:00Z\nName?\n  resolved sam 2026-10-04T19:02:00Z\n```\n';
      final desk = await pumpNote(tester, body);
      expect(desk.comments.summary(), '2 comments, 1 open');
      desk.comments.openList();
      await tester.pump();
      await settle(tester);
      expect(find.bySemanticsLabel('Comments'), findsWidgets);
      await tester.tap(find.descendant(of: sheet, matching: find.byKey(const ValueKey<String>('thread c2'))));
      await tester.pump();
      await settle(tester);
      expect(desk.comments.page, const ThreadPage('c2'));
      expect(saidOn(tester, sheet).join('\n'), contains('Resolved by sam'));
      // Back to the list, where there is more than one.
      await tester.tap(find.text('All comments'));
      await tester.pump();
      expect(desk.comments.page, const ListPage());
      await away(tester);
      expect((await pumpNote(tester, 'No comments here')).comments.summary(), isNull);
      await away(tester);
    });

    testWidgets('starts one on the title line when a note’s menu asked for it, and the note keeps its name', (tester) async {
      final asks = CommentAsks()..ask('n1');
      final desk = await pumpNote(tester, '---\nlook: reading\n---\n# Plan\n\nwords', asks: asks);
      desk.comments.takeAsk();
      await tester.pump();
      await settle(tester);
      expect(desk.comments.page, const NewPage(null));
      expect(asks.value, isNull);
      await write(tester, 'Better name?', 'Add comment');
      expect(desk.view.state.doc.line(4).text, matches(RegExp(r'^# Plan\[\^c[0-9a-z]{4}\]$')));
      expect(noteTitle(desk.doc), 'Plan');
      // Taken once: the next look finds nothing waiting.
      desk.comments.takeAsk();
      expect(desk.comments.page, isNull);
      await away(tester);
    });

    testWidgets('leaves an ask for another note where it is', (tester) async {
      final asks = CommentAsks()..ask('other');
      final desk = await pumpNote(tester, 'words', asks: asks);
      desk.comments.takeAsk();
      expect(desk.comments.page, isNull);
      expect(asks.value?.noteId, 'other');
      await away(tester);
    });

    testWidgets('says why where a comment cannot go: a note that cannot be written in, and the comments themselves', (tester) async {
      final locked = await pumpNote(tester, 'words', readOnly: true);
      locked.comments.start();
      expect(locked.said, [commentRefused]);
      expect(locked.comments.page, isNull);
      await away(tester);
      const body = 'Words[^c1]\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall?\n```\n';
      final desk = await pumpNote(tester, body);
      final inside = body.indexOf('The hall?');
      desk.comments.start((from: inside, to: inside));
      expect(desk.said, [commentMisplaced]);
      expect(desk.comments.page, isNull);
      await away(tester);
    });

    testWidgets('reads an open card’s thread again when the note changes under it', (tester) async {
      const body = 'Words[^c1]\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall?\n```\n';
      final desk = await pumpNote(tester, body);
      desk.comments.hooks.open('c1');
      await tester.pump();
      await settle(tester);
      // Another member's reply, arriving as a change to the note.
      final at = body.indexOf('```\n', body.indexOf('```comments') + 3);
      desk.view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: '  kit 2026-10-04T19:03:00Z\n  The barn.\n')));
      await tester.pump();
      await tester.pump();
      expect(saidOn(tester, sheet), containsAllInOrder(['The hall?', 'kit', 'The barn.']));
      await away(tester);
    });

    testWidgets('draws the rounds again when the colours change, and not when they have not', (tester) async {
      const body = 'Words[^c1]\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall?\n```\n';
      var wears = commentColours(orgId: 'org', theirs: const {'sam': null});
      late final Desk desk;
      desk = await pumpNote(tester, body, colours: null);
      // The desk's own colours are asked each time: held here by a controller of the test's own.
      final comments = ScreenComments(noteId: 'n1', view: () => desk.view, say: (_) {}, colours: () => wears);
      addTearDown(comments.dispose);
      var refreshed = 0;
      desk.view.dispatch(TransactionSpec(effects: StateEffect.appendConfig.of(EditorViewLike.updateListener.of((update) {
        if (update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(refreshComments)))) refreshed += 1;
      }))));
      comments.recolour();
      expect(refreshed, 1);
      comments.recolour();
      expect(refreshed, 1);
      wears = commentColours(orgId: 'org', theirs: const {'sam': 'sea'});
      comments.recolour();
      expect(refreshed, 2);
      expect(comments.hooks.colour('sam'), 'sea');
      await away(tester);
    });

    test('finds the line a note is called by: its first words after its front matter', () {
      expect(titleLine('# Plan\n\nwords'), 1);
      expect(titleLine('\n\n# Plan'), 3);
      expect(titleLine('---\nlook: reading\n---\n# Plan\n\nwords'), 4);
      expect(titleLine('---\nlook: reading\n---\n'), 4);
      expect(titleLine(''), 1);
    });
  });
}
