// A to-do's fields on the press-and-hold menu (lib/editor/items/field_items.dart): `src/app/editor/FieldItems.test.tsx`,
// case for case. Thursday 1 October 2026.
//
// What is asked differently: `fieldItems(...)` answers a page's rows as data, so each case reads the rows (their
// words, their names for a screen reader, which is lit) and presses one, where the page's test drew the band and
// clicked its buttons. A row is found as the page's `button(label)` finds one: by its name, or by its words. The
// menu "closing" is `onClose` being called, and "Back" is `onBack`. `Pick a date` is offered only where the
// `dayPicker` facet has a picker, which stands for the phone's own.
//
// Left out, being the band's (lib/editor/band/context_band.dart) and not this file's: that Due date, Priority and
// Assign are rows among a line's actions, and the band's own `aria-label` turning from "Note actions" to "Fields".
// The first two cases hold what this file answers of them: which lines take fields, and that each of the three
// pages has rows for such a line. Where the menu hangs (`style.left`) is `FieldMenuHost`'s, drawn in the last case.
import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/field_chips.dart';
import 'package:ghost_md/editor/items/field_items.dart';
import 'package:ghost_md/editor/items/field_menu.dart';
import 'package:ghost_md/editor/items/task_fields.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

const String today = '2026-10-01';

/// The picker `Pick a date` opens: what it was opened on, and the day it answers when the test says.
class Picker {
  final List<String?> shown = <String?>[];
  final Completer<String?> chosen = Completer<String?>();

  Future<String?> call(Offset at, String? current) {
    shown.add(current);
    return chosen.future;
  }
}

late EditorView view;

EditorView editor(String doc, {int anchor = 0, Picker? picker}) {
  view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      selection: EditorSelection.single(anchor),
      extensions: noteExtensions(more: <Extension>[taskFields(), fieldsToday.of(() => today), fieldsLocale.of('en-GB'), dayPicker.of((picker ?? Picker()).call)]),
    ),
  );
  addTearDown(view.destroy);
  return view;
}

String line(int n) => view.state.doc.line(n).text;

/// One page of the menu, open on a line.
class Menu {
  Menu(this.page, this.line, {this.fromBand = false});

  final FieldPage page;
  final int line;

  /// Whether the page was turned to from the line's actions, and so has Back.
  final bool fromBand;
  bool closed = false;
  int backs = 0;

  List<FieldItem> get rows => fieldItems(view, line, page, onBack: fromBand ? () => backs += 1 : null, onClose: () => closed = true, today: today)!;
  List<String> get words => <String>[for (final row in rows) row.label];

  /// The row named `label`, by what a screen reader hears or by its words.
  FieldItem row(String label) => rows.firstWhere((row) => row.name == label || row.label == label, orElse: () => throw StateError('no row $label'));

  void choose(String label) => row(label).onPress(Rect.zero);
}

