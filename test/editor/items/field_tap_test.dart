// A chip tapped on the page: the tap is told to the menu (`fieldTapOf`), the caret stays where it was, and the
// kit's menu over the editor (`FieldMenuHost`) draws that field's page and writes what is pressed. The web's
// counterpart is the `FIELD_TAP` event of fieldMenu.ts reaching ContextMenu.tsx, and FieldItems.tsx's rows.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/items/items.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';

const String _note = '- [ ] Stove @sam ⏫ 📅 2026-10-03\n- [ ] Food 🔁 every week\nwords';

Future<EditorView> _pump(WidgetTester tester, {bool readOnly = false}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: _note,
      extensions: noteExtensions(readOnly: readOnly, more: <Extension>[itemExtensions(), fieldsToday.of(() => '2026-10-07'), fieldsLocale.of('en-GB')]),
    ),
  );
  addTearDown(view.destroy);
  await pumpApp(
    tester,
    prefs: const AppPreferences(theme: 'light'),
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 390, child: FieldMenuHost(view: view, child: SingleChildScrollView(child: EditorColumn(view: view)))),
    ),
  );
  await tester.pump();
  return view;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a tapped due day tells the menu its page, its line and where the chip is', (tester) async {
    final view = await _pump(tester);
    expect(find.byType(FieldChip), findsNWidgets(4));
    final due = find.byWidgetPredicate((w) => w is FieldChip && w.look.key == 'due');
    final box = tester.getRect(due);
    await tester.tap(due);
    await tester.pump();
    final tap = fieldTapOf(view).value!;
    expect(tap.page, const DatePage('due'));
    expect(tap.line, 1);
    expect(tap.x, closeTo(box.center.dx, 6));
    // The press was the chip's: the caret is where it was.
    expect(view.state.selection.main.head, 0);
    // The page's rows, in the kit's menu: the three days and Remove (no calendar is given here, so no Pick a date).
    await tester.pump(const Duration(milliseconds: 400));
    for (final label in const <String>['Today', 'Tomorrow', 'Next week', 'Remove']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    expect(view.state.doc.line(1).text, '- [ ] Stove @sam ⏫ 📅 2026-10-08');
    expect(fieldTapOf(view).value, isNull);
    await tester.pump(const Duration(seconds: 1));
    // `pumpApp` turned the shadows on, and the binding checks the switch as a test ends.
    debugDisableShadows = true;
  });

  testWidgets('a priority and a person open theirs; a recurrence has no menu and is the editor\'s to take', (tester) async {
    final view = await _pump(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is FieldChip && w.look.key == 'priority'));
    await tester.pump();
    expect(fieldTapOf(view).value!.page, const PriorityPage());
    fieldTapOf(view).value = null;
    await tester.pump();
    await tester.tap(find.byWidgetPredicate((w) => w is FieldChip && w.look.key == 'sam'));
    await tester.pump();
    expect(fieldTapOf(view).value!.page, const PersonPage('sam'));
    fieldTapOf(view).value = null;
    await tester.pump();
    final recurs = tester.widget<FieldChip>(find.byWidgetPredicate((w) => w is FieldChip && w.look.key == 'recurs'));
    expect(recurs.onTap, isNull);
    await tester.pump(const Duration(seconds: 1));
    // `pumpApp` turned the shadows on, and the binding checks the switch as a test ends.
    debugDisableShadows = true;
  });

  testWidgets('on a page that cannot be edited the chips are drawn and a tap does nothing', (tester) async {
    final view = await _pump(tester, readOnly: true);
    final chips = tester.widgetList<FieldChip>(find.byType(FieldChip)).toList();
    expect(chips.length, 4);
    expect(chips.every((chip) => chip.onTap == null), isTrue);
    expect(fieldTapOf(view).value, isNull);
    await tester.pump(const Duration(seconds: 1));
    // `pumpApp` turned the shadows on, and the binding checks the switch as a test ends.
    debugDisableShadows = true;
  });

  testWidgets('the fields are their characters again on the caret\'s line', (tester) async {
    final view = await _pump(tester);
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(8)));
    await tester.pump();
    // Line 1 has the caret: its three chips are gone, line 2's stays.
    expect(find.byType(FieldChip), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    // `pumpApp` turned the shadows on, and the binding checks the switch as a test ends.
    debugDisableShadows = true;
  });
}
