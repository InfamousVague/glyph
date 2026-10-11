import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/properties.dart' show StatusCategory;
import 'package:ghost_md/core/query/query.dart';

/// A query as a gantt (lib/core/query/gantt.dart): the bars Mermaid draws, and a record's words made safe for
/// Mermaid's own grammar, since they are whatever a person wrote. Case for case with the web's
/// `core/query/gantt.test.ts`.
QueryRow row({String name = 'Ship it', String? id, bool? done = false, StatusCategory category = StatusCategory.todo, String? start, String? due, bool overdue = false}) => QueryRow(
      key: 'k',
      kind: RecordKind.task,
      noteId: 'n',
      line: 0,
      source: '',
      anchor: null,
      name: name,
      id: id,
      done: done,
      category: category,
      workflow: const [],
      cells: const [],
      day: null,
      start: start,
      due: due,
      overdue: overdue,
    );
QueryGroup grouped(String label, List<QueryRow> rows) => QueryGroup(key: label, label: label, cell: null, rows: rows, totals: const []);

void main() {
  group('a record’s words in a gantt', () {
    test('keeps them one line Mermaid reads as words', () {
      expect(ganttWords('Fix: the login; loop #2', 'x'), 'Fix the login loop 2');
      expect(ganttWords('Line one\nline two', 'x'), 'Line one line two');
      expect(ganttWords('100%% done', 'x'), '100% done');
    });

    test('sets apart words that start like one of Mermaid’s lines', () {
      expect(ganttWords('section of the fence', 'x'), '\u00a0section of the fence');
      expect(ganttWords('Title page', 'x'), '\u00a0Title page');
      expect(ganttWords('Sectional sofa', 'x'), 'Sectional sofa');
    });

    test('falls back where nothing is left, and keeps a long name short', () {
      expect(ganttWords(' :;# ', 'Untitled'), 'Untitled');
      expect(ganttWords('a' * 200, 'x'), hasLength(80));
    });
  });

  group('the bars', () {
    test('runs a bar from its start to the end of its due day, and a bar of one day where it has one of them', () {
      final made = ganttOf([
        grouped('', [row(start: '2026-10-01', due: '2026-10-03'), row(name: 'Due only', due: '2026-10-07'), row(name: 'Start only', start: '2026-10-09')]),
      ], 'To-dos');
      expect(made.placed, 3);
      // Not grouped: no section, so the bars have the room a section's name would take.
      expect(made.code.split('\n').sublist(5), ['  Ship it :2026-10-01, 2026-10-04', '  Due only :2026-10-07, 2026-10-08', '  Start only :2026-10-09, 2026-10-10']);
    });

    test('is laid out for a phone, in a directive any Mermaid reads, its ticks as far apart as the bars span', () {
      final lines = ganttOf([grouped('', [row(start: '2026-10-01', due: '2026-10-03')])]).code.split('\n');
      expect(lines[0], startsWith('%%{init: {"gantt":{"leftPadding":8,"rightPadding":16,'));
      expect(lines.sublist(1, 5), ['gantt', '  dateFormat YYYY-MM-DD', '  axisFormat %e', '  tickInterval 1day']);
      expect(
        ganttOf([grouped('Doing', [row(due: '2026-10-01')]), grouped('Done', [row(due: '2026-11-20')])]).code,
        contains('"leftPadding":80'),
      );
    });

    test('spaces its ticks a day, a week or a month apart', () {
      expect(ticksFor(7), (tick: '1day', axis: '%e'));
      expect(ticksFor(30), (tick: '1week', axis: '%e %b'));
      expect(ticksFor(200), (tick: '1month', axis: '%b'));
      expect(ticksFor(900), (tick: '3month', axis: '%b %Y'));
    });

    test('turns a start after the due day round, and leaves out a record with neither', () {
      final made = ganttOf([grouped('', [row(start: '2026-10-05', due: '2026-10-02'), row(name: 'Undated')])]);
      expect(made.placed, 1);
      expect(made.code, contains('Ship it :2026-10-02, 2026-10-06'));
      expect(made.code, isNot(contains('Undated')));
    });

    test('marks done, under way and overdue in Mermaid’s own words, and names a ticket by its key', () {
      final code = ganttOf([
        grouped('Doing', [
          row(id: 'GHO-4', name: 'Pricing', category: StatusCategory.doing, due: '2026-10-01', overdue: true),
          row(name: 'Old', done: true, category: StatusCategory.done, due: '2026-09-01'),
        ]),
      ]).code;
      expect(code, contains('  section Doing'));
      expect(code, contains('  GHO-4 Pricing :active, crit, 2026-10-01, 2026-10-02'));
      expect(code, contains('  Old :done, 2026-09-01, 2026-09-02'));
    });

    test('leaves out a group with no bars, and is empty with none at all', () {
      expect(ganttOf([grouped('Empty', [row()]), grouped('Some', [row(due: '2026-10-01')])]).code, isNot(contains('Empty')));
      expect(ganttOf([grouped('', [row()])]), const Gantt(code: '', placed: 0));
    });
  });
}
