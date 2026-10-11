// Which sheet a query's value opens, with what it holds now (lib/editor/fields/field_picks.dart; docs/DESIGN.md
// §169), and the marks a status and a person wear in it: `src/app/editor/fieldPicks.test.ts`, case for case.
//
// The rows and cells are the query core's own (lib/core/query/run.dart), as the page's cases hand `pickOf` a query's
// `Row` and `Cell`.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/fields/field_picks.dart';

QueryRow row({bool task = false, bool? done, List<String> workflow = defaultStatuses}) => QueryRow(
  key: 'n',
  kind: task ? RecordKind.task : RecordKind.ticket,
  noteId: 'n',
  line: task ? 0 : -1,
  source: '',
  anchor: null,
  name: 'A record',
  id: null,
  done: done,
  category: StatusCategory.todo,
  workflow: workflow,
  cells: const <Cell>[],
  day: null,
  start: null,
  due: null,
  overdue: false,
);
const Cell empty = EmptyCell();
const String today = '2026-10-05';
List<String> none() => const <String>[];

void main() {
  group('the sheet a value opens', () {
    test('opens a ticket’s status on its workflow, with the status it has', () {
      const workflow = <String>['Open', 'Doing', 'Shipped'];
      expect(pickOf(row(workflow: workflow), 'status', const StatusCell('Doing', StatusCategory.doing), today, none), const StatusPick(value: 'Doing', workflow: workflow));
      expect(pickOf(row(), 'status', empty, today, none), const StatusPick(value: null, workflow: defaultStatuses));
    });

    test('opens a to-do’s status as its box, To do or Done', () {
      expect(pickOf(row(task: true, done: true), 'status', empty, today, none), const BoxPick(done: true));
      expect(pickOf(row(task: true), 'status', empty, today, none), isNull);
    });

    test('opens a priority, a person and a day with what each holds', () {
      expect(pickOf(row(), 'priority', const PriorityCell('high'), today, none), const PriorityPick(value: 'high'));
      expect(pickOf(row(), 'Assignee', const PeopleCell(<String>['Sam']), today, () => const <String>['Sam', 'Alex']), const PersonPick(value: 'Sam', people: <String>['Sam', 'Alex']));
      expect(pickOf(row(), 'due', const DayCell('2026-10-03'), today, none), const DayPick(value: '2026-10-03', today: today));
      expect(pickOf(row(task: true, done: false), 'scheduled', empty, today, none), const DayPick(value: null, today: today));
    });

    test('reads the people only for a person, since that reads every note', () {
      var asked = 0;
      List<String> people() {
        asked += 1;
        return const <String>['Sam'];
      }

      pickOf(row(), 'priority', empty, today, people);
      pickOf(row(), 'status', empty, today, people);
      expect(asked, 0);
    });

    test('opens nothing for what is not picked: a title, a tag, a ticket’s scheduled day', () {
      for (final field in const <String>['title', 'tags', 'note', 'estimate', 'updated']) {
        expect(pickOf(row(), field, empty, today, none), isNull, reason: field);
      }
      expect(pickOf(row(), 'scheduled', empty, today, none), isNull);
      expect(picksField(row(), 'title'), isFalse);
      expect(picksField(row(), 'status'), isTrue);
      expect(picksField(row(task: true, done: false), 'scheduled'), isTrue);
    });
  });

  group('the marks', () {
    test('marks a status by where it stands, a backlog and a review by name', () {
      expect(defaultStatuses.map((status) => statusLook(status, defaultStatuses)), const <StatusLook>[StatusLook.backlog, StatusLook.todo, StatusLook.doing, StatusLook.review, StatusLook.done]);
      expect(statusLook('Won’t do'), StatusLook.done);
    });

    test('gives a person one hue, however they are written', () {
      expect(hueOf('sam'), hueOf('@Sam'));
      expect(hues, contains(hueOf('Priya Shah')));
    });

    // Not on the page: the sums its `hueOf` comes to (node, 2026-10-08), so a person wears here the hue they wear there.
    test('gives the hues the page gives', () {
      expect(<String>[hueOf('Sam'), hueOf('Priya Shah'), hueOf('matt'), hueOf('@jo'), hueOf('')], const <String>['red', 'green', 'purple', 'purple', 'blue']);
    });
  });
}
