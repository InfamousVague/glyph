import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/simple/simple_todos.dart';
import 'package:ghost_md/simple/todos_groups.dart';

import '../core/make_note.dart';
import '../support/render.dart';

/// The To-dos view of simple mode (GHST-105, lib/simple): every open to-do across the notes in Todoist's buckets by
/// its due date, a tick that asks the root to write, and words that open the note at the line.
void main() {
  // A Saturday; the clock stands at noon on it.
  final noon = DateTime(2026, 10, 17, 12);
  const today = '2026-10-17';

  final notes = [
    makeNote('plumber', body: '# The flat\n- [ ] Call the plumber @matt ⏫ 📅 2026-10-15\n- [ ] Buy a washer 📅 2026-10-17\n- [x] Find the stopcock', updatedAt: 30),
    makeNote('trip', body: '# Trip\n- [ ] Book the ferry [due:: 2026-10-21] 🔼\n- [ ] Pack 📅 2026-10-21 🔺\n- [ ] Tell Sam\n```md\n- [ ] not a task\n```', updatedAt: 20),
    makeNote('old', body: '# Old\n- [ ] Read the manual\n- [ ] Overdue by a day 📅 2026-10-16', updatedAt: 10),
    makeNote('gone', body: '# Gone\n- [ ] archived', updatedAt: 40, archivedAt: 50),
  ];

  group('todoGroups', () {
    test('places each open to-do by its due day against today, and leaves out the archive and a fence', () {
      final groups = todoGroups(notes, today);
      expect([for (final g in groups) g.group], [TodoGroup.overdue, TodoGroup.today, TodoGroup.later, TodoGroup.someday]);
      expect([for (final t in groups[0].todos) t.text], ['Call the plumber', 'Overdue by a day']);
      expect([for (final t in groups[1].todos) t.text], ['Buy a washer']);
      expect([for (final t in groups[2].todos) t.text], ['Pack', 'Book the ferry']);
      expect([for (final t in groups[3].todos) t.text], ['Tell Sam', 'Read the manual']);
    });

    test('orders a dated group by due day then priority, and Someday by the note touched last', () {
      final groups = todoGroups([
        makeNote('a', body: '- [ ] Low later 📅 2026-10-20 🔽\n- [ ] Sooner 📅 2026-10-18\n- [ ] Someday a', updatedAt: 1),
        makeNote('b', body: '- [ ] High later 📅 2026-10-20 ⏫\n- [ ] Someday b', updatedAt: 2),
      ], today);
      expect([for (final t in groups[0].todos) t.text], ['Sooner', 'High later', 'Low later']);
      expect([for (final t in groups[1].todos) t.text], ['Someday b', 'Someday a']);
    });

    test('reads the due day and priority off the line, and strips the fields from the words', () {
      final overdue = todoGroups(notes, today)[0].todos[0];
      expect(overdue.text, 'Call the plumber');
      expect(overdue.due, '2026-10-15');
      expect(overdue.priority, 'high');
      expect(overdue.noteId, 'plumber');
      expect(overdue.line, 1);
      expect(overdue.noteName, 'The flat');
      final dataview = todoGroups(notes, today)[2].todos[1];
      expect(dataview.due, '2026-10-21');
      expect(dataview.priority, 'medium');
    });

    test('leaves out a note in the trash when given the whole library', () {
      final trashed = todoGroups(notes, today, held: const {'plumber': 1});
      expect([for (final g in trashed) for (final t in g.todos) t.noteId], isNot(contains('plumber')));
      expect(trashed.first.group, TodoGroup.overdue);
      expect([for (final t in trashed.first.todos) t.text], ['Overdue by a day']);
    });

    test('says a due day in words counted from today', () {
      expect(dueWords('2026-10-17', today), 'Today');
      expect(dueWords('2026-10-18', today), 'Tomorrow');
      expect(dueWords('2026-10-16', today), 'Yesterday');
      expect(dueWords('2026-10-20', today), 'Tuesday');
      expect(dueWords('2026-10-14', today), '3 days ago');
      expect(dueWords('2026-11-03', today), '3 November');
      expect(dueWords('2025-10-03', today), '3 October 2025');
    });
  });

  group('SimpleTodos', () {
    setUpAll(loadAppFonts);

    final ticks = <(String, int, bool)>[];
    final opens = <(String, int)>[];
    late ValueNotifier<List<Note>> shown;

    setUp(() {
      ticks.clear();
      opens.clear();
      shown = ValueNotifier(notes);
    });

    Future<void> pump(WidgetTester tester, {VoidCallback? onAdd, ValueListenable<TrashHeld>? trash}) async {
      await pumpApp(
        tester,
        home: SimpleTodos(notes: shown, clock: () => noon, onTick: (id, line, done) => ticks.add((id, line, done)), onOpen: (id, line) => opens.add((id, line)), onAdd: onAdd, trash: trash),
      );
      await tester.pump();
    }

    /// Takes the view down, and puts back the binding's switch for shadows that [pumpApp] turned on.
    Future<void> away(WidgetTester tester) async {
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('lists the groups with their counts, each to-do with its note and due day under it', (tester) async {
      await pump(tester);
      expect(find.bySemanticsLabel('Overdue, 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Today, 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Later, 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Someday, 2'), findsOneWidget);
      expect(find.text('Call the plumber'), findsOneWidget);
      expect(find.text('Buy a washer'), findsOneWidget);
      // The fields are not in the words; the due day and a high priority are said under them.
      expect(find.textContaining('📅'), findsNothing);
      expect(find.textContaining('⏫'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Call the plumber, The flat, 2 days ago, High, overdue')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Buy a washer, The flat, Today\.')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Tell Sam, Trip\.')), findsOneWidget);
      // The archived note's to-do and the fence's example are not here.
      expect(find.text('archived'), findsNothing);
      expect(find.text('not a task'), findsNothing);
      expect(find.text('Find the stopcock'), findsNothing);
      await away(tester);
    });

    testWidgets('a tick asks the root to tick that note and line, holds the row for a beat, then shelves it under Done', (tester) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Tick Buy a washer'));
      await tester.pump();
      expect(ticks, [('plumber', 2, true)]);
      // The root writes the note; the list stays as it was, the row ticked, until the beat is over.
      shown.value = [for (final n in notes) n.id == 'plumber' ? makeNote('plumber', body: n.body.replaceFirst('- [ ] Buy a washer', '- [x] Buy a washer'), updatedAt: 60) : n];
      await tester.pump();
      expect(find.text('Buy a washer'), findsOneWidget);
      expect(find.bySemanticsLabel('Today, 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Clear Buy a washer'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.bySemanticsLabel('Today, 1'), findsNothing);
      expect(find.bySemanticsLabel('Done, 1, show'), findsOneWidget);
      // Collapsed until asked; opened, the row's tick clears the box again.
      expect(find.text('Buy a washer'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Done, 1, show'));
      await tester.pump();
      expect(find.text('Buy a washer'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Clear Buy a washer'));
      await tester.pump();
      expect(ticks.last, ('plumber', 2, false));
      expect(find.bySemanticsLabel(RegExp(r'^Done, ')), findsNothing);
      await away(tester);
    });

    testWidgets('a tap on the words opens the note at the line', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Tell Sam'));
      await tester.pump();
      expect(opens, [('trip', 3)]);
      expect(ticks, isEmpty);
      await away(tester);
    });

    testWidgets('reads the groups again only when the notes list is another object', (tester) async {
      await pump(tester);
      expect(find.text('Read the manual'), findsOneWidget);
      shown.value = [...notes.where((n) => n.id != 'old')];
      await tester.pump();
      expect(find.text('Read the manual'), findsNothing);
      expect(find.bySemanticsLabel('Someday, 1'), findsOneWidget);
      await away(tester);
    });

    testWidgets('leaves out a note the trash holds', (tester) async {
      final trash = ValueNotifier<TrashHeld>(const {'trip': 1});
      await pump(tester, trash: trash);
      expect(find.text('Tell Sam'), findsNothing);
      expect(find.bySemanticsLabel('Later, 2'), findsNothing);
      trash.value = const {};
      await tester.pump();
      expect(find.text('Tell Sam'), findsOneWidget);
      await away(tester);
    });

    testWidgets('with nothing to do says so, and how a to-do is made', (tester) async {
      shown.value = [makeNote('n', body: '# Notes only\n- [x] done\n- plain', updatedAt: 1)];
      await pump(tester);
      expect(find.text('Nothing to do.'), findsOneWidget);
      expect(find.text('To-dos you write in any note show here.'), findsOneWidget);
      expect(find.textContaining('- [ ] '), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^To-dos, ')), findsNothing);
      await away(tester);
    });
  });
}
