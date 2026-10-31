import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/gantt/gantt.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart' show convertGanttWords;
import 'package:ghost_md/editor/editor.dart' show undoNote;
import 'package:ghost_md/editor/gantt/gantt.dart';
import 'package:ghost_md/editor/plus/add_rows.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/sheet/ask_first.dart';

import '../editor/queries/support.dart' show Asked, optionsOver, pumpQueries;
import '../support/render.dart';
import 'gantt_chart_test.dart' show mouseDrag;
import 'support.dart';

/// A ```gantt fence's tickets, a query shown as the same chart writing its records' days, the Mermaid gantt turned
/// into a fence, the + and the palette's Gantt chart, and three hundred tasks carried without a widget built again.
QueryNote note(String id, String body) => QueryNote(id: id, body: body, createdAt: 0, updatedAt: 0);

final List<QueryNote> tickets = <QueryNote>[
  note('k12', '---\ntype: ticket\nid: KLN-12\nstatus: In progress\nassignee: sam\nstart: 2026-11-03\ndue: 2026-11-06\n---\n# Fix the login loop\n'),
  note('k13', '---\ntype: ticket\nid: KLN-13\nstatus: Done\nstart: 2026-11-02\ndue: 2026-11-03\n---\n# Write the docs\n'),
  note('k14', '---\ntype: ticket\nid: KLN-14\nstatus: To do\ndue: 2026-11-10\nblocked-by: "[[KLN-12]]"\n---\n# Ship it\n'),
];

