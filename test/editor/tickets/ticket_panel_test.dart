// A ticket's properties panel (lib/editor/tickets/ticket_panel.dart; docs/DESIGN.md §157): each value picked writes
// one property, as a status, a person, a priority, a day, a number, labels and other tickets; a ticket with no key
// is offered its notebook's next; and a panel that cannot be edited picks nothing.
// `src/app/editor/TicketPanel.test.tsx`, case for case.
//
// What is asked differently (the library says why each differs):
// - A status, a person, a priority and a day are picked in the app's one field sheet, so a status's row wears its
//   mark where the page's wore a dot, and a day is picked from the sheet's days and its calendar where the page
//   typed into the phone's own date field.
// - An estimate and labels are typed in a sheet and written as it is left, where the page typed in place and wrote
//   as the field was left.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/fields/field_picker.dart';
import 'package:ghost_md/editor/fields/field_picks.dart';
import 'package:ghost_md/editor/items/field_chips.dart' show priorityIcon;
import 'package:ghost_md/editor/queries/query_look.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

const TicketChoice cookie = TicketChoice(key: 'GHO-9', title: 'Fix the session cookie', status: 'In review', category: StatusCategory.doing);
const TicketChoice beta = TicketChoice(key: 'GHO-3', title: 'Ship the beta', status: 'Done', category: StatusCategory.done);

const String front = '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\ndue: 2026-09-28\n---';

late Asked asked;
int openedLines = 0;

