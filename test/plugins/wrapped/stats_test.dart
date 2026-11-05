// Wrapped's counts with no AI (lib/plugins/wrapped/stats.dart, todos.dart; docs/WRAPPED.md, "The counts"): notes and
// words of the period, the busiest month, day and hour, the longest streak, the notes most linked to, the top tags and
// folders, to-dos done and open, meetings and recordings; and the to-dos read, checked off and taken out.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/wrapped/wrapped.dart';

import 'support.dart';

void main() {
  late WrappedWorld world;
  setUp(() => world = WrappedWorld());

  test('this year: the notes written in it, their words, and when', () {
    final stats = world.service().stats(WrappedPeriod.year);
    // The ten less last year's draft, the soup of the year before and the organization's note.
    expect(stats.notes, 7);
    expect(stats.words, greaterThan(40));
    // March and May have three each; the first to get there wins.
    expect(stats.busiestMonth, (year: 2026, month: 3, count: 3));
    expect(stats.busiestMonthWords, 'March');
    // The two standups, the meeting and the packing list on Tuesdays; most at nine.
    expect(stats.busiestDayWords, 'Tuesdays');
    expect(stats.busiestHourWords, '9 am');
    expect(stats.longestStreak, 3, reason: 'the 2nd, 3rd and 4th of March');
    expect(stats.todosDone, 4);
    expect(stats.todosOpen, 4);
    expect(stats.meetings, 1);
    expect(stats.recordings, 1);
  });

  test('the notes most linked to, the tags and the folders', () {
    final stats = world.service().stats(WrappedPeriod.year);
    expect(stats.mostLinked.first, (id: 'packing', title: 'Packing list', links: 2));
    expect([for (final t in stats.topTags) t.name], containsAll(['travel', 'work']));
    expect(stats.topFolders.first, (name: 'Work', count: 2));
  });

  test('all time counts every note of the person’s own; an empty period is empty', () {
    expect(world.service().stats(WrappedPeriod.all).notes, 9);
    final empty = wrappedStats(const [], WrappedPeriod.year, now: wrappedNow);
    expect(empty.isEmpty, isTrue);
    expect(empty.longestStreak, 0);
    expect(empty.busiestMonth, isNull);
  });

  test('last 12 months reaches back into last November', () {
    final stats = wrappedStats([wrappedNote('a', '# A', written: at(2025, 12, 1)), wrappedNote('b', '# B', written: at(2025, 10, 1))], WrappedPeriod.last12, now: wrappedNow);
    expect(stats.notes, 1);
  });

  test('a note in the Trash is not counted', () {
    final notes = [wrappedNote('a', '# A', written: at(2026, 2, 1)), wrappedNote('b', '# B', written: at(2026, 2, 1)).copyWith(path: () => '.trash/B.md')];
    expect(wrappedStats(notes, WrappedPeriod.year, now: wrappedNow).notes, 1);
  });

  group('to-dos', () {
    const body = '# List\n\n- [ ] One\n- [x] Two\n  * [ ] Three nested\n```\n- [ ] in code\n```\n1. [ ] Numbered';

    test('open ones are read outside code, with their lines', () {
      final todos = openTodos('n', body);
      expect([for (final t in todos) t.words], ['One', 'Three nested', 'Numbered']);
      expect(todos.first.line, 2);
      expect(todoCounts(body), (done: 1, open: 3));
    });

    test('checked off and taken out where they are now, even moved', () {
      final todos = openTodos('n', body);
      expect(checkedOff(body, [todos.first]), contains('- [x] One'));
      final moved = '# List\n\nNew line\n${body.split('\n').skip(2).join('\n')}';
      expect(checkedOff(moved, [todos[1]]), contains('  * [x] Three nested'));
      expect(withoutTodos(body, [todos.first]), isNot(contains('One')));
      expect(withoutTodos('# Gone', [todos.first]), isNull);
    });
  });
}