/// [asked]'s writes to [id], made in turn on its note as it is.
String written(Asked asked, String id) {
  var body = tickets.firstWhere((each) => each.id == id).body;
  for (final write in asked.written.where((each) => each.$1 == id)) {
    body = write.$2(body) ?? body;
  }
  return body;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a fence’s [[ticket]] is drawn from the ticket, and carried writes the ticket’s start and due', (tester) async {
    final asked = Asked();
    final view = await pumpGantt(tester, '```gantt\n- [[KLN-12]]\n- Review after: KLN-12\n```\n', options: optionsOver(() => tickets, asked), screen: 1100);
    final model = ganttChart(tester).widget.model;
    expect((model.byKey['L0']!.name, model.byKey['L0']!.label, model.byKey['L0']!.start, model.byKey['L0']!.end, model.byKey['L0']!.person), ('Fix the login loop', 'KLN-12', '2026-11-03', '2026-11-06', 'sam'));
    expect(model.byKey['L1']!.start, '2026-11-07');
    final wide = ganttChart(tester).dayWide;
    await mouseDrag(tester, barAt(tester, 'L0'), Offset(wide, 0));
    expect(fenceBody(view), '- [[KLN-12]]\n- Review after: KLN-12', reason: 'the fence says nothing new: the days are the ticket’s');
    final body = written(asked, 'k12');
    expect(body, contains('start: 2026-11-04'));
    expect(body, contains('due: 2026-11-07'));
    expect(body, contains('# Fix the login loop'));
  });

  testWidgets('show: gantt is this chart, its bars writing the records’ own days; show: timeline the same', (tester) async {
    for (final show in ['gantt', 'timeline']) {
      final asked = Asked();
      await pumpQueries(tester, '# Kiln\n\n```query\nfrom: tickets\nshow: $show\n```\n', options: optionsOver(() => tickets, asked), screen: 1100, today: '2026-11-04');
      expect(find.byType(GanttChart), findsOneWidget);
      final model = ganttChart(tester).widget.model;
      expect(model.items.map((item) => item.label).toSet(), {'KLN-12', 'KLN-13', 'KLN-14'});
      final wide = ganttChart(tester).dayWide;
      await mouseDrag(tester, barAt(tester, 'k12', where: 'end'), Offset(2 * wide, 0));
      final body = written(asked, 'k12');
      expect(body, contains('due: 2026-11-08'));
      expect(body, contains('start: 2026-11-03'));
      expect(asked.written.length, 1, reason: 'only the end’s field, which changed');
      // KLN-14, due alone, gets a start of its own when it is carried.
      await mouseDrag(tester, barAt(tester, 'k14'), Offset(wide, 0));
      final moved = written(asked, 'k14');
      expect(moved, contains('start: 2026-11-11'));
      expect(moved, contains('due: 2026-11-11'));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a Mermaid gantt keeps its drawing and offers Convert, which writes the fence as one undo', (tester) async {
    const mermaid = '```mermaid\ngantt\n  title Sprint\n  dateFormat YYYY-MM-DD\n  section Build\n  Design :d, 2026-11-02, 3d\n  Code :after d, 4d\n```';
    final view = await pumpGantt(tester, '# Plan\n\n$mermaid\n\nAfter.\n', screen: 1100);
    expect(find.text(convertGanttWords), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('diagram-convert-gantt')));
    await tester.pump();
    expect(view.state.doc.toString(), '# Plan\n\n```gantt\ntitle: Sprint\n\n## Build\n- Design [2026-11-02 +3d]\n- Code [+4d] after: Design\n```\n\nAfter.\n');
    expect(find.byType(GanttChart), findsOneWidget);
    undoNote(view);
    await tester.pump(const Duration(milliseconds: 100));
    expect(view.state.doc.toString(), '# Plan\n\n$mermaid\n\nAfter.\n');
  });

  testWidgets('a Mermaid gantt with what cannot come asks first, and Cancel writes nothing', (tester) async {
    const mermaid = '```mermaid\ngantt\n  dateFormat YYYY-MM-DD\n  excludes 2026-12-25\n  Cover :c, 2026-12-21, 36h\n```';
    final view = await pumpGantt(tester, '$mermaid\n', screen: 1100);
    final asks = <FirstAsk>[];
    var yes = false;
    debugAskFirst = (ask) async {
      asks.add(ask);
      return yes;
    };
    addTearDown(() => debugAskFirst = null);
    await tester.tap(find.byKey(const ValueKey<String>('diagram-convert-gantt')));
    await tester.pump();
    expect(asks.single.title, 'Convert to an interactive Gantt?');
    expect(asks.single.note, startsWith('Some of it can’t come with it: Days left out one at a time (excludes 2026-12-25)'));
    expect(view.state.doc.toString(), '$mermaid\n');
    yes = true;
    await tester.tap(find.byKey(const ValueKey<String>('diagram-convert-gantt')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(view.state.doc.toString(), '```gantt\n- Cover [2026-12-21 +2d]\n```\n');
  });

  test('the + and the palette offer a Gantt chart, a small one with its title chosen', () {
    final rows = allRows(const AddGates(picture: false, video: false, place: PlaceGate.absent, note: false, canvas: false, gantt: true), DateTime(2026, 11, 4));
    expect(rows.where((row) => row.id == 'gantt').single.words, 'A Gantt chart');
    expect(allRows(const AddGates(picture: false, video: false, place: PlaceGate.absent, note: false, canvas: false), DateTime(2026, 11, 4)).where((row) => row.id == 'gantt'), isEmpty, reason: 'only where the editor draws one');
    final state = EditorState.create(doc: '');
    final made = planFor(state, 'gantt', DateTime(2026, 11, 4, 9))! as RowBlock;
    expect(made.text, '```gantt\ntitle: Project\n\n## Plan\n- Plan it [2026-11-04 → 2026-11-06]\n- Build it [+3d] after: Plan it\n- ◆ Ship it after: Build it\n```');
    final body = readGantt(made.text.split('\n').sublist(1, 7).join('\n'));
    expect(body.problems, isEmpty);
    expect(ganttModelOf(body, today: '2026-11-04').byKey['L5']!.start, '2026-11-10');
  });

  testWidgets('three hundred tasks: a bar carried builds nothing again, and each step is a repaint', (tester) async {
    final lines = <String>['title: Big', 'workdays: true'];
    for (var section = 0; section < 10; section += 1) {
      lines.add('## Stream ${section + 1}');
      for (var n = 0; n < 30; n += 1) {
        final at = section * 30 + n;
        final day = isoAfter('2026-11-02', n * 2 + section);
        lines.add(n == 0 ? '- Task $at [$day +2d]' : '- Task $at [+2d] after: Task ${at - 1}');
      }
    }
    final view = await pumpGantt(tester, '```gantt\n${lines.join('\n')}\n```\n', screen: 1100, height: 900);
    final state = ganttChart(tester);
    expect(state.widget.model.items.length, 300);
    final builds = GanttChartState.builds;
    final paints = GanttPainter.paints;
    final wide = state.dayWide;
    final mouse = await tester.startGesture(barAt(tester, 'L3'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    final painted = GanttPainter.painting;
    final clock = Stopwatch()..start();
    var frames = 0;
    for (var step = 1; step <= 12; step += 1) {
      await mouse.moveBy(Offset(wide, 0));
      await tester.pump();
      frames += 1;
    }
    clock.stop();
    expect(GanttChartState.builds - builds, 0, reason: 'a carry builds no widget again');
    expect(GanttPainter.paints - paints, inInclusiveRange(frames, frames + 2), reason: 'each step is one repaint of the days');
    // The painting alone, which is all a step redoes, measured; held loosely, since a test's clock runs on a debug
    // build on a machine doing other work (a phone's release build paints it in a fraction of this).
    expect((GanttPainter.painting - painted).inMilliseconds / frames, lessThan(40));
    debugPrint('three hundred tasks: ${(clock.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)} ms a step, ${((GanttPainter.painting - painted).inMicroseconds / frames / 1000).toStringAsFixed(2)} ms of it painting, ${GanttPainter.paints - paints} repaints, ${GanttChartState.builds - builds} builds');
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fenceBody(view).split('\n')[3], '- Task 0 [2026-11-16 +2d]', reason: 'carried onto a Saturday, it goes on to the Monday, two working days long');
    expect(fenceBody(view).split('\n')[4], '- Task 1 [+2d] after: Task 0', reason: 'what waits on it follows by itself');
  });
}

String isoAfter(String day, int count) => DateTime.parse(day).add(Duration(days: count)).toIso8601String().substring(0, 10);
