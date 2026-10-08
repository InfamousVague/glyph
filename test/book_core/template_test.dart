import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/journal.dart' show entryPresets;
import 'package:ghost_md/core/template.dart';

/// A journal's template filled for an entry: Obsidian's placeholders, Moment's tokens, and where a spoken entry's
/// words go. Monday 28 September 2026, 14:05, in the device's own zone. Case for case with the web's
/// `core/template.test.ts`, less what the port has not got:
///
/// - **the en-US and de-DE halves of a case**: the page asks the device's language, and lib/core/template.dart
///   writes English as en-GB orders it (see there), so only the en-GB expectations are held;
/// - **what a take does with a placing** (`capture/place.ts` `placeTake`), which is the recorder's (stage 8): the
///   placing itself is held.
DateTime at() => DateTime(2026, 9, 28, 14, 5);
String fill(String text) => fillTemplate(text, at: at(), title: '2026-09-28 14.05', journal: 'Diary');

void main() {
  group('the placeholders', () {
    test('fills each one, the time on a 24-hour clock', () {
      const all = '{{date}} | {{time}} | {{weekday}} | {{title}} | {{journal}}';
      expect(fill(all), 'Monday 28 September | 14:05 | Monday | 2026-09-28 14.05 | Diary');
    });

    test('fills every preset as a person would start an entry', () {
      expect(fill(entryPresets[0].text), '# Monday 28 September\n\n**14:05** ');
      expect(fill(entryPresets[1].text), '**14:05** ');
      expect(fill(entryPresets[2].text), '# Monday 28 September\n\n> What is on your mind this morning?\n\n');
      expect(fill(entryPresets[3].text), '# Monday 28 September\n\n## To do\n\n- [ ] ');
    });

    test('leaves anything it does not know as it was typed, a name an object has of its own included', () {
      expect(fill('{{x}} {{Date}} {{date:}} {{title:YYYY}}'), '{{x}} {{Date}} Monday 28 September {{title:YYYY}}');
      expect(fill('{{__proto__}} {{constructor}} {{toString}} {{hasOwnProperty}}'), '{{__proto__}} {{constructor}} {{toString}} {{hasOwnProperty}}');
      expect(fill('{ {date} } {{date'), '{ {date} } {{date');
      // Spaces inside the braces, as Obsidian allows them.
      expect(fill('{{ time }} {{ date:YYYY }}'), '14:05 2026');
    });

    test('takes the three words already written, for a caller that fills a year of entries', () {
      // Not a web case of its own: `said` is how book/journalMonths.ts fills, held here where it is read.
      expect(fillTemplate('{{date}} {{time}} {{weekday}} {{date:YYYY}}', at: at(), said: (date: 'D', time: 'T', weekday: 'W')), 'D T W 2026');
    });
  });

  group('the next ticket’s id (docs/DESIGN.md §157)', () {
    const ticket = '---\ntype: ticket\nid: "{{next-id}}"\nstatus: To do\n---\n# {{title}}\n\nSee {{next-id}}.';

    test('fills the id’s own line bare, its quotes gone, and the placeholder anywhere else as it is', () {
      expect(fillTemplate(ticket, at: at(), nextId: 'GHO-13', title: 'Login'), '---\ntype: ticket\nid: GHO-13\nstatus: To do\n---\n# Login\n\nSee GHO-13.');
      expect(fillTemplate("---\nid: '{{ next-id }}'\n---\n", at: at(), nextId: 'GHO-1'), '---\nid: GHO-1\n---\n');
      expect(fillTemplate('---\nid: {{next-id}}\n---\n', at: at(), nextId: 'GHO-1'), '---\nid: GHO-1\n---\n');
    });

    test('leaves the id’s line out where there is no key, and fills the placeholder in the words with nothing', () {
      expect(fillTemplate(ticket, at: at(), title: 'Login'), '---\ntype: ticket\nstatus: To do\n---\n# Login\n\nSee .');
      expect(fillTemplate(ticket, at: at(), nextId: null), '---\ntype: ticket\nstatus: To do\n---\n# \n\nSee .');
      // A line of the words that looks like a key is words, not front matter, and is kept.
      expect(fillTemplate('# Notes\n\nid: {{next-id}}', at: at()), '# Notes\n\nid: ');
    });
  });

  group('a format', () {
    String format(String text, [DateTime? when]) => formatStamp(when ?? at(), text);

    test('reads every token Moment reads', () {
      expect(format('YYYY YY MMMM MMM MM M DD D dddd ddd HH H hh h mm A a'), '2026 26 September Sept 09 9 28 28 Monday Mon 14 14 02 2 05 PM pm');
      final morning = DateTime(2026, 1, 2, 0, 7);
      expect(format('DD/MM/YY h:mm a, H:mm', morning), '02/01/26 12:07 am, 0:07');
      // One figure or two, as the token says, for a day and an hour under ten.
      expect(format('D DD M MM H HH h hh', DateTime(2026, 1, 2, 7, 9)), '2 02 1 01 7 07 7 07');
    });

    test('writes the day as an ordinal in English', () {
      String on(int day) => format('Do', DateTime(2026, 10, day));
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(on), ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '31st']);
    });

    test('keeps words in square brackets, and reads letters outside them as Moment does', () {
      expect(fill('{{date:dddd [at] HH:mm}}.'), 'Monday at 14:05.');
      expect(fill('{{date:D MMMM at HH:mm}}'), '28 September pmt 14:05');
      expect(fill('{{date:YYYY-MM-DD}} {{time:HH.mm}}'), '2026-09-28 14.05');
      // The page's case is en-US, "Week of 28 Sep"; en-GB's short September is Sept.
      expect(fill('{{date:[Week of] D MMM}}'), 'Week of 28 Sept');
    });
  });

  group('the ISO week', () {
    String week(DateTime when, [String text = 'GGGG-[W]WW']) => formatStamp(when, text);

    test('names the week its Thursday is in', () {
      expect(week(at()), '2026-W40');
      // A Friday in 2021 is in 2020's last week, and the last days of a year can be the next year's first week.
      expect(week(DateTime(2021, 1, 1)), '2020-W53');
      expect(week(DateTime(2026, 12, 31)), '2026-W53');
      expect(week(DateTime(2027, 1, 1)), '2026-W53');
      expect(week(DateTime(2024, 12, 30)), '2025-W01');
      // A Sunday is the end of its week, not the start of the next, as it would be in en-US's own week.
      expect(week(DateTime(2026, 10, 4)), '2026-W40');
      expect(week(DateTime(2026, 10, 5)), '2026-W41');
    });

    test('writes W with no leading nought, keeps [W] a letter, and leaves Moment’s own week as it was typed', () {
      expect(week(DateTime(2026, 1, 5), 'W WW [W]'), '2 02 W');
      expect(week(at(), 'gggg-[W]ww'), 'gggg-Www');
      expect(fill('{{date:GGGG-[W]WW}}'), '2026-W40');
    });
  });

  group('where a new note’s caret goes', () {
    test('is the end of the first line left open: an empty heading, an empty lead, or words ending in a space', () {
      expect(firstOpenAt('# \n\n- [ ] '), 2);
      expect(firstOpenAt('# 2026-09-28\n\nMonday 28 September\n\n- [ ] '), '# 2026-09-28\n\nMonday 28 September\n\n- [ ] '.length);
      expect(firstOpenAt('# Meeting 2026-09-28 14.05\n\nWith \n\n## Notes\n\n- '), '# Meeting 2026-09-28 14.05\n\nWith '.length);
      expect(firstOpenAt('# Title\n\n> '), '# Title\n\n> '.length);
      expect(firstOpenAt('# Title\n\n1. '), '# Title\n\n1. '.length);
      expect(firstOpenAt('## \n'), 3);
    });

    test('is never a blank line, and is the end of the words when nothing is left open', () {
      expect(firstOpenAt('# Title\n\nWords.\n'), '# Title\n\nWords.\n'.length);
      expect(firstOpenAt('\n\n'), 2);
      expect(firstOpenAt(''), 0);
    });
  });

  group('where a spoken entry’s words go', () {
    test('goes on from the time the default leaves open, so the entry still starts with it', () {
      final (:base, :placing) = openEnd(fill(entryPresets[0].text));
      expect(base, '# Monday 28 September\n');
      expect(placing, const PlacingEnd(lead: '**14:05** '));
      expect(placing.toJson(), {'kind': 'end', 'lead': '**14:05** '});
      expect(openEnd(fill(entryPresets[1].text)), (base: '', placing: const PlacingEnd(lead: '**14:05** ')));
    });

    test('makes a day’s to-dos said aloud into to-dos, the empty box gone', () {
      final (:base, :placing) = openEnd(fill(entryPresets[3].text));
      expect(base, '# Monday 28 September\n\n## To do\n');
      expect(placing, const PlacingLists(task: true, heading: null, fresh: FreshList.task));
      expect(placing.toJson(), {'kind': 'lists', 'task': true, 'heading': null, 'fresh': 'task'});
      expect(openEnd('- ').placing, const PlacingLists(task: false, heading: null, fresh: FreshList.bullet));
    });

    test('numbers what is said for a template of your own that ends in an empty numbered item', () {
      final (:base, :placing) = openEnd('# Steps\n\n1. ');
      expect(base, '# Steps\n');
      expect(placing, const PlacingLists(task: false, heading: null, fresh: FreshList.number));
    });

    test('puts the words at the end of a morning page, whose last line is already closed', () {
      final words = fill(entryPresets[2].text);
      expect(openEnd(words), (base: words, placing: const PlacingEnd()));
      expect(openEnd('Words.'), (base: 'Words.', placing: const PlacingEnd()));
      expect(const PlacingEnd().toJson(), {'kind': 'end'});
    });
  });
}
