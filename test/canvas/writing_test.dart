import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/comments.dart';
import 'package:ghost_md/canvas/edits.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/canvas/viewport.dart';
import 'package:ghost_md/comments/format.dart' show Stamp;
import 'package:ghost_md/editor/editor_widget.dart';

import '../support/render.dart';
import 'view_support.dart';

/// Writing in a card with the note's own editor, under the canvas's transform; and a canvas's comments in the
/// view (`src/app/canvas/CanvasView.comments.test.tsx`, as far as the view goes by itself: the rounds, what they
/// say, what a press on one and on Comment asks for, and a change handed back; with the sheet that answers, the
/// same cases are canvas_comments_test.dart's).
/// What a reader is told of something, by the words it is given.
Finder said(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

void main() {
  setUpAll(loadAppFonts);

  const threaded = '''{
  "nodes": [
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin" },
    { "id": "site", "type": "link", "x": 0, "y": 160, "width": 260, "height": 100, "url": "https://attack.fm/glyph" }
  ],
  "edges": [],
  "comments": [
    { "id": "c1", "node": "book", "by": "sam", "at": "2026-10-05T14:00:00Z", "text": "Which Friday?", "replies": [] },
    { "id": "c2", "node": "book", "by": "lee", "at": "2026-10-05T14:01:00Z", "text": "And where?", "replies": [], "resolved": { "by": "matt", "at": "2026-10-05T14:02:00Z" } }
  ]
}''';

  group('a canvas’s comments', () {
    testWidgets('marks a card with its open threads, and opens its threads from the round', (tester) async {
      final shown = Shown(tester);
      await shown.show(canvas: threaded);
      final round = find.byKey(const ValueKey('round book'));
      expect(round, findsOneWidget);
      expect(find.descendant(of: round, matching: find.text('1')), findsOneWidget);
      expect(said('2 comments on this card, 1 open'), findsOneWidget);
      expect(find.byKey(const ValueKey('round site')), findsNothing);
      // At the card's corner, one size on the screen at any zoom.
      final size = tester.getSize(round);
      shown.state.camera.zoomBy(0.5);
      await tester.pump();
      expect(tester.getSize(round), size);
      expect((tester.getCenter(round) - shown.at(0, 0)).distance, lessThan(8));
      await tester.tap(round);
      await tester.pump();
      expect(shown.threads, [(node: 'book', start: false)]);
      // A reply written in the sheet is the canvas handed back with it.
      shown.threadChange!(withReply(shown.state.live, 'c1', const Stamp(by: 'matt', at: '2026-10-05T15:00:00Z'), 'The 10th.')!);
      await tester.pump();
      expect(shown.last.comments!.firstWhere((thread) => thread.id == 'c1').replies.single.text, 'The 10th.');
      await shown.done();
    });

    testWidgets('shows a tick once every thread is resolved, and starts a thread from the picked card’s bar', (tester) async {
      final shown = Shown(tester);
      await shown.show(canvas: threaded);
      await tester.tap(find.byKey(const ValueKey('round book')));
      shown.threadChange!(resolvedThread(shown.state.live, 'c1', const Stamp(by: 'matt', at: '2026-10-05T15:00:00Z'))!);
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('round book')), matching: find.text('✓')), findsOneWidget);
      expect(said('2 comments on this card, resolved'), findsOneWidget);
      await shown.tapCard('site');
      await shown.press('Comment on this card');
      expect(shown.threads.last, (node: 'site', start: true));
      await shown.done();
    });

    testWidgets('draws no rounds, and no Comment, on a canvas that cannot change', (tester) async {
      final shown = Shown(tester);
      await shown.show(canvas: threaded, editable: false);
      expect(find.byKey(const ValueKey('round book')), findsNothing);
      await shown.done();
    });

    testWidgets('keeps the threads when a card is moved, written in or joined, and lets a card’s go with the card', (tester) async {
      // Not the web's: there, `withNode` and its kin answer a canvas without its `comments`, and a card moved on a
      // canvas with threads writes the note without them.
      final shown = Shown(tester);
      await shown.show(canvas: threaded);
      final from = shown.card('site');
      await shown.drag([from, from + const Offset(40, 30)], hold: shown.held);
      expect(shown.last.nodeOf('site'), isNotNull);
      expect(shown.last.comments!.map((thread) => thread.id), ['c1', 'c2']);
      expect(canvasOf(shown.body)!.comments, hasLength(2));
      // The model's own edit, as the web has it, drops them: that is what the view puts back.
      expect(movedWithHeld(shown.state.live, shown.node('site'), 0, 0).comments, isNull);
      await shown.tapCard('book');
      await shown.press('Take this card off the canvas');
      expect(shown.last.comments, isNull);
      await shown.done();
    });
  });

  group('writing in a card', () {
    testWidgets('opens the note’s own editor in the card, and the words typed go straight into the canvas', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('t');
      await shown.tapCard('t');
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('card t')), matching: find.byType(Editor)), findsOneWidget);
      // The keyboard is up with it: the editor has the keyboard's client.
      expect(tester.testTextInput.hasAnyClients, isTrue);
      await shown.done();
    });

    testWidgets('tells the keyboard where the editor is under the canvas’s scale', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      // Half life size, the card's corner at 100,100 on the screen.
      shown.state.camera.moveTo(const CameraView(x: 100, y: 100, scale: 0.5));
      await tester.pump();
      await shown.tapCard('t');
      await shown.tapCard('t');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final sent = tester.testTextInput.log.where((call) => call.method == 'TextInput.setEditableSizeAndTransform').toList();
      expect(sent, isNotEmpty);
      final args = sent.last.arguments as Map;
      final transform = (args['transform'] as List).cast<double>();
      // The editor's box is handed over in its own pixels, with the canvas's scale in its transform.
      expect(transform[0], closeTo(0.5, 1e-9));
      expect(transform[5], closeTo(0.5, 1e-9));
      final editor = tester.getRect(find.descendant(of: find.byKey(const ValueKey('card t')), matching: find.byType(CustomScrollView)));
      expect(transform[12], closeTo(editor.left, 0.01));
      expect(transform[13], closeTo(editor.top, 0.01));
      expect((args['width'] as num) * 0.5, closeTo(editor.width, 0.01));
      // The caret's rectangle too is in the editor's own pixels (lib/editor/input/ime.dart `sendGeometry`), which
      // that transform carries to the screen: at half size a caret is sent as tall as it is at life size, where it
      // used to be sent as it was drawn on the screen and so read as half of that again.
      final carets = tester.testTextInput.log.where((call) => call.method == 'TextInput.setCaretRect').toList();
      expect(carets, isNotEmpty);
      final caret = carets.last.arguments as Map;
      final view = tester.widget<Editor>(find.descendant(of: find.byKey(const ValueKey('card t')), matching: find.byType(Editor))).view;
      final at = view.coordsAtPos(view.state.selection.main.head, 1)!;
      expect((caret['height'] as num) * 0.5, closeTo(at.bottom - at.top, 0.01));
      expect(editor.left + (caret['x'] as num) * 0.5, closeTo(at.left, 0.01));
      expect(editor.top + (caret['y'] as num) * 0.5, closeTo(at.top, 0.01));
      await shown.done();
    });
  });
}
