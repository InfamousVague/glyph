// The sheet a query's value or an index's status opens (lib/editor/fields/field_picker.dart; docs/DESIGN.md §169):
// every choice with its mark in its colour, the one it has lit, and a choice written and the sheet closed.
// `src/app/editor/FieldPicker.test.tsx`, case for case.
//
// What is asked differently: a mark's `data-status`, `data-priority` and `data-hue` are the widget's own fields and
// the colour its icon is drawn in; a row's `aria-pressed` is its `chosen`; and Pick a date, which the page always
// offers from its own date input, is offered where a calendar is handed in, so the day's case hands one in. Added
// after the page's cases: the calendar's own, and a name typed.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/fields/field_picker.dart';
import 'package:ghost_md/editor/fields/field_picks.dart';
import 'package:ghost_md/editor/items/field_chips.dart' show priorityIcon;
import 'package:ghost_md/editor/items/field_menu.dart' show DayPicker;
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:glacier/glacier.dart';

import '../../sidebar/support.dart';
import '../../support/icons.dart';
import '../../support/render.dart';

const String today = '2026-10-05';

class Opened {
  Opened(this.tester);
  final WidgetTester tester;
  final List<String?> picked = <String?>[];
  int closed = 0;

  Tokens get tokens => tester.element(find.byType(SheetGroup).first).tokens;

  /// A row's label, as said: its words without its mark, its hint or its tick.
  String said(SheetRow row) {
    final marks = tester.widgetList<Text>(find.descendant(of: find.descendant(of: find.byWidget(row), matching: find.byType(SheetIcon)), matching: find.byType(Text))).toSet();
    return tester.widgetList<Text>(find.descendant(of: find.byWidget(row), matching: find.byType(Text))).firstWhere((text) => !marks.contains(text)).data!;
  }

  List<String> rows() => [for (final row in tester.widgetList<SheetRow>(find.byType(SheetRow))) said(row)];
  SheetRow row(String text) => tester.widgetList<SheetRow>(find.byType(SheetRow)).firstWhere((row) => said(row) == text);

  Future<void> press(String text) async {
    await tester.tap(find.byWidget(row(text)));
    await tester.pump();
  }
}

Future<Opened> open(WidgetTester tester, FieldPick pick, {String label = 'Status', DayPicker? dayPicker}) async {
  final opened = Opened(tester);
  await pumpPage(
    tester,
    BackScope(
      child: Stack(
        children: [
          const Positioned.fill(child: SizedBox.expand()),
          FieldPicker(pick: pick, label: label, record: 'GHO-1 · Fix the login loop', onPick: opened.picked.add, onClose: () => opened.closed += 1, dayPicker: dayPicker),
        ],
      ),
    ),
  );
  await settle(tester);
  return opened;
}

