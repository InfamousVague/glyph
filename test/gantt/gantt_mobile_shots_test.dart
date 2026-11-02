// The pictures of a long Mermaid gantt on a phone (Matt, 2026-11-02, from the Fold's cover screen: "Clean up the gantt
// chart viewing experience to be scrolling on mobile and bigger right now it's very cluttered and impossible to
// parse"), into build/gantt-mobile/: a chart shaped like his, nine months in five sections, long names, a milestone
// at the end and today in the middle, at 390, 880 and 1280 across, light and dark, in the note and full screen.
// Written only with FEATURE_SHOTS=1 or --update-goldens; GANTT_SHOTS names the set (`before`, `after`).
//
// The Mermaid picture of the set before is Mermaid's own, drawn by tool/diagram_fixtures.mjs from the asks a run
// with DIAGRAM_FIXTURES=want writes down.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/gantt/gantt.dart' show mermaidToGantt;
import 'package:ghost_md/editor/diagrams/diagrams.dart';

import '../editor/diagrams/support.dart' show PicturedBridge, settleDiagrams;
import '../support/render.dart';
import 'support.dart';

/// A plan shaped like his: three long phases, eight months, four stretches of getting ready, five checks with long
/// names, and the day it is done.
const String plan = '''# The renovation

The whole job on one chart.

```mermaid
gantt
    title The renovation, done May 17, 2027
    dateFormat YYYY-MM-DD
    axisFormat %b %d

    section Phases
    First phase (weeks 1-13)         :t1, 2026-08-10, 2026-11-09
    Second phase (weeks 14-27)       :t2, 2026-11-09, 2027-02-15
    Third phase (weeks 28-40)        :t3, 2027-02-15, 2027-05-17

    section Plan months
    Month 2 (week 8)                 :m2, 2026-09-28, 2026-10-05
    Month 3 (weeks 9-13)             :m3, 2026-10-05, 2026-11-09
    Month 4 (weeks 14-17)            :m4, 2026-11-09, 2026-12-07
    Month 5 (weeks 18-22)            :m5, 2026-12-07, 2027-01-11
    Month 6 (weeks 23-27)            :m6, 2027-01-11, 2027-02-15
    Month 7 (weeks 28-31)            :m7, 2027-02-15, 2027-03-15
    Month 8 (weeks 32-35)            :m8, 2027-03-15, 2027-04-12
    Month 9 (weeks 36-40)            :m9, 2027-04-12, 2027-05-17

    section Getting ready
    Planning and permits             :p1, 2026-09-28, 2026-12-07
    Buying the materials             :p2, 2026-12-07, 2027-02-15
    Clearing the rooms               :p3, 2027-02-15, 2027-04-12
    Tools packed, waiting            :p4, 2027-04-12, 2027-05-17

    section Usual inspections and checks
    First structural inspection (weeks 11-14) :s1, 2026-10-19, 2026-11-16
    Wiring check (about week 20)     :s2, 2026-12-21, 2026-12-28
    Plumbing test (weeks 24-28)      :s3, 2027-01-18, 2027-02-22
    Paint touch-ups (weeks 27-36)    :s4, 2027-02-08, 2027-04-19
    Final safety check (weeks 36-37) :s5, 2027-04-12, 2027-04-26

    section Done
    Done date                        :milestone, due, 2027-05-17, 0d
```

After the chart.
''';

final String _set = Platform.environment['GANTT_SHOTS'] ?? 'after';

/// A picture of the app as it stands, into build/gantt-mobile/[name].png.
Future<void> _snap(WidgetTester tester, String name) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 200));
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
  File('build/gantt-mobile/$_set-$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    diagramStore = DiagramStore(bridge: PicturedBridge());
    rememberDiagramHeights = false;
  });

  for (final theme in ['light', 'dark']) {
    for (final (width, height) in [(390.0, 2000.0), (880.0, 1500.0), (1280.0, 1400.0)]) {
      final across = width.round();
      testWidgets('his chart in a note, $across, $theme', (tester) async {
        if (!featureShots) return;
        await pumpGantt(tester, plan, theme: theme, screen: width, height: height, today: '2026-11-02');
        await settleDiagrams(tester);
        await _snap(tester, 'note-$across-$theme');
      });

      testWidgets('his chart as the app’s own gantt fence, $across, $theme', (tester) async {
        if (!featureShots) return;
        final code = RegExp(r'```mermaid\n([\s\S]*?)```').firstMatch(plan)!.group(1)!;
        final fence = plan.replaceFirst(RegExp(r'```mermaid\n[\s\S]*?```'), '```gantt\n${mermaidToGantt(code).body}\n```');
        await pumpGantt(tester, fence, theme: theme, screen: width, height: height, today: '2026-11-02');
        await _snap(tester, 'fence-$across-$theme');
      });

      testWidgets('his chart full screen, $across, $theme', (tester) async {
        if (!featureShots) return;
        await pumpGantt(tester, plan, theme: theme, screen: width, height: width < 600 ? 844 : 900, today: '2026-11-02');
        await settleDiagrams(tester);
        // The chart's own Full screen, or, before, the diagram's.
        var button = find.byKey(const ValueKey<String>('gantt-full'));
        if (button.evaluate().isEmpty) button = find.byKey(const ValueKey<String>('diagram-full'));
        if (button.evaluate().isEmpty) return;
        await tester.tap(button.first);
        await tester.pump();
        await settleDiagrams(tester);
        await _snap(tester, 'full-$across-$theme');
        // Scrolled down the rows: the head stays at the top.
        final scroll = find.byKey(const ValueKey<String>('gantt-full-scroll'));
        if (scroll.evaluate().isEmpty) return;
        tester.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable)).first).position.jumpTo(500);
        await tester.pump();
        await _snap(tester, 'full-scrolled-$across-$theme');
      });

      testWidgets('his chart in a note scrolled up, $across, $theme', (tester) async {
        if (!featureShots) return;
        await pumpGantt(tester, plan, theme: theme, screen: width, height: width < 600 ? 844 : 900, today: '2026-11-02');
        await settleDiagrams(tester);
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(width < 600 ? 900 : 700);
        await tester.pump();
        await _snap(tester, 'note-scrolled-$across-$theme');
      });
    }
  }
}
