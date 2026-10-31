import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/gantt/gantt.dart';

/// A ```gantt fence read (lib/core/gantt/format.dart) and worked out in days (plan.dart): every mark a task's line
/// can have, the days in each of their forms, working days, milestones, waits, loops, tickets, and the body written
/// back unchanged where nothing was done to it.
const String project = '''title: Waitlist launch
start: 2026-11-02
workdays: true
today: 2026-11-04

## Research
- Interview five users [2026-11-02 → 2026-11-04] @matt #research 100%
- Read the competition [2026-11-03 +3d] @sam

## Build
- Design the waitlist [2026-11-05 → 2026-11-11] @matt #design after: Interview five users 60%
- Build the signup page [+4d] after: Design the waitlist
- ◆ Launch [2026-11-20] after: Build the signup page

Later:
- Tell the press
%% a comment the chart reads as nothing''';

void main() {
  group('a task’s line', () {
    test('reads every mark, in any order, and where each is', () {
      final task = readTaskLine('- Design the waitlist [2026-11-02 → 2026-11-06] @matt #design after: Research, Read up 60% colour: teal', 0, 0)!;
      expect(task.name, 'Design the waitlist');
      expect(task.dates!.form, DatesForm.range);
      expect((task.dates!.start, task.dates!.end), ('2026-11-02', '2026-11-06'));
      expect(task.people.map((p) => p.value), ['matt']);
      expect(task.tags.map((t) => t.value), ['design']);
      expect(task.after, ['Research', 'Read up']);
      expect(task.progress, 60);
      expect(task.colour, 'teal');
      final moved = readTaskLine('- Design 40% @sam after: Research [2026-11-02 +2w] #ux', 0, 0)!;
      expect((moved.name, moved.progress, moved.person, moved.dates!.length, moved.dates!.weeks), ('Design', 40, 'sam', 2, true));
      expect(moved.after, ['Research']);
    });

    test('reads each form of days', () {
      DatesForm? form(String line) => readTaskLine(line, 0, 0)!.dates?.form;
      expect(form('- A [2026-11-02 → 2026-11-06]'), DatesForm.range);
      expect(form('- A [2026-11-02 -> 2026-11-06]'), DatesForm.range);
      expect(form('- A [2026-11-02 .. 2026-11-06]'), DatesForm.range);
      expect(form('- A [2026-11-02 to 2026-11-06]'), DatesForm.range);
      expect(form('- A [2026-11-02 +5d]'), DatesForm.length);
      expect(form('- A [2026-11-02 + 5 days]'), DatesForm.length);
      expect(form('- A [2026-11-02]'), DatesForm.day);
      expect(form('- A [+5d]'), DatesForm.lengthOnly);
      expect(form('- A [3w]'), DatesForm.lengthOnly);
      expect(form('- A [soon]'), isNull);
      expect(readTaskLine('- A [soon]', 0, 0)!.name, 'A [soon]', reason: 'brackets that are not days are words');
    });

    test('takes a [[link]] alone for a ticket, and a milestone by its mark', () {
      final ticket = readTaskLine('- [[KLN-12|Login]] after: Design', 0, 0)!;
      expect((ticket.link, ticket.alias, ticket.shown), ('KLN-12', 'Login', 'Login'));
      expect(ticket.after, ['Design']);
      final words = readTaskLine('- Fix [[KLN-12]] for good', 0, 0)!;
      expect((words.link, words.shown), (null, 'Fix KLN-12 for good'));
      final stone = readTaskLine('- ◆ Launch [2026-11-20]', 0, 0)!;
      expect((stone.milestone, stone.name), (true, 'Launch'));
    });

    test('keeps a mark inside a link as the link’s words', () {
      final task = readTaskLine('- [[Plan @home #2]] [2026-11-02]', 0, 0)!;
      expect(task.people, isEmpty);
      expect(task.tags, isEmpty);
      expect(task.link, 'Plan @home #2');
    });
  });

  group('a fence', () {
    test('reads its front lines, its sections both ways, and keeps every other line', () {
      final body = readGantt(project);
      expect(body.front.title, 'Waitlist launch');
      expect(body.front.start, '2026-11-02');
      expect(body.front.workdays, isTrue);
      expect(body.front.today, '2026-11-04');
      expect(body.front.follow, isTrue);
      expect(body.sections.map((s) => (s.name, s.heading)), [('Research', true), ('Build', true), ('Later', false)]);
      expect(body.tasks.map((t) => t.section), [0, 0, 1, 1, 1, 2]);
      expect(body.problems, isEmpty);
      expect(body.text, project, reason: 'read and written back, nothing changes');
    });

    test('says what it cannot read, with its line', () {
      final body = readGantt('zoom: decade\nworkdays: maybe\n- A [2026-02-30]');
      expect(body.problems, ['Line 1: zoom: is week, month or quarter.', 'Line 2: workdays: is true or false.', 'Line 3: 2026-02-30 isn’t a day on the calendar.']);
    });
  });

  group('the days worked out', () {
    GanttModel model(String body, {GanttTickets? tickets}) => ganttModelOf(readGantt(body), today: '2026-10-30', tickets: tickets);

    test('a range, a length in working days, one that waits, and a milestone', () {
      final chart = model(project);
      final days = {for (final item in chart.items) item.name: (item.start, item.end)};
      expect(days['Interview five users'], ('2026-11-02', '2026-11-04'));
      expect(days['Read the competition'], ('2026-11-03', '2026-11-05'), reason: 'three working days from a Tuesday');
      expect(days['Design the waitlist'], ('2026-11-05', '2026-11-11'));
      expect(days['Build the signup page'], ('2026-11-12', '2026-11-17'), reason: 'four working days from the Thursday after, the weekend skipped');
      expect(days['Launch'], ('2026-11-20', '2026-11-20'));
      expect(days['Tell the press'], ('2026-11-02', '2026-11-02'), reason: 'no days and nothing to wait on: the chart’s start');
      expect(chart.byKey['L15']!.undated, isTrue);
      expect(chart.byKey['L11']!.derivedStart, isTrue);
      expect(chart.byKey['L11']!.after, ['L10']);
      expect(chart.today, '2026-11-04', reason: 'the fence’s own today');
      expect(chart.groups.map((g) => g.name), ['Research', 'Build', 'Later']);
    });

    test('calendar days without workdays, and weeks', () {
      final chart = model('- A [2026-11-06 +3d]\n- B [2026-11-06 +1w]\n- C [+2d] after: A');
      expect([for (final item in chart.items) (item.start, item.end)], [('2026-11-06', '2026-11-08'), ('2026-11-06', '2026-11-12'), ('2026-11-09', '2026-11-10')]);
    });

    test('a loop is drawn without the wait that closes it, and said', () {
      final chart = model('- A [2026-11-02] after: C\n- B after: A\n- C after: B');
      expect(chart.problems.single, contains('which is a loop'));
      expect(chart.byKey['L1']!.after, isEmpty, reason: 'found walking from A: A waits on C, C on B, and B’s wait on A closes it');
      expect(chart.byKey['L0']!.after, ['L2']);
      expect(chart.byKey['L2']!.after, ['L1']);
    });

    test('a name no task has, and a task that waits on itself, are said', () {
      final chart = model('- A after: Nobody\n- B after: B');
      expect(chart.problems, ['Line 1: no task is called “Nobody”.', 'Line 2: “B” can’t wait on itself.']);
    });

    test('a ticket’s line takes the ticket’s days, person and done until it has its own', () {
      GanttTicket? find(String title) => title == 'KLN-12' ? const GanttTicket(noteId: 'n12', title: 'Fix the login loop', key: 'KLN-12', start: '2026-11-03', due: '2026-11-06', assignee: 'sam', done: true) : null;
      final chart = model('- [[KLN-12]]\n- [[KLN-12]] [2026-11-10]\n- Ship after: KLN-12', tickets: find);
      final ticket = chart.byKey['L0']!;
      expect((ticket.name, ticket.label, ticket.start, ticket.end, ticket.person, ticket.done, ticket.ticket?.noteId), ('Fix the login loop', 'KLN-12', '2026-11-03', '2026-11-06', 'sam', true, 'n12'));
      expect(chart.byKey['L1']!.ticket, isNull, reason: 'its own days are the line’s to write');
      expect(chart.byKey['L1']!.start, '2026-11-10');
      expect(chart.byKey['L2']!.after, ['L0'], reason: 'a ticket answers to its key');
      expect(chart.byKey['L2']!.start, '2026-11-07');
    });
  });

  group('following', () {
    test('pushes what waits along just far enough, and what waits on that, and keeps their lengths', () {
      final chart = ganttModelOf(readGantt('- A [2026-11-02 → 2026-11-04]\n- B [2026-11-06 → 2026-11-09] after: A\n- C [2026-11-20] after: B\n- D [+2d] after: A'), today: '2026-11-01');
      final moved = followed(chart, {'L0': (start: '2026-11-05', end: '2026-11-07')});
      expect(moved['L1'], (start: '2026-11-08', end: '2026-11-11'));
      expect(moved.containsKey('L2'), isFalse, reason: 'it already starts after B');
      expect(moved['L3'], (start: '2026-11-08', end: '2026-11-09'), reason: 'a start that is its waits’ goes with them');
      final back = followed(chart, {'L0': (start: '2026-10-30', end: '2026-10-31')});
      expect(back.containsKey('L1'), isFalse, reason: 'moved earlier, nothing is pulled');
      expect(back['L3'], (start: '2026-11-01', end: '2026-11-02'));
      expect(followed(chart, {'L0': (start: '2026-11-05', end: '2026-11-07')}, follow: false).keys, ['L0']);
    });

    test('refuses a wait that would make a loop, with why', () {
      final chart = ganttModelOf(readGantt('- A [2026-11-02]\n- B after: A\n- C after: B'), today: '2026-11-01');
      expect(waitProblem(chart, 'L0', 'L2'), 'That would make a loop: “C” already waits on “A”.');
      expect(waitProblem(chart, 'L1', 'L0'), '“B” already waits on “A”.');
      expect(waitProblem(chart, 'L0', 'L0'), '“A” can’t wait on itself.');
      expect(waitProblem(chart, 'L2', 'L0'), isNull);
    });
  });
}