void main() {
  setUpAll(loadAppFonts);

  group('a field picked from its sheet', () {
    testWidgets('offers the workflow, each status with its mark in its colour, the one it has lit', (tester) async {
      final sheet = await open(tester, const StatusPick(value: 'In progress', workflow: defaultStatuses));
      final t = sheet.tokens;
      expect(tester.widget<Sheet>(find.byType(Sheet)).label, 'Status');
      expect(find.text('GHO-1 · Fix the login loop'), findsOneWidget);
      expect(sheet.rows(), [...defaultStatuses, 'No status']);
      final marks = tester.widgetList<StatusIcon>(find.byType(StatusIcon)).toList();
      expect([for (final mark in marks) mark.look], const [StatusLook.backlog, StatusLook.todo, StatusLook.doing, StatusLook.review, StatusLook.done]);
      // `.mark[data-status]`: the faint ink not started, blue under way, purple in review, green done, each on its icon.
      final drawn = tester.widgetList<AppIcon>(find.descendant(of: find.byType(StatusIcon), matching: find.byType(AppIcon))).toList();
      expect([for (final icon in drawn) icon.icon], [Lucide.circleDashed, Lucide.circle, Lucide.circleDot, Lucide.eye, Lucide.circleCheck]);
      expect([for (final icon in drawn) icon.color], [t.color('app-ink-3'), t.color('app-ink-3'), t.color('glacier-blue-11'), t.color('glacier-purple-11'), t.color('glacier-green-11')]);
      expect([for (final icon in drawn) icon.strokeWidth], everyElement(2.4));
      // `.icon svg { inline-size: 18px }`, in the row's 30 px ring.
      expect(tester.getSize(find.byType(StatusIcon).first), const Size(18, 18));
      expect(byLucide(Lucide.ban), findsOneWidget);
      expect(sheet.row('In progress').chosen, isTrue);
      expect(sheet.row('Done').chosen, isFalse);
      await away(tester);
    });

    testWidgets('writes the status chosen and closes', (tester) async {
      final sheet = await open(tester, const StatusPick(value: 'In progress', workflow: defaultStatuses));
      await sheet.press('Done');
      expect(sheet.picked, ['Done']);
      expect(sheet.closed, 1);
      await away(tester);
    });

    testWidgets('keeps a status the workflow does not name, so the one it has is never hidden', (tester) async {
      final sheet = await open(tester, const StatusPick(value: 'Blocked', workflow: defaultStatuses));
      expect(sheet.rows(), contains('Blocked'));
      expect(sheet.row('Blocked').chosen, isTrue);
      await away(tester);
    });

    testWidgets('takes a to-do’s status as its box', (tester) async {
      final sheet = await open(tester, const BoxPick(done: false));
      expect(sheet.rows(), ['To do', 'Done']);
      expect(sheet.row('To do').chosen, isTrue);
      await sheet.press('Done');
      expect(sheet.picked, ['done']);
      await away(tester);
    });

    testWidgets('offers the five priorities in their chevrons’ colours, and None to take it off', (tester) async {
      final sheet = await open(tester, const PriorityPick(value: 'high'), label: 'Priority');
      final t = sheet.tokens;
      const names = ['highest', 'high', 'medium', 'low', 'lowest'];
      expect(sheet.rows(), ['Highest', 'High', 'Medium', 'Low', 'Lowest', 'None']);
      final drawn = tester.widgetList<AppIcon>(find.descendant(of: find.byType(SheetIcon), matching: find.byType(AppIcon))).toList();
      expect([for (final icon in drawn.take(5)) icon.icon], [for (final name in names) priorityIcon[name]]);
      expect([for (final icon in drawn.take(5)) icon.color], [t.color('glacier-red-11'), t.color('glacier-red-11'), t.color('glacier-amber-11'), t.color('glacier-blue-11'), t.color('app-ink-3')]);
      expect([for (final icon in drawn.take(5)) icon.strokeWidth], everyElement(2.6));
      expect(sheet.row('High').chosen, isTrue);
      await sheet.press('None');
      expect(sheet.picked, [null]);
      await away(tester);
    });

    testWidgets('offers the people with their initials, and No one', (tester) async {
      final sheet = await open(tester, const PersonPick(value: 'Sam', people: ['Sam', 'Priya Shah']), label: 'Assignee');
      final t = sheet.tokens;
      final avatars = tester.widgetList<Avatar>(find.byType(Avatar)).toList();
      expect([for (final avatar in avatars) avatar.initial], ['S', 'P']);
      expect([for (final avatar in avatars) avatar.hue], ['red', 'green']);
      // A round of their hue's third step, the initial in its eleventh; 1.35em of 0.85 of the slot's 18.
      final round = tester.widget<Container>(find.descendant(of: find.byType(Avatar).first, matching: find.byType(Container)));
      expect((round.decoration! as BoxDecoration).color, t.color('glacier-red-3'));
      expect((round.decoration! as BoxDecoration).shape, BoxShape.circle);
      expect(tester.getSize(find.byType(Avatar).first).width, closeTo(1.35 * 0.85 * 18, 0.01));
      final initial = tester.widget<RichText>(find.descendant(of: find.byType(Avatar).first, matching: find.byType(RichText))).text.style!;
      expect([initial.color, initial.fontSize], [t.color('glacier-red-11'), closeTo(0.85 * 18, 0.001)]);
      expect(sheet.rows(), ['Sam', 'Priya Shah', 'No one']);
      expect(sheet.row('Sam').chosen, isTrue);
      expect(sheet.row('No one').chosen, isFalse);
      await sheet.press('Priya Shah');
      expect(sheet.picked, ['Priya Shah']);
      await away(tester);
    });

    testWidgets('offers today, tomorrow and next week, a date of your own, and Remove where there is a day', (tester) async {
      final sheet = await open(tester, const DayPick(value: '2026-10-06', today: today), label: 'Due', dayPicker: (at, current) async => null);
      final t = sheet.tokens;
      expect(sheet.rows(), ['Today', 'Tomorrow', 'Next week', 'Pick a date', 'Remove']);
      expect(sheet.row('Tomorrow').chosen, isTrue);
      expect(sheet.row('Pick a date').chosen, isFalse);
      final drawn = tester.widgetList<AppIcon>(find.descendant(of: find.byType(SheetIcon), matching: find.byType(AppIcon))).toList();
      expect([for (final icon in drawn) icon.icon], [Lucide.sun, Lucide.sunrise, Lucide.calendarDays, Lucide.calendarSearch, Lucide.calendarX]);
      expect([for (final icon in drawn) icon.color], [...List.filled(4, t.color('glacier-accent-11')), t.color('glacier-red-11')]);
      // Next week is its Monday, said under the words.
      expect(find.text('Mon 12 Oct').evaluate().length + find.text('Mon, Oct 12').evaluate().length, 1);
      await sheet.press('Today');
      expect(sheet.picked, [today]);
      expect(sheet.closed, 1);
      await away(tester);
    });

    testWidgets('has no Remove for a day not set', (tester) async {
      final sheet = await open(tester, const DayPick(value: null, today: today), label: 'Due', dayPicker: (at, current) async => null);
      expect(sheet.rows(), isNot(contains('Remove')));
      await away(tester);
    });
  });

  group('what the port adds', () {
    testWidgets('a date of your own is asked of the calendar handed in, in the middle of the window, on the day the field has', (tester) async {
      final asked = <(Offset, String?)>[];
      final sheet = await open(tester, const DayPick(value: '2026-11-20', today: today), label: 'Due', dayPicker: (at, current) async {
        asked.add((at, current));
        return '2026-12-01';
      });
      // A day that is none of the three is the date picked, lit and said.
      expect(sheet.row('Pick a date').chosen, isTrue);
      expect(find.text('Fri 20 Nov').evaluate().length + find.text('Fri, Nov 20').evaluate().length, 1);
      await sheet.press('Pick a date');
      await tester.pump();
      expect(asked, [(const Offset(195, 422), '2026-11-20')]);
      expect(sheet.closed, 1);
      expect(sheet.picked, ['2026-12-01']);
      await away(tester);
    });

    testWidgets('a calendar closed on nothing writes nothing, and with no calendar there is no Pick a date', (tester) async {
      var sheet = await open(tester, const DayPick(value: null, today: today), label: 'Due', dayPicker: (at, current) async => null);
      await sheet.press('Pick a date');
      await tester.pump();
      expect([sheet.closed, sheet.picked], [1, <String?>[]]);
      await away(tester);
      sheet = await open(tester, const DayPick(value: '2026-10-06', today: today), label: 'Due');
      expect(sheet.rows(), ['Today', 'Tomorrow', 'Next week', 'Remove']);
      await away(tester);
    });

    testWidgets('a name typed narrows the people, offers someone new, and Enter assigns them', (tester) async {
      final sheet = await open(tester, const PersonPick(value: null, people: ['Sam', 'Priya Shah']), label: 'Assignee');
      expect(sheet.row('No one').chosen, isTrue);
      await tester.enterText(find.byType(EditableText), ' @pri');
      await tester.pump();
      expect(sheet.rows(), ['Assign to pri', 'Priya Shah', 'No one']);
      await tester.enterText(find.byType(EditableText), 'sam');
      await tester.pump();
      // Someone the list already has, however written, is not offered as new.
      expect(sheet.rows(), ['Sam', 'No one']);
      await tester.enterText(find.byType(EditableText), 'Jo');
      await tester.pump();
      expect(sheet.rows(), ['Assign to Jo', 'No one']);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(sheet.picked, ['Jo']);
      expect(sheet.closed, 1);
      await away(tester);
    });
  });
}
