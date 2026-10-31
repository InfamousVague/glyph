import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/planning/cycles.dart';
import 'package:ghost_md/core/planning/history.dart';
import 'package:ghost_md/core/planning/planning.dart';
import 'package:ghost_md/core/properties.dart';

int at(String day, [int hour = 12]) => DateTime(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)), int.parse(day.substring(8)), hour).millisecondsSinceEpoch;

String ticket(String status) => '---\ntype: ticket\nstatus: $status\n---\n# A ticket\n';

void main() {
  group('estimates', () {
    test('are points, or hours however they are written', () {
      expect(estimateOf('3'), const Estimate(3, EstimateUnit.points));
      expect(estimateOf('2.5 points'), const Estimate(2.5, EstimateUnit.points));
      expect(estimateOf('5sp'), const Estimate(5, EstimateUnit.points));
      expect(estimateOf('4h'), const Estimate(4, EstimateUnit.hours));
      expect(estimateOf('90m'), const Estimate(1.5, EstimateUnit.hours));
      expect(estimateOf('2d'), const Estimate(16, EstimateUnit.hours));
      expect(estimateOf('some'), isNull);
      expect(estimateOf(null), isNull);
    });

    test('add up apart, points beside hours, and per assignee', () {
      expect(totalsOf(['3', '5', '4h', null, '30m']).words, '8 points · 4.5h');
      expect(totalsOf(['3', '5', '4h', null, '30m']).unestimated, 1);
      expect(totalsOf(['1']).words, '1 point');
      expect(totalsOf([null]).words, 'No estimates');
      final by = totalsBy([(who: 'Sam', estimate: '3'), (who: 'Priya', estimate: '5'), (who: 'Sam', estimate: '2'), (who: null, estimate: '1h')]);
      expect(by['Sam']!.words, '5 points');
      expect(by['Priya']!.points, 5);
      expect(by[null]!.words, '1h');
    });
  });

  group('a burndown', () {
    const cycle = Cycle(name: '2026-C45', start: '2026-11-02', end: '2026-11-08');

    test('counts down what remains at the end of each day, and stops at today', () {
      final days = burndownOf(cycle, [
        (key: 'a', weight: 3, done: '2026-11-03'),
        (key: 'b', weight: 5, done: '2026-11-05'),
        (key: 'c', weight: 2, done: null),
        // Finished before the cycle began: finished on its first day.
        (key: 'd', weight: 1, done: '2026-10-30'),
      ], '2026-11-05');
      expect([for (final day in days) day.remaining], [10, 7, 7, 2, null, null, null]);
      expect([for (final day in days) day.ideal], [11, closeTo(11 * 5 / 6, 1e-9), closeTo(11 * 4 / 6, 1e-9), 5.5, closeTo(11 * 2 / 6, 1e-9), closeTo(11 / 6, 1e-9), 0]);
      expect(days[3].left, ['c']);
      expect(days.first.day, '2026-11-02');
      expect(days.last.day, '2026-11-08');
    });

    test('of a cycle with no days is nothing', () {
      expect(burndownOf(const Cycle(name: 'Someday', start: null, end: null), const [], '2026-11-05'), isEmpty);
    });

    test('weighs a ticket by its points, or one each where none is estimated', () {
      expect(weightOf('3', byPoints: true), 3);
      expect(weightOf(null, byPoints: true), 0);
      expect(weightOf('3', byPoints: false), 1);
      expect(anyEstimated([null, '2']), isTrue);
      expect(anyEstimated([null, 'soon']), isFalse);
    });
  });

  group('velocity', () {
    const c43 = Cycle(name: '2026-C43', start: '2026-10-19', end: '2026-11-01');
    const c45 = Cycle(name: '2026-C45', start: '2026-11-02', end: '2026-11-15');
    bool same(Cycle? a, Cycle? b) => a?.name == b?.name;

    test('is what each cycle finished, of what it had', () {
      final bars = velocityOf([c43, c45], [
        (key: 'a', cycle: c43, weight: 3, finished: true),
        (key: 'b', cycle: c43, weight: 5, finished: true),
        (key: 'c', cycle: c43, weight: 2, finished: false),
        (key: 'd', cycle: c45, weight: 8, finished: true),
        (key: 'e', cycle: null, weight: 13, finished: true),
      ], same);
      expect([for (final bar in bars) bar.finished], [8, 8]);
      expect([for (final bar in bars) bar.committed], [10, 8]);
      expect(bars.first.keys, ['a', 'b']);
      expect(averageVelocity(bars, '2026-11-05'), 8);
      expect(averageVelocity(bars, '2026-10-20'), isNull);
    });
  });

  group('an epic', () {
    test('is a ticket with type: epic, and its tickets are under it by parent:', () {
      const epic = '---\ntype: epic\nid: KLN-1\nstatus: In progress\n---\n# Second kiln\n';
      expect(isTicket(epic), isTrue);
      expect(ticketOf(epic)!.epic, isTrue);
      expect(ticketOf(ticket('To do'))!.epic, isFalse);
      // `epic:` is read as its parent where it names none.
      expect(ticketOf('---\ntype: ticket\nepic: "[[KLN-1]]"\n---\n')!.parent, 'KLN-1');
      expect(ticketOf('---\ntype: ticket\nparent: "[[KLN-2]]"\nepic: "[[KLN-1]]"\n---\n')!.parent, 'KLN-2');
    });

    test('shows how far it is, by count and by points', () {
      final progress = epicProgressOf([
        (category: StatusCategory.done, estimate: '3'),
        (category: StatusCategory.doing, estimate: '5'),
        (category: StatusCategory.done, estimate: null),
        (category: StatusCategory.todo, estimate: '2'),
      ]);
      expect(progress.words, '2 of 4 done · 3 of 10 points');
      expect(progress.fraction, closeTo(0.3, 1e-9));
      expect(epicProgressOf([(category: StatusCategory.done, estimate: null), (category: StatusCategory.todo, estimate: null)]).words, '1 of 2 done');
      expect(epicProgressOf(const []).isEmpty, isTrue);
    });

    test('a milestone is a dated note', () {
      expect(isMilestoneType('Milestone'), isTrue);
      expect(milestoneDayOf({'date': '2026-12-01'}), '2026-12-01');
      expect(milestoneDayOf({'due': '2026-12-02'}), '2026-12-02');
      expect(milestoneDayOf({'date': 'soon'}), isNull);
    });
  });

  group('priority', () {
    test('a ticket’s urgent is Tasks’ highest, and a note that is no ticket keeps its words', () {
      expect(ticketOf('---\ntype: ticket\npriority: urgent\n---\n')!.priority, 'highest');
      expect(ticketOf('---\ntype: ticket\npriority: Urgent\n---\n')!.priority, 'highest');
      expect(ticketPriorityOf('high')!.name, 'high');
      expect([for (final each in ticketPriorities) each.label], ['Urgent', 'High', 'Medium', 'Low']);
      expect(ticketPriorityLabel('highest'), 'Urgent');
      expect(ticketPriorityLabel('lowest'), 'Lowest');
      expect([for (final name in ['highest', 'high', 'medium', 'low', 'lowest']) priorityHue(name)], ['red', 'red', 'amber', 'blue', 'gray']);
    });
  });

  group('aging', () {
    test('a notebook’s stale-after, fourteen days where unsaid', () {
      expect(staleAfterOf('---\nstale-after: 7d\n---\n'), 7);
      expect(staleAfterOf('---\nstale-after: 2w\n---\n'), 14);
      expect(staleAfterOf('---\nbook: true\n---\n'), defaultStaleDays);
      expect(staleAfterOf(null), defaultStaleDays);
      expect(staleAfterOf('---\nstale-after: off\n---\n'), isNull);
    });

    test('a ticket is stale once its status has sat longer than that, and never once it is done', () {
      expect(staleDays(category: StatusCategory.doing, since: '2026-10-21', today: '2026-10-30', after: 7), 9);
      expect(staleDays(category: StatusCategory.doing, since: '2026-10-23', today: '2026-10-30', after: 7), isNull);
      expect(staleDays(category: StatusCategory.done, since: '2026-09-01', today: '2026-10-30', after: 7), isNull);
      expect(staleDays(category: StatusCategory.todo, since: '2026-09-01', today: '2026-10-30', after: null), isNull);
      expect(staleWords(9), 'stale · 9 days');
      expect(staleWords(1), 'stale · 1 day');
    });
  });

  group('a ticket’s history', () {
    final versions = [
      (at: at('2026-10-20', 9), text: ticket('To do')),
      (at: at('2026-10-20', 15), text: '${ticket('To do')}More words.\n'),
      (at: at('2026-10-22'), text: ticket('In progress')),
      (at: at('2026-10-26'), text: ticket('Done')),
      (at: at('2026-10-27'), text: ticket('In review')),
      (at: at('2026-10-29'), text: ticket('done')),
    ];

    test('is each change of status, read from its versions in any order', () {
      expect(statusChanges(versions.reversed), const [
        StatusChange(day: '2026-10-20', status: 'To do'),
        StatusChange(day: '2026-10-22', status: 'In progress'),
        StatusChange(day: '2026-10-26', status: 'Done'),
        StatusChange(day: '2026-10-27', status: 'In review'),
        StatusChange(day: '2026-10-29', status: 'done'),
      ]);
      expect(statusChanges(const []), isEmpty);
    });

    test('says when a status began and when it was last finished', () {
      final changes = statusChanges(versions);
      expect(sinceIn(changes, 'Done'), '2026-10-29');
      expect(sinceIn(changes, 'In progress'), isNull);
      expect(doneIn(changes, defaultStatuses), '2026-10-29');
      expect(doneIn(statusChanges(versions.take(3)), defaultStatuses), isNull);
    });

    test('falls back on the ticket’s own words where it keeps no versions', () {
      final history = TicketHistory((id) async => const []);
      expect(statusSince(history, 'k1', 'In progress', updated: '2026-10-25'), (day: '2026-10-25', source: HistorySource.changed));
      // The day written as it moved (`withStatus`) comes before the file's day, which a checkout resets.
      expect(statusSince(history, 'k1', 'In progress', updated: '2026-10-25', body: '---\ntype: ticket\nstatus: In progress\nstatus-since: 2026-10-23\n---\n'), (day: '2026-10-23', source: HistorySource.written));
      expect(writtenSince('---\nstatus-since: soon\n---\n'), isNull);
      history.hold('k1', statusChanges(versions.take(3)));
      expect(statusSince(history, 'k1', 'In progress', updated: '2026-10-25'), (day: '2026-10-22', source: HistorySource.versions));
      expect(finishedOn(const NoPast(), 'k2', '---\ntype: ticket\nstatus: Done\ndone: 2026-10-24\n---\n', 'Done', defaultStatuses, updated: '2026-10-28'), (day: '2026-10-24', source: HistorySource.written));
      expect(finishedOn(const NoPast(), 'k2', ticket('Done'), 'Done', defaultStatuses, updated: '2026-10-28'), (day: '2026-10-28', source: HistorySource.changed));
      expect(finishedOn(const NoPast(), 'k2', ticket('To do'), 'To do', defaultStatuses, updated: '2026-10-28'), isNull);
    });

    test('reads a ticket’s versions when first asked, and says so once they are read', () async {
      var asked = <String>[];
      final history = TicketHistory((id) async {
        asked = [...asked, id];
        return versions;
      });
      var told = 0;
      history.addListener(() => told += 1);
      expect(history.changesOf('k1'), isNull);
      expect(history.changesOf('k1'), isNull);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(asked, ['k1']);
      expect(told, 1);
      expect(history.changesOf('k1')!.last.status, 'done');
      history.forget('k1');
      expect(history.changesOf('k1'), isNull);
    });
  });
}
