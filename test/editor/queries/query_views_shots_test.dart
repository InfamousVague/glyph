// Pictures of the port's own query views (Matt, 2026-10-30, "add all 12"): the calendar on a phone and as a wide
// window's month and week, the drawn timeline, the chart as bars, a line and a pie, in Calm too, a rollup's column
// with a relation's chips, and the builder's rows behind More in simple mode; light and dark. Written only by
// `flutter test --update-goldens test/editor/queries/query_views_shots_test.dart`, into
// build/feature-shots/queries-views/*.png (not committed), to be looked at, not held as goldens.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/query/query.dart';

import '../../support/render.dart';
import 'support.dart';

const String today = '2026-10-08';

QueryNote note(String id, String body) => QueryNote(id: id, body: body, createdAt: 0, updatedAt: 0);

String ticket(int n, String title, String status, String who, String? start, String? due, int estimate, {String project = 'Kiln', int hours = 0}) =>
    '---\ntype: ticket\nid: KLN-$n\nstatus: $status\nassignee: $who\n${start == null ? '' : 'start: $start\n'}${due == null ? '' : 'due: $due\n'}estimate: $estimate\nproject: "[[$project]]"\nhours: $hours\n---\n# $title\n';

final List<QueryNote> library = <QueryNote>[
  note('kiln', '---\nstatus: In progress\n---\n# Kiln\n\nThe studio\'s second kiln: [[Glaze tests]], [[Firing log]].\n'),
  note('shop', '---\nstatus: To do\n---\n# Shop front\n'),
  note('k1', ticket(1, 'Wire the controller', 'Done', 'Sam', '2026-09-28', '2026-10-02', 3, hours: 6)),
  note('k2', ticket(2, 'Glaze tests', 'In progress', 'Priya', '2026-10-05', '2026-10-12', 5, hours: 9)),
  note('k3', ticket(3, 'Firing log', 'To do', 'Alex', '2026-10-09', '2026-10-16', 2, hours: 2)),
  note('k4', ticket(4, 'Order shelves', 'To do', 'Sam', null, '2026-10-06', 1, hours: 1)),
  note('k5', ticket(5, 'Vent the room', 'In review', 'Priya', '2026-10-13', '2026-10-21', 3, hours: 4)),
  note('k6', ticket(6, 'Photograph the first firing', 'To do', 'Alex', '2026-10-19', '2026-10-23', 2)),
  note('k7', ticket(7, 'Price list', 'In progress', 'Kim', '2026-10-07', '2026-10-14', 3, project: 'Shop front', hours: 3)),
  note('k8', ticket(8, 'Shop window', 'To do', 'Kim', '2026-10-15', '2026-10-30', 5, project: 'Shop front')),
  note('k9', ticket(9, 'Card reader', 'Done', 'Sam', '2026-10-01', '2026-10-08', 1, project: 'Shop front', hours: 2)),
];

String fence(String lines, [String heading = 'Studio']) => '# $heading\n\n```query\n$lines\n```\n';

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
    File('build/feature-shots/queries-views/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  Future<void> shoot(WidgetTester tester, String name, String doc, {double screen = 390, String theme = 'light', bool calm = false, Future<void> Function()? then}) async {
    if (!autoUpdateGoldenFiles) return;
    await pumpQueries(tester, doc, options: optionsOver(() => library, Asked()), today: today, screen: screen, theme: theme);
    if (calm) {
      preferences.update((now) => now.copyWith(calm: true));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));
    await then?.call();
    await snap(tester, name);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  for (final theme in const <String>['light', 'dark']) {
    testWidgets('the calendar, $theme', (tester) async {
      await shoot(tester, 'calendar-phone-$theme', fence('from: tickets\nshow: calendar'), theme: theme, then: () async {
        await tester.tap(parts('dayCell').at(10));
        await tester.pump();
      });
      await shoot(tester, 'calendar-month-wide-$theme', fence('from: tickets\nshow: calendar'), screen: 1100, theme: theme);
      await shoot(tester, 'calendar-week-wide-$theme', fence('from: tickets\nshow: calendar\ndate: start'), screen: 1100, theme: theme, then: () async {
        await tester.tap(said('Show a week'));
        await tester.pump();
      });
    });

    testWidgets('the timeline, $theme', (tester) async {
      await shoot(tester, 'timeline-phone-$theme', fence('from: tickets\nshow: timeline\nzoom: week'), theme: theme);
      await shoot(tester, 'timeline-wide-grouped-$theme', fence('from: tickets\nshow: timeline\ngroup: project\nzoom: month'), screen: 1100, theme: theme);
    });

    testWidgets('the chart, $theme', (tester) async {
      await shoot(tester, 'chart-bars-phone-$theme', fence('from: tickets\nshow: chart\nx: status\ny: sum(estimate)\nseries: assignee'), theme: theme);
      await shoot(tester, 'chart-bars-picked-$theme', fence('from: tickets\nshow: chart'), theme: theme, then: () async {
        final box = tester.getRect(find.byKey(const ValueKey<String>('query-chart')));
        await tester.tapAt(Offset(box.left + 60, box.bottom - 30));
        await tester.pump();
      });
      await shoot(tester, 'chart-line-wide-$theme', fence('from: tickets\nshow: chart\nchart: line\nx: due\ny: sum(hours)'), screen: 1100, theme: theme);
      await shoot(tester, 'chart-pie-phone-$theme', fence('from: tickets\nshow: chart\nchart: pie\nx: assignee'), theme: theme);
      await shoot(tester, 'chart-pie-wide-$theme', fence('from: tickets\nshow: chart\nchart: pie\nx: status'), screen: 1100, theme: theme);
      await shoot(tester, 'chart-calm-$theme', fence('from: tickets\nshow: chart\nx: status\ny: sum(estimate)\nseries: assignee'), theme: theme, calm: true);
    });

    testWidgets('a rollup and a relation, $theme', (tester) async {
      await shoot(tester, 'rollup-table-$theme', fence('where: title = Kiln or title = "Shop front"\ncolumns: title, open, hours, done\nshow: table\nrollup: open = count(backlinks.project where status != done)\nrollup: hours = sum(hours of backlinks.project)\nrollup: done = percent(backlinks.project)', 'Projects'), theme: theme);
      await shoot(tester, 'relation-chips-$theme', fence('from: tickets\ncolumns: id, title, project, status\nshow: table\nlimit: 5'), theme: theme);
    });

    testWidgets('the builder, $theme', (tester) async {
      await shoot(tester, 'builder-simple-more-$theme', fence('from: tickets\nshow: chart'), theme: theme, then: () async {
        preferences.update((now) => now.copyWith(experience: 'simple', experienceChosen: true));
        await tester.tap(said('Build the query'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.ensureVisible(find.byKey(const ValueKey<String>('more')));
        await tester.pump(const Duration(milliseconds: 300));
      });
      await shoot(tester, 'builder-timeline-$theme', fence('from: tickets\nshow: timeline'), theme: theme, then: () async {
        await tester.tap(said('Build the query'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.ensureVisible(find.byKey(const ValueKey<String>('zoom:week')));
        await tester.pump(const Duration(milliseconds: 300));
      });
    });
  }
}
