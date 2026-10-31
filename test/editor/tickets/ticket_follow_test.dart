// A ticket's team parts in its panel (lib/editor/tickets/ticket_follow.dart; Matt, 2026-10-31): Watch and Unwatch,
// the history three at a time with Show all, the possible duplicates and Merge into… (behind More in simple mode), a
// closed duplicate's Undo merge, Add sub-ticket's duplicate hints, and the editor writing its watchers as it is
// written (lib/editor/tickets/tickets.dart `autoWatch`), one Undo taking both back. On a phone and on a Mac's width.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_history.dart';
import 'package:ghost_md/book/ticket_watchers.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/queries/query_look.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

const TicketChoice loop = TicketChoice(key: 'GHO-1', title: 'Login loops after signing in', status: 'In progress', category: StatusCategory.doing);
const TicketChoice docs = TicketChoice(key: 'GHO-14', title: 'Write the docs', status: 'To do', category: StatusCategory.todo);

const String front = '---\ntype: ticket\nid: GHO-12\nstatus: In review\nassignee: sam\nwatchers: ["@sam"]\n---';

const int hour = 3600000;
const int now = 100 * hour;

final List<TicketChange> changes = [
  const TicketChange(at: 90 * hour, by: 'matt', key: 'type', from: null, to: 'ticket'),
  const TicketChange(at: 91 * hour, by: 'matt', key: 'assignee', from: null, to: 'sam'),
  const TicketChange(at: 95 * hour, by: 'sam', key: 'status', from: 'To do', to: 'In progress'),
  const TicketChange(at: 97 * hour, by: 'sam', key: 'due', from: null, to: '2026-11-06'),
  const TicketChange(at: 98 * hour, by: 'sam', key: 'status', from: 'In progress', to: 'In review'),
];

late List<(String, Object?)> written;
late List<String> opened;
late List<TicketChoice> merged;
bool simple = false;
bool undone = false;

TicketOptions options({String? me = 'matt', bool closed = false, List<TicketChange>? history}) => TicketOptions(
  statuses: () => defaultStatuses,
  people: () => const ['sam'],
  choices: () => const [loop, docs],
  find: (target) => const [loop, docs].where((choice) => choice.key == target.toUpperCase()).firstOrNull,
  open: opened.add,
  addSubTicket: (_) {},
  follow: TicketFollow(
    me: () => me,
    history: () async => history ?? changes,
    duplicates: () => closed ? const [] : const [(ticket: loop, shared: ['login', 'loop'])],
    similar: (title) => title.toLowerCase().contains('login') ? const [(ticket: loop, shared: ['login'])] : const [],
    merge: merged.add,
    undoMerge: () => closed ? () => undone = true : null,
    simple: () => simple,
    now: () => now,
  ),
);

