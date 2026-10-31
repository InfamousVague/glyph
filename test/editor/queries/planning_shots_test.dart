// Pictures of a ticket's planning (Matt, 2026-10-31; lib/core/query/planning.dart, lib/editor/queries/plan_marks.dart):
// the current cycle's board with its carry bar, a card's coloured priority, estimate and stale, the burndown and
// velocity, the roadmap, a list of what is stale, and a ticket's and an epic's panel with their sheets; on a phone
// and a desktop's wide window, light and dark, and in Calm. Written only by `flutter test --update-goldens
// test/editor/queries/planning_shots_test.dart`, into build/feature-shots/tickets-planning/*.png (not committed), to
// be looked at, not held as goldens.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/planning/history.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/tickets/ticket_panel.dart';

import '../../query/planning_library.dart' as planned;
import '../../support/render.dart';
import '../tickets/support.dart' as tickets;
import 'support.dart';

final TicketHistory past = TicketHistory((id) async => const [])..hold('k5', const [StatusChange(day: '2026-11-02', status: 'To do'), StatusChange(day: '2026-11-03', status: 'Done')]);

QueryOptions options() => QueryOptions(notes: () => planned.library, noteId: 'here', open: (_, _) {}, write: (_, _) {}, history: () => past);

String fence(String lines, [String heading = 'Kiln, this cycle']) => '# $heading\n\n```query\n$lines\n```\n';

final PlanningIndex plan = PlanningIndex(libraryOf(planned.library), planned.today, past: past);

TicketOptions ticketOptions(String id) => TicketOptions(
  statuses: () => defaultStatuses,
  people: () => const ['Sam', 'Priya', 'Alex', 'Kim'],
  choices: () => const <TicketChoice>[],
  find: (_) => null,
  open: (_) {},
  subTickets: () => [
    for (final child in plan.children[id] ?? const <QueryRecord>[]) TicketChoice(key: child.ticket!.id, title: child.title, status: child.ticket!.status, category: child.ticket!.category),
  ],
  planning: () => ticketPlanningOf(plan, id),
);

void main() {
  setUpAll(loadAppFonts);

  Future<void> snap(WidgetTester tester, String name) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/tickets-planning/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  Future<void> after(WidgetTester tester, {bool calm = false, Future<void> Function()? then}) async {
    if (calm) {
      preferences.update((now) => now.copyWith(calm: true));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));
    await then?.call();
  }

  Future<void> done(WidgetTester tester) async {
    preferences.update((now) => now.copyWith(calm: false));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> shoot(WidgetTester tester, String name, String doc, {double screen = 390, String theme = 'light', bool calm = false, Future<void> Function()? then}) async {
    if (!autoUpdateGoldenFiles) return;
    await pumpQueries(tester, doc, options: options(), today: planned.today, screen: screen, theme: theme);
    await after(tester, calm: calm, then: then);
    await snap(tester, name);
    await done(tester);
  }

  Future<void> panel(WidgetTester tester, String name, String id, {double screen = 390, String theme = 'light', bool calm = false, Future<void> Function()? then}) async {
    if (!autoUpdateGoldenFiles) return;
    final body = planned.library.firstWhere((note) => note.id == id).body;
    await tickets.pumpTickets(tester, body, options: ticketOptions(id), today: planned.today, screen: screen, theme: theme);
    await after(tester, calm: calm, then: then);
    await snap(tester, name);
    await done(tester);
  }

  for (final theme in const <String>['light', 'dark']) {
    testWidgets('the current cycle’s board, $theme', (tester) async {
      await shoot(tester, 'board-cycle-phone-$theme', fence('from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board'), theme: theme);
      await shoot(tester, 'board-cycle-wide-$theme', fence('from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board'), screen: 1100, theme: theme);
      await shoot(tester, 'board-all-wide-$theme', fence('from: tickets [[Kiln]]\nshow: board', 'Kiln'), screen: 1100, theme: theme);
    });

    testWidgets('the burndown and velocity, $theme', (tester) async {
      await shoot(tester, 'burndown-phone-$theme', fence('from: tickets [[Kiln]]\nshow: burndown'), theme: theme);
      await shoot(tester, 'burndown-wide-$theme', fence('from: tickets [[Kiln]]\nshow: burndown'), screen: 1100, theme: theme);
      await shoot(tester, 'velocity-phone-$theme', fence('from: tickets [[Kiln]]\nshow: velocity', 'Kiln, every cycle'), theme: theme);
    });

    testWidgets('the roadmap and what is stale, $theme', (tester) async {
      await shoot(tester, 'roadmap-wide-$theme', fence('from: notes [[Kiln]]\nshow: roadmap\nzoom: quarter', 'Kiln roadmap'), screen: 1100, theme: theme);
      await shoot(tester, 'roadmap-phone-$theme', fence('from: notes [[Kiln]]\nshow: roadmap', 'Kiln roadmap'), theme: theme);
      await shoot(tester, 'stale-list-phone-$theme', fence('from: tickets [[Kiln]]\nwhere: stale\nsort: age desc\nshow: list', 'Left a while'), theme: theme);
      await shoot(tester, 'totals-table-wide-$theme', fence('from: tickets [[Kiln]]\ncolumns: id, title, assignee, priority, estimate, cycle, age\ngroup: cycle\ntotal: estimate\nsort: priority', 'Kiln by cycle'), screen: 1100, theme: theme);
    });

    testWidgets('a ticket’s panel and an epic’s, $theme', (tester) async {
      await panel(tester, 'panel-ticket-phone-$theme', 'k3', theme: theme);
      await panel(tester, 'panel-epic-wide-$theme', 'k1', screen: 1024, theme: theme);
      await panel(tester, 'panel-cycle-sheet-$theme', 'k6', theme: theme, then: () async {
        await tester.tap(said(RegExp(r'^Cycle: ')));
        await tester.pump(const Duration(milliseconds: 500));
      });
      await panel(tester, 'panel-priority-sheet-$theme', 'k6', theme: theme, then: () async {
        await tester.tap(said(RegExp(r'^Priority: ')));
        await tester.pump(const Duration(milliseconds: 500));
      });
    });
  }

  testWidgets('in Calm, and a card’s estimate sheet', (tester) async {
    await shoot(tester, 'board-cycle-calm', fence('from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board'), calm: true);
    await shoot(tester, 'burndown-calm', fence('from: tickets [[Kiln]]\nshow: burndown'), calm: true);
    await shoot(tester, 'estimate-sheet-phone', fence('from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board'), then: () async {
      final chip = said('Estimate: 8 pts. Change it');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
