import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/book/journal_months.dart';
import 'package:ghost_md/core/book.dart' show BookPlace, bookIndex, placeOf;
import 'package:ghost_md/core/geotag.dart' show GeoTag, withGeoTag;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle, titleKey;
import 'package:ghost_md/core/template.dart' show fillTemplate;

import '../core/make_note.dart';

/// A journal's entries in months, newest first by when each was written, whatever order its index is in; what a row
/// says; and the lines with no note, dropped or listed apart. Case for case with the web's
/// `book/journalMonths.test.ts`, whose cases are pinned to en-GB, which is what lib/book/journal_months.dart writes.
/// Two things differ and are said where they do: a journal's card (en-US, as the home page was measured), and the
/// case that sets the process's zone, which a Dart test cannot.
Note entry(String title, String? date, String words, [int createdAt = 0]) =>
    makeNote(title, body: date != null ? entryBody(title, date, words) : '---\ntitle: "$title"\n---\n$words', createdAt: createdAt);

/// Notes, and names with no note, as the lines of an index.
List<JournalPage> pages(List<Object> lines) => [
      for (var line = 0; line < lines.length; line += 1)
        switch (lines[line]) {
          final Note note => JournalPage(title: note.id, line: line, note: note),
          final Object name => JournalPage(title: name as String, line: line, note: null),
        },
    ];

List<List<Object>> titles(List<JournalMonth> months) => [
      for (final m in months) [m.label, [for (final e in m.entries) e.title]],
    ];

/// The book a note of that title is a page of (the web's `bookOf`).
BookPlace? bookOf(List<Note> notes, String title) {
  final index = bookIndex(notes);
  for (final note in notes) {
    if (titleKey(noteTitle(note.body)) == titleKey(title)) return placeOf(index, note);
  }
  return null;
}