/// The panel alone on a page, on the first of October 2026, its days said the British way.
Future<void> draw(WidgetTester tester, {String front = front, bool editable = true, bool given = true, List<String> statuses = defaultStatuses, String? nextId, String? picksDay}) async {
  final options = given ? optionsWith(const <TicketChoice>[cookie, beta], asked: asked, statuses: statuses, nextId: nextId) : null;
  await pumpApp(
    tester,
    home: Builder(
      builder: (context) => BackScope(
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 390,
              child: TicketPanel(
                look: QueryLook.of(context, null),
                front: front,
                options: options,
                editable: editable,
                today: '2026-10-01',
                locale: 'en-GB',
                dayPicker: picksDay == null ? null : (at, current) async => picksDay,
                write: (key, value) => asked.written.add((key, value)),
                openLines: () => openedLines += 1,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  debugDisableShadows = true;
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// The names of the rows, in order, and a row's value as it is said.
List<String> names(WidgetTester tester) => <String>[for (var index = 0; index < parts('name').evaluate().length; index += 1) wordsOf(tester, parts('name').at(index)).trim()];
String valueOf(WidgetTester tester, String name) => wordsOf(tester, parts('value').at(names(tester).indexOf(name))).replaceAll('\n', '');
Finder inValue(WidgetTester tester, String name, Finder matching) => find.descendant(of: parts('value').at(names(tester).indexOf(name)), matching: matching);

/// A row of the open sheet whose label starts with `label`, and the rows' labels in order.
Finder sheetRow(String label) => find.descendant(of: find.byType(SheetRow), matching: find.textContaining(RegExp('^${RegExp.escape(label)}')));
Finder sheetRowCalled(String label) => find.descendant(of: find.byType(SheetRow), matching: find.text(label));

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    asked = Asked();
    openedLines = 0;
  });

  group('the panel', () {
    testWidgets('heads with the key and shows the four always asked, an overdue day in red', (tester) async {
      await draw(tester);
      expect(wordsOf(tester, parts('head')).trim(), 'GHO-12');
      expect(names(tester), <String>['Status', 'Assignee', 'Priority', 'Due']);
      expect(valueOf(tester, 'Status'), 'In progress');
      expect(valueOf(tester, 'Priority'), 'Empty');
      expect(valueOf(tester, 'Due'), 'Mon 28 Sept');
      final t = tester.element(panel).tokens;
      final due = tester.widget<RichText>(inValue(tester, 'Due', find.byType(RichText)));
      expect(due.text.style!.color, t.color('glacier-red-11'));
    });

    testWidgets('shows the rest behind More, and the lines as text from its button', (tester) async {
      await draw(tester);
      expect(wordsOf(tester, parts('more')).trim(), 'Start, Estimate, Blocked by, Parent, Labels');
      await tester.tap(parts('more'));
      await tester.pump();
      expect(names(tester), <String>['Status', 'Assignee', 'Priority', 'Due', 'Start', 'Estimate', 'Blocked by', 'Parent', 'Labels']);
      await tester.tap(said('Show the properties as text'));
      expect(openedLines, 1);
    });
  });

  group('a value picked', () {
    testWidgets('writes a status from the notebook’s workflow, each in its category’s colour', (tester) async {
      await draw(tester, statuses: const <String>['Ideas', 'Building', 'Live']);
      await press(tester, said(RegExp('^Status: ')));
      final marks = <StatusLook>[for (final mark in tester.widgetList<StatusIcon>(find.descendant(of: find.byType(Sheet), matching: find.byType(StatusIcon)))) mark.look];
      // The workflow's three, and the status the ticket has, which that workflow does not name.
      expect(marks.take(3), <StatusLook>[StatusLook.todo, StatusLook.doing, StatusLook.done]);
      await press(tester, sheetRowCalled('Live'));
      expect(asked.written, <(String, Object?)>[('status', 'Live')]);
      expect(find.byType(Sheet), findsNothing);
    });

    testWidgets('writes a priority by its name, or takes it off', (tester) async {
      await draw(tester);
      await press(tester, said(RegExp('^Priority: ')));
      // "High" alone: Highest starts the same way.
      await press(tester, sheetRowCalled('High'));
      expect(asked.written.last, ('priority', 'high'));
      await press(tester, said(RegExp('^Priority: ')));
      await press(tester, sheetRowCalled('None'));
      expect(asked.written.last, ('priority', null));
    });

    testWidgets('draws a priority as the kit’s chevrons in its colour, never the emoji it is written with', (tester) async {
      await draw(tester, front: front.replaceFirst('due:', 'priority: highest\ndue:'));
      expect(valueOf(tester, 'Priority'), 'Highest');
      final t = tester.element(panel).tokens;
      final mark = tester.widget<AppIcon>(inValue(tester, 'Priority', find.byType(AppIcon)));
      expect(mark.icon, priorityIcon['highest']);
      expect(mark.color, t.color('glacier-red-11'));
      await press(tester, said(RegExp('^Priority: ')));
      final rows = <String>[for (final row in tester.widgetList<SheetRow>(find.byType(SheetRow)).take(5)) wordsOf(tester, find.byWidget(row)).trim().split('\n').last];
      expect(rows, <String>['Highest', 'High', 'Medium', 'Low', 'Lowest']);
      final icons = <LucideIcon>[for (final icon in tester.widgetList<AppIcon>(find.descendant(of: find.byType(SheetRow), matching: find.byType(AppIcon))).take(5)) icon.icon];
      expect(icons, <LucideIcon?>[for (final name in const <String>['highest', 'high', 'medium', 'low', 'lowest']) priorityIcon[name]]);
      final drawn = <String>[for (final text in tester.widgetList<RichText>(find.byType(RichText))) text.text.toPlainText()].join();
      expect(drawn, isNot(matches(RegExp('🔺|⏫|🔼|🔽|⏬', unicode: true))));
    });

    testWidgets('writes a person the library names, or one typed', (tester) async {
      await draw(tester);
      await press(tester, said(RegExp('^Assignee: ')));
      await press(tester, sheetRowCalled('Priya Shah'));
      expect(asked.written.last, ('assignee', 'Priya Shah'));
      await press(tester, said(RegExp('^Assignee: ')));
      await tester.enterText(find.byType(EditableText), 'Kit');
      await tester.pump();
      await press(tester, sheetRowCalled('Assign to Kit'));
      expect(asked.written.last, ('assignee', 'Kit'));
    });

    testWidgets('writes a day from its sheet and the calendar, and takes it off from its cross', (tester) async {
      await draw(tester, picksDay: '2026-10-03');
      await press(tester, said(RegExp('^Due: ')));
      await press(tester, sheetRowCalled('Tomorrow'));
      expect(asked.written.last, ('due', '2026-10-02'));
      await press(tester, said(RegExp('^Due: ')));
      await press(tester, sheetRowCalled('Pick a date'));
      expect(asked.written.last, ('due', '2026-10-03'));
      await tester.tap(said('Take due off'));
      expect(asked.written.last, ('due', null));
    });

    testWidgets('writes an estimate and labels when the field is left, and nothing for a field left as it was', (tester) async {
      await draw(tester, front: '${front.substring(0, front.length - 3)}estimate: 3\nlabels: [bug]\n---');
      await press(tester, said(RegExp('^Estimate: ')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(asked.written, isEmpty);
      await press(tester, said(RegExp('^Estimate: ')));
      await tester.enterText(find.byType(EditableText), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(asked.written.last, ('estimate', '5'));
      expect(valueOf(tester, 'Labels'), 'bug');
      await press(tester, said(RegExp('^Labels: ')));
      await tester.enterText(find.byType(EditableText), 'bug, ui');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(asked.written.last.$1, 'labels');
      expect(asked.written.last.$2, <String>['bug', 'ui']);
    });

    testWidgets('links another ticket by its key, and says it waits on one that is not done with a lock', (tester) async {
      await draw(tester, front: '${front.substring(0, front.length - 3)}blocked-by: "[[GHO-9]]"\n---');
      expect(wordsOf(tester, parts('waiting')).replaceAll('\n', ''), 'Waiting onGHO-9Fix the session cookie');
      await press(tester, said('Change Blocked by'));
      expect(tester.widget<SheetRow>(find.ancestor(of: sheetRow('GHO-9'), matching: find.byType(SheetRow))).chosen, isTrue);
      await press(tester, sheetRow('GHO-3'));
      expect(asked.written.last.$1, 'blocked-by');
      expect(asked.written.last.$2, <String>['[[GHO-9]]', '[[GHO-3]]']);
      await press(tester, sheetRow('GHO-9'));
      expect(asked.written.last, ('blocked-by', null));
    });

    testWidgets('offers a ticket with no key its notebook’s next', (tester) async {
      await draw(tester, front: '---\ntype: ticket\nstatus: To do\n---', nextId: 'GHO-14');
      await tester.tap(said('Give it GHO-14'));
      expect(asked.written, <(String, Object?)>[('id', 'GHO-14')]);
    });
  });

  group('a panel that cannot be edited', () {
    testWidgets('picks nothing: no buttons to open a sheet, no fields', (tester) async {
      await draw(tester, editable: false);
      expect(said(RegExp('Change it')), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(valueOf(tester, 'Status'), 'In progress');
    });
  });
}
