// A team's canvas in its view (lib/live/team_canvas.dart): the host over a document this file makes, with the
// real view under it. What is held is what a device found the first time a second member joined a canvas: a
// change that arrives from the document is handed to the view as a body anew, the view opens the camera on it
// while the host is still being built, and the host, which follows the camera for the pointers, must not ask to
// be drawn again inside its own build.
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/live/open.dart';
import 'package:ghost_md/live/team_canvas.dart';
import 'package:ghost_md/team/doc.dart';

import '../support/render.dart';

/// A team's document that holds a canvas and tells its listeners when the test says another member changed it.
class _Doc implements TeamDoc {
  Canvas? held;
  final List<void Function(Canvas canvas)> listeners = [];
  final List<Canvas> applied = [];

  @override
  bool editing = false;
  @override
  Canvas? get canvas => held;
  @override
  Future<Canvas?> seedCanvas() async => held;
  @override
  Future<void> applyCanvas(Canvas next) async => applied.add(next);
  @override
  void Function() onCanvas(void Function(Canvas canvas) listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  void arrives(Canvas canvas) {
    held = canvas;
    for (final each in listeners.toList()) {
      each(canvas);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Canvas _canvas(List<(String, double, double, String)> cards) => parseCanvas('{"nodes":[${cards.map((c) => '{"id":"${c.$1}","type":"text","x":${c.$2},"y":${c.$3},"width":260,"height":120,"text":"${c.$4}"}').join(',')}],"edges":[]}')!;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('another member’s change is drawn, the view fitted to it, with the host built once and no error', (tester) async {
    final doc = _Doc()..held = _canvas([('a', 0, 24, '')]);
    var body = canvasNoteBody('Untitled canvas', doc.held!);
    final wrote = <String>[];
    late StateSetter redraw;
    await pumpApp(
      tester,
      home: StatefulBuilder(builder: (context, setState) {
        redraw = setState;
        return TeamCanvasHost(
          team: TeamBinding(doc: doc, room: null, orgId: 'o1'),
          body: body,
          onChange: (next) {
            wrote.add(next);
            redraw(() => body = next);
          },
          draw: (context, body, onChange, camera) => CanvasView(body: body, onChange: onChange, camera: camera),
        );
      }),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(doc.editing, isTrue);
    expect(doc.listeners, hasLength(1));

    // A card far from the first, from the other member: the view's canvas is another, and its camera opens on it.
    doc.arrives(_canvas([('a', 0, 24, ''), ('b', 2400, 1800, 'theirs')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(canvasOf(wrote.last)!.nodes.map((node) => node.id), ['a', 'b']);
    expect(tester.state<CanvasViewState>(find.byType(CanvasView)).live.nodes, hasLength(2));

    // The binding's own switch for shadows, which `pumpApp` turned on.
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(doc.editing, isFalse);
    expect(doc.listeners, isEmpty);
  });
}