void main() {
  group('a journal’s months', () {
    test('draws the entries newest first by their date, in one run a month, whatever the index’s order', () {
      final a = entry('2026-08-30 10.00', '2026-08-30T10:00', 'August.');
      final b = entry('2026-09-28 14.05', '2026-09-28T14:05', 'Afternoon.');
      final c = entry('2026-09-28 08.10', '2026-09-28T08:10', 'Morning.');
      final d = entry('2026-07-01 07.00', '2026-07-01T07:00', 'July.');
      // Out of time order, as a notebook kept as a journal or one merged from two devices would be.
      final months = monthsOf(pages([b, a, d, c])).months;
      expect(titles(months), [
        ['September 2026', ['2026-09-28 14.05', '2026-09-28 08.10']],
        ['August 2026', ['2026-08-30 10.00']],
        ['July 2026', ['2026-07-01 07.00']],
      ]);
    });

    test('reads when the note was made where an entry says no date, and the later line where two say the same minute', () {
      final dated = entry('2026-09-10 09.00', '2026-09-10T09:00', 'Dated.');
      final undated = entry('Planned page', null, 'Written later.', DateTime(2026, 9, 12, 18, 0).millisecondsSinceEpoch);
      final first = entry('2026-09-12 18.00', '2026-09-12T18:00', 'One.');
      final second = entry('2026-09-12 18.00 (2)', '2026-09-12T18:00', 'Two.');
      final months = monthsOf(pages([dated, second, undated, first])).months;
      expect([for (final e in months[0].entries) e.title], ['2026-09-12 18.00', 'Planned page', '2026-09-12 18.00 (2)', '2026-09-10 09.00']);
    });

    test('drops an entry’s line with no note, and lists any other name with no note apart, in the index’s order', () {
      final kept = entry('2026-09-28 14.05', '2026-09-28T14:05', 'Kept.');
      final (:months, :unwritten) = monthsOf(pages(['2026-09-27 21.40', kept, 'Packing list', '2026-09-26 08.00 (2)', 'The route']));
      expect([for (final m in months) ...m.entries.map((e) => e.title)], ['2026-09-28 14.05']);
      expect(unwritten, ['Packing list', 'The route']);
    });

    test('puts an entry in the month its clock said, whatever moment that is here', () {
      // The page's case reads this in New York, by setting the process's zone. Here it is this device's, whichever
      // that is: ten past midnight on the 1st is October by the clock it says, and is nobody's September.
      final october = entry('2026-10-01 00.10', '2026-10-01T00:10', 'October.');
      final september = entry('2026-09-30 21.00', '2026-09-30T21:00', 'September.');
      final months = monthsOf(pages([october, september])).months;
      expect(titles(months), [
        ['October 2026', ['2026-10-01 00.10']],
        ['September 2026', ['2026-09-30 21.00']],
      ]);
    });

    test('keeps a travelling entry on the day its clock said, wherever it is read', () {
      final late = entry('2026-09-28 23.30', '2026-09-28T23:30', 'Written in New York.');
      final next = entry('2026-09-29 00.10', '2026-09-29T00:10', 'Just after midnight.');
      final months = monthsOf(pages([late, next])).months;
      expect([for (final e in months[0].entries) (e.day, e.weekday, e.time)], [
        ('29', 'Tue', '00:10'),
        ('28', 'Mon', '23:30'),
      ]);
    });

    test('says a row whole: the day, the time, where, and how it starts', () {
      final tagged = entry('2026-09-28 14.05', '2026-09-28T14:05', '# Monday 28 September\n\n**14:05** Walked along the river after lunch.');
      final placed = tagged.copyWith(body: withGeoTag(tagged.body, const GeoTag(lat: 51.508, lon: -0.1281, place: 'Trafalgar Square', rough: false)));
      final coords = entry('2026-09-28 08.10', '2026-09-28T08:10', 'Coffee.');
      final unnamed = coords.copyWith(body: withGeoTag(coords.body, const GeoTag(lat: 51.5, lon: -0.12, place: null, rough: true)));
      final months = monthsOf(pages([placed, unnamed]), defaultTemplate).months;
      final [one, two] = months[0].entries;
      expect((one.day, one.weekday, one.time, one.place, one.first), ('28', 'Mon', '14:05', 'Trafalgar Square', 'Walked along the river after lunch.'));
      expect(one.label, 'Monday 28 September, 14:05, Trafalgar Square. Walked along the river after lunch.');
      expect(two.place, 'Roughly 51.50, -0.12');
    });
  });

  group('an entry’s first line', () {
    final at = DateTime(2026, 9, 28, 14, 5);
    String filled(String template) => fillTemplate(template, at: at, title: '2026-09-28 14.05', journal: 'Diary');
    String first(String words, String template) => firstWords(entryBody('2026-09-28 14.05', '2026-09-28T14:05', words), filled(template));

    test('skips its front matter, headings, the template’s own lines and the time that leads a line', () {
      expect(first('# Monday 28 September\n\n**14:05** ', defaultTemplate), '');
      expect(first('# Monday\n\n> What is on your mind this morning?\n\nThe garden, mostly.', entryPresets[2].text), 'The garden, mostly.');
      expect(first('# Monday\n\n## To do\n\n- [ ] \n- [ ] Call **Sam**', entryPresets[3].text), 'Call Sam');
      expect(firstWords('---\ntitle: "x"\n---\n![](image/a.jpg)\n14:05 Tea.'), 'Tea.');
    });

    test('skips only what the template wrote for this entry, never every line a placeholder could stand for', () {
      // A line of your own that is only a placeholder, or a format with words round it, left open for the entry's words.
      const own = '# {{date}}\n{{date:dddd [at] HH:mm}}. ';
      expect(first('# Monday 28 September\nMonday at 14:05. Walked along the river after lunch.', own), 'Walked along the river after lunch.');
      expect(first('Monday 28 September\n\n14:05 Walked along the river after lunch.', '{{date}}\n\n{{time}} '), 'Walked along the river after lunch.');
      // Bold of the entry's own, whole or at the line's end, is words.
      expect(first('# Monday 28 September\n\n**14:05** \n**Remember the milk**', defaultTemplate), 'Remember the milk');
      expect(first('# Monday 28 September\n\n**14:05** Walked **fast**', defaultTemplate), 'Walked fast');
      // A heading of the entry's own is still a heading.
      expect(first('# Monday 28 September\n\n## Lunch\n\nSoup.', defaultTemplate), 'Soup.');
    });

    group('when the + beside the line wrote the first thing in it', () {
      // The default template, then Enter, Enter, and the insert on the empty line, as the + writes each.
      const opening = '# Monday 28 September\n\n**14:05** \n\n';
      String after(String insert) => first('$opening$insert\n\nWalked along the river.', defaultTemplate);
      String alone(String insert) => first('$opening$insert\n', defaultTemplate);

      for (final (what, insert) in const [
        ('a place', '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)'),
        ('a place with no name yet', '[38.7057, -9.1446](geo:38.7057,-9.1446)'),
        ('a film', '[![video 0:12](image/p1.jpg)](video/f1.mp4)'),
        ('a picture', '![](image/pic1.jpg)'),
        ('a canvas in a frame', '![[Plan]]'),
        ('a table', '| Column | Column |\n| --- | --- |\n| Cell | Cell |'),
        ('a divider', '---'),
        ('a block of code', '```\nconst a = 1;\n```'),
        ('a board', '```board\n## To do\n- first-card\n## Doing\n## Done\n```'),
        ('a chart', '```mermaid\nflowchart LR\n  A[Start] --> B[Then]\n```'),
        ('a callout', '> [!NOTE]\n> '),
        ('a footnote', '[^1]\n\n[^1]: '),
        ('a heading', '## '),
        ('a bulleted list', '- '),
        ('a numbered list', '1. '),
        ('a choice', '- ( ) '),
        ('a sum', '= '),
      ]) {
        test('skips $what: the row starts with the words after it, and has none where it is all there is', () {
          expect(after(insert), 'Walked along the river.');
          expect(alone(insert), '');
        });
      }

      test('reads what it wrote as words when it is words: a callout’s title, a link, a card, a footnote, a sum', () {
        expect(alone('> [!NOTE] Pack the charger'), 'Pack the charger');
        expect(alone('Lunch at [Cais do Sodré, Lisbon](geo:38.7057,-9.1446) with Sam'), 'Lunch at Cais do Sodré, Lisbon with Sam');
        expect(alone('See [[Lisbon]] and [[Porto|the north]]'), 'See Lisbon and the north');
        expect(alone('```board\n## To do\n- first-card\n```\n\n- [ ] First card ^first-card'), 'First card');
        expect(alone('Four hundred[^1]\n\n[^1]: Counted twice.'), 'Four hundred');
        expect(alone('= 12 * 3'), '12 * 3');
        expect(alone('Before ![](image/pic1.jpg) after'), 'Before  after');
        // The time the + writes is the person's own words.
        expect(alone('28 Sep 2026, 14:05'), '28 Sep 2026, 14:05');
      });

      test('never says a place’s coordinates in the row, nor in what it says to a screen reader', () {
        final made = entry('2026-09-28 14.05', '2026-09-28T14:05', '$opening[38.7057, -9.1446](geo:38.7057,-9.1446)\n');
        final months = monthsOf(pages([made]), defaultTemplate).months;
        final [row] = months[0].entries;
        expect(row.first, '');
        expect(row.label, 'Monday 28 September, 14:05.');
      });
    });

    test('draws a row’s words for a template of your own, filled for each entry’s own minute', () {
      final one = entry('2026-09-28 20.58', '2026-09-28T20:58', '# Monday 28 September\nMonday at 20:58. Walked along the river after lunch.');
      final two = entry('2026-09-27 07.30', '2026-09-27T07:30', '# Sunday 27 September\nSunday at 07:30. ');
      final months = monthsOf(pages([one, two]), '# {{date}}\n{{date:dddd [at] HH:mm}}. ', 'Diary').months;
      expect([for (final e in months[0].entries) e.first], ['Walked along the river after lunch.', '']);
      expect(months[0].entries[0].label, 'Monday 28 September, 20:58. Walked along the river after lunch.');
    });
  });

  group('a journal elsewhere', () {
    const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-09-28 14.05]]\n- [[Planned]]\n- [[2026-09-27 21.40]]\n- [[2026-09-26 09.00]]\n';
    final notes = [
      makeNote('diary', body: journal),
      entry('2026-09-28 14.05', '2026-09-28T14:05', 'Newest.'),
      entry('2026-09-27 21.40', '2026-09-27T21:40', 'Before.'),
      makeNote('notebook', body: '---\ntitle: "Guide"\nbook: true\n---\n- [[Trees]]\n'),
      // The web's `bookOf` finds a book by a title alone; here a place is a note's, so the notebook's page is one.
      makeNote('trees', body: '# Trees'),
    ];
    Note? noteOf(String title) => notes.where((note) => note.id == title).firstOrNull;

    test('gives a journal’s card its count of entries written and its newest by day and time, and a notebook none', () {
      final cards = journalCards(notes);
      expect(cards.keys, ['diary']);
      // The planned page is not an entry: not counted, not listed.
      expect(cards['diary']!.count, 2);
      // The page's case is en-GB, "Mon 28 Sept, 14:05"; a card here is as the home page was measured (en-US).
      expect(cards['diary']!.newest, [
        (title: '2026-09-28 14.05', when: 'Mon, Sep 28, 14:05'),
        (title: '2026-09-27 21.40', when: 'Sun, Sep 27, 21:40'),
      ]);
    });

    test('walks a journal’s written entries oldest first for the bar, and a notebook’s pages as they are', () {
      final place = inTimeOrder(bookOf(notes, '2026-09-28 14.05')!, noteOf);
      // A page planned and never written is not walked to.
      expect([for (final c in place.chapters) c.title], ['2026-09-27 21.40', '2026-09-28 14.05']);
      expect(place.at, 1);
      final guide = bookOf(notes, 'Trees')!;
      expect(inTimeOrder(guide, noteOf), same(guide));
    });

    test('names an entry either side by its time on the same day, else by its day, and any other page as it is', () {
      expect(sideName('2026-09-28 08.10', '2026-09-28 14.05'), '08:10');
      expect(sideName('2026-09-28 14.05 (2)', '2026-09-28 14.05'), '14:05');
      expect(sideName('2026-09-27 21.40', '2026-09-28 14.05'), '27 Sept');
      expect(sideName('Packing list', '2026-09-28 14.05'), 'Packing list');
      expect(sideName('2026-09-28 08.10', 'Packing list'), '28 Sept');
    });

    test('gives the aside the month of the entry open, or the newest', () {
      expect([for (final e in asideMonth(notes[0], notes, '2026-09-27 21.40')!.entries) e.title], ['2026-09-28 14.05', '2026-09-27 21.40']);
      expect(asideMonth(notes[0], notes, null)?.key, '2026-09');
      expect(asideMonth(makeNote('empty', body: '---\nbook: true\njournal: true\n---\n'), notes, null), isNull);
    });
  });
}
