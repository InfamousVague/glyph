// What a team's canvas asks of the view (lib/canvas/canvas_view.dart; `src/app/canvas/CanvasView.team.test.tsx` and
// CanvasView.tsx's `goTo`): a spot to centre on, from an organization's dashboard's Jump to cursor; the card being
// written in told as it opens and closes; another member's ring and handle on the card they have open; and a view
// that is not fitted again for a card another member moved. The room these come from is the host's
// (test/live/team_canvas_host_test.dart).
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/geometry.dart' show Point;
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

Canvas _canvas(List<(String, double, double, String)> cards) => parseCanvas('{"nodes":[${cards.map((c) => '{"id":"${c.$1}","type":"text","x":${c.$2},"y":${c.$3},"width":260,"height":120,"text":"${c.$4}"}').join(',')}],"edges":[]}')!;

void main() {
  setUpAll(loadAppFonts);

  Future<void> done(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('centres the screen on a spot it is given, at the scale it is at, and again on another', (tester) async {
    final body = canvasNoteBody('Map', _canvas([('a', 0, 0, 'Here'), ('b', 2400, 1800, 'There')]));
    Point? spot = (x: 2530, y: 1860);
    late StateSetter redraw;
    await pumpApp(
      tester,
      size: const Size(800, 600),
      prefs: const AppPreferences(theme: 'light'),
      home: StatefulBuilder(builder: (context, setState) {
        redraw = setState;
        return CanvasView(body: body, onChange: (_) {}, goTo: spot);
      }),
    );
    await tester.pump();
    final state = tester.state<CanvasViewState>(find.byType(CanvasView));
    final view = state.camera.view;
    // The member's pointer is under the middle of the screen, and the view is as close as it was.
    final under = state.camera.under(state.camera.width / 2, state.camera.height / 2);
    expect(under.x, closeTo(2530, 0.01));
    expect(under.y, closeTo(1860, 0.01));
    expect(view.scale, greaterThan(0));
    // Moved as a hand moves it: no longer fitted when the screen changes size.
    expect(state.camera.touched, isTrue);

    redraw(() => spot = (x: 130, y: 60));
    await tester.pump();
    await tester.pump();
    final again = state.camera.under(state.camera.width / 2, state.camera.height / 2);
    expect(again.x, closeTo(130, 0.01));
    expect(again.y, closeTo(60, 0.01));
    expect(state.camera.view.scale, view.scale);
    await done(tester);
  });

  testWidgets('tells the card being written in as it opens and closes', (tester) async {
    final body = canvasNoteBody('Map', _canvas([('a', 0, 0, 'Here'), ('b', 400, 0, 'There')]));
    final told = <String?>[];
    await pumpApp(tester, size: const Size(800, 600), prefs: const AppPreferences(theme: 'light'), home: CanvasView(body: body, onChange: (_) {}, onEditing: told.add));
    await tester.pump();
    final state = tester.state<CanvasViewState>(find.byType(CanvasView));
    Offset middle(String id) {
      final node = state.live.nodeOf(id)!;
      final view = state.camera.view;
      return Offset(view.x + (node.x + node.width / 2) * view.scale, view.y + (node.y + node.height / 2) * view.scale);
    }

    expect(told, isEmpty);
    // A double tap opens a card of words to be written in.
    await tester.tapAt(middle('a'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(middle('a'));
    await tester.pump();
    await tester.pump();
    expect(told, ['a']);
    // A tap on the canvas beside it closes it.
    await tester.tapAt(const Offset(780, 20));
    await tester.pump();
    await tester.pump();
    expect(told, ['a', null]);
    await done(tester);
  });

  testWidgets('rings a card another member has open in their colour, their handle on its corner', (tester) async {
    final body = canvasNoteBody('Map', _canvas([('a', 0, 0, 'Booked the cabin'), ('b', 400, 0, 'Bring the map')]));
    await pumpApp(
      tester,
      size: const Size(800, 600),
      prefs: const AppPreferences(theme: 'light'),
      home: Builder(
        builder: (context) => CanvasView(
          body: body,
          onChange: (_) {},
          editedBy: (id) => id == 'b' ? (name: 'sam', colour: context.tokens.child(attrs: {'hue': 'sea'}).color('app-space')) : null,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('edited b')), findsOneWidget);
    expect(find.byKey(const ValueKey('edited a')), findsNothing);
    expect(find.descendant(of: find.byType(EditedBy), matching: find.text('sam')), findsOneWidget);
    // As big as the card, and scaled with the world as the card is.
    final state = tester.state<CanvasViewState>(find.byType(CanvasView));
    final view = state.camera.view;
    final ring = tester.getRect(find.byType(EditedBy));
    expect(ring.left, closeTo(view.x + 400 * view.scale, 0.5));
    expect(ring.width, closeTo(260 * view.scale, 0.5));
    expect(ring.height, closeTo(120 * view.scale, 0.5));
    await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/edited-by.png'));
    await done(tester);
  });

  testWidgets('is fitted again when the note reloads its canvas, and not when it is a team\'s and a member moved a card', (tester) async {
    final first = canvasNoteBody('Map', _canvas([('a', 0, 0, 'Here')]));
    final second = canvasNoteBody('Map', _canvas([('a', 0, 0, 'Here'), ('b', 2400, 1800, 'There')]));
    for (final team in const [false, true]) {
      var body = first;
      late StateSetter redraw;
      await pumpApp(
        tester,
        size: const Size(800, 600),
        prefs: const AppPreferences(theme: 'light'),
        home: StatefulBuilder(builder: (context, setState) {
          redraw = setState;
          return CanvasView(body: body, onChange: (_) {}, team: team);
        }),
      );
      await tester.pump();
      final state = tester.state<CanvasViewState>(find.byType(CanvasView));
      final before = state.camera.view;
      redraw(() => body = second);
      await tester.pump();
      await tester.pump();
      expect(state.live.nodes, hasLength(2), reason: 'the canvas is the note\'s either way');
      expect(state.camera.view == before, team, reason: team ? 'a team\'s view stays where it was' : 'the note reloaded: fitted to all of it');
      await done(tester);
    }
  });
}
