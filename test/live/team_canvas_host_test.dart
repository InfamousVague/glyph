// A team's canvas in its view (lib/live/team_canvas.dart): the host over a document this file makes, with the
// real view under it. What is held is what a device found the first time a second member joined a canvas: a
// change that arrives from the document is handed to the view as a body anew, the view opens the camera on it
// while the host is still being built, and the host, which follows the camera for the pointers, must not ask to
// be drawn again inside its own build. And what the room adds: a team's view is not fitted again for a member's
// change, the card this device has open is said in the room, and a card another member has open is ringed.
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/live/open.dart';
import 'package:ghost_md/live/team.dart';
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

/// A note's room that holds what its members say of themselves, and what this device was told to say.
class _Room implements TeamRoom {
  final Map<int, Map<String, Object?>> said = {};
  final List<void Function()> listeners = [];
  final List<(String, Object?)> fields = [];

  @override
  int get clientId => 1;
  @override
  Map<int, Map<String, Object?>> get states => said;
  @override
  void Function() onChange(void Function() listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  void setField(String field, Object? value) => fields.add((field, value));
  @override
  Future<void> caughtUp() async {}

  void says(int client, Map<String, Object?> state) {
    said[client] = state;
    for (final each in listeners.toList()) {
      each();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Canvas _canvas(List<(String, double, double, String)> cards) => parseCanvas('{"nodes":[${cards.map((c) => '{"id":"${c.$1}","type":"text","x":${c.$2},"y":${c.$3},"width":260,"height":120,"text":"${c.$4}"}').join(',')}],"edges":[]}')!;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('another member’s change is drawn where the view stands, with the host built once and no error', (tester) async {
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
          draw: (context, body, onChange, camera, people) => CanvasView(body: body, onChange: onChange, camera: camera, team: true, onEditing: people.onEditing, editedBy: people.editedBy),
        );
      }),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(doc.editing, isTrue);
    expect(doc.listeners, hasLength(1));
    final before = tester.state<CanvasViewState>(find.byType(CanvasView)).camera.view;

    // A card far from the first, from the other member: the view's canvas is another, and the view stays where it
    // was, as a team's does on the page (a view is not refitted for a card moved).
    doc.arrives(_canvas([('a', 0, 24, ''), ('b', 2400, 1800, 'theirs')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(canvasOf(wrote.last)!.nodes.map((node) => node.id), ['a', 'b']);
    expect(tester.state<CanvasViewState>(find.byType(CanvasView)).live.nodes, hasLength(2));
    expect(tester.state<CanvasViewState>(find.byType(CanvasView)).camera.view, before);

    // The binding's own switch for shadows, which `pumpApp` turned on.
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(doc.editing, isFalse);
    expect(doc.listeners, isEmpty);
  });

  testWidgets('the card this device has open is said in the room, and a card another member has open is ringed with their handle', (tester) async {
    final doc = _Doc()..held = _canvas([('a', 0, 0, 'Mine'), ('b', 400, 0, 'Theirs')]);
    final room = _Room();
    final body = canvasNoteBody('Untitled canvas', doc.held!);
    await pumpApp(
      tester,
      size: const Size(800, 600),
      home: TeamCanvasHost(
        team: TeamBinding(doc: doc, room: room, orgId: 'o1'),
        body: body,
        onChange: (_) {},
        draw: (context, body, onChange, camera, people) => CanvasView(body: body, onChange: onChange, camera: camera, team: true, onEditing: people.onEditing, editedBy: people.editedBy),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(EditedBy), findsNothing);

    // Sam opens the second card to write in it.
    room.says(7, {
      'user': {'name': 'sam', 'hue': 'sea'},
      'card': 'b',
    });
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('edited b')), findsOneWidget);
    expect(find.descendant(of: find.byType(EditedBy), matching: find.text('sam')), findsOneWidget);
    // What this device says of itself is not drawn on its own canvas.
    room.says(1, {
      'user': {'name': 'matt', 'hue': 'rose'},
      'card': 'a',
    });
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('edited a')), findsNothing);

    // This device opens the first card: said in the room, and unsaid when it is closed.
    final state = tester.state<CanvasViewState>(find.byType(CanvasView));
    final node = state.live.nodeOf('a')!;
    final view = state.camera.view;
    final middle = Offset(view.x + (node.x + node.width / 2) * view.scale, view.y + (node.y + node.height / 2) * view.scale);
    await tester.tapAt(middle);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(middle);
    await tester.pump();
    await tester.pump();
    expect(room.fields.where((field) => field.$1 == 'card'), [('card', 'a')]);
    await tester.tapAt(const Offset(780, 20));
    await tester.pump();
    await tester.pump();
    expect(room.fields.where((field) => field.$1 == 'card'), [('card', 'a'), ('card', null)]);

    // Sam closes theirs: the ring goes.
    room.says(7, {
      'user': {'name': 'sam', 'hue': 'sea'},
      'card': null,
    });
    await tester.pump();
    await tester.pump();
    expect(find.byType(EditedBy), findsNothing);

    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
