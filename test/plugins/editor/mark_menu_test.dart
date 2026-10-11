// editor/MarkMenu.test.tsx, case for case.
//
// A linked line's drawer: the task read through its plugin's provider (lib/plugins/mark_details.dart), then Open,
// the board's own actions, Refresh and Unlink. A provider named for this file stands in for a plugin.
//
// Not ported: "the drawer's own root: mounts into the widget's host and comes down a microtask after it is asked
// to". There is no root of its own here: the row whose menu is open builds the drawer, which linked_rows_test.dart
// asks ("the drawer the row itself draws").
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/items/mark_menu.dart';
import 'package:ghost_md/plugins/mark_details.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

const String url = 'https://example.test/task/1';

/// What the stand-in provider knows, and what it can do: changed by each test.
final StandIn board = StandIn();
List<MarkAction> actions = <MarkAction>[];

MarkEntry ready(String title) => MarkReady(
  MarkDetails(url: url, title: title, status: const MarkStatus('In progress', Stage.doing), brief: const <String>['P1'], fields: const <MarkField>[MarkField('Due', 'Sep 20')], readAt: DateTime.now().millisecondsSinceEpoch),
);

class Told {
  final List<String> said = <String>[];
  int closed = 0;
  int unlinked = 0;
}

Future<Told> drawer(WidgetTester tester) async {
  final told = Told();
  final props = MarkMenuProps(name: 'testboard', url: url, words: 'Buy milk', say: told.said.add, close: () => told.closed += 1, unlink: () => told.unlinked += 1);
  await pumpApp(tester, home: BackScope(child: Stack(children: <Widget>[MarkMenu(props: props)])));
  // pumpApp turns real shadows on for a picture; no picture is taken here, and the binding wants its switch back.
  debugDisableShadows = true;
  await tester.pump(const Duration(milliseconds: 400));
  return told;
}

Finder option(String id) => find.byKey(ValueKey<String>('markMenu-option-$id'));
bool still(WidgetTester tester, String id) => tester.widget<GlacierPressable>(option(id)).onPressed == null;

void main() {
  setUpAll(() async {
    await loadAppFonts();
    board.actionsFor = (_, _) => actions;
    provideMarkDetails('testboard', () => board);
  });
  setUp(() {
    board.known.clear();
    board.wanted.clear();
    actions = <MarkAction>[];
  });

  group('a linked line’s drawer', () {
    testWidgets('reads the task afresh as it opens, and draws what the provider knows', (tester) async {
      board.known[url] = ready('Buy oat milk');
      final handle = tester.ensureSemantics();
      await drawer(tester);
      expect(board.wanted, <(String, bool)>[(url, true)]);
      expect(find.bySemanticsLabel(RegExp('^Testboard Buy oat milk')), findsWidgets);
      // The eyebrow is set in capitals (`text-transform: uppercase`).
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('Sep 20'), findsOneWidget);
      expect(find.text('Open in Testboard'), findsOneWidget);
      expect(find.bySemanticsLabel('Open in Testboard'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('says it cannot read the task when the provider has nothing', (tester) async {
      await drawer(tester);
      expect(find.text('Ghost.md can’t read Testboard right now.'), findsOneWidget);
      // The item's own words stand in for the task's title.
      expect(find.text('Buy milk'), findsOneWidget);
    });

    testWidgets('keeps the row under the finger when the task is read again, rather than drawing a new one', (tester) async {
      board.known[url] = ready('Buy oat milk');
      await drawer(tester);
      final unlink = tester.state(option('unlink'));
      board.known[url] = ready('Buy oat milk, two');
      markDetailsChanged();
      await tester.pump();
      expect(find.text('Buy oat milk, two'), findsOneWidget);
      expect(tester.state(option('unlink')), same(unlink));
    });

    testWidgets('shows an action’s busy words while it runs, stills the rows, and says what it did', (tester) async {
      final finish = Completer<String?>();
      board.known[url] = ready('Buy oat milk');
      actions = <MarkAction>[MarkAction(id: 'done', label: 'Mark done', icon: MarkActionIcon.done, busyLabel: 'Marking done…', run: () => finish.future)];
      final told = await drawer(tester);
      await tester.tap(find.text('Mark done'));
      await tester.pump();
      expect(find.text('Marking done…'), findsOneWidget);
      expect(still(tester, 'done'), isTrue);
      expect(still(tester, 'unlink'), isTrue);
      finish.complete('Marked done in Testboard.');
      await tester.pump();
      await tester.pump();
      expect(told.said, <String>['Marked done in Testboard.']);
      expect(find.text('Mark done'), findsOneWidget);
      expect(still(tester, 'done'), isFalse);
      // The motor's pattern for how it went plays out.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('says why an action failed, in its own words', (tester) async {
      board.known[url] = ready('Buy oat milk');
      actions = <MarkAction>[MarkAction(id: 'done', label: 'Mark done', icon: MarkActionIcon.done, busyLabel: 'Marking done…', run: () => Future<String?>.error(Exception('Testboard said no.')))];
      final told = await drawer(tester);
      await tester.tap(find.text('Mark done'));
      await tester.pump();
      await tester.pump();
      expect(told.said, <String>['Testboard said no.']);
      // The motor's pattern for how it went plays out.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('unlinks, keeping the words, and closes on the back gesture', (tester) async {
      final told = await drawer(tester);
      await tester.tap(find.text('Unlink'));
      await tester.pump();
      await tester.pump();
      expect(told.unlinked, 1);
      expect(told.said, <String>['Unlinked. The words stay.']);
      await tester.binding.handlePopRoute();
      expect(told.closed, 1);
      // The motor's pattern for how it went plays out.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('closes on a tap on the dimmed note, and not on a tap inside it', (tester) async {
      final told = await drawer(tester);
      await tester.tapAt(tester.getRect(find.byKey(const ValueKey<String>('sheet-panel'))).topCenter + const Offset(0, 4));
      await tester.pump();
      expect(told.closed, 0);
      await tester.tapAt(const Offset(195, 40));
      await tester.pump();
      expect(told.closed, 1);
    });

    testWidgets('opens the thing itself from its first row, closing first', (tester) async {
      board.known[url] = ready('Buy oat milk');
      board.opened.clear();
      final told = await drawer(tester);
      await tester.tap(find.text('Open in Testboard'));
      await tester.pump();
      expect(told.closed, 1);
      expect(board.opened, <String>[url]);
    });
  });
}
