// A thread's card, a new comment's field and the threads' list (lib/comments/ui/card.dart, sheet.dart):
// `src/app/editor/CommentCard.test.tsx`, case for case and in its order, drawn from parsed threads alone (the note's,
// here read from a fence, and a canvas's) and saying what was pressed. Then the sheet they are drawn in
// (`editor/CommentSheet.tsx`, which the page tested through its screens), and its pictures (shots/), looked at
// beside CommentCard.module.css.
//
// What is asked differently: a comment's colour is the hue its initial was drawn in, read from the disc's own
// ground where the page read `data-hue`; and a key is the test's own (Enter, with Shift held or not) where the page
// dispatched a `keydown`.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/comments/format.dart';
import 'package:ghost_md/comments/ui/card.dart';
import 'package:ghost_md/comments/ui/sheet.dart';
import 'package:ghost_md/core/back.dart';
import 'package:glacier/glacier.dart';

import '../sidebar/support.dart';
import '../support/render.dart';

final String fence = [
  '```comments',
  'c1 sam 2026-10-04T19:00:12Z',
  'The venue needs confirming - the hall or the barn?',
  '  matt 2026-10-04T19:05:40Z',
  '  The hall.',
  '  Confirmed this morning.',
  'c2 matt 2026-10-04T19:10:00Z',
  'Which band?',
  '  resolved sam 2026-10-04T19:12:00Z',
  '```',
].join('\n');

final List<CardThread> _threads = [for (final thread in readComments(fence).threads) cardThread(thread)];
final CardThread venue = _threads[0], band = _threads[1];
final CardPeople people = CardPeople(colour: (handle) => handle == 'sam' ? 'sea' : 'rose', me: 'matt');
final int now = DateTime.parse('2026-10-04T21:30:00Z').millisecondsSinceEpoch;

/// What a card was asked to do.
class Pressed {
  final List<String> replied = [];
  int resolved = 0, reopened = 0, deleted = 0;
}

/// A page with [child] on it, as wide as a phone's sheet is inside its gutters.
Widget onPage(Widget child) => BackScope(
      child: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('app-paper-2'),
          child: Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.all(20), child: SizedBox(width: 350, child: child))),
        ),
      ),
    );

Future<Pressed> pumpThread(WidgetTester tester, {CardThread? thread, String? quote}) async {
  final pressed = Pressed();
  await pumpPage(
    tester,
    onPage(
      CommentThread(
        thread: thread ?? venue,
        people: people,
        quote: quote,
        onReply: pressed.replied.add,
        onResolve: () => pressed.resolved += 1,
        onReopen: () => pressed.reopened += 1,
        onDelete: () => pressed.deleted += 1,
        now: now,
      ),
    ),
  );
  return pressed;
}

/// Everything drawn says, in order.
List<String> said(WidgetTester tester, [Finder? under]) => [
      for (final element in (under == null ? find.byType(RichText) : find.descendant(of: under, matching: find.byType(RichText))).evaluate()) (element.widget as RichText).text.toPlainText(),
    ];

/// The ground an initial is drawn on.
Color? discOf(WidgetTester tester, Finder initial) => ((tester.widget<Container>(find.descendant(of: initial, matching: find.byType(Container)).first).decoration as BoxDecoration?)?.color);

/// The field's send, by what it is called.
GlacierPressable sendOf(WidgetTester tester, String label) => tester.widget<GlacierPressable>(find.byWidgetPredicate((widget) => widget is GlacierPressable && widget.semanticLabel == label));

