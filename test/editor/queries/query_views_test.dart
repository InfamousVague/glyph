// The port's own query views drawn (Matt, 2026-10-30, "add all 12"): the calendar on a phone and a wide window, the
// timeline that is the Gantt chart now (lib/editor/queries/query_gantt.dart), the chart (query_chart.dart), a relation's chips and
// the builder's new rows; that carrying a record to a day or a bar's ends writes its front matter; and that a
// thousand records cost a frame no more than ten.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/days.dart' show isoDayAfter;
import 'package:ghost_md/core/hold_drag.dart' show holdTime;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/gantt/gantt.dart' show ganttOfQuery;
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../../support/render.dart';
import '../../gantt/support.dart' show barAt, ganttChart;
import 'support.dart';

const String today = '2026-10-08';

QueryNote note(String id, String body) => QueryNote(id: id, body: body, createdAt: 0, updatedAt: 0);

final List<QueryNote> library = <QueryNote>[
  note('gho1', '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nassignee: Sam\nstart: 2026-10-01\ndue: 2026-10-06\nestimate: 3\n---\n# Fix the login loop\n'),
  note('gho2', '---\ntype: ticket\nid: GHO-2\nstatus: To do\nassignee: Alex\ndue: 2026-10-12\nestimate: 5\n---\n# Ship the pricing page\n'),
  note('gho3', '---\ntype: ticket\nid: GHO-3\nstatus: Done\nassignee: Sam\nstart: 2026-10-05\ndue: 2026-10-09\nestimate: 2\n---\n# Write the changelog\n'),
  note('gho4', '---\ntype: ticket\nid: GHO-4\nstatus: To do\n---\n# Draw the icons\n'),
  note('kiln', '# Kiln\n'),
  note('glaze', '---\nproject: "[[Kiln]]"\nhours: 3\n---\n# Glaze tests\n'),
];

String fence(String lines) => '# This week\n\n```query\n$lines\n```\n';

/// The note's words once every change the screen was asked to make to [id] is made.
String writtenTo(Asked asked, String id) {
  var body = library.firstWhere((each) => each.id == id).body;
  for (final (noteId, change) in asked.written) {
    if (noteId == id) body = change(body) ?? body;
  }
  return body;
}