void main() {
  setUpAll(loadAppFonts);

  group('among a line’s actions', () {
    test('offers Due date, Priority and Assign on a list item', () {
      editor('- [ ] Fix the login loop', anchor: 3);
      expect(takesFields(line(view.state.doc.lineAt(view.state.selection.main.head).number)), isTrue);
      for (final page in const <FieldPage>[DatePage('due'), PriorityPage(), AssignPage()]) {
        expect(Menu(page, 1, fromBand: true).rows, isNotEmpty);
      }
    });

    test('offers none of them on a line of words', () {
      editor('Just a sentence.', anchor: 3);
      expect(takesFields(line(1)), isFalse);
    });

    test('turns the band over to a field’s page and back', () {
      editor('- [ ] Fix the login loop', anchor: 3);
      final menu = Menu(const DatePage('due'), 1, fromBand: true);
      expect(menu.words, <String>['Back', 'Today', 'Tomorrow', 'Next week', 'Pick a date']);
      menu.choose('Back');
      expect(menu.backs, 1);
      expect(menu.closed, isFalse);
      expect(menu.row('Back').closes, isFalse);
    });

    test('writes the day pressed where Obsidian Tasks reads it, and closes', () {
      editor('- [ ] Fix the login loop ^login-loop', anchor: 3);
      final menu = Menu(const DatePage('due'), 1, fromBand: true);
      menu.choose('Next week');
      expect(line(1), '- [ ] Fix the login loop 📅 2026-10-05 ^login-loop');
      expect(menu.closed, isTrue);
    });

    test('assigns the people the note names, one press each, and someone new by their at sign', () {
      editor('- [ ] Fix the login loop\n- [ ] Ask @sam\n- [ ] Tell @matt', anchor: 3);
      final menu = Menu(const AssignPage(), 1, fromBand: true);
      expect(menu.words, <String>['Back', 'sam', 'matt', 'Someone new']);
      menu.choose('Assign sam');
      expect(line(1), '- [ ] Fix the login loop @sam');
      // It stays open for a second, with the first lit.
      expect(menu.closed, isFalse);
      expect(menu.row('Take sam off').lit, isTrue);
      menu.choose('Someone new');
      expect(line(1), '- [ ] Fix the login loop @sam @');
      expect(view.state.selection.main.head, line(1).length);
      expect(menu.closed, isTrue);
    });
  });

  group('from a chip', () {
    test('opens a due day’s page at the chip, its day lit, with Remove', () {
      editor('Top\n- [ ] Fix it 📅 2026-10-02');
      final menu = Menu(const DatePage('due'), 2);
      expect(menu.words, <String>['Today', 'Tomorrow', 'Next week', 'Pick a date', 'Remove']);
      expect(menu.row('Due tomorrow').lit, isTrue);
      menu.choose('Remove the due date');
      expect(line(2), '- [ ] Fix it');
    });

    test('offers the five priorities and None, the one it has lit', () {
      editor('- [ ] Fix it ⏫ 📅 2026-10-02');
      var menu = Menu(const PriorityPage(), 1);
      expect(menu.words, <String>['Highest', 'High', 'Medium', 'Low', 'Lowest', 'None']);
      expect(menu.row('High priority').lit, isTrue);
      expect(<bool?>[for (final row in menu.rows) row.lit].where((lit) => lit == true), hasLength(1));
      menu.choose('Lowest priority');
      expect(line(1), '- [ ] Fix it ⏬ 📅 2026-10-02');
      menu = Menu(const PriorityPage(), 1);
      menu.choose('No priority');
      expect(line(1), '- [ ] Fix it 📅 2026-10-02');
    });

    test('takes a person off', () {
      editor('- [ ] Fix it @sam @matt');
      final menu = Menu(const PersonPage('sam'), 1);
      expect(menu.words, <String>['Remove']);
      menu.choose('Take sam off');
      expect(line(1), '- [ ] Fix it @matt');
    });

    test('opens Pick a date on the phone’s own picker, and writes the day chosen', () async {
      final picker = Picker();
      editor('- [ ] Fix it', picker: picker);
      final menu = Menu(const DatePage('start'), 1);
      menu.choose('Pick a date');
      expect(picker.shown, hasLength(1));
      expect(menu.closed, isTrue);
      picker.chosen.complete('2026-10-12');
      await pumpEventQueue();
      expect(line(1), '- [ ] Fix it 🛫 2026-10-12');
    });

    testWidgets('opens from a chip drawn in the note', (tester) async {
      editor('Top\n- [ ] Fix it ⏫');
      await pumpApp(
        tester,
        prefs: const AppPreferences(theme: 'light'),
        home: Builder(
          builder: (context) => ColoredBox(
            color: context.tokens.color('glacier-bg'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 390,
                child: FieldMenuHost(view: view, child: SingleChildScrollView(child: EditorColumn(view: view))),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Highest'), findsNothing);
      await tester.tap(find.byType(FieldChip));
      await tester.pumpAndSettle();
      final tap = fieldTapOf(view).value;
      expect(tap?.page, const PriorityPage());
      expect(tap?.line, 2);
      expect(find.text('Highest'), findsOneWidget);
      debugDisableShadows = true;
    });
  });
}
