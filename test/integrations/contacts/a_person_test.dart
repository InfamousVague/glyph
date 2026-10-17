// A person in the editor once Settings › Contacts is on (docs/INTEGRATIONS.md §2): a tapped chip of a contact opens
// their card in place of the chip's page, Remove kept; Assign's A person and the +'s A person each write the contact
// picked as `@Sam-Ortiz`, on the item and at the caret.
import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/items.dart';
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/integrations/contacts/contact_card.dart';
import 'package:ghost_md/integrations/contacts/contact_match.dart';
import 'package:ghost_md/integrations/contacts/contacts.dart';
import 'package:ghost_md/sheet/sheet.dart';

import '../../editor/plus/support.dart' show editorOf, plusTest, pumpPlus;
import '../../support/render.dart';
import 'support.dart';

EditorView editor(String doc, {int anchor = 0, List<Extension> more = const <Extension>[]}) {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(doc: doc, selection: EditorSelection.single(anchor), extensions: noteExtensions(more: <Extension>[itemExtensions(), fieldsToday.of(() => '2026-10-17'), ...more])),
  );
  addTearDown(view.destroy);
  return view;
}

List<FieldItem> assignRows(EditorView view, {void Function()? closed}) => fieldItems(view, 1, const AssignPage(), onClose: closed ?? () {}, today: '2026-10-17')!;