Future<(EditorView, Asked)> open(WidgetTester tester, String lines, {double screen = 390, String theme = 'light', List<QueryNote>? notes}) async {
  final asked = Asked();
  final view = await pumpQueries(tester, fence(lines), options: optionsOver(() => notes ?? library, asked), today: today, screen: screen, theme: theme);
  await tester.pump(const Duration(milliseconds: 50));
  return (view, asked);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Day cells of the month shown, in order: a month of October 2026 starts on Monday 28 September.
Finder dayCell(int index) => parts('dayCell').at(index);

void main() {
  setUpAll(loadAppFonts);

  group('the calendar', () {
    testWidgets('on a phone, a record held in the day\'s list and carried onto a day sets the field its day is from', (tester) async {
      final (_, asked) = await open(tester, 'from: tickets\nshow: calendar');
      expect(parts('dayCell'), findsNWidgets(35));
      // Tuesday 6 October, GHO-1's due day.
      await tester.tap(dayCell(8));
      await tester.pump();
      final row = find.descendant(of: parts('dayList'), matching: parts('row'));
      expect(row, findsOneWidget);
      final finger = await tester.startGesture(tester.getCenter(row));
      await tester.pump(holdTime + const Duration(milliseconds: 50));
      await finger.moveTo(tester.getCenter(dayCell(15)));
      await tester.pump();
      await finger.moveTo(tester.getCenter(dayCell(16)));
      await tester.pump();
      await finger.up();
      await tester.pump();
      expect(asked.written.map((each) => each.$1), <String>['gho1']);
      expect(writtenTo(asked, 'gho1'), contains('due: 2026-10-14'));
    });

    testWidgets('a calendar on another day field writes that field, and Today comes back from another month', (tester) async {
      final (_, asked) = await open(tester, 'from: tickets\nshow: calendar\ndate: start');
      await tester.tap(dayCell(3));
      await tester.pump();
      final row = find.descendant(of: parts('dayList'), matching: parts('row'));
      final finger = await tester.startGesture(tester.getCenter(row));
      await tester.pump(holdTime + const Duration(milliseconds: 50));
      await finger.moveTo(tester.getCenter(dayCell(10)));
      await tester.pump();
      await finger.moveTo(tester.getCenter(dayCell(9)));
      await tester.pump();
      await finger.up();
      await tester.pump();
      expect(writtenTo(asked, 'gho1'), allOf(contains('start: 2026-10-07'), contains('due: 2026-10-06')));
      expect(said('Today’s month'), findsNothing);
      await tester.tap(said('The month after'));
      await tester.pump();
      expect(said('Today’s month'), findsOneWidget);
      await tester.tap(said('Today’s month'));
      await tester.pump();
      expect(find.textContaining('October 2026'), findsOneWidget);
    });

    testWidgets('on a wide window: names in the days, a week, Today, and a record carried with a pointer', (tester) async {
      {
        final (_, asked) = await open(tester, 'from: tickets\nshow: calendar', screen: 1000);
        expect(parts('dayChip'), findsNWidgets(3));
        expect(find.text('GHO-2 Ship the pricing page'), findsOneWidget);
        await tester.tap(said('Show a week'));
        await tester.pump();
        expect(parts('dayCell'), findsNWidgets(7));
        expect(find.textContaining('5 – 11 Oct 2026'), findsOneWidget);
        // GHO-1 (due Tuesday) and GHO-3 (due Friday) are in it; carried from Tuesday to Wednesday.
        final chip = find.ancestor(of: find.text('GHO-1 Fix the login loop'), matching: parts('dayChip'));
        final mouse = await tester.startGesture(tester.getCenter(chip), kind: PointerDeviceKind.mouse);
        await tester.pump(holdTime + const Duration(milliseconds: 50));
        await mouse.moveBy(const Offset(20, 0));
        await tester.pump();
        await mouse.moveTo(tester.getCenter(parts('dayCell').at(2)));
        await tester.pump();
        await mouse.up();
        await tester.pump();
        expect(writtenTo(asked, 'gho1'), contains('due: 2026-10-07'));
        await tester.tap(said('The week after'));
        await tester.pump();
        expect(find.textContaining('12 – 18 Oct 2026'), findsOneWidget);
        await tester.tap(said('This week'));
        await tester.pump();
        expect(find.textContaining('5 – 11 Oct 2026'), findsOneWidget);
        await tester.tap(said('Show the month'));
        await tester.pump();
        expect(parts('dayCell'), findsNWidgets(35));
        // A tap on a name opens it.
        await tester.tap(find.text('GHO-2 Ship the pricing page'));
        expect(asked.opened, <(String, int?)>[('gho2', null)]);
      }
    });

    testWidgets('where the note cannot be changed, nothing is carried', (tester) async {
      final asked = Asked();
      await pumpQueries(tester, fence('from: tickets\nshow: calendar'), options: optionsOver(() => library, asked), today: today, readOnly: true);
      await tester.tap(dayCell(8));
      await tester.pump();
      final row = find.descendant(of: parts('dayList'), matching: parts('row'));
      final finger = await tester.startGesture(tester.getCenter(row));
      await tester.pump(holdTime + const Duration(milliseconds: 50));
      await finger.moveTo(tester.getCenter(dayCell(16)));
      await tester.pump();
      await finger.up();
      await tester.pump();
      expect(asked.written, isEmpty);
    });
  });

  // `show: timeline` is the Gantt chart a ```gantt fence draws (lib/editor/queries/query_gantt.dart; Matt,
  // 2026-10-31): the drawn timeline it was, carried over.
  group('the timeline, the Gantt chart now', () {
    Finder days() => find.descendant(of: find.byKey(const ValueKey<String>('gantt-scroll')), matching: find.byType(Scrollable));

    testWidgets('a row a record, its name held at the left, the undated dashed on today; its panel opens it', (tester) async {
      final (_, asked) = await open(tester, 'from: tickets\nshow: timeline\nzoom: week');
      expect(parts('ganttName'), findsNWidgets(4));
      expect(ganttChart(tester).widget.model.byKey['gho4']!.undated, isTrue);
      expect(ganttChart(tester).widget.model.byKey['gho4']!.start, today);
      final names = tester.getTopLeft(parts('ganttName').first);
      tester.state<ScrollableState>(days()).position.jumpTo(300);
      await tester.pump();
      expect(tester.getTopLeft(parts('ganttName').first), names, reason: 'the names stay as the days scroll');
      await tester.tap(find.byKey(const ValueKey<String>('gantt-name:gho2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('gantt-name:gho2')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('gantt-open')));
      expect(asked.opened.single.$1, 'gho2');
    });

    testWidgets('zooms, and Today scrolls to today', (tester) async {
      await open(tester, 'from: tickets\nshow: timeline', screen: 1000);
      await tester.tap(said('Zoom to a quarter'));
      await tester.pump();
      expect(ganttChart(tester).dayWide, 6);
      expect(tester.getSemantics(said('Zoom to a quarter')).flagsCollection.isSelected.toBoolOrNull(), isTrue);
      await tester.tap(said('Zoom to a week'));
      await tester.pump();
      tester.state<ScrollableState>(days()).position.jumpTo(0);
      await tester.pump();
      await tester.tap(said('Scroll to today'));
      await settle(tester);
      expect(tester.state<ScrollableState>(days()).position.pixels, greaterThan(0));
    });

    testWidgets('a bar\'s end carried writes its due day, its middle both days, each into the ticket\'s front matter', (tester) async {
      final (_, asked) = await open(tester, 'from: tickets\nshow: timeline\nzoom: week', screen: 1000);
      // GHO-2 is one day, the 12th: chosen, its end is taken by a finger at once. Two days on.
      ganttChart(tester).select('gho2');
      await tester.pump();
      await tester.dragFrom(barAt(tester, 'gho2', where: 'end'), const Offset(88, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(writtenTo(asked, 'gho2'), contains('due: 2026-10-14'));
      expect(writtenTo(asked, 'gho2'), isNot(contains('start:')));
      // GHO-1 runs the 1st to the 6th: its middle, with a pointer, back three days.
      final mouse = await tester.startGesture(barAt(tester, 'gho1'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var i = 0; i < 12; i += 1) {
        await mouse.moveBy(const Offset(-11, 0));
        await tester.pump();
      }
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(writtenTo(asked, 'gho1'), allOf(contains('start: 2026-09-28'), contains('due: 2026-10-03')));
    });

    testWidgets('a finger swiping across a row scrolls the days and moves nothing', (tester) async {
      final (_, asked) = await open(tester, 'from: tickets\nshow: timeline\nzoom: week');
      final before = tester.state<ScrollableState>(days()).position.pixels;
      // On GHO-1's row, where the days show on a phone.
      final from = Offset(tester.getCenter(find.byKey(const ValueKey<String>('gantt-scroll'))).dx, barAt(tester, 'gho1').dy);
      await tester.dragFrom(from, Offset(before > 0 ? 120 : -120, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(asked.written, isEmpty);
      expect(tester.state<ScrollableState>(days()).position.pixels, isNot(before));
    });
  });

  group('the chart', () {
    testWidgets('a bar a status, each saying its count; a tap lists its records under it, a second lets them go', (tester) async {
      final semantics = tester.ensureSemantics();
      final (_, asked) = await open(tester, 'from: tickets\nshow: chart');
      expect(find.semantics.byLabel('To do: 2'), findsOne);
      expect(find.semantics.byLabel('In progress: 1'), findsOne);
      expect(find.semantics.byLabel('Done: 1'), findsOne);
      tester.semantics.tap(find.semantics.byLabel('To do: 2'));
      await tester.pump();
      final listed = find.descendant(of: parts('chartRows'), matching: parts('row'));
      expect(listed, findsNWidgets(2));
      expect(wordsOf(tester, parts('chartRows')), allOf(contains('Ship the pricing page'), contains('Draw the icons'), isNot(contains('Fix the login loop'))));
      await tester.tap(find.descendant(of: parts('chartRows'), matching: find.text('Draw the icons')));
      expect(asked.opened.single.$1, 'gho4');
      tester.semantics.tap(find.semantics.byLabel('To do: 2'));
      await tester.pump();
      expect(parts('chartRows'), findsNothing);
      // A bar of one record, tapped twice, opens it.
      tester.semantics.tap(find.semantics.byLabel('Done: 1'));
      await tester.pump();
      tester.semantics.tap(find.semantics.byLabel('Done: 1'));
      await tester.pump();
      expect(asked.opened.last.$1, 'gho3');
      semantics.dispose();
    });

    testWidgets('a sum split by a series, a tap on the drawing itself, and a pie\'s legend', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, 'from: tickets\nshow: chart\nx: assignee\ny: sum(estimate)\nseries: status');
      expect(parts('legend'), findsOneWidget);
      expect(find.semantics.byLabel('Sam: 5'), findsOne);
      expect(find.semantics.byLabel('Alex: 5'), findsOne);
      expect(find.semantics.byLabel('No assignee: 0'), findsOne);
      // The first bar's place on the drawing.
      final chart = find.byKey(const ValueKey<String>('query-chart'));
      final box = tester.getRect(chart);
      await tester.tapAt(Offset(box.left + 60, box.bottom - 30));
      await tester.pump();
      expect(parts('chartRows'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a pie: a slice a status, its legend a list of buttons', (tester) async {
      await open(tester, 'from: tickets\nshow: chart\nchart: pie');
      await tester.tap(said('In progress: 1'));
      await tester.pump();
      expect(wordsOf(tester, parts('chartRows')), contains('Fix the login loop'));
    });

    test('its colours are the activity work\'s, and the ink at strengths in Calm', () {
      expect(chartTokens.first, 'activity-sync');
      expect(niceScale(7), (top: 8.0, step: 2.0));
      expect(niceScale(0), (top: 4.0, step: 1.0));
      expect(niceScale(130), (top: 150.0, step: 50.0));
      expect(niceScale(40, percent: true), (top: 100.0, step: 25.0));
    });
  });

  group('a relation', () {
    testWidgets('is drawn as chips that open the notes it names', (tester) async {
      final (_, asked) = await open(tester, 'where: project\ncolumns: title, project, hours\nshow: table');
      expect(parts('relationChip'), findsOneWidget);
      await tester.tap(said('Open Kiln'));
      expect(asked.opened, <(String, int?)>[('kiln', null)]);
    });

    testWidgets('a rollup is a column of its own', (tester) async {
      await open(tester, 'where: title = Kiln\nshow: table\nrollup: hours = sum(hours of backlinks.project)');
      expect(find.text('Hours'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('the builder', () {
    Future<void> build(WidgetTester tester) async {
      await tester.tap(said('Build the query'));
      await settle(tester);
    }

    Finder row(String key) => find.byKey(ValueKey<String>(key));

    Future<void> press(WidgetTester tester, String key) async {
      await tester.ensureVisible(row(key));
      await tester.pump();
      await tester.tap(row(key));
      await settle(tester);
    }

    testWidgets('offers the Gantt chart and the chart, a calendar\'s day field and a Gantt chart\'s fields', (tester) async {
      final (view, _) = await open(tester, 'from: tickets\nshow: calendar');
      await build(tester);
      await press(tester, 'date:start');
      expect(view.state.doc.toString(), contains('show: calendar\ndate: start'));
      await press(tester, 'show:gantt');
      expect(row('date:start'), findsNothing);
      await press(tester, 'end:end');
      await press(tester, 'zoom:month');
      expect(view.state.doc.toString(), contains('show: gantt\ndate: start\nend: end\nzoom: month'));
      expect(tester.widget<SheetRow>(row('show:gantt')).chosen, isTrue);
      expect(row('show:timeline'), findsNothing, reason: 'the timeline is the Gantt chart');
    });

    testWidgets('in simple mode, the chart\'s rows and the rollups wait behind More, which opens in place', (tester) async {
      final (view, _) = await open(tester, 'from: tickets\nshow: chart');
      preferences.value = preferences.value.copyWith(experience: 'simple', experienceChosen: true);
      await build(tester);
      expect(row('more'), findsOneWidget);
      expect(row('x:assignee'), findsNothing);
      expect(row('rollup:open'), findsNothing);
      await press(tester, 'more');
      expect(row('more'), findsNothing);
      await press(tester, 'x:assignee');
      await press(tester, 'rollup:open');
      expect(view.state.doc.toString(), contains('x: assignee\nrollup: open = count(links where status != done)'));
      await press(tester, 'rollup:done');
      expect(row('rollup-off:open'), findsOneWidget);
      await press(tester, 'rollup-off:open');
      expect(view.state.doc.toString(), isNot(contains('rollup: open')));
      expect(view.state.doc.toString(), contains('rollup: done = percent(links)'));
    });

    testWidgets('in advanced mode the rollups are there at once', (tester) async {
      await open(tester, 'from: tickets');
      await build(tester);
      expect(row('more'), findsNothing);
      expect(row('rollup:linked'), findsOneWidget);
    });
  });

  group('the switcher', () {
    testWidgets('six on a phone, the chart\'s place the count\'s while it is shown; every way on a wide window', (tester) async {
      await open(tester, 'from: tickets\nshow: count');
      expect(said(RegExp('^Show as a ')), findsNWidgets(6));
      expect(said('Show as a count'), findsOneWidget);
      expect(said('Show as a chart'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final (view, _) = await open(tester, 'from: tickets\nview: count', screen: 1000);
      expect(said(RegExp('^Show as a ')), findsNWidgets(7));
      await tester.tap(said('Show as a gantt'));
      await tester.pump();
      expect(view.state.doc.toString(), contains('view: gantt'));
      expect(parts('gantt'), findsOneWidget);
    });
  });

  group('every view on a phone and a wide window, light and dark', () {
    for (final lines in const <String>[
      'from: tickets\nshow: calendar',
      'from: tickets\nshow: timeline\ngroup: assignee',
      'from: tickets\nshow: chart\nseries: assignee',
      'from: tickets\nshow: chart\nchart: line\nx: due',
      'from: tickets\nshow: chart\nchart: pie\nx: assignee',
    ]) {
      for (final screen in const <double>[390, 1000]) {
        for (final theme in const <String>['light', 'dark']) {
          testWidgets('${lines.replaceAll('\n', '; ')} at $screen, $theme', (tester) async {
            await open(tester, lines, screen: screen, theme: theme);
            expect(tester.takeException(), isNull);
            final card = boxOf(tester, parts('query'));
            expect(card.width, lessThanOrEqualTo(screen));
          });
        }
      }
    }
  });

  group('a thousand records', () {
    /// A library of [n] tickets over a quarter, each in a project, and the projects.
    List<QueryNote> many(int n) => <QueryNote>[
      for (var p = 0; p < 20; p += 1) note('p$p', '# Project $p\n'),
      for (var i = 0; i < n; i += 1)
        note(
          't$i',
          '---\ntype: ticket\nid: K-$i\nstatus: ${const <String>['To do', 'In progress', 'Done'][i % 3]}\nassignee: ${const <String>['Sam', 'Alex', 'Priya', 'Kim'][i % 4]}\nproject: "[[Project ${i % 20}]]"\nhours: ${i % 7}\nstart: ${isoDayAfter('2026-09-01', i % 80)}\ndue: ${isoDayAfter('2026-09-01', i % 80 + 1 + i % 9)}\n---\n# Ticket $i\n',
        ),
    ];

    test('are run as every view, and again as a keystroke runs them, the notes read once and each view as dear as a table', () {
      final notes = many(1000);
      final cache = recordCache();
      final cold = libraryOf(notes, cache);
      final kept = <Object>[for (final read in cache.read.values) read.note];
      final warm = libraryOf(notes, cache);
      expect([for (final read in cache.read.values) read.note], orderedEquals(kept), reason: 'no note is read again while its words are the same');
      int once(String lines, [void Function(QueryResult result)? then]) {
        final watch = Stopwatch()..start();
        final result = runQuery(readQuery(lines).query!, warm, today);
        then?.call(result);
        return watch.elapsedMicroseconds;
      }

      // A table of the same thousand, as every query was drawn before, is what each view is held to: measured in
      // turn with the views, so a load that comes and goes on the machine falls on both.
      const table = 'from: tickets\nshow: table';
      final asked = <String, (String, void Function(QueryResult)?)>{
        'gantt': ('from: tickets\nshow: gantt\ngroup: assignee', (result) => ganttOfQuery(result, today)),
        'chart': ('from: tickets\nshow: chart\nx: status\ny: sum(hours)\nseries: assignee', null),
        'calendar': ('from: tickets\nshow: calendar', null),
        'rollups': ('from: tickets\nrollup: siblings = count(project)\nrollup: open = count(backlinks.project where status != done)\nrollup: hours = sum(hours of links)', null),
      };
      // Each round a view and a table run side by side; the view is held to the round where it came off best.
      final rounds = <String, List<(int, int)>>{};
      for (var round = 0; round < 5; round += 1) {
        for (final MapEntry(key: name, value: (lines, then)) in asked.entries) {
          final base = once(table);
          final mine = once(lines, then);
          (rounds[name] ??= <(int, int)>[]).add((mine, base));
        }
      }
      final best = <String, (int, int)>{
        for (final MapEntry(key: name, value: pairs) in rounds.entries) name: pairs.reduce((a, b) => a.$1 - 3 * a.$2 <= b.$1 - 3 * b.$2 ? a : b),
      };
      // ignore: avoid_print
      print('1000 tickets, each beside a table, best of five: ${best.entries.map((each) => '${each.key} ${each.value.$1 ~/ 1000}ms (a table ${each.value.$2 ~/ 1000}ms)').join(', ')}');
      for (final MapEntry(key: name, value: (mine, base)) in best.entries) {
        expect(mine, lessThan(3 * base + 20000), reason: '$name costs ${mine ~/ 1000}ms where a table beside it costs ${base ~/ 1000}ms');
      }
      expect(cold.records.length, 1020);
      final plan = ganttOfQuery(runQuery(readQuery('from: tickets\nshow: gantt').query!, warm, today), today);
      expect(plan.items.length, 1000);
      final rolled = runQuery(
        readQuery('from: notes\nwhere: title contains Project\nrollup: open = count(backlinks.project where status != done)\nrollup: hours = sum(hours of backlinks)\nrollup: done = percent(backlinks)').query!,
        warm,
        today,
      ).groups.single.rows.firstWhere((row) => row.key == 'p0');
      expect(rolled.cells.map((cell) => cell.toJson()).toList().sublist(2), <Object?>[
        {'kind': 'number', 'text': '33'},
        {'kind': 'number', 'text': '147'},
        {'kind': 'number', 'text': '34%'},
      ]);
    });

    testWidgets('a bar carried across a Gantt chart of a thousand builds nothing again, a frame of it a repaint', (tester) async {
      final notes = many(1000);
      final (_, asked) = await open(tester, 'from: tickets\nshow: gantt\nzoom: month\nsort: start', screen: 1000, notes: notes);
      expect(parts('ganttName'), findsNWidgets(1000));
      final first = ganttChart(tester).widget.model.items.first;
      final mouse = await tester.startGesture(barAt(tester, first.key, where: 'end'), kind: PointerDeviceKind.mouse);
      await mouse.moveBy(const Offset(20, 0));
      await tester.pump();
      var built = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) => built += 1;
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      for (var i = 0; i < 12; i += 1) {
        await mouse.moveBy(const Offset(4, 0));
        await tester.pump();
      }
      debugOnRebuildDirtyWidget = null;
      expect(built, 0, reason: 'a carry repaints the days; no row is built again');
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(asked.written.single.$1, first.ticket!.noteId);
    });
  });
}
