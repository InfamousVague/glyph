import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/tickets/bulk.dart';
import 'package:ghost_md/tickets/ui/bulk_bar.dart';

import '../editor/queries/support.dart';
import '../support/render.dart';
import 'support.dart' show notes;

/// What the bar asked of the root.
class _Bulk {
  final List<(List<String>, BulkEdit)> edits = [];
  final List<(List<String>, String)> moves = [];
  final List<List<String>> trashed = [];

  BulkActions get actions => BulkActions(
    edit: (ids, edit) async => edits.add((ids, edit)),
    move: (ids, notebook) async => moves.add((ids, notebook)),
    trash: trashed.add,
    notebooks: () => const [(id: 'waitlist', title: 'Waitlist'), (id: 'launch', title: 'Launch')],
    labels: () => const ['bug', 'ui', 'email'],
    people: () => const ['Matt', 'Sam'],
  );
}

String _fence(String lines) => '# Board\n\n```query\n$lines\n```\n';

Future<_Bulk> _open(WidgetTester tester, String lines, {double screen = 1180}) async {
  final bulk = _Bulk();
  final asked = Asked();
  await pumpQueries(
    tester,
    _fence(lines),
    screen: screen,
    today: '2026-10-28',
    options: QueryOptions(
      notes: () => notes,
      noteId: 'here',
      open: (id, line) => asked.opened.add((id, line)),
      write: (id, change) => asked.written.add((id, change)),
      bulk: bulk.actions,
      labelColours: (id) => id.startsWith('wait') ? const {'bug': 'amber'} : const {},
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return bulk;
}

Finder _card(String title) => find.ancestor(of: find.text(title), matching: find.byType(QuerySelectable)).first;

Future<void> _commandTap(WidgetTester tester, Finder finder, {LogicalKeyboardKey key = LogicalKeyboardKey.metaLeft}) async {
  await tester.sendKeyDownEvent(key);
  await tester.tap(finder, kind: PointerDeviceKind.mouse);
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

/// Bulk edit in a query (lib/tickets/ui/bulk_bar.dart): tickets picked with Command or Shift, by a box or by a held
/// press, the bar that appears, and each of its edits handed to the root as one batch.
void main() {
  setUpAll(loadAppFonts);

  const board = 'from: tickets\nwhere: status != Done and labels is not empty\nshow: board';

  testWidgets('on a desktop, Command-click picks cards, the bar says how many, and Status writes them all at once', (tester) async {
    final bulk = await _open(tester, board);
    expect(find.byKey(const ValueKey('bulk-bar')), findsNothing);
    await _commandTap(tester, find.text('Invite emails bounce'));
    await _commandTap(tester, find.text('Refund webhook'));
    expect(find.byKey(const ValueKey('bulk-bar')), findsOneWidget);
    expect(find.text('2 picked'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('status:Done')));
    await tester.pumpAndSettle();
    expect(bulk.edits, hasLength(1));
    expect(bulk.edits.single.$1, unorderedEquals(['wait1', 'pay1']));
    expect((bulk.edits.single.$2 as SetField).field, 'status');
    expect((bulk.edits.single.$2 as SetField).value, 'Done');
  });

  testWidgets('a Command-click picks rather than opens, a second lets go, and Let go clears them all', (tester) async {
    final bulk = await _open(tester, 'from: tickets\nwhere: labels is not empty\nsort: id\nshow: list');
    await _commandTap(tester, find.text('Confirm page copy'));
    await _commandTap(tester, find.text('Card form focus'));
    await _commandTap(tester, find.text('Confirm page copy'));
    expect(find.text('1 picked'), findsOneWidget);
    // While any are picked a plain click picks too.
    await tester.tap(find.text('Refund webhook'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('2 picked'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bulk-bar')), findsNothing);
    expect(bulk.edits, isEmpty);
  });

  testWidgets('Shift-click picks the run of rows in a table, and Labels and Priority go to every one', (tester) async {
    final bulk = await _open(tester, 'from: tickets\nwhere: labels is not empty\nsort: id\nshow: table');
    await _commandTap(tester, find.text('Refund webhook'));
    expect(find.text('1 picked'), findsOneWidget);
    await _commandTap(tester, find.text('Invite emails bounce'), key: LogicalKeyboardKey.shiftLeft);
    // PAY-1, PAY-2, WAIT-1, WAIT-2 by key: the run from PAY-1 to WAIT-1.
    expect(find.text('3 picked'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-labels')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('label:email')));
    await tester.pumpAndSettle();
    expect(bulk.edits.single.$1, unorderedEquals(['pay1', 'pay2', 'wait1']));
    expect((bulk.edits.single.$2 as ChangeLabels).add, ['email']);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-priority')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('priority:high')));
    await tester.pumpAndSettle();
    expect((bulk.edits.last.$2 as SetField).value, 'high');
  });

  testWidgets('a box dragged from the empty ground picks every card it touches', (tester) async {
    await _open(tester, board);
    final first = tester.getRect(_card('Refund webhook'));
    final second = tester.getRect(_card('Confirm page copy'));
    final from = Offset(first.left - 4, first.top - 6);
    final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await gesture.moveTo(Offset(second.right - 4, second.top + 4));
    await tester.pump();
    expect(find.byKey(const ValueKey('selection-box')), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bulk-bar')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ picked$')), findsOneWidget);
  });

  testWidgets('on a phone, a held press picks a row, a tap picks another, and Delete sends them to the Trash', (tester) async {
    final bulk = await _open(tester, 'from: tickets\nwhere: labels is not empty\nsort: id\nshow: list', screen: 390);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Refund webhook')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('1 picked'), findsOneWidget);
    await tester.tap(find.text('Confirm page copy'));
    await tester.pumpAndSettle();
    expect(find.text('2 picked'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-delete')));
    await tester.pumpAndSettle();
    expect(bulk.trashed.single, unorderedEquals(['pay1', 'wait2']));
    expect(find.byKey(const ValueKey('bulk-bar')), findsNothing);
  });

  testWidgets('Move to notebook hands the notebook picked to the root', (tester) async {
    final bulk = await _open(tester, board);
    await _commandTap(tester, find.text('Refund webhook'));
    await tester.tap(find.byKey(const ValueKey('bulk-move')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-move:launch')));
    await tester.pumpAndSettle();
    expect(bulk.moves.single.$1, ['pay1']);
    expect(bulk.moves.single.$2, 'launch');
  });

  testWidgets('a card wears its labels in its notebook’s colours, a board can be grouped by label', (tester) async {
    await _open(tester, 'from: tickets\nwhere: labels is not empty\ngroup: labels\nshow: board');
    // WAIT-1 and PAY-1 each in the bug lane, and each of their other labels' lanes.
    expect(find.byKey(const ValueKey('label-chip-bug')), findsWidgets);
    expect(find.text('backend'), findsWidgets);
    expect(find.text('Invite emails bounce'), findsNWidgets(2));
  });
}