void main() {
  setUpAll(loadAppFonts);

  group('a tapped chip', () {
    test('of a contact opens their card, and the menu hears nothing', () {
      final cards = <(String, int)>[];
      final view = editor('- [ ] Stove @sam', more: <Extension>[personCard.of((view, tap, name) {
        cards.add((name, tap.line));
        return true;
      })]);
      tapField(view, const FieldTap(page: PersonPage('sam'), line: 1, x: 10, y: 10));
      expect(cards, <(String, int)>[('sam', 1)]);
      expect(fieldTapOf(view).value, isNull);
    });

    test('of someone who is no contact opens their page, as before', () {
      final view = editor('- [ ] Stove @matt', more: <Extension>[personCard.of((view, tap, name) => false)]);
      tapField(view, const FieldTap(page: PersonPage('matt'), line: 1, x: 10, y: 10));
      expect(fieldTapOf(view).value?.page, const PersonPage('matt'));
    });

    test('of a day or a priority never asks for a card', () {
      var asked = 0;
      final view = editor('- [ ] Stove @sam ⏫', more: <Extension>[personCard.of((view, tap, name) => (asked += 1) > 0)]);
      tapField(view, const FieldTap(page: PriorityPage(), line: 1, x: 10, y: 10));
      expect(asked, 0);
      expect(fieldTapOf(view).value?.page, const PriorityPage());
    });

    testWidgets('on the page opens the card at the chip, whose Remove takes the person off the line', (tester) async {
      final contacts = ContactsStore(book: FakeContactBook(), kept: MemoryStored());
      useContacts(contacts);
      addTearDown(() => useContacts(null));
      await tester.runAsync(contacts.turnOn);
      late final EditorView view;
      // What the note's desk gives the editor (lib/root/note_desk.dart `_personCard`): the card where they are a contact.
      bool open(EditorViewLike on, FieldTap tap, String name) {
        final contact = contacts.contactOf(name);
        if (contact == null) return false;
        showPersonCard(
          tester.element(find.byType(EditorColumn)),
          contact: contact,
          name: name,
          at: Rect.fromLTWH(tap.x, tap.y, 0, 20),
          store: contacts,
          coarse: true,
          launch: (_) async => true,
          actions: <PersonCardAction>[PersonCardAction(icon: Lucide.userMinus, label: 'Remove', onPress: () => setLinePerson(on, tap.line, name, false))],
        );
        return true;
      }

      view = editor('- [ ] Stove @sam ⏫\n- [ ] Ask @matt', more: <Extension>[personCard.of(open)]);
      await pumpApp(
        tester,
        prefs: const AppPreferences(theme: 'light'),
        home: Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, child: FieldMenuHost(view: view, child: SingleChildScrollView(child: EditorColumn(view: view))))),
      );
      await tester.pump();
      await tester.tap(find.byWidgetPredicate((w) => w is FieldChip && w.look.key == 'sam'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Sheet), findsOneWidget);
      expect(find.text('Sam Ortiz'), findsOneWidget);
      expect(fieldTapOf(view).value, isNull);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Sheet), findsNothing);
      expect(view.state.doc.line(1).text, '- [ ] Stove ⏫');
      // Matt is no contact: his chip opens the menu's page, Remove there.
      await tester.tap(find.byWidgetPredicate((w) => w is FieldChip && w.look.key == 'matt'));
      await tester.pump();
      expect(fieldTapOf(view).value?.page, const PersonPage('matt'));
      await tester.pump(const Duration(seconds: 1));
      debugDisableShadows = true;
    });
  });

  group('Assign', () {
    test('offers A person before Someone new where a contact can be picked, and puts the one picked on the line', () async {
      final asked = <Offset>[];
      final picked = Completer<String?>();
      final view = editor('- [ ] Call the plumber\n- [ ] Ask @ana', more: <Extension>[
        personPicker.of(PersonPicking(offered: () => true, pick: (at) {
          asked.add(at);
          return picked.future;
        })),
      ]);
      var closed = 0;
      final rows = assignRows(view, closed: () => closed += 1);
      expect(<String>[for (final row in rows) row.label], <String>['ana', 'A person', 'Someone new']);
      final person = rows.firstWhere((row) => row.label == 'A person');
      expect(person.name, 'A person from your contacts');
      person.onPress(const Rect.fromLTWH(40, 60, 10, 10));
      expect(closed, 1);
      expect(asked, <Offset>[const Offset(40, 60)]);
      picked.complete(mentionOf(sam));
      await pumpEventQueue();
      expect(view.state.doc.line(1).text, '- [ ] Call the plumber @Sam-Ortiz');
    });

    test('writes nothing where the picking is closed with no one', () async {
      final view = editor('- [ ] Call the plumber', more: <Extension>[personPicker.of(PersonPicking(offered: () => true, pick: (_) async => null))]);
      assignRows(view).firstWhere((row) => row.label == 'A person').onPress(Rect.zero);
      await pumpEventQueue();
      expect(view.state.doc.line(1).text, '- [ ] Call the plumber');
    });

    test('has no A person where Contacts is off or the app gives no picker', () {
      expect(<String>[for (final row in assignRows(editor('- [ ] Call'))) row.label], <String>['Someone new']);
      final off = editor('- [ ] Call', more: <Extension>[personPicker.of(PersonPicking(offered: () => false, pick: (_) async => 'Sam'))]);
      expect(<String>[for (final row in assignRows(off)) row.label], <String>['Someone new']);
    });
  });

  group('the +', () {
    test('has A person, before A to-do, only where the screen can pick one', () {
      final now = DateTime(2026, 10, 17, 9);
      List<String> ids({required bool person}) => <String>[for (final row in topRows(readGates(picture: false, video: false, place: false, note: true, canvas: false, person: person), now)) row.id];
      expect(ids(person: false), isNot(contains('person')));
      final on = ids(person: true);
      expect(on.indexOf('person'), on.indexOf('todo') - 1);
      expect(on.indexOf('person'), on.indexOf('note') + 1);
      expect(allRows(readGates(picture: false, video: false, place: false, note: false, canvas: false, person: true), now).where((row) => row.id == 'person').single.words, 'A person');
    });

    test('writes the person at the caret, spaced from the words around it', () {
      final view = editor('Ask about the boiler', anchor: 3);
      expect(writePerson(view, mentionOf(sam)!), isTrue);
      expect(view.state.doc.toString(), 'Ask @Sam-Ortiz about the boiler');
      expect(view.state.selection.main.head, 'Ask @Sam-Ortiz'.length);
      final empty = editor('- [ ] ', anchor: 6);
      writePerson(empty, 'José Núñez');
      expect(empty.state.doc.toString(), '- [ ] @José-Núñez');
      expect(writePerson(empty, '!!'), isFalse);
    });

    plusTest('lists A person where the screen gives it, and a press on it is the screen’s', (tester) async {
      var persons = 0;
      final plus = PlusController();
      final view = editorOf('Lunch\n', plus.extension);
      await pumpPlus(tester, view, controller: plus, config: AddConfig(onPerson: () => persons += 1), clock: () => DateTime(2026, 10, 17, 9), coarse: true);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(PlusButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state<AddListState>(find.byType(AddList)).words, contains('A person'));
      await tester.tap(find.text('A person'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(persons, 1);
      expect(plus.opening, isNull);
    });
  });
}
