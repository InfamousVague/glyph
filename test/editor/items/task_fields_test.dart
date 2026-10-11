// A to-do's fields drawn in a note (lib/editor/items/task_fields.dart): `src/app/editor/taskFields.test.ts`, case
// for case. Thursday 1 October 2026, in British.
//
// What is asked differently: a chip is the widget a field's characters are replaced by, read from the view's
// decorations (its look's label and tone, and the characters it stands in for); today is the `fieldsToday` facet
// and the language `fieldsLocale`; "the note is being written" is `view.setFocused(true)`; and a tapped chip is
// heard through the `fieldTaps` facet, in a view that is drawn, where the page's test listened for a DOM event.
// `role="button"` is the chip's widget answering its own taps (and saying it is a button); a `mousedown` kept from
// the editor is the widget taking the pointer.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/field_chips.dart';
import 'package:ghost_md/editor/items/field_menu.dart';
import 'package:ghost_md/editor/items/tags.dart';
import 'package:ghost_md/editor/items/task_fields.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// Every tap told, in order.
final List<FieldTap> heard = <FieldTap>[];

EditorView open(String doc, {int anchor = 0, bool editable = true}) {
  heard.clear();
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      selection: EditorSelection.single(anchor),
      extensions: noteExtensions(readOnly: !editable, more: <Extension>[taskFields(), tags(), fieldsToday.of(() => '2026-10-01'), fieldsLocale.of('en-GB'), fieldTaps.of(heard.add)]),
    ),
  );
  addTearDown(view.destroy);
  return view;
}

/// The chips drawn, in the note's order: the characters each stands in for, and its widget.
List<({int from, int to, FieldWidget widget})> chips(EditorView on) {
  final found = <({int from, int to, FieldWidget widget})>[];
  for (final set in on.decorations) {
    set.between(0, on.state.doc.length, (from, to, value) {
      final widget = value.widget;
      if (widget is FieldWidget) found.add((from: from, to: to, widget: widget));
      return null;
    });
  }
  return found..sort((a, b) => a.from - b.from);
}

List<String> labels(EditorView on) => <String>[for (final chip in chips(on)) chip.widget.look.label];
List<String> tones(EditorView on) => <String>[for (final chip in chips(on)) chip.widget.look.tone];

/// What line `n` shows of its own characters: the line without those a chip stands in for.
String shown(EditorView on, int n) {
  final line = on.state.doc.line(n);
  final out = StringBuffer();
  var at = line.from;
  for (final chip in chips(on).where((chip) => chip.from >= line.from && chip.to <= line.to)) {
    out.write(on.state.sliceDoc(at, chip.from));
    at = chip.to;
  }
  out.write(on.state.sliceDoc(at, line.to));
  return out.toString();
}

