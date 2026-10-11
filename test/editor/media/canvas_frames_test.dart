// A canvas in a frame inside a note (lib/editor/media/canvas_frames.dart): `src/app/editor/canvasFrames.test.ts`,
// case for case and in its order, and then what the page left to its stylesheet and its browser: the caret on the
// line stepping the frame aside, the frame's box, and its picture (shots/).
//
// What is asked differently: "drawn again when the app is painted the other way" has no counterpart, since the
// canvas reads its colours from the tokens over it; what a refresh must still do is leave a frame that has not
// changed as it is and draw one whose canvas has, which is the case here.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/canvas_frames.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/editor_text.dart';
import '../../support/render.dart';

Canvas _one(String words) => parseCanvas('{"nodes":[{"id":"a","type":"text","text":"$words","x":0,"y":0,"width":120,"height":60}],"edges":[]}')!;

/// A note on the screen with its frames, the notes it can name, and what it opened.
class Framed {
  final Map<String, String> bodies = <String, String>{'Map': canvasNoteBody('Map', _one('A card')), 'Words': '# Words\n\nJust words.'};
  final List<String> opened = <String>[];
  late final EditorView view;

  Future<void> show(WidgetTester tester, String doc, {String theme = 'light', int? caret}) async {
    view = EditorView(
      wholeDocument: true,
      state: EditorState.create(
        doc: doc,
        extensions: noteExtensions(
          more: <Extension>[canvasFrames(FrameOptions(body: (title) => bodies[title], known: bodies.containsKey, open: (title, [anchor]) => opened.add(anchor == null ? title : '$title#$anchor')))],
        ),
      ),
    );
    addTearDown(view.destroy);
    view.focusRequest = () => view.setFocused(true);
    await pumpApp(
      tester,
      prefs: AppPreferences(theme: theme),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
          child: BackScope(
            child: ColoredBox(
              color: context.tokens.color('app-paper'),
              child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view)))),
            ),
          ),
        ),
      ),
    );
    debugDisableShadows = true;
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
    if (caret != null) {
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
      await tester.pump();
    }
    await tester.pump();
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('embeds in a note', () {
    test('finds a line that is only ![[Title]], the title being what is before any #', () {
      expect(framesIn('# Trip\n\n![[Cabin, laid out]]\n\nwords'), [(line: 3, title: 'Cabin, laid out')]);
      expect(framesIn('  ![[Map#^card]]  '), [(line: 1, title: 'Map')]);
      expect(framesIn('![[One]]\n![[Two]]').map((frame) => frame.title), ['One', 'Two']);
    });

    test('leaves a link without the !, an embed inside a sentence, and an empty one alone', () {
      expect(framesIn('[[Map]]'), isEmpty);
      expect(framesIn('see ![[Map]] here'), isEmpty);
      expect(framesIn('![[ ]]'), isEmpty);
      expect(framesIn('![[#^card]]'), isEmpty);
    });
  });

  group('the frame', () {
    testWidgets('draws a canvas named on its own line as a frame with its name and an Open, and leaves a note of words as the link', (tester) async {
      final framed = Framed();
      await framed.show(tester, '![[Map]]\n\n![[Words]]\n\n![[Nowhere]]');
      final frames = find.byType(DrawnFrame);
      expect(frames, findsOneWidget);
      expect(find.bySemanticsLabel('Canvas: Map'), findsOneWidget);
      expect(find.descendant(of: frames, matching: find.text('Map')), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(framed.opened, ['Map']);
      // The line itself is gone from the page; the two that name no canvas stay as typed.
      expect(editorText('![[Map]]'), findsNothing);
      expect(editorText('![[Words]]'), findsOneWidget);
      expect(editorText('![[Nowhere]]'), findsOneWidget);
      // The canvas note's own view, with no way to change it.
      final canvas = tester.widget<CanvasView>(find.descendant(of: frames, matching: find.byType(CanvasView)));
      expect(canvas.onChange, isNull);
      expect(canvas.body, framed.bodies['Map']);
    });

    testWidgets('is kept when nothing changed, and drawn again when its canvas has', (tester) async {
      final framed = Framed();
      await framed.show(tester, '![[Map]]');
      final before = tester.state<CanvasViewState>(find.byType(CanvasView));
      framed.view.dispatch(TransactionSpec(effects: refreshCanvasFrames.of(null)));
      await tester.pump();
      // Nothing changed: the same frame stays.
      expect(tester.state<CanvasViewState>(find.byType(CanvasView)), same(before));
      expect(before.live.nodes.single.text, 'A card');
      // The canvas was drawn on, somewhere else.
      framed.bodies['Map'] = canvasNoteBody('Map', _one('Another card'));
      framed.view.dispatch(TransactionSpec(effects: refreshCanvasFrames.of(null)));
      await tester.pump();
      await tester.pump();
      expect(tester.state<CanvasViewState>(find.byType(CanvasView)).live.nodes.single.text, 'Another card');
    });

    testWidgets('steps aside for its line while the caret is on it, and a press on its name puts the caret there', (tester) async {
      final framed = Framed();
      await framed.show(tester, 'Before\n\n![[Map]]\n\nAfter');
      expect(find.byType(DrawnFrame), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(DrawnFrame), matching: find.text('Map')));
      await tester.pump();
      await tester.pump();
      expect(framed.view.state.selection.main.head, 'Before\n\n'.length);
      expect(find.byType(DrawnFrame), findsNothing);
      expect(editorText('![[Map]]'), findsOneWidget);
      // Leaving the line draws the frame again.
      framed.view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      await tester.pump();
      expect(find.byType(DrawnFrame), findsOneWidget);
    });

    testWidgets('is the note\'s width inside its gutters, its bar thirty pixels and its box 42 parts of the screen', (tester) async {
      final framed = Framed();
      await framed.show(tester, '![[Map]]');
      final t = tester.element(find.byType(DrawnFrame)).tokens;
      final box = tester.getRect(find.byType(CanvasView));
      expect(box.left, closeTo(t.len('app-gutter'), 0.02));
      expect(box.width, closeTo(390 - 2 * t.len('app-gutter'), 0.04));
      // clamp(220px, 42vh, 360px) of a screen 844 tall.
      expect(box.height, closeTo(844 * 0.42, 0.01));
      expect(box.top - tester.getRect(find.byType(DrawnFrame)).top, closeTo((0.4 * t.len('app-body') * 64).floorToDouble() / 64 + barHeight, 0.02));
    });

    for (final theme in const ['light', 'dark']) {
      testWidgets('how it looks, $theme', (tester) async {
        final framed = Framed();
        framed.bodies['Map'] = canvasNoteBody(
          'Map',
          parseCanvas('{"nodes":[{"id":"a","type":"text","text":"# Cabin","x":0,"y":0,"width":220,"height":90},{"id":"b","type":"text","text":"Bring the map","x":300,"y":140,"width":220,"height":90,"color":"4"}],"edges":[{"id":"e","fromNode":"a","toNode":"b"}]}')!,
        );
        await framed.show(tester, '# Trip\n\nThe plan, laid out:\n\n![[Map]]\n\nAnd what comes after it.', theme: theme);
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/canvas-frame-$theme.png'));
      });
    }
  });
}