Future<void> draw(WidgetTester tester, {String front = front, TicketOptions? given, double width = 390, bool editable = true}) async {
  await pumpApp(
    tester,
    size: Size(width, 1200),
    home: Builder(
      builder: (context) => BackScope(
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: TicketPanel(look: QueryLook.of(context, null), front: front, options: given ?? options(), editable: editable, today: '2026-10-31', locale: 'en-GB', write: (key, value) => written.add((key, value)), openLines: () {}),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  debugDisableShadows = true;
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}


void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    written = [];
    opened = [];
    merged = [];
    simple = false;
    undone = false;
  });

  for (final (where, width) in [('a phone', 390.0), ('a Mac', 1100.0)]) {
    group('on $where', () {
      testWidgets('Watch adds you to its watchers and Unwatch takes you off, as front matter', (tester) async {
        await draw(tester, width: width);
        expect(find.bySemanticsLabel('Watched by sam'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('ticket-watch')));
        await settle(tester);
        expect(written.single.$1, 'watchers');
        expect(written.single.$2, ['@sam', '@matt']);
        written.clear();
        await draw(tester, front: front.replaceFirst('["@sam"]', '["@sam", "@matt"]'), width: width);
        expect(find.bySemanticsLabel('Watched by sam, You'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('ticket-unwatch')));
        await settle(tester);
        expect(written.single.$2, ['@sam']);
        written.clear();
        await draw(tester, front: front.replaceFirst('["@sam"]', '["@matt"]'), width: width);
        await tester.tap(find.byKey(const ValueKey('ticket-unwatch')));
        await settle(tester);
        expect((written.single.$1, written.single.$2), ('watchers', null), reason: 'the last watcher takes the key with them');
      });

      testWidgets('the history shows the three newest with when, and Show all the rest', (tester) async {
        await draw(tester, width: width);
        expect(find.bySemanticsLabel('sam moved it In progress → In review, 2 hr ago'), findsOneWidget);
        expect(find.bySemanticsLabel('sam set the due date to 2026-11-06, 3 hr ago'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('^You created it')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('ticket-history-all')));
        await settle(tester);
        expect(find.bySemanticsLabel(RegExp('^You created it')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('^You assigned it to sam')), findsOneWidget);
      });

      testWidgets('possible duplicates open, and Merge into… picks the ticket to merge it into', (tester) async {
        await draw(tester, width: width);
        expect(find.bySemanticsLabel('Possible duplicate: GHO-1  Login loops after signing in'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('duplicate:GHO-1')));
        await settle(tester);
        expect(opened, ['GHO-1']);
        await tester.tap(find.byKey(const ValueKey('ticket-merge-into')));
        await settle(tester);
        expect(find.byKey(const ValueKey('merge-target-sheet')), findsOneWidget);
        expect(find.text('Likely duplicate · login, loop'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('merge-target:GHO-1')));
        await settle(tester);
        expect(merged.single.key, 'GHO-1');
        expect(find.byKey(const ValueKey('merge-target-sheet')), findsNothing);
      });
    });
  }

  testWidgets('in simple mode the watchers and history show, and the merge tools wait behind More', (tester) async {
    simple = true;
    await draw(tester);
    expect(find.bySemanticsLabel('Watched by sam'), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-history-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-merge-into')), findsNothing);
    expect(find.byKey(const ValueKey('ticket-follow-more')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ticket-follow-more')));
    await settle(tester);
    expect(find.byKey(const ValueKey('ticket-merge-into')), findsOneWidget);
    expect(find.byKey(const ValueKey('duplicate:GHO-1')), findsOneWidget);
  });

  testWidgets('a duplicate closed by a merge says what it duplicates, and Undo merge takes it back', (tester) async {
    await draw(tester, front: '---\ntype: ticket\nid: GHO-12\nstatus: Done\nduplicate-of: "[[GHO-1]]"\n---', given: options(closed: true));
    expect(find.text('Duplicate of GHO-1'), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-merge-into')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ticket-undo-merge')));
    await settle(tester);
    expect(undone, isTrue);
  });

  testWidgets('signed out there is no Watch, and a panel that cannot be edited changes nothing', (tester) async {
    await draw(tester, given: options(me: null));
    expect(find.byKey(const ValueKey('ticket-watch')), findsNothing);
    expect(find.bySemanticsLabel('Watched by sam'), findsOneWidget);
    await draw(tester, editable: false);
    expect(find.byKey(const ValueKey('ticket-watch')), findsNothing);
    expect(find.byKey(const ValueKey('ticket-merge-into')), findsNothing);
  });

  testWidgets('Add sub-ticket says what the title typed may duplicate, a tap away', (tester) async {
    await draw(tester);
    await tester.tap(said('Add sub-ticket'));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'Login is broken');
    await settle(tester);
    expect(find.byKey(const ValueKey('duplicate-hint:GHO-1')), findsOneWidget);
    expect(find.text('Shares login'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duplicate-hint:GHO-1')));
    await settle(tester);
    expect(opened, ['GHO-1']);
  });

  group('the editor writes its watchers as it is written', () {
    const ticket = '---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Fix the login loop\n\nIt loops.\n';
    EditorState start([String doc = ticket]) => EditorState.create(doc: doc, extensions: Extension.list(<Extension>[history(), tickets(() => TicketOptions(statuses: () => defaultStatuses, people: () => const [], choices: () => const [], find: (_) => null, open: (_) {}, follow: TicketFollow(me: () => 'matt')))]));

    test('a comment written makes its writer a watcher in the same change, and one Undo takes both back', () {
      var state = start();
      const comment = 'It loops.[^c1]\n\n```comments\nc1 ana 2026-10-31T09:00:00Z\nOnly on Safari.\n```\n';
      final at = ticket.indexOf('It loops.');
      state = state.update(TransactionSpec(changes: ChangeSpec(from: at, to: ticket.length, insert: comment), userEvent: 'input.comment')).state;
      expect(watchersOf(state.doc.toString()), ['ana']);
      final target = StateCommandTarget(state, (tr) => state = tr.state);
      expect(undo(target), isTrue);
      expect(state.doc.toString(), ticket, reason: 'one step back: the comment and its watcher');
    });

    test('a name being typed waits; a name finished is a watcher; an assignee picked from the panel is one', () {
      var state = start();
      final end = ticket.length;
      state = state.update(TransactionSpec(changes: ChangeSpec(from: end, insert: 'Ask @sa'), selection: EditorSelection.single(end + 7), userEvent: 'input.type')).state;
      expect(watchersOf(state.doc.toString()), isEmpty);
      state = state.update(TransactionSpec(changes: ChangeSpec(from: end + 7, insert: 'm '), selection: EditorSelection.single(end + 9), userEvent: 'input.type')).state;
      expect(watchersOf(state.doc.toString()), ['sam']);
      final doc = state.doc.toString();
      final picked = withProperty(doc, 'assignee', 'zed');
      var from = 0;
      while (doc.codeUnitAt(from) == picked.codeUnitAt(from)) {
        from += 1;
      }
      state = state.update(TransactionSpec(changes: ChangeSpec(from: from, insert: picked.substring(from, from + picked.length - doc.length)), userEvent: propertyUserEvent)).state;
      expect(watchersOf(state.doc.toString()), ['sam', 'zed']);
    });

    test('a note that is no ticket, another device’s change and an undo are left as they are', () {
      var state = start('# Plain\n');
      state = state.update(TransactionSpec(changes: ChangeSpec(from: 8, insert: 'Ask @sam about it.\n'), userEvent: 'input.type')).state;
      expect(state.doc.toString(), '# Plain\nAsk @sam about it.\n');
      var team = start();
      team = team.update(TransactionSpec(changes: ChangeSpec(from: ticket.length, insert: 'Ask @sam about it.\n'), annotations: Transaction.remote.of(true))).state;
      expect(watchersOf(team.doc.toString()), isEmpty);
    });
  });
}
