// A card's fields (lib/editor/boards/board_card.dart; the web's editor/boards/fields.test.ts): the item's words
// without them, and its due day, priority and people as chips of the card's own in its footer, quiet once the card
// is ticked, a tap on one opening its page of the press-and-hold menu for the item's line. Thursday 1 October 2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/boards.dart' show Item;
import 'package:ghost_md/editor/boards/boards.dart';
import 'package:ghost_md/editor/items/field_chips.dart';
import 'package:ghost_md/editor/items/field_menu.dart';
import 'package:ghost_md/editor/state/state.dart' show Extension;

import '../../support/render.dart';
import 'support.dart';

const String doc =
    '```board\n'
    'To do: login, notes\n'
    'Done: demo\n'
    '```\n'
    '\n'
    '- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03 🔁 every week ^login\n'
    '- [ ] Write the notes ^notes\n'
    '- [x] Book the demo room @matt 📅 2026-09-28 ^demo';

List<FieldChip> chipsOf(WidgetTester tester, String id) => tester.widgetList<FieldChip>(find.descendant(of: cardOf(id), matching: find.byType(FieldChip))).toList();

void main() {
  setUpAll(loadAppFonts);

  testWidgets('says the item’s words without them, and shows its due day, priority and people as chips', (tester) async {
    await pumpBoards(tester, doc, today: '2026-10-01');
    expect(tester.widget<BoardWords>(inCard('login', 'words')).text, 'Fix the login loop #bug');
    final labels = <String>[for (final chip in chipsOf(tester, 'login')) chip.look.label];
    expect(labels.sublist(0, 2), <String>['Assigned to sam', 'High priority']);
    expect(labels[2], startsWith('Due Saturday'));
    expect(labels, hasLength(3), reason: 'a recurrence is the line’s to show, not the card’s');
  });

  testWidgets('has no row of chips for an item with no fields', (tester) async {
    await pumpBoards(tester, doc, today: '2026-10-01');
    expect(inCard('notes', 'fields'), findsNothing);
    expect(chipsOf(tester, 'notes'), isEmpty);
  });

  testWidgets('quiets the chips of a ticked card', (tester) async {
    await pumpBoards(tester, doc, today: '2026-10-01');
    expect(<String>[for (final chip in chipsOf(tester, 'demo')) chip.look.tone], <String>['done', 'done']);
  });

  testWidgets('opens the press-and-hold menu on a chip’s page for the item’s line', (tester) async {
    final heard = <FieldTap>[];
    final view = await pumpBoards(tester, doc, today: '2026-10-01', more: <Extension>[fieldTaps.of(heard.add)]);
    final due = find.descendant(of: cardOf('login'), matching: find.byType(FieldChip)).at(2);
    await tester.tap(due);
    await tester.pump();
    expect(<(FieldPage, int)>[for (final tap in heard) (tap.page, tap.line)], <(FieldPage, int)>[(const DatePage('due'), 6)]);
    // Over the middle of the chip's top, where the menu hangs from.
    final box = boxOf(tester, due);
    expect(heard.single.x, closeTo(box.center.dx, 0.01));
    expect(heard.single.y, closeTo(box.top, 0.01));
    expect(fieldTapOf(view).value, same(heard.single));
    // A priority's and a person's chips open their own pages.
    await tester.tap(find.descendant(of: cardOf('login'), matching: find.byType(FieldChip)).at(0));
    await tester.tap(find.descendant(of: cardOf('login'), matching: find.byType(FieldChip)).at(1));
    await tester.pump();
    expect(<FieldPage>[for (final tap in heard.skip(1)) tap.page], <FieldPage>[const PersonPage('sam'), const PriorityPage()]);
    // And a chip pressed and held lifts the card it is on, as its words do.
    final finger = await holdAt(tester, boxOf(tester, due).center);
    expect(keyed('gap'), findsOneWidget);
    await finger.cancel();
    await tester.pump();
  });

  testWidgets('draws them but opens nothing on a page that cannot be edited', (tester) async {
    final heard = <FieldTap>[];
    await pumpBoards(tester, doc, today: '2026-10-01', readOnly: true, more: <Extension>[fieldTaps.of(heard.add)]);
    final chips = find.descendant(of: cardOf('login'), matching: find.byType(FieldChip));
    expect(chips, findsNWidgets(3));
    await tester.tap(chips.at(2), warnIfMissed: false);
    await tester.pump();
    expect(heard, isEmpty);
    // What a span on the page is: on the chip's own shorter line.
    expect(tester.widget<FieldChip>(chips.first).lineHeight, 1.35);
  });

  test('shows only the three a card is a glance at', () {
    // A start day, a recurrence and a named field are the line's.
    final chips = cardChips(const Item(id: 'x', text: 'Go 🛫 2026-10-02 📅 2026-10-03 🔁 every week [effort:: 3] 🔽 @ana', done: false, line: 1), today: '2026-10-01');
    expect(chips, hasLength(3));
    expect(chips[0].look.label, startsWith('Due'));
    expect(<String>[chips[1].look.label, chips[2].look.label], <String>['Low priority', 'Assigned to ana']);
    expect(<FieldPage>[for (final chip in chips) chipPage(chip.span)], <FieldPage>[const DatePage('due'), const PriorityPage(), const PersonPage('ana')]);
  });
}
