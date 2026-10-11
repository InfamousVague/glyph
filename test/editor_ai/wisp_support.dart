// What the wisp's tests in this folder share: a note's editor on a narrow page with the arrivals (and whatever
// else) over the base editor, the clock held, the marks read back as the web's tests read `.cm-wispCh` and
// `.cm-wispWait` from the DOM, and a picture of the page.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/art/wisp_text.dart' show wispSlotSeed;
import 'package:ghost_md/editor/ai/wisp_arrivals.dart';
import 'package:ghost_md/editor/ai/wisp_filters.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// The clock the wisp reads, held: a test moves it.
double clock = 50000;

/// Holds the wisp's clock for a test and gives it back after.
void holdClock() {
  final real = wispNow;
  setUp(() {
    clock = 50000;
    wispNow = () => clock;
  });
  tearDown(() => wispNow = real);
}

/// The wisp's shaders and the noise of every filter the arrivals' pool and the ripples name: a picture wants them.
Future<void> loadWisp(WidgetTester tester) async {
  await tester.runAsync(() => WispKit.load(seeds: <int>[for (var i = 0; i < poolMax; i++) wispSlotSeed(i), for (var i = 0; i < 4; i++) i * 13 + 5]));
}

final List<EditorView> _views = <EditorView>[];

/// A note's editor, 390 wide, with `more` over the base editor. Answers the view.
Future<EditorView> pumpEditor(WidgetTester tester, String doc, {List<Extension> more = const <Extension>[], String theme = 'light', Size size = const Size(390, 844)}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(doc: doc, extensions: noteExtensions(more: more)),
  );
  _views.add(view);
  addTearDown(view.destroy);
  await pumpApp(
    tester,
    size: size,
    prefs: AppPreferences(theme: theme),
    home: Builder(
      builder: (context) => ColoredBox(
        color: context.tokens.color('glacier-bg'),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: size.width, child: SingleChildScrollView(child: EditorColumn(view: view))),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  return view;
}

/// Moves the held clock on by `ms`, a frame every `step`, as the page's frames come.
Future<void> advance(WidgetTester tester, double ms, {double step = 50}) async {
  for (var gone = 0.0; gone < ms - 0.001; gone += step) {
    final by = step < ms - gone ? step : ms - gone;
    clock += by;
    await tester.pump(Duration(microseconds: (by * 1000).round()));
  }
}

/// A mark the arrivals drew: what a test of the page reads from `.cm-wispCh` and `.cm-wispWait`.
typedef Drawn = ({int from, int to, String name, String? filter, String? text, String? ripple});

List<Drawn> drawnBy(DecorationSet set, int length) {
  final found = <Drawn>[];
  set.between(0, length, (from, to, value) {
    final attrs = value.spec.attributes ?? const <String, String>{};
    found.add((from: from, to: to, name: value.spec.className ?? '', filter: filterIdOf(attrs), text: attrs['data-text'], ripple: attrs['data-ripple']));
    return null;
  });
  return found..sort((a, b) => a.from - b.from);
}

/// The arrivals' marks in `view`, in document order.
List<Drawn> drawn(EditorView view) => drawnBy(view.plugin(wispPlugin)?.decorations ?? Decoration.none, view.state.doc.length);

/// The letters wearing a filter, and the words waiting.
List<Drawn> wearing(EditorView view) => <Drawn>[
  for (final mark in drawn(view))
    if (mark.name == 'cm-wispCh') mark,
];
List<Drawn> waiting(EditorView view) => <Drawn>[
  for (final mark in drawn(view))
    if (mark.name == 'cm-wispWait') mark,
];

/// Where every position of the note is drawn: the layout, to hold one editor's against another's.
List<Rect?> layoutOf(EditorView view) => <Rect?>[for (var pos = 0; pos <= view.state.doc.length; pos++) view.coordsAtPos(pos, 1)];

/// The page as drawn, as pixels.
Future<Uint8List> pixels(WidgetTester tester) async {
  final bytes = await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(GhostApp)));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

/// Writes `test/editor_ai/shots/<name>.png` when the pictures are being made (`flutter test --update-goldens`), and
/// holds it to nothing: a picture of several words mid-arc is not the same twice, each word's arc being a little
/// longer or shorter at random (`wisp_motion.dart`), so it is one to look at, not one to compare.
Future<void> look(WidgetTester tester, String name) async {
  if (!autoUpdateGoldenFiles) return;
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(GhostApp)));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('test/editor_ai/shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Ends a test that drew the app with real shadows ([pumpApp] turns them on, and the binding checks as a test ends).
Future<void> done(WidgetTester tester) async {
  // The editors first: one still drawing would ask for a frame after the page has gone.
  for (final view in _views) {
    view.destroy();
  }
  _views.clear();
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