void main() {
  setUpAll(loadAppFonts);

  group('a thread’s card', () {
    testWidgets('shows each comment’s author in their colour, how long ago, and its words over several lines', (tester) async {
      await pumpThread(tester, quote: 'venue');
      final words = said(tester);
      expect(words, containsAllInOrder(['venue', 'S', 'sam', '2 hr ago', 'The venue needs confirming - the hall or the barn?', 'M', 'You', '2 hr ago', 'The hall.\nConfirmed this morning.']));
      final initials = find.byType(CommentInitial);
      expect(initials, findsNWidgets(2));
      final t = tester.element(initials.first).tokens;
      expect(discOf(tester, initials.at(0)), hued(t, 'sea').colorOf('color-mix(in oklch, var(--app-space) 22%, transparent)'));
      expect(discOf(tester, initials.at(1)), hued(t, 'rose').colorOf('color-mix(in oklch, var(--app-space) 22%, transparent)'));
      // Your own comment says You, and its reply sits in by a step.
      expect(tester.getTopLeft(initials.at(1)).dx - tester.getTopLeft(initials.at(0)).dx, closeTo(t.space(6), 0.01));
      await away(tester);
    });

    testWidgets('sends a reply on Enter, and keeps Shift+Enter for a new line', (tester) async {
      final pressed = await pumpThread(tester);
      final field = find.byType(EditableText);
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'Booked ');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(pressed.replied, isEmpty);
      expect(tester.widget<EditableText>(field).controller.text, 'Booked \n');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed.replied, ['Booked']);
      expect(tester.widget<EditableText>(field).controller.text, '');
      expect(sendOf(tester, 'Send reply').onPressed, isNull);
      await away(tester);
    });

    testWidgets('offers Resolve on an open thread and Reopen on a resolved one, saying who closed it', (tester) async {
      final open = await pumpThread(tester);
      await tester.tap(find.text('Resolve'));
      await tester.pump();
      expect(open.resolved, 1);
      await away(tester);
      final closed = await pumpThread(tester, thread: band);
      expect(said(tester), contains('Resolved by sam, 2 hr ago.'));
      await tester.tap(find.text('Reopen'));
      await tester.pump();
      expect(closed.reopened, 1);
      await away(tester);
    });

    testWidgets('deletes only on a second press, and forgets the first after four seconds', (tester) async {
      final pressed = await pumpThread(tester);
      await tester.tap(find.text('Delete thread'));
      await tester.pump();
      expect(pressed.deleted, 0);
      expect(find.text('Delete it? Press again'), findsOneWidget);
      expect(find.text('Its comments and its mark in the note go.'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 4000));
      await tester.pump();
      expect(find.text('Delete thread'), findsOneWidget);
      await tester.tap(find.text('Delete thread'));
      await tester.pump();
      await tester.tap(find.text('Delete it? Press again'));
      await tester.pump();
      expect(pressed.deleted, 1);
      await away(tester);
    });
  });

  group('a new comment and the list', () {
    testWidgets('focuses the new comment’s field, and adds only words', (tester) async {
      final saved = <String>[];
      await pumpPage(tester, onPage(NewComment(quote: 'the barn', onSave: saved.add)));
      await tester.pump();
      final field = find.byType(EditableText);
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      expect(said(tester), contains('the barn'));
      bool enabled() => sendOf(tester, 'Add comment').onPressed != null;
      expect(enabled(), isFalse);
      await tester.enterText(field, '   ');
      await tester.pump();
      expect(enabled(), isFalse);
      await tester.enterText(field, ' Which barn? ');
      await tester.pump();
      await tester.tap(find.byWidget(sendOf(tester, 'Add comment')));
      await tester.pump();
      expect(saved, ['Which barn?']);
      await away(tester);
    });

    testWidgets('lists the open threads first, with their replies, and opens the one pressed', (tester) async {
      final opened = <String>[];
      await pumpPage(tester, onPage(CommentList(threads: [band, venue], people: people, onOpen: opened.add, now: now)));
      final rows = [find.byKey(const ValueKey<String>('thread c1')), find.byKey(const ValueKey<String>('thread c2'))];
      expect(tester.getTopLeft(rows[0]).dy, lessThan(tester.getTopLeft(rows[1]).dy));
      expect(said(tester, rows[0]).join('\n'), allOf(contains('The venue needs confirming'), contains('1 reply')));
      expect(said(tester, rows[1]), contains('Resolved'));
      // A resolved thread keeps its words and goes quiet.
      expect(tester.widget<Opacity>(find.descendant(of: rows[1], matching: find.byType(Opacity)).first).opacity, 0.6);
      expect(tester.widget<Opacity>(find.descendant(of: rows[0], matching: find.byType(Opacity)).first).opacity, 1);
      await tester.tap(rows[1]);
      await tester.pump();
      expect(opened, ['c2']);
      await away(tester);
    });

    test('says a time it cannot read as it was written', () {
      expect(ago('yesterday'), 'yesterday');
      expect(ago('2026-10-04T21:29:30Z', now), 'Just now');
    });

    test('cuts a list’s first line at ninety characters, and names a person by "You" where it is them', () {
      expect(firstLine('one\ntwo'), 'one');
      final long = List.filled(30, 'word').join(' ');
      expect(firstLine(long), hasLength(lessThanOrEqualTo(90)));
      expect(firstLine(long), endsWith('…'));
      expect(nameOf('me', people), 'You');
      expect(nameOf('matt', people), 'You');
      expect(nameOf('sam', people), 'sam');
      // Your own initial is your handle's; with no handle it is You's.
      expect(CommentInitial.letterOf('matt', people), 'M');
      expect(CommentInitial.letterOf('me', people), 'Y');
      expect(CommentInitial.letterOf('sam', people), 'S');
    });
  });

  group('the sheet', () {
    Widget sheet(CommentPage page, {List<CardThread>? threads, ValueChanged<String>? onOpen, VoidCallback? onList, VoidCallback? onClose}) => BackScope(
          child: Stack(
            children: [
              CommentSheet(
                page: page,
                threads: threads ?? _threads,
                people: people,
                quoteOf: (id) => id == 'c1' ? 'venue' : null,
                onClose: onClose ?? () {},
                onOpen: onOpen ?? (_) {},
                onList: onList ?? () {},
                onAdd: (_) {},
                onReply: (_, _) {},
                onResolve: (_) {},
                onReopen: (_) {},
                onDelete: (_) {},
                now: now,
              ),
            ],
          ),
        );

    testWidgets('a thread, with the way back to the list where there are several', (tester) async {
      var listed = 0;
      await pumpPage(tester, sheet(const ThreadPage('c1'), onList: () => listed += 1));
      await settle(tester);
      expect(find.bySemanticsLabel('Comment thread'), findsWidgets);
      expect(said(tester), containsAllInOrder(['All comments', 'venue', 'sam', 'The venue needs confirming - the hall or the barn?', 'Resolve', 'Delete thread']));
      await tester.tap(find.text('All comments'));
      await tester.pump();
      expect(listed, 1);
      await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/sheet-thread.png'));
      await away(tester);
    });

    testWidgets('one thread alone has no way back, and one that has gone says so', (tester) async {
      await pumpPage(tester, sheet(const ThreadPage('c1'), threads: [venue]));
      await settle(tester);
      expect(find.text('All comments'), findsNothing);
      await away(tester);
      await pumpPage(tester, sheet(const ThreadPage('gone')));
      await settle(tester);
      expect(find.text('This thread is not in the note any more.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('the list, and what it says with no threads', (tester) async {
      final opened = <String>[];
      await pumpPage(tester, sheet(const ListPage(), onOpen: opened.add));
      await settle(tester);
      expect(said(tester).first, 'Comments');
      await tester.tap(find.byKey(const ValueKey<String>('thread c2')));
      await tester.pump();
      expect(opened, ['c2']);
      await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/sheet-list.png'));
      await away(tester);
      await pumpPage(tester, sheet(const ListPage(), threads: const []));
      await settle(tester);
      expect(find.text('No comments yet. Select some words, or put the caret on a line, and press Comment.'), findsOneWidget);
      await away(tester);
    });

    for (final theme in const ['light', 'dark']) {
      testWidgets('a resolved thread and a new comment, $theme', (tester) async {
        await pumpPage(tester, sheet(const ThreadPage('c2')), theme: theme);
        await settle(tester);
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/sheet-resolved-$theme.png'));
        await away(tester);
        await pumpPage(tester, sheet(const NewPage('the barn')), theme: theme);
        await settle(tester);
        expect(said(tester), containsAllInOrder(['New comment', 'the barn', 'Write a comment']));
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/sheet-new-$theme.png'));
        await away(tester);
      });
    }
  });
}
