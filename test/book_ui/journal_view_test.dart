import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_nav.dart';
import 'package:ghost_md/book/entry_starts.dart';
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/book/journal_months.dart';
import 'package:ghost_md/book/journal_view.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle, titleKey;
import 'package:ghost_md/core/stored.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import 'support.dart';

/// A journal drawn: New entry, its entries newest first by month with the older months folded, a row said whole,
/// the pages planned and not written, and a year that draws a few months, not every day. And the bar and the foot an
/// entry wears, which walk the entries in the order they were written. The web's `book/JournalView.test.tsx`, case
/// for case. A day is said as lib/core/template.dart says it, "Monday 28 September", where the web's tests run in
/// en-US and say "Monday, September 28": the port's days and months are English in the one order (see there).

/// A journal indexing these notes in the order given, and a lookup for them (`journalOf`).
({String body, Note? Function(String title) noteOf}) journalOf(List<Note> entries, [List<String> extra = const []]) {
  var body = journalNoteBody('Diary', defaultTemplate, false);
  final titles = [for (final note in entries) noteTitle(note.body)];
  for (final title in [...titles, ...extra]) {
    body = withEntry(body, title);
  }
  final map = {for (final (i, note) in entries.indexed) titleKey(titles[i]): note};
  return (body: body, noteOf: (title) => map[titleKey(title)]);
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));

  Future<void> show(WidgetTester tester, String body, Note? Function(String title) noteOf, {ValueChanged<String>? open, ValueChanged<String>? onChange, ValueChanged<String>? onNewEntry}) =>
      pumpView(tester, JournalView(body: body, noteOf: noteOf, known: (_) => true, open: open ?? (_) {}, onChange: onChange ?? (_) {}, onNewEntry: onNewEntry, clock: () => probeNow));

  Iterable<GlacierPressable> keyed(WidgetTester tester, String prefix) => tester.widgetList<GlacierPressable>(find.byWidgetPredicate((w) => w is GlacierPressable && '${w.key}'.contains(prefix)));
  List<String> monthNames(WidgetTester tester) => [
        for (final element in find.byWidgetPredicate((w) => w.key is ValueKey<String> && ((w.key! as ValueKey<String>).value.startsWith('journal-month:') || (w.key! as ValueKey<String>).value == 'journal-unwritten')).evaluate())
          (find.descendant(of: find.byWidget(element.widget), matching: find.byType(RichText)).evaluate().first.widget as RichText).text.toPlainText(),
      ];
  List<String> entryLabels(WidgetTester tester) => [for (final w in keyed(tester, 'journal-entry:')) w.semanticLabel!];

  group('a journal drawn', () {
    testWidgets('lists its entries newest first by when each was written, a month at a time, whatever the index’s order', (tester) async {
      final journal = journalOf([entryAt(2026, 9, 27, 21, 40, 'Dinner with Sam.'), entryAt(2026, 8, 30, 10, 0), entryAt(2026, 9, 28, 14, 5, 'Walked along the river.'), entryAt(2026, 9, 28, 8, 10)]);
      final opened = <String>[];
      await show(tester, journal.body, journal.noteOf, open: opened.add);
      expect(monthNames(tester), ['September 2026', 'August 2026']);
      expect([for (final label in entryLabels(tester)) label.split('.').first], ['Monday 28 September, 14:05', 'Monday 28 September, 08:10', 'Sunday 27 September, 21:40', 'Sunday 30 August, 10:00']);
      await press(tester, entryLabels(tester).first);
      expect(opened, ['2026-09-28 14.05']);
      await away(tester);
    });

    testWidgets('says a row whole for a screen reader, and shows the day, the time and how the entry starts', (tester) async {
      final journal = journalOf([entryAt(2026, 9, 28, 14, 5, 'Walked along the river after lunch.')]);
      await show(tester, journal.body, journal.noteOf);
      expect(entryLabels(tester).single, 'Monday 28 September, 14:05. Walked along the river after lunch.');
      final row = find.byKey(const ValueKey('journal-entry:2026-09-28 14.05'));
      for (final words in ['28', 'Mon', '14:05', 'Walked along the river after lunch.']) {
        expect(find.descendant(of: row, matching: find.text(words)), findsOneWidget);
      }
      await away(tester);
    });

    testWidgets('opens the three newest months and folds the rest to a row each, which a tap opens in place', (tester) async {
      final journal = journalOf([for (final month in [1, 2, 3, 4, 5]) entryAt(2026, month, 15, 9, 0)]);
      await show(tester, journal.body, journal.noteOf);
      expect(monthNames(tester), ['May 2026', 'April 2026', 'March 2026']);
      expect([for (final w in keyed(tester, 'journal-folded:')) w.semanticLabel], ['February 2026 · 1', 'January 2026 · 1']);
      await press(tester, 'January 2026 · 1');
      expect(monthNames(tester), ['May 2026', 'April 2026', 'March 2026', 'January 2026']);
      await away(tester);
    });

    testWidgets('draws a year of entries as a few months of rows, not a row a day', (tester) async {
      final entries = <Note>[];
      for (var day = 0; day < 365; day += 1) {
        final at = DateTime.utc(2026, 1, 1 + day);
        entries.add(entryAt(at.year, at.month, at.day, 8, 0));
      }
      final journal = journalOf(entries);
      await show(tester, journal.body, journal.noteOf);
      expect(tester.widgetList(find.byType(GlacierPressable)).length, lessThan(120));
      expect(monthNames(tester), ['December 2026', 'November 2026', 'October 2026']);
      await away(tester);
    });

    testWidgets('lists a page planned and not written apart, with its cross, and leaves out an entry’s line with no note', (tester) async {
      final journal = journalOf([entryAt(2026, 9, 28, 14, 5)], ['Packing list', '2026-09-27 09.00']);
      final written = <String>[], opened = <String>[];
      await show(tester, journal.body, journal.noteOf, open: opened.add, onChange: written.add);
      expect(monthNames(tester), ['September 2026', 'Not written yet']);
      expect(find.textContaining('2026-09-27 09.00'), findsNothing);
      await press(tester, 'Packing list, not written yet');
      expect(opened, ['Packing list']);
      await press(tester, 'Take Packing list out of the journal');
      expect([for (final c in chaptersOf(written.single)) c.title], ['2026-09-28 14.05', '2026-09-27 09.00']);
      await away(tester);
    });

    testWidgets('draws a row again when its entry changes, though the journal’s own words did not', (tester) async {
      final first = entryAt(2026, 9, 28, 14, 5, 'Walked.');
      final journal = journalOf([first]);
      var now = first;
      await show(tester, journal.body, (_) => now);
      expect(find.text('Walked.'), findsOneWidget);
      now = first.copyWith(body: first.body.replaceFirst('Walked.', 'Walked along the river.'), updatedAt: first.updatedAt + 1);
      await show(tester, journal.body, (_) => now);
      expect(find.text('Walked along the river.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('has one action, New entry, only where one can be made, and says what an entry starts with while it is empty', (tester) async {
      final body = journalNoteBody('Log', entryPresets[3].text, false);
      final made = <String>[];
      await show(tester, body, (_) => null, onNewEntry: made.add);
      expect(find.text('No entries yet.'), findsOneWidget);
      expect(find.text('Starts with a to-do list.'), findsOneWidget);
      expect([for (final w in tester.widgetList<GlacierPressable>(find.byType(GlacierPressable))) w.semanticLabel], ['New entry']);
      // New entry shows the templates to start from, the journal's usual one first, and makes nothing yet.
      await press(tester, 'New entry');
      expect(made, isEmpty);
      final starts = entryStarts(entryPresets[3].text);
      expect([for (final start in starts) start.name], ['A day’s to-dos', 'The date and the time', 'Just the time', 'A morning page', 'An empty page']);
      expect([for (final w in keyed(tester, 'journal-start:')) '${w.key}'], [for (final start in starts) "[<'journal-start:${start.id}'>]"]);
      expect(find.descendant(of: find.byKey(const ValueKey('journal-start:usual')), matching: find.text('Usual')), findsOneWidget);
      expect(find.text('Usual'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('journal-start:${starts[3].id}')));
      await tester.pump();
      expect(made, [entryPresets[2].text]);
      expect(find.byKey(const ValueKey('journal-choose')), findsNothing);
      // No grips, moves or Add a page: time decides the order.
      expect(find.text('Add a page'), findsNothing);
      await away(tester);
      await show(tester, body, (_) => null);
      expect(tester.widgetList(find.byType(GlacierPressable)), isEmpty);
      await away(tester);
    });

    testWidgets('says how each template starts on one line, and lets the choice be put away', (tester) async {
      expect(startLine('# {{journal}}\n\n## To do\n\n- [ ] ', 'Log'), 'Log · To do');
      expect(startLine('', 'Log'), 'Nothing, a blank page');
      expect([for (final s in entryStarts('my own words')) s.name], ['My own', for (final p in entryPresets) p.name, 'An empty page']);
      final made = <String>[];
      await show(tester, journalNoteBody('Log', entryPresets[0].text, false), (_) => null, onNewEntry: made.add);
      await press(tester, 'New entry');
      // Each row says its line for this minute.
      expect(find.text('Thursday 8 October · 15:30'), findsOneWidget);
      await press(tester, 'Cancel');
      expect(find.byKey(const ValueKey('journal-choose')), findsNothing);
      expect(made, isEmpty);
      // The back gesture folds the choice first, before it would leave the journal.
      await press(tester, 'New entry');
      final stack = BackScope.of(tester.element(find.byType(JournalView)));
      expect(stack.goBack(), isTrue);
      await tester.pump();
      expect(find.byKey(const ValueKey('journal-choose')), findsNothing);
      expect(stack.goBack(), isFalse);
      await press(tester, 'New entry');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('journal-choose')), findsNothing);
      await away(tester);
    });
  });

  group('the bar and the foot an entry wears', () {
    testWidgets('walk the entries in the order they were written and say entries, the newest last', (tester) async {
      final older = entryAt(2026, 9, 27, 21, 40);
      final newest = entryAt(2026, 9, 28, 14, 5);
      final middle = entryAt(2026, 9, 28, 8, 10);
      // Made in another order than written: a notebook kept as a journal.
      final journal = journalOf([newest, older, middle]);
      final diary = makeNote('diary', body: journal.body);
      final place = inTimeOrder(bookOf([diary], '2026-09-28 08.10')!, journal.noteOf);
      final opened = <String>[];
      await pumpView(tester, BookBar(place: place, open: opened.add));
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Journal'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      // Each side says what tells it apart: the day it was written, or its time on this one's day.
      expect(find.descendant(of: find.byKey(const ValueKey('book-bar-prev')), matching: find.text('27 Sept')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('book-bar-next')), matching: find.text('14:05')), findsOneWidget);
      await press(tester, 'Previous entry: 2026-09-27 21.40');
      await press(tester, 'Next entry: 2026-09-28 14.05');
      await press(tester, 'Open the journal Diary');
      expect(opened, ['2026-09-27 21.40', '2026-09-28 14.05', 'Diary']);
      await away(tester);

      final last = inTimeOrder(bookOf([diary], '2026-09-28 14.05')!, journal.noteOf);
      await pumpView(tester, BookFoot(place: last, open: (_) {}));
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Previous and next entry'), findsOneWidget);
      await away(tester);
      expect(last.at, 2);
      await pumpView(tester, BookBar(place: last, open: (_) {}));
      expect(disabled(tester, 'Last entry'), isTrue);
      await away(tester);
      await pumpView(tester, BookBar(place: inTimeOrder(bookOf([diary], '2026-09-27 21.40')!, journal.noteOf), open: (_) {}));
      expect(disabled(tester, 'First entry'), isTrue);
      await away(tester);
    });
  });
}
