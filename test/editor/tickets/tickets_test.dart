// A ticket drawn in its note (lib/editor/tickets/tickets.dart; docs/DESIGN.md §157): its front matter as a panel in
// place of the folded keys, stepping aside for the lines when the caret is in them; a property written as the
// smallest change; and a `[[GHO-12]]` drawn with its ticket's title. `src/app/editor/tickets.test.ts`, case for
// case.
//
// What is asked differently: a title after a key is a piece a word here (the library says why), so a case reads
// the title off the first piece, which holds it whole for a screen reader, and its colour off its dot.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:ghost_md/editor/view/extended.dart' show frontMatterFolded;
import 'package:ghost_md/editor/view/plugin.dart';

import '../../support/render.dart';
import 'support.dart';

const TicketChoice cookie = TicketChoice(key: 'GHO-9', title: 'Fix the session cookie', status: 'In review', category: StatusCategory.doing);
const TicketChoice shipped = TicketChoice(key: 'GHO-3', title: 'Ship the beta', status: 'Done', category: StatusCategory.done);

const String ticket = '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\nblocked-by: "[[GHO-9]]"\nauthors: Matt\n---\n# Fix the login loop\n\nSee [[GHO-9]], [[GHO-3]] and [[GHO-404]].';

TicketOptions options([List<TicketChoice> found = const <TicketChoice>[cookie, shipped]]) => optionsWith(found, people: const <String>['Sam', 'Priya']);

/// The titles drawn after keys: each one's words and its category, off its first piece.
List<(String, StatusCategory)> titles(WidgetTester tester) => <(String, StatusCategory)>[
  for (final word in tester.widgetList<KeyTitleWord>(find.byType(KeyTitleWord)))
    if (word.piece.first) (word.piece.title, word.piece.category),
];

void main() {
  setUpAll(loadAppFonts);

  group('a ticket’s panel', () {
    testWidgets('draws the front matter as the ticket’s properties, in place of the folded keys', (tester) async {
      final view = await pumpTickets(tester, ticket, options: options());
      expect(panel, findsOneWidget);
      expect(frontMatterFolded(view.state), isFalse);
      final words = wordsOf(tester, panel).replaceAll('\n', '');
      expect(words, contains('GHO-12'));
      expect(words, contains('In progress'));
      expect(words, contains('Sam'));
      // What it waits on first, with a lock; the keys a ticket does not have on the quiet line.
      expect(words, contains('Waiting onGHO-9Fix the session cookie'));
      expect(words, contains('authors'));
      // The words under it as they are.
      expect(shownLines(tester, view), contains('Fix the login loop'));
    });

    testWidgets('leaves a note that is not a ticket folded as it was, and a ticket too where no tickets were given', (tester) async {
      final plain = await pumpTickets(tester, '---\ntitle: "A note"\nauthors: Matt\n---\n# A note', options: options());
      expect(panel, findsNothing);
      expect(frontMatterFolded(plain.state), isTrue);
      final bare = await pumpTickets(tester, ticket);
      expect(panel, findsNothing);
      expect(frontMatterFolded(bare.state), isTrue);
    });

    testWidgets('steps aside for the lines when the caret is in them, and comes back when it leaves', (tester) async {
      final view = await pumpTickets(tester, ticket, options: options());
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(4)));
      await tester.pump();
      expect(panel, findsNothing);
      // The front matter's eight lines, as they are written.
      expect(shownLines(tester, view).split('\n').take(8).join('\n'), ticket.split('\n').take(8).join('\n'));
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length)));
      await tester.pump();
      expect(panel, findsOneWidget);
    });

    testWidgets('opens the lines from its button, the caret on the first key', (tester) async {
      final view = await pumpTickets(tester, ticket, options: options());
      await tester.tap(said('Show the properties as text').first);
      await tester.pump();
      expect(view.state.doc.lineAt(view.state.selection.main.head).text, 'type: ticket');
      expect(panel, findsNothing);
    });

    testWidgets('is read, with nothing to pick, where the note cannot be edited', (tester) async {
      await pumpTickets(tester, ticket, options: options(), readOnly: true);
      expect(panel, findsOneWidget);
      expect(said(RegExp('Change it')), findsNothing);
      expect(said(RegExp('^Change ')), findsNothing);
      expect(said('Show the properties as text'), findsNothing);
    });
  });

  group('a property written', () {
    testWidgets('is one change, the smallest, with the caret where it was and the key in the case the note wrote it', (tester) async {
      final changes = <String>[];
      final view = await pumpTickets(
        tester,
        '---\ntype: ticket\nStatus: To do\n---\n# Login\n\nWords.',
        options: options(),
        more: <Extension>[
          EditorViewLike.updateListener.of((update) {
            for (final tr in update.transactions) {
              tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) => changes.add('$fromA-$toA:$inserted'));
            }
          }),
        ],
      );
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length)));
      changes.clear();
      writeProperty(view, 'status', 'Done');
      expect(view.state.doc.toString(), '---\ntype: ticket\nStatus: Done\n---\n# Login\n\nWords.');
      expect(changes, <String>['25-30:Done']);
      expect(view.state.selection.main.head, view.state.doc.length);
      writeProperty(view, 'priority', 'high');
      expect(view.state.doc.toString(), '---\ntype: ticket\nStatus: Done\npriority: high\n---\n# Login\n\nWords.');
      writeProperty(view, 'priority', null);
      expect(view.state.doc.toString(), '---\ntype: ticket\nStatus: Done\n---\n# Login\n\nWords.');
      await tester.pump();
    });
  });

  group('a key as a link', () {
    testWidgets('is drawn with its ticket’s title and its status’s colour, struck once done, and a key no ticket has is left alone', (tester) async {
      await pumpTickets(tester, ticket, options: options());
      expect(titles(tester), <(String, StatusCategory)>[('Fix the session cookie', StatusCategory.doing), ('Ship the beta', StatusCategory.done)]);
      // Struck once done, and only then.
      final struck = <String, bool>{
        for (final word in tester.widgetList<KeyTitleWord>(find.byType(KeyTitleWord)))
          word.piece.title: tester.widget<Text>(find.descendant(of: find.byWidget(word), matching: find.byType(Text))).style!.decoration == TextDecoration.lineThrough,
      };
      expect(struck, <String, bool>{'Fix the session cookie': false, 'Ship the beta': true});
      // Every word of a title is drawn, in order.
      expect(<String>[for (final word in tester.widgetList<KeyTitleWord>(find.byType(KeyTitleWord))) if (word.piece.title == 'Ship the beta') word.piece.word], <String>['Ship', 'the', 'beta']);
    });

    testWidgets('is drawn again when the library’s tickets change', (tester) async {
      var now = cookie;
      final given = TicketOptions(statuses: () => defaultStatuses, people: () => const <String>[], choices: () => const <TicketChoice>[], find: (target) => target == 'GHO-9' ? now : null, open: (_) {});
      final view = await pumpTickets(tester, 'See [[GHO-9]].', options: given);
      expect(titles(tester).single.$2, StatusCategory.doing);
      now = const TicketChoice(key: 'GHO-9', title: 'Fix the session cookie', status: 'Done', category: StatusCategory.done);
      view.dispatch(TransactionSpec(effects: refreshTickets.of(null)));
      await tester.pump();
      expect(titles(tester).single.$2, StatusCategory.done);
    });
  });
}
