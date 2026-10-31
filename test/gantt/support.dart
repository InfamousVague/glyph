import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart' show drawnMermaid;
import 'package:ghost_md/editor/editor.dart' show history;
import 'package:ghost_md/editor/gantt/gantt.dart';
import 'package:ghost_md/editor/items/task_fields.dart' show fieldsToday;
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// A note with its ```gantt fences drawn: on a phone's width (390) or a Mac's (1100), light or dark, the library
/// [options] hands its tickets from.
Future<EditorView> pumpGantt(WidgetTester tester, String doc, {QueryOptions? options, String theme = 'light', double screen = 390, double height = 844, String today = '2026-11-04', bool readOnly = false, List<Extension> more = const <Extension>[], bool calm = false, bool simple = false}) async {
  queriesWatchMidnight = false;
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(readOnly: readOnly, more: <Extension>[history(), drawnGantt(() => options), queries(() => options), drawnMermaid(), fieldsToday.of(() => today), ...more]),
    ),
  );
  addTearDown(view.destroy);
  view.focusRequest = () => view.setFocused(true);
  await pumpApp(
    tester,
    size: Size(screen, height),
    prefs: AppPreferences(theme: theme, calm: calm, experience: simple ? 'simple' : 'advanced', experienceChosen: true),
    home: Builder(
      builder: (context) => BackScope(
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: screen, child: SingleChildScrollView(padding: const EdgeInsets.only(top: 24), child: EditorColumn(view: view))),
          ),
        ),
      ),
    ),
  );
  debugDisableShadows = true;
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump();
  return view;
}

/// The caret put at [at], in a focused editor.
Future<void> caretAt(WidgetTester tester, EditorView view, int at) async {
  view.setFocused(true);
  view.dispatch(TransactionSpec(selection: EditorSelection.single(at)));
  await tester.pump();
}

/// The chart's state.
GanttChartState ganttChart(WidgetTester tester) => tester.state<GanttChartState>(find.byType(GanttChart).first);

/// The fence's body as the note has it now.
String fenceBody(EditorView view) => ganttFencesOf(view.state.doc).first.body;

/// Where on the screen the middle of [key]'s bar is, [dx] along from it.
Offset barAt(WidgetTester tester, String key, {double dx = 0, String where = 'middle'}) {
  final state = ganttChart(tester);
  final item = state.widget.model.byKey[key]!;
  final rect = state.barRect(item, state.frame, state.rows);
  final origin = tester.getTopLeft(find.byKey(const ValueKey<String>('gantt-days')));
  final x = switch (where) {
    'start' => rect.left + 2,
    'end' => rect.right - 2,
    'knob' => state.knobOf(rect).dx,
    _ => rect.center.dx,
  };
  return origin + Offset(x + dx, rect.center.dy);
}

/// Where on the screen [day] is in the row of [key].
Offset dayInRow(WidgetTester tester, String key, String day) {
  final state = ganttChart(tester);
  final item = state.widget.model.byKey[key]!;
  final rect = state.barRect(item, state.frame, state.rows);
  final origin = tester.getTopLeft(find.byKey(const ValueKey<String>('gantt-days')));
  return origin + Offset(state.frame.x(day) + state.frame.wide / 2, rect.center.dy);
}

bool get featureShots => autoUpdateGoldenFiles || Platform.environment.containsKey('FEATURE_SHOTS');

/// A picture of the app as it stands, into build/feature-shots/gantt/[name].png.
Future<void> snap(WidgetTester tester, String name) async {
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
  File('build/feature-shots/gantt/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}
