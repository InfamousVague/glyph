// The pictures of the Gantt chart (docs/GANTT.md; Matt, 2026-10-31), into build/feature-shots/gantt/: a project with
// sections, waits, milestones and today; a bar being carried, pushing what waits on it; a task's panel (a popover on a
// Mac, a sheet on a phone); a Mermaid gantt with its Convert, and the chart it converts to; a query shown as the
// chart; and Calm. On a phone and on a Mac, light and dark. Written only with FEATURE_SHOTS=1 or --update-goldens.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';

import '../editor/queries/support.dart' show Asked, optionsOver, pumpQueries;
import '../support/render.dart';
import 'support.dart';

const String project = '''# Waitlist launch

The plan for the beta's waitlist, as of Wednesday.

```gantt
title: Waitlist launch
workdays: true
today: 2026-11-04

## Research
- Interview five users [2026-11-02 → 2026-11-04] @matt #research 100%
- Read the competition [2026-11-03 +3d] @sam 40%

## Build
- Design the waitlist [2026-11-05 → 2026-11-11] @matt #design after: Interview five users 60%
- Build the signup page [+4d] @sam after: Design the waitlist
- Email the list [+2d] after: Build the signup page colour: purple
- ◆ Beta opens [2026-11-20] after: Email the list

## Launch
- Press kit [2026-11-16 → 2026-11-19] @ana
- ◆ Launch [2026-11-25] after: Beta opens, Press kit
```
''';

const String mermaid = '''# Sprint 14

```mermaid
gantt
  title Sprint 14
  dateFormat YYYY-MM-DD
  excludes weekends
  section Backend
  API design      :api, 2026-11-02, 3d
  Endpoints       :ep, after api, 5d
  section Frontend
  Mockups         :done, mock, 2026-11-02, 2d
  Screens         :active, scr, after mock api, 4d
  section Release
  Ship it         :milestone, after ep scr, 0d
```
''';

void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    for (final (where, width, height) in [('phone', 390.0, 844.0), ('mac', 1100.0, 760.0)]) {
      testWidgets('a project, $where, $theme', (tester) async {
        if (!featureShots) return;
        await pumpGantt(tester, project, theme: theme, screen: width, height: height);
        await snap(tester, 'project-$where-$theme');
      });

      testWidgets('a bar being carried, $where, $theme', (tester) async {
        if (!featureShots) return;
        await pumpGantt(tester, project, theme: theme, screen: width, height: height);
        final wide = ganttChart(tester).dayWide;
        final TestGesture hand;
        if (where == 'mac') {
          hand = await tester.startGesture(barAt(tester, 'L11'), kind: PointerDeviceKind.mouse);
          await tester.pump();
        } else {
          hand = await tester.startGesture(barAt(tester, 'L11'));
          await tester.pump(const Duration(milliseconds: 600));
        }
        await hand.moveBy(Offset(wide * 1.6, 0));
        await tester.pump();
        await hand.moveBy(Offset(wide * 1.6, 0));
        await tester.pump();
        await snap(tester, 'dragging-$where-$theme');
        await hand.up();
        await tester.pump(const Duration(milliseconds: 100));
      });

      testWidgets('a task’s panel, $where, $theme', (tester) async {
        if (!featureShots) return;
        await pumpGantt(tester, project, theme: theme, screen: width, height: where == 'mac' ? 1180 : height);
        ganttChart(tester).select('L11', edit: true);
        await tester.pump(const Duration(milliseconds: 500));
        await snap(tester, 'panel-$where-$theme');
      });

      testWidgets('a Mermaid gantt converted, $where, $theme', (tester) async {
        if (!featureShots) return;
        await pumpGantt(tester, mermaid, theme: theme, screen: width, height: height);
        await snap(tester, 'mermaid-before-$where-$theme');
        await tester.tap(find.byKey(const ValueKey<String>('diagram-convert-gantt')));
        await tester.pump(const Duration(milliseconds: 100));
        await snap(tester, 'mermaid-converted-$where-$theme');
      });

      testWidgets('a query shown as the chart, $where, $theme', (tester) async {
        if (!featureShots) return;
        QueryNote note(String id, String body) => QueryNote(id: id, body: body, createdAt: 0, updatedAt: 0);
        final library = <QueryNote>[
          note('a', '---\ntype: ticket\nid: KLN-12\nstatus: In progress\nassignee: sam\nstart: 2026-11-02\ndue: 2026-11-06\n---\n# Fix the login loop\n'),
          note('b', '---\ntype: ticket\nid: KLN-13\nstatus: Done\nassignee: matt\nstart: 2026-10-28\ndue: 2026-11-02\n---\n# Write the docs\n'),
          note('c', '---\ntype: ticket\nid: KLN-14\nstatus: To do\nassignee: sam\nstart: 2026-11-09\ndue: 2026-11-13\nblocked-by: "[[KLN-12]]"\n---\n# Ship the beta\n'),
          note('d', '---\ntype: ticket\nid: KLN-15\nstatus: To do\nassignee: ana\ndue: 2026-11-11\n---\n# Pricing page\n'),
        ];
        final options = optionsOver(() => library, Asked());
        await pumpQueries(tester, '# Kiln\n\n```query\nfrom: tickets\nshow: gantt\ngroup: assignee\n```\n', options: options, theme: theme, screen: width, today: '2026-11-04');
        await snap(tester, 'query-$where-$theme');
      });
    }

    testWidgets('a project in Calm, mac, $theme', (tester) async {
      if (!featureShots) return;
      await pumpGantt(tester, project, theme: theme, screen: 1100, height: 760, calm: true);
      await snap(tester, 'project-calm-mac-$theme');
    });
  }
}
