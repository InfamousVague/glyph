import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kMiddleMouseButton, kPrimaryButton;
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/gestures.dart' show holdMs;
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/canvas/viewport.dart';
import 'package:ghost_md/core/images.dart';

import '../support/render.dart';
import 'samples.dart';

export 'package:ghost_md/canvas/gestures.dart' show holdMs;

/// A canvas on the screen for the view's tests, the way the web's tests show one (`src/test/render.tsx` `show`):
/// the view sample unless another is given, and what `onChange` was called with, read back as canvases.
///
/// The web's tests run where nothing is laid out (jsdom), so their canvas has no size and its view is the one a
/// canvas opens with before it has a screen: 32px in from the corner at life size. Their presses are written
/// against that. Here the canvas is laid out and fitted, so [Shown.show] then moves the view there by hand unless
/// told to leave the fit ([fit]): every number of the web's tests then means the same point.
class Shown {
  Shown(this.tester);
  final WidgetTester tester;
  final GlobalKey<CanvasViewState> key = GlobalKey<CanvasViewState>();

  /// Every canvas handed on, in order.
  final List<Canvas> changes = [];
  final List<String> opened = [];
  final List<String> links = [];
  final List<({String node, bool start})> threads = [];
  int felt = 0;

  /// The way the comment sheet was last handed to change the canvas.
  void Function(Canvas next)? threadChange;
  late String body;

  CanvasViewState get state => key.currentState!;
  Canvas get last => changes.last;
  CameraView get view => state.camera.view;

  Future<void> show({
    String? canvas,
    bool editable = true,
    bool snap = false,
    bool fit = false,
    Size size = const Size(800, 600),
    CanvasWiki? wiki,
    bool known = true,
    Future<String?> Function()? pick,
    bool threaded = true,
    PictureStore? pictures,
  }) async {
    body = canvasNoteBody('Test', parseCanvas(canvas ?? viewSample)!);
    await pumpApp(
      tester,
      size: size,
      prefs: AppPreferences(theme: 'light', canvasSnap: snap),
      home: StatefulBuilder(
        builder: (context, setState) => CanvasView(
          key: key,
          body: body,
          wiki: wiki ?? CanvasWiki(known: (_) => known, open: (title, [at]) => opened.add(at == null ? title : '$title#$at')),
          openLink: (url) async => links.add(url),
          pickPicture: pick,
          pictures: pictures,
          felt: () => felt += 1,
          threads: !threaded
              ? null
              : (context, {required canvas, required node, required start, required change}) {
                  threads.add((node: node, start: start));
                  threadChange = change;
                },
          onChange: !editable
              ? null
              : (next) {
                  changes.add(canvasOf(next)!);
                  setState(() => body = next);
                },
        ),
      ),
    );
    await tester.pump();
    if (!fit) {
      state.camera.moveTo(home);
      await tester.pump();
    }
    addTearDown(() => debugDisableShadows = true);
  }

  /// Ends a test the way `shot` does: the binding's switch for shadows put back, and the tree let go.
  Future<void> done() async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  /// A point of the canvas, on the screen.
  Offset at(double x, double y) => Offset(view.x + x * view.scale, view.y + y * view.scale);

  CanvasNode node(String id) => state.live.nodeOf(id)!;

  /// The middle of a card, on the screen.
  Offset card(String id) {
    final n = node(id);
    return at(n.x + n.width / 2, n.y + n.height / 2);
  }

  /// A tap as a finger makes one, or a mouse: a press and a release in one place.
  Future<void> tap(Offset where, {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
    final gesture = await tester.startGesture(where, kind: kind);
    await gesture.up();
    await tester.pump();
  }

  Future<void> tapCard(String id, {PointerDeviceKind kind = PointerDeviceKind.touch}) => tap(card(id), kind: kind);

  /// A press, its moves, and its release, with no waiting between them.
  Future<void> drag(List<Offset> through, {PointerDeviceKind kind = PointerDeviceKind.touch, bool middle = false, Duration? hold}) async {
    final gesture = await tester.startGesture(through.first, kind: kind, buttons: middle ? kMiddleMouseButton : kPrimaryButton);
    if (hold != null) await tester.pump(hold);
    for (final point in through.skip(1)) {
      await gesture.moveTo(point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  Finder button(String label) => find.bySemanticsLabel(label);

  Future<void> press(String label) async {
    await tester.tap(button(label));
    await tester.pump();
  }

  /// The labels of the picked card's bar, in order.
  List<String> bar(String id) => [
    for (final element in find.descendant(of: find.byKey(ValueKey('bar $id')), matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label != null && (w.properties.button ?? false))).evaluate())
      (element.widget as Semantics).properties.label!,
  ];

  bool has(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

  /// The handles a picked card wears.
  int handles(String id) => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('handle $id ')).evaluate().length;

  /// The middle of a handle, on the screen.
  Offset handle(String id, String name) => tester.getCenter(find.byKey(ValueKey('handle $id $name')));

  /// A point on a line, on the screen: where its label sits.
  Offset line(String id) {
    final found = state.lines.firstWhere((line) => line.edge.id == id);
    return at(found.path.mid.x, found.path.mid.y);
  }

  List<Object> placed(Canvas canvas) => [
    for (final n in canvas.nodes) [n.id, n.x, n.y],
  ];

  /// Waits out a hold on a card.
  Duration get held => Duration(milliseconds: holdMs + 30);
}
