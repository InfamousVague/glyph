// Cases taken from src/app/capture/listAppend.test.ts and capture/spoken/fields.test.ts, to hold the half of those
// files that lib/ai/support carries for the review (list_append.dart, spoken_fields.dart) to the web's answers. Not
// the whole of either file: the rest comes with the capture stage's own port.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/support/list_append.dart';
import 'package:ghost_md/ai/support/spoken_fields.dart';

void main() {
  const today = '2026-10-01';

  group('items put on a note’s list', () {
    test('take the list’s own style: its number, its bullet, its box', () {
      expect(appendToList('Steps\n\n1) Build\n2) Test', ['ship it', 'celebrate']).body, 'Steps\n\n1) Build\n2) Test\n3) Ship it\n4) Celebrate');
      expect(appendToList('- One\n  more about one\n* Two\n  - child\n\nEnd.', ['three']).body, '- One\n  more about one\n* Two\n  - child\n* Three\n\nEnd.');
      expect(appendToList('* [ ] Milk\n* [x] Eggs', ['bread']).added, ['* [ ] Bread']);
      expect(appendToList('1. [ ] Unplug it\n2. [ ] Wait', ['plug it back in']).added, ['3. [ ] Plug it back in']);
      expect(appendToList('- [ ]', ['first thing']).added, ['- [ ] First thing']);
      expect(appendToList('# Ideas\n\n-\tTabbed\n-  Spaced', ['more']).body, '# Ideas\n\n-\tTabbed\n-  Spaced\n- More');
      expect(appendToList('1000. The thousandth', ['next']).added, ['1001. Next']);
    });

    test('start a list on a note with none, and add nothing for nothing', () {
      expect(appendToList('# Backlog\n\nIdeas go here.\n', ['dark mode']).body, '# Backlog\n\nIdeas go here.\n\n- Dark mode\n');
      expect(appendToList('# Backlog', ['dark mode'], asTasks: true).body, '# Backlog\n\n- [ ] Dark mode\n');
      expect(appendToList('', ['first']).body, '- First\n');
      expect(appendToList('- a', ['  ', '.']).added, isEmpty);
    });

    test('write the fields said at an item’s end', () {
      expect(appendToList('# House\n\n- [ ] Fix the tap', ['call the plumber due Friday.'], today: today).added, ['- [ ] Call the plumber 📅 2026-10-02']);
      expect(appendToList('', ['renew the passport, urgent, for Sam'], asTasks: true, today: today).added, ['- [ ] Renew the passport @Sam ⏫']);
      expect(appendToList('1. Build', ['ship it by Friday'], today: today).added, ['2. Ship it by Friday']);
    });

    test('leave a short thing as an item of the list it fits', () {
      expect(leaveNote('# Bugs\n\n- Menu runs off the edge', 'to fix the bug where the menu flickers').added, ['- Fix the bug where the menu flickers']);
      expect(leaveNote('# Plain', 'that says the login is broken on Android').body, '# Plain\n\nThe login is broken on Android.\n');
    });
  });

  group('cues read at the end of an item', () {
    SpokenFields read(String words) => spokenFields(words, today);

    test('reads a due day, a priority and a person, and leaves words that are none of them', () {
      final due = read('Call the plumber due Friday');
      expect([due.words, due.due, due.priority, due.people], ['Call the plumber', '2026-10-02', null, <String>[]]);
      expect(read('The report is due next week').words, 'The report');
      expect(read('Ship the patch top priority').priority, 'highest');
      expect(read('Answer the auditor, it’s a medium-priority').words, 'Answer the auditor');
      expect(read('Renew the passport, priority high').priority, 'high');
      expect(read("Call the bank, it's urgent").priority, 'high');
      expect(read('Plan the offsite assign it to Sam Ortiz').people, ['Sam Ortiz']);
      expect(read('Plan the offsite for sam').people, isEmpty);
    });
  });
}
