import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/planning/cycles.dart';

void main() {
  group('a notebook’s cycles', () {
    test('are two weeks from a Monday every notebook shares, unless it says otherwise', () {
      expect(cycleRuleOf('---\nbook: true\n---\n'), const CycleRule());
      expect(cycleRuleOf(null), const CycleRule());
      expect(cycleRuleOf('---\nbook: true\ncycles: {length: 2w, start: 2026-11-02}\n---\n'), const CycleRule(days: 14, start: '2026-11-02'));
      expect(cycleRuleOf('---\ncycles: {length: 10d, start: 2026-11-04}\n---\n'), const CycleRule(days: 10, start: '2026-11-04'));
      expect(cycleRuleOf('---\ncycles: 1w\n---\n'), const CycleRule(days: 7));
      expect(cycleRuleOf('---\ncycles: "{length: 3 weeks}"\n---\n'), const CycleRule(days: 21));
      expect(cycleRuleOf('---\ncycles: off\n---\n'), isNull);
      expect(cycleRuleOf('---\ncycles: {start: not a day}\n---\n'), const CycleRule());
    });

    test('read a length in days or weeks', () {
      expect([daysOf('14d'), daysOf('2w'), daysOf('2 weeks'), daysOf('10'), daysOf('1 week'), daysOf('0'), daysOf('soon')], [14, 14, 14, 10, 7, null, null]);
    });

    test('are named by the year and the ISO week they start in', () {
      expect(cycleNameOn('2026-11-02'), '2026-C45');
      expect(cycleNameOn('2026-12-28'), '2026-C53');
      expect(cycleNameOn('2027-01-04'), '2027-C01');
      // The first days of January can be the last week of the year before.
      expect(cycleNameOn('2027-01-01'), '2026-C53');
      expect(mondayOfWeek(2026, 45), '2026-11-02');
      expect(mondayOfWeek(2025, 53), isNull);
      expect(isCycleName('2026-c45'), isTrue);
      expect(isCycleName('Sprint 12'), isFalse);
    });

    test('follow on from the rule’s start, and the anchor lines them up on 2 November 2026', () {
      final rule = cycleRuleOf('---\ncycles: {length: 2w, start: 2026-11-02}\n---\n')!;
      expect(ruledCycleOn(rule, '2026-11-02'), const Cycle(name: '2026-C45', start: '2026-11-02', end: '2026-11-15'));
      expect(ruledCycleOn(rule, '2026-11-15').name, '2026-C45');
      expect(ruledCycleOn(rule, '2026-11-16'), const Cycle(name: '2026-C47', start: '2026-11-16', end: '2026-11-29'));
      expect(ruledCycleOn(rule, '2026-11-01'), const Cycle(name: '2026-C43', start: '2026-10-19', end: '2026-11-01'));
      expect(ruledCycleOn(const CycleRule(), '2026-11-05').start, '2026-11-02');
    });
  });

  group('a cycle book', () {
    final book = CycleBook(rule: const CycleRule(start: '2026-11-02'));

    test('says which cycle today is in, and the ones either side', () {
      final now = book.current('2026-11-20')!;
      expect(now.name, '2026-C47');
      expect(book.before(now)!.name, '2026-C45');
      expect(book.after(now)!.name, '2026-C49');
      expect([for (final cycle in book.around('2026-11-20', count: 2)) cycle.name], ['2026-C43', '2026-C45', '2026-C47', '2026-C49']);
    });

    test('finds a ticket’s cycle by its name, its link, or a cycle note’s title', () {
      final notes = CycleBook(
        rule: const CycleRule(start: '2026-11-02'),
        notes: [cycleNoteOf(id: 's12', title: 'Sprint 12', props: {'type': 'cycle', 'start': '2026-12-01', 'end': '2026-12-12'})!],
      );
      expect(notes.named('2026-C45'), const Cycle(name: '2026-C45', start: '2026-11-02', end: '2026-11-15'));
      expect(notes.named('2026-c45')!.name, '2026-C45');
      expect(notes.named('[[Sprint 12]]'), const Cycle(name: 'Sprint 12', start: '2026-12-01', end: '2026-12-12', noteId: 's12'));
      expect(notes.named('sprint 12')!.noteId, 's12');
      expect(notes.named('Someday'), const Cycle(name: 'Someday', start: null, end: null));
      expect(notes.named(''), isNull);
      expect(notes.named(null), isNull);
      // A cycle note covers its own days; the rule the rest.
      expect(notes.on('2026-12-05')!.name, 'Sprint 12');
      expect(notes.on('2026-12-14')!.name, '2026-C51');
    });

    test('tells the same cycle however it is written', () {
      expect(CycleBook.same(book.named('2026-C45'), book.current('2026-11-03')), isTrue);
      expect(CycleBook.same(book.named('2026-C47'), book.current('2026-11-03')), isFalse);
      expect(CycleBook.same(book.named('Someday'), book.named('someday')), isTrue);
      expect(CycleBook.same(null, book.current('2026-11-03')), isFalse);
    });

    test('a cycle made by hand needs a start and an end to have days', () {
      expect(cycleNoteOf(id: 'x', title: 'Sprint 1', props: {'type': 'cycle', 'start': '2026-11-01'})!.dated, isFalse);
      expect(cycleNoteOf(id: 'x', title: 'Sprint 1', props: {'type': 'ticket'}), isNull);
      expect(cycleNoteOf(id: 'x', title: 'Sprint 1', props: {'type': 'Cycle', 'start': '2026-11-01', 'due': '2026-11-07'})!.days.length, 7);
    });

    test('a ticket is moved by its cycle: a name, or a link to a cycle note', () {
      const body = '---\ntype: ticket\nid: KLN-3\ncycle: 2026-C45\n---\n# Glaze tests\n';
      final next = book.after(book.named('2026-C45')!)!;
      expect(withCycle(body, next), '---\ntype: ticket\nid: KLN-3\ncycle: 2026-C47\n---\n# Glaze tests\n');
      expect(withCycle(body, const Cycle(name: 'Sprint 12', start: '2026-12-01', end: '2026-12-12', noteId: 's12')), '---\ntype: ticket\nid: KLN-3\ncycle: "[[Sprint 12]]"\n---\n# Glaze tests\n');
      expect(withCycle(body, null), '---\ntype: ticket\nid: KLN-3\n---\n# Glaze tests\n');
      expect(carryWords(4, next), 'Move 4 unfinished to 2026-C47');
    });
  });
}
