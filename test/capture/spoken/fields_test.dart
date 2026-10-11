import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/spoken/fields.dart';
import 'package:ghost_md/core/task_fields.dart';

/// A to-do's fields said at its end (lib/capture/spoken/fields.dart): what is read as a due day, a priority or a
/// person, and, as much, what stays words, since a false field takes words out of what someone said. Counted from
/// Thursday 1 October 2026. Case for case with the web's `capture/spoken/fields.test.ts`.

const today = '2026-10-01';
SpokenFields read(String words) => spokenFields(words, today);
String line(String item) => withSpokenFields(item, today);

void main() {
  group('cues read at the end of an item', () {
    test('reads a due day after "due"', () {
      expect(read('Call the plumber due Friday'), const SpokenFields(words: 'Call the plumber', due: '2026-10-02', priority: null, people: []));
      expect(read('Send the invoice, due tomorrow.').due, '2026-10-02');
      expect(read('The report is due next week').words, 'The report');
      expect(read('Book the venue due the third of October').due, '2026-10-03');
      expect(read('Pay the deposit, due on the 15th').due, '2026-10-15');
    });

    test('reads a priority by its name, by "urgent", and either way round', () {
      var found = read('Fix the login loop, high priority');
      expect((found.words, found.priority), ('Fix the login loop', 'high'));
      expect(read('Ship the patch top priority').priority, 'highest');
      expect(read('Ship the patch, highest priority').priority, 'highest');
      expect(read('Tidy the drive, low priority').priority, 'low');
      expect(read('Archive the old boards lowest priority').priority, 'lowest');
      found = read('Answer the auditor, it’s a medium-priority');
      expect((found.words, found.priority), ('Answer the auditor', 'medium'));
      expect(read('Answer the auditor, medium priority').priority, 'medium');
      expect(read('Renew the passport, priority high').priority, 'high');
      found = read('Renew the passport, urgent');
      expect((found.words, found.priority), ('Renew the passport', 'high'));
      expect(read("Call the bank, it's urgent").priority, 'high');
    });

    test('reads a person after "for" or "assigned to"', () {
      final found = read('Book the venue for Sam');
      expect(found.words, 'Book the venue');
      expect(found.people, ['Sam']);
      expect(read('Renew the passport, assigned to Matt').people, ['Matt']);
      expect(read('Plan the offsite assign it to Sam Ortiz').people, ['Sam Ortiz']);
      expect(read('Plan the offsite. Assigned to Sam').people, ['Sam']);
      expect(read('Plan the offsite for sam').people, isEmpty);
    });

    test('reads them in any order, each kind once', () {
      expect(
        read('Fix the login loop, due tomorrow, high priority, for Sam'),
        const SpokenFields(words: 'Fix the login loop', due: '2026-10-02', priority: 'high', people: ['Sam']),
      );
      expect(read('Fix the login loop for Sam, urgent, due Friday'), const SpokenFields(words: 'Fix the login loop', due: '2026-10-02', priority: 'high', people: ['Sam']));
      // The second "due" at the end is the field; the first is the item's words.
      final found = read('Move the meeting due Friday due Monday');
      expect((found.words, found.due), ('Move the meeting due Friday', '2026-10-05'));
    });
  });

  group('what stays words', () {
    test('keeps a "due" with no day it can read after it', () {
      for (final words in ['The rent is due', 'The rent is due soon', 'Check what is due at the end of the month', 'Due Friday the deck is ready']) {
        expect(read(words), SpokenFields(words: words, due: null, priority: null, people: const []), reason: words);
      }
    });

    test('keeps a priority said in the middle of an item', () {
      expect(read('High priority work on the deck').priority, isNull);
      expect(read('Ask why it was urgent yesterday').priority, isNull);
    });

    test('keeps a "for" that is not who does it', () {
      for (final words in [
        'Buy a present for Sam',
        'Book flights for Lisbon',
        'Bake a cake for Friday',
        'Set it up for now',
        'Hold the table for Christmas',
        'Talk to Jo for an hour',
        'Plan the budget for Q3',
        'Ask about it for October',
      ]) {
        expect(read(words).people, isEmpty, reason: words);
      }
    });

    test('keeps an item that is nothing but a cue', () {
      expect(line('- [ ] Urgent'), '- [ ] Urgent');
      expect(line('Due tomorrow'), 'Due tomorrow');
    });
  });

  group('written as the item’s fields', () {
    test('writes them where Obsidian Tasks reads them, a person before the run', () {
      expect(line('- [ ] Fix the login loop, due tomorrow, high priority, for Sam'), '- [ ] Fix the login loop @Sam ⏫ 📅 2026-10-02');
      expect(line('- Renew the passport, urgent, assigned to Matt'), '- Renew the passport @Matt ⏫');
      expect(line('- [ ] Plan the offsite for Sam Ortiz'), '- [ ] Plan the offsite @Sam-Ortiz');
    });

    test('writes them on the words alone too, and leaves an item with no cue as it is', () {
      expect(line('Call the plumber due Friday'), 'Call the plumber 📅 2026-10-02');
      expect(line('- [ ] Call the plumber'), '- [ ] Call the plumber');
    });

    test('keeps what the item already has', () {
      final written = line('- [ ] Call the plumber @matt #home due Friday');
      expect(written, '- [ ] Call the plumber @matt #home 📅 2026-10-02');
      final fields = fieldsOf(written);
      expect(fields.due, '2026-10-02');
      expect(fields.assignees, ['matt']);
    });
  });

  group('a sentence that is only a field', () {
    test('is a due day or a priority, but never a person on their own', () {
      expect(onlyFields('Due Friday.', today), true);
      expect(onlyFields('High priority.', today), true);
      expect(onlyFields('Urgent, due tomorrow.', today), true);
      expect(onlyFields('For Sam.', today), false);
      expect(onlyFields('The rent is due.', today), false);
      expect(onlyFields('Due soon.', today), false);
    });
  });
}
