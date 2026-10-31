import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/gantt/gantt.dart';

/// What each thing done to a chart writes into its fence (lib/core/gantt/edits.dart): exactly the line it changes,
/// each mark written in the form the line had it, and nothing else; the waits that follow; what is refused.
const String fence = '''title: Launch
## Build
- Design [2026-11-02 → 2026-11-04] @matt 50%
- Build [2026-11-05 +3d] after: Design
- Test [+2d] after: Build
- ◆ Ship [2026-11-12] after: Test
## Later
- Tell the press''';

GanttBody body0() => readGantt(fence);
GanttModel model0([String text = fence]) => ganttModelOf(readGantt(text), today: '2026-11-01');

/// The fence once [change] is written, and the lines it wrote.
(String, List<GanttLineChange>) run(GanttChange change, [String text = fence]) => (appliedGantt(text, change), change.lines);

void main() {
  group('a bar carried', () {
    test('writes over its days alone, the arrow as it was', () {
      final (after, lines) = run(moveDays(body0(), model0(), 'L2', '2026-11-03', '2026-11-05', follow: false));
      expect(lines, [const GanttLineChange(2, 1, ['- Design [2026-11-03 → 2026-11-05] @matt 50%'])]);
      expect(after.split('\n')[2], '- Design [2026-11-03 → 2026-11-05] @matt 50%');
      final arrow = readGantt('- A [2026-11-02 -> 2026-11-04] #x');
      final moved = moveDays(arrow, ganttModelOf(arrow, today: '2026-11-01'), 'L0', '2026-11-09', '2026-11-11');
      expect(appliedGantt(arrow.text, moved), '- A [2026-11-09 -> 2026-11-11] #x');
    });

    test('pushes what waits on it along, one line each, a start that is its waits’ left alone', () {
      final change = moveDays(body0(), model0(), 'L2', '2026-11-04', '2026-11-06');
      final (after, lines) = run(change);
      expect(lines, [
        const GanttLineChange(2, 1, ['- Design [2026-11-04 → 2026-11-06] @matt 50%']),
        const GanttLineChange(3, 1, ['- Build [2026-11-07 +3d] after: Design']),
      ]);
      // Build now ends on the 9th, Test (its start Build's) runs the 10th and 11th and its line says nothing new;
      // Ship is on the 12th, still after it.
      expect(after.split('\n')[4], '- Test [+2d] after: Build');
      expect(after.split('\n')[5], '- ◆ Ship [2026-11-12] after: Test');
      final further = moveDays(body0(), model0(), 'L2', '2026-11-06', '2026-11-08');
      expect(appliedGantt(fence, further).split('\n')[5], '- ◆ Ship [2026-11-14] after: Test', reason: 'pushed by Test, which was pushed by Build');
    });

    test('an end carried keeps a length a length, and a start that is its waits’', () {
      final model = model0();
      expect(run(moveDays(body0(), model, 'L3', '2026-11-05', '2026-11-09', how: GanttGrip.end, follow: false)).$2.single.insert.single, '- Build [2026-11-05 +5d] after: Design');
      // Test runs the 8th and 9th; its end carried to the 11th.
      expect(run(moveDays(body0(), model, 'L4', '2026-11-08', '2026-11-11', how: GanttGrip.end, follow: false)).$2.single.insert.single, '- Test [+4d] after: Build');
      expect(run(moveDays(body0(), model, 'L4', '2026-11-09', '2026-11-10', follow: false)).$2.single.insert.single, '- Test [2026-11-09 +2d] after: Build', reason: 'moved, it has a start of its own');
    });

    test('in working days, and in weeks where it still comes to weeks', () {
      const text = 'workdays: true\n- A [2026-11-02 +1w]\n- B [2026-11-02 +1w]';
      final model = model0(text);
      expect(model.byKey['L1']!.end, '2026-11-06');
      expect(run(moveDays(readGantt(text), model, 'L1', '2026-11-09', '2026-11-13'), text).$2.single.insert.single, '- A [2026-11-09 +1w]');
      expect(run(moveDays(readGantt(text), model, 'L2', '2026-11-02', '2026-11-09', how: GanttGrip.end), text).$2.single.insert.single, '- B [2026-11-02 +6d]');
    });

    test('a task with no days is given some after its name; a milestone a day', () {
      final change = moveDays(body0(), model0(), 'L7', '2026-11-20', '2026-11-21');
      expect(change.lines.single.insert.single, '- Tell the press [2026-11-20 → 2026-11-21]');
      final stone = moveDays(body0(), model0(), 'L5', '2026-11-13', '2026-11-13');
      expect(stone.lines.single.insert.single, '- ◆ Ship [2026-11-13] after: Test');
    });

    test('a ticket’s days are written to the ticket, not the fence', () {
      const ticket = GanttTicket(noteId: 'n12', title: 'Fix the login loop', key: 'KLN-12', start: '2026-11-03', due: '2026-11-06');
      final body = readGantt('- [[KLN-12]]');
      final model = ganttModelOf(body, today: '2026-11-01', tickets: (title) => ticket);
      final change = moveDays(body, model, 'L0', '2026-11-05', '2026-11-08');
      expect(change.lines, isEmpty);
      expect(change.tickets.single.ticket.noteId, 'n12');
      expect(change.tickets.single.fields, {'start': '2026-11-05', 'due': '2026-11-08'});
    });
  });

  group('waits', () {
    test('one drawn writes its after:, before how far along, and pushes the task along', () {
      const text = '- A [2026-11-05]\n- B [2026-11-02 → 2026-11-03] 50%\n- C [+1d] after: B';
      final change = addWait(readGantt(text), model0(text), 'L1', 'L0');
      expect(change.refused, isNull);
      expect(change.lines, [const GanttLineChange(1, 1, ['- B [2026-11-06 → 2026-11-07] after: A 50%'])], reason: 'C starts after B whatever B does');
    });

    test('one drawn where the chart does not follow writes only the after:', () {
      const text = 'follow: false\n- A [2026-11-02]\n- B [2026-11-01]';
      final change = addWait(readGantt(text), model0(text), 'L2', 'L1');
      expect(change.lines, [const GanttLineChange(2, 1, ['- B [2026-11-01] after: A'])]);
    });

    test('one that makes a loop is refused, with why', () {
      final change = addWait(body0(), model0(), 'L2', 'L5');
      expect(change.refused, 'That would make a loop: “Ship” already waits on “Design”.');
      expect(change.isEmpty, isTrue);
    });

    test('one taken off takes its name out, and the after: with its last name', () {
      expect(run(removeWait(body0(), model0(), 'L3', 'L2')).$2.single.insert.single, '- Build [2026-11-05 +3d]');
      const text = '- A [2026-11-02]\n- B [2026-11-02]\n- C [2026-11-09] after: A, B 20%';
      expect(run(removeWait(readGantt(text), model0(text), 'L2', 'L0'), text).$2.single.insert.single, '- C [2026-11-09] after: B 20%');
    });

    test('set from the panel: a name no task has, or a loop, is refused', () {
      expect(setWaits(body0(), model0(), 'L2', ['Nobody']).refused, 'no task is called “Nobody”.');
      expect(setWaits(body0(), model0(), 'L2', ['Ship']).refused, contains('loop'));
      expect(setWaits(body0(), model0(), 'L7', ['Ship']).lines.first.insert.single, '- Tell the press after: Ship');
    });
  });

  group('tasks', () {
    test('one added goes under the one selected, as its list item, and is selected', () {
      final change = addTask(body0(), model0(), afterKey: 'L2', start: '2026-11-05', end: '2026-11-06');
      expect(change.lines, [const GanttLineChange(3, 0, ['- New task [2026-11-05 → 2026-11-06]'])]);
      expect(change.select, 3);
      final last = addTask(body0(), model0(), group: 1, name: 'Blog post', start: '2026-11-20');
      expect(last.lines, [const GanttLineChange(8, 0, ['- Blog post [2026-11-20]'])]);
      final starred = readGantt('* A [2026-11-02]');
      expect(addTask(starred, ganttModelOf(starred, today: '2026-11-01'), afterKey: 'L0', start: '2026-11-03').lines.single.insert.single, '* New task [2026-11-03]');
    });

    test('one added to an empty section goes under its heading, and to an empty fence on its one line', () {
      const text = '## Now\n\n## Next';
      expect(addTask(readGantt(text), model0(text), group: 1, start: '2026-11-02').lines.single, const GanttLineChange(3, 0, ['- New task [2026-11-02]']));
      expect(appliedGantt('', addTask(readGantt(''), model0(''), start: '2026-11-02')), '- New task [2026-11-02]');
    });

    test('one taken out goes, and its name from every after: with it', () {
      final (after, _) = run(deleteTask(body0(), model0(), 'L3'));
      expect(after, fence.replaceFirst('- Build [2026-11-05 +3d] after: Design\n', '').replaceFirst('- Test [+2d] after: Build', '- Test [+2d]'));
    });

    test('one renamed is renamed in every after: too, a milestone keeping its mark', () {
      final (after, lines) = run(renameTask(body0(), model0(), 'L3', 'Build it'));
      expect(lines.length, 2);
      expect(after.split('\n')[3], '- Build it [2026-11-05 +3d] after: Design');
      expect(after.split('\n')[4], '- Test [+2d] after: Build it');
      expect(run(renameTask(body0(), model0(), 'L5', 'Go live')).$1.split('\n')[5], '- ◆ Go live [2026-11-12] after: Test');
    });

    test('its people, how far along, its colour and its milestone, each its own mark', () {
      expect(setPeople(body0(), model0(), 'L2', ['@sam', 'ana']).lines.single.insert.single, '- Design [2026-11-02 → 2026-11-04] @sam @ana 50%');
      expect(setPeople(body0(), model0(), 'L3', ['sam']).lines.single.insert.single, '- Build [2026-11-05 +3d] @sam after: Design');
      expect(setPeople(body0(), model0(), 'L2', []).lines.single.insert.single, '- Design [2026-11-02 → 2026-11-04] 50%');
      expect(setProgress(body0(), model0(), 'L2', 80).lines.single.insert.single, '- Design [2026-11-02 → 2026-11-04] @matt 80%');
      expect(setProgress(body0(), model0(), 'L3', 10).lines.single.insert.single, '- Build [2026-11-05 +3d] after: Design 10%');
      expect(setProgress(body0(), model0(), 'L2', null).lines.single.insert.single, '- Design [2026-11-02 → 2026-11-04] @matt');
      expect(setColour(body0(), model0(), 'L3', 'teal').lines.single.insert.single, '- Build [2026-11-05 +3d] colour: teal after: Design');
      expect(setMilestone(body0(), model0(), 'L2', true).lines.single.insert.single, '- ◆ Design [2026-11-02] @matt 50%');
      expect(setMilestone(body0(), model0(), 'L5', false).lines.single.insert.single, '- Ship [2026-11-12] after: Test');
    });

    test('a row moved to another section: two lines, and selected where it lands', () {
      final change = moveRow(body0(), model0(), 'L2', group: 1);
      expect(change.lines, [const GanttLineChange(2, 1, []), const GanttLineChange(8, 0, ['- Design [2026-11-02 → 2026-11-04] @matt 50%'])]);
      expect(change.select, 7);
      final up = moveRow(body0(), model0(), 'L4', group: 0, beforeKey: 'L2');
      expect(appliedGantt(fence, up).split('\n').sublist(2, 5), ['- Test [+2d] after: Build', '- Design [2026-11-02 → 2026-11-04] @matt 50%', '- Build [2026-11-05 +3d] after: Design']);
      expect(up.select, 2);
    });

    test('a front line set where it is, or put in at the top', () {
      expect(setFront(body0(), 'title', 'Go').lines.single, const GanttLineChange(0, 1, ['title: Go']));
      expect(setFront(body0(), 'follow', 'false').lines.single, const GanttLineChange(1, 0, ['follow: false']));
      expect(appliedGantt(fence, setFront(body0(), 'title', null)).startsWith('## Build'), isTrue);
    });
  });

  group('the fewest lines', () {
    test('a line changed is that line; one put in is one insert', () {
      expect(lineDiff(['a', 'b', 'c'], ['a', 'B', 'c']), [const GanttLineChange(1, 1, ['B'])]);
      expect(lineDiff(['a', 'b', 'c'], ['a', 'b', 'x', 'c']), [const GanttLineChange(2, 0, ['x'])]);
      expect(lineDiff(['a', 'b', 'c', 'd'], ['A', 'b', 'c', 'D']), [const GanttLineChange(0, 1, ['A']), const GanttLineChange(3, 1, ['D'])]);
      expect(lineDiff(['a'], ['a']), isEmpty);
    });
  });
}
