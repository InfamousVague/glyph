import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/reminders/tick_item.dart';

/// Done from a notification or the home screen (lib/reminders/tick_item.dart): the box ticked as a tap on it ticks
/// it, found by its words where lines were written above it, and a ticket's status set to its workflow's done.
void main() {
  group('a to-do', () {
    test('ticked on its line', () {
      expect(doneIn('# Errands\n- [ ] Call the plumber 📅 2026-10-03\n- [ ] Buy milk', line: 2, words: 'Call the plumber'), '# Errands\n- [x] Call the plumber 📅 2026-10-03\n- [ ] Buy milk');
    });

    test('found by its words where lines were written above it since', () {
      expect(doneIn('# Errands\n\nA new line\n- [ ] Buy milk\n- [ ] Call the plumber', line: 2, words: 'Call the plumber'), '# Errands\n\nA new line\n- [ ] Buy milk\n- [x] Call the plumber');
    });

    test('the nearest of two that say the same', () {
      expect(doneIn('- [ ] Call\n\n\n\n- [ ] Call', line: 4, words: 'Call'), '- [ ] Call\n\n\n\n- [x] Call');
    });

    test('nothing where it is ticked already, gone, or has no box', () {
      expect(doneIn('- [x] Call', line: 1, words: 'Call'), isNull);
      expect(doneIn('- [ ] Something else', line: 1, words: 'Call'), isNull);
      expect(doneIn('- Call', line: 1, words: 'Call'), isNull);
    });

    test('a card on a board moves to Done with it, as a tap on its box moves it', () {
      const body = '```board\nTo do: ship-page, pick-date\nDone:\n```\n\n- [ ] Ship the pricing page ^ship-page\n- [ ] Pick a launch date ^pick-date';
      final ticked = doneIn(body, line: 7, words: 'Pick a launch date')!;
      expect(ticked.split('\n').last, '- [x] Pick a launch date ^pick-date');
      expect(ticked, contains('Done: pick-date'));
      expect(ticked, isNot(contains('To do: ship-page, pick-date')));
    });
  });

  group('a ticket', () {
    test('its status set to its workflow’s done', () {
      final done = doneIn('---\ntype: ticket\nstatus: To do\n---\n# Fix the login', line: 0, words: '')!;
      expect(frontMatterValue(done, 'status'), 'Done');
      final own = doneIn('---\ntype: ticket\nstatus: Ideas\n---\n# A thing', line: 0, words: '', statuses: ['Ideas', 'Building', 'Live'])!;
      expect(frontMatterValue(own, 'status'), 'Live');
    });

    test('nothing once it is done, or for a note that is not one', () {
      expect(doneIn('---\ntype: ticket\nstatus: Done\n---\n# Old', line: 0, words: ''), isNull);
      expect(doneIn('# Just a note', line: 0, words: ''), isNull);
    });
  });

  test('a link’s words find the line they begin', () {
    expect(findItemNear('a\n- [ ] Call the plumber about the boiler\nb', 3, 'Call the plumber'), 2);
    expect(findItemNear('a\nb', 2, 'Gone'), 2);
  });
}