Future<void> draw(WidgetTester tester, EditorView view) async {
  await pumpApp(
    tester,
    prefs: const AppPreferences(theme: 'light'),
    home: Builder(
      builder: (context) => ColoredBox(
        color: context.tokens.color('glacier-bg'),
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view)))),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  group('the chips', () {
    test('draws each field on a to-do as its chip, in the line’s order', () {
      final on = open('# Sprint\n- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03');
      expect(labels(on), <String>['Assigned to sam', 'High priority', 'Due Saturday 3 October']);
      expect(tones(on), <String>['plain', 'high', 'plain']);
      // The tag is a tag's, and the characters of the fields are not on the page while their chips are.
      expect(shown(on, 2), isNot(contains('📅')));
      expect(shown(on, 2), contains('#bug'));
    });

    test('colours a due day red once it has passed, amber on the day, and quiet once the box is ticked', () {
      final on = open('x\n- [ ] Late 📅 2026-09-29\n- [ ] Now 📅 2026-10-01\n- [x] Done late 📅 2026-09-29 ⏫');
      expect(tones(on), <String>['overdue', 'today', 'done', 'done']);
      expect(chips(on)[1].widget.look.text, 'Today');
    });

    test('shows the line as written while the caret is on it, and the chips again once it leaves', () {
      final on = open('Top\n- [ ] Fix it @sam 📅 2026-10-02');
      on.setFocused(true);
      on.dispatch(TransactionSpec(selection: EditorSelection.single(on.state.doc.length)));
      expect(chips(on), isEmpty);
      expect(shown(on, 2), '- [ ] Fix it @sam 📅 2026-10-02');
      on.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      expect(chips(on), hasLength(2));
    });

    test('draws the caret’s line too while the note is not being written', () {
      final on = open('- [ ] Fix it 📅 2026-10-02', anchor: 3);
      expect(chips(on), hasLength(1));
    });

    test('draws nothing in code, front matter or a blank’s question', () {
      final on = open('---\nowner: @sam\n---\nSay `@sam ⏫` and {?who is @sam?}\n\n```\n- [ ] 📅 2026-10-02\n```');
      expect(labels(on), isEmpty);
    });

    test('draws a person anywhere in the words, as a tag is drawn', () {
      final on = open('Ask @sam about it.');
      expect(labels(on), <String>['Assigned to sam']);
    });
  });

  group('a tap on a chip', () {
    testWidgets('tells the menu which field and which line, and keeps the caret where it was', (tester) async {
      final semantics = tester.ensureSemantics();
      final on = open('Top\n- [ ] Fix it @sam ⏫ 📅 2026-10-02');
      await draw(tester, on);
      // The press is the chip's, kept from the editor.
      expect(chips(on).map((chip) => chip.widget.takesPointer(const PointerDownEvent())), <bool>[true, true, true]);
      Finder chip(String label) => find.byWidgetPredicate((widget) => widget is FieldChip && widget.look.label == label);
      for (final label in <String>['Due Friday 2 October', 'High priority', 'Assigned to sam']) {
        await tester.tap(chip(label));
        await tester.pump();
      }
      expect(<(FieldPage, int)>[for (final tap in heard) (tap.page, tap.line)], <(FieldPage, int)>[(const DatePage('due'), 2), (const PriorityPage(), 2), (const PersonPage('sam'), 2)]);
      expect(fieldTapOf(on).value?.page, const PersonPage('sam'));
      expect(on.state.selection.main.head, 0);
      expect(tester.getSemantics(find.bySemanticsLabel('Due Friday 2 October')).flagsCollection.isButton, isTrue);
      semantics.dispose();
      debugDisableShadows = true;
    });

    testWidgets('is the editor’s on a chip with no menu, and on a page that cannot be edited', (tester) async {
      final semantics = tester.ensureSemantics();
      final on = open('- [ ] Water the plants 🔁 every week [effort:: 3]');
      await draw(tester, on);
      expect(chips(on), hasLength(2));
      for (final chip in chips(on)) {
        expect(pageOf(chip.widget.look), isNull);
        expect(chip.widget.takesPointer(const PointerDownEvent()), isFalse);
      }
      for (final label in <String>['Repeats every week', 'effort: 3']) {
        expect(tester.getSemantics(find.bySemanticsLabel(label)).flagsCollection.isButton, isFalse);
        await tester.tap(find.byWidgetPredicate((widget) => widget is FieldChip && widget.look.label == label), warnIfMissed: false);
        await tester.pump();
      }
      expect(heard, isEmpty);

      final reading = open('- [ ] Fix it 📅 2026-10-02', editable: false);
      await draw(tester, reading);
      expect(chips(reading).single.widget.takesPointer(const PointerDownEvent()), isFalse);
      await tester.tap(find.byType(FieldChip), warnIfMissed: false);
      await tester.pump();
      expect(heard, isEmpty);
      expect(tester.getSemantics(find.bySemanticsLabel('Due Friday 2 October')).flagsCollection.isButton, isFalse);
      semantics.dispose();
      debugDisableShadows = true;
    });
  });
}
