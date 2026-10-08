// editor/swipeItems.test.ts, case for case.
//
// What is asked differently: the note is drawn 300 px wide (the page's test told jsdom every line was), so the
// swipe counts once it is 90 px along. A line's `style.transform` is how far the swipe's field says it is moved
// (`swipeOf(state).dx`, and the drawn line's box with it), the tile is the field's word and reach, and the pointer
// events are handed to the plugin's handlers as the editor's input layer hands them (support.dart `sendPointer`).
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/swipe_items.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';
import 'support.dart';

const String doc = '- [ ] Buy milk\nplain words\n- [ ] Call Sam [notion](https://www.notion.so/Call-Sam-3db522a4563081298304c129ce6004e4)';

/// The note, the action a swipe runs on it, and the finished run it is waiting on.
class Opened {
  Opened(this.tester, this.on, this.ran, this.finish);

  final WidgetTester tester;
  final EditorView on;
  final List<String> ran;
  final void Function() finish;

  /// Where line `n` is on the screen, down its middle.
  double y(int n) {
    final line = drawnLines(tester)[n - 1];
    return borderBox(line).center.dy;
  }

  void pointer(String type, int n, double x, [double dy = 0, int id = 1]) {
    final at = Offset(x, y(n) + dy);
    sendPointer(on, switch (type) {
      'down' => PointerDownEvent(pointer: id, position: at),
      'move' => PointerMoveEvent(pointer: id, position: at),
      'up' => PointerUpEvent(pointer: id, position: at),
      _ => PointerCancelEvent(pointer: id, position: at),
    });
  }

  /// `item.style.transform`: how far the line under the finger is moved, nothing when it is not.
  double get moved => swipeOf(on.state)?.dx ?? 0;

  /// The tile, or null: its word, and whether it counts yet.
  ({String word, bool armed})? get tile {
    final swipe = swipeOf(on.state);
    return swipe == null || swipe.reach == null ? null : (word: swipe.word, armed: swipe.armed);
  }
}

Future<Opened> open(WidgetTester tester, {bool offered = true}) async {
  var done = Completer<void>();
  final ran = <String>[];
  final action = SwipeAction(
    label: 'Send to Notion',
    busyLabel: 'Sending…',
    run: (text) {
      ran.add(text);
      done = Completer<void>();
      return done.future;
    },
  );
  final on = await pumpNote(tester, doc, more: <Extension>[swipeItemAction(action: () => offered ? action : null), swipeItemTheme], width: 300);
  return Opened(tester, on, ran, () => done.complete());
}

void main() {
  setUpAll(loadAppFonts);

  group('swiping a list item left', () {
    testWidgets('follows the finger, fills a tile with the action’s word, and runs it on the item’s words past the point where it counts', (tester) async {
      final note = await open(tester);
      note.pointer('down', 1, 250);
      // Under a finger's intent, 12 px, nothing moves yet; at it, the line follows.
      note.pointer('move', 1, 242);
      expect(note.moved, 0);
      note.pointer('move', 1, 239);
      expect(note.moved, 0);
      note.pointer('move', 1, 238);
      expect(note.moved, -12);
      note.pointer('move', 1, 140, 4);
      expect(note.moved, -110);
      expect(note.tile?.word, 'Send to Notion');
      expect(note.tile?.armed, isTrue);
      // And the line is drawn where the field says, as wide as it was.
      await tester.pump();
      final box = borderBox(drawnLines(tester)[0]);
      expect((box.left, box.right), (-110.0, 190.0));
      expect(tester.renderObject<RenderSwipeTile>(find.byType(SwipeTile)).globalTileRect, Rect.fromLTRB(190, box.top, 300, box.bottom));

      note.pointer('up', 1, 140, 4);
      expect(note.ran, <String>['Buy milk']);
      // The line is back, and the tile says what is happening until it is done.
      expect(note.moved, 0);
      expect(note.tile?.word, 'Sending…');
      await tester.pump();
      expect(borderBox(drawnLines(tester)[0]).left, 0);
      note.finish();
      await tester.pump();
      expect(note.tile, isNull);
      await tester.pump();
      expect(find.byType(SwipeTile), findsNothing);
    });

    testWidgets('springs back short of the point, running nothing', (tester) async {
      final note = await open(tester);
      note.pointer('down', 1, 250);
      note.pointer('move', 1, 200);
      expect(note.tile?.armed, isFalse);
      note.pointer('up', 1, 200);
      expect(note.ran, isEmpty);
      expect(note.moved, 0);
      expect(note.tile, isNull);
    });

    testWidgets('leaves a drag that is mostly down the page, or to the right, to the editor', (tester) async {
      final note = await open(tester);
      note.pointer('down', 1, 250);
      note.pointer('move', 1, 230, 50);
      note.pointer('move', 1, 100, 50);
      expect(note.moved, 0);
      note.pointer('up', 1, 100, 50);
      note.pointer('down', 1, 100, 0, 2);
      note.pointer('move', 1, 200, 0, 2);
      note.pointer('up', 1, 200, 0, 2);
      expect(note.moved, 0);
      expect(note.ran, isEmpty);
    });

    testWidgets('springs back when the pointer is called off', (tester) async {
      final note = await open(tester);
      note.pointer('down', 1, 250);
      note.pointer('move', 1, 100);
      expect(note.moved, -150);
      note.pointer('cancel', 1, 100);
      expect(note.moved, 0);
      expect(note.tile, isNull);
      expect(note.ran, isEmpty);
    });

    testWidgets('is only on an item not linked yet, in a note a plugin offers an action on', (tester) async {
      final plain = await open(tester);
      for (final n in <int>[2, 3]) {
        plain.pointer('down', n, 250);
        plain.pointer('move', n, 100);
        expect(plain.moved, 0);
        plain.pointer('up', n, 100);
      }
      final unoffered = await open(tester, offered: false);
      unoffered.pointer('down', 1, 250);
      unoffered.pointer('move', 1, 100);
      expect(unoffered.moved, 0);
      expect(unoffered.tile, isNull);
    });
  });
}
