// A tap on a box in the words, through both boxes that answer one (lib/editor/items/box_taps.dart, with
// task_toggle.dart and choices.dart): `src/app/editor/boxTaps.test.ts`, case for case.
//
// What is asked differently: the page's `mousedown` is the plugins' `mouseDown` called with a point of a view laid
// out on a grid, as the page's test laid jsdom out; a modifier held is a key of the hardware keyboard held down,
// which is where `plainPress` reads them; "the other button" is a mouse's secondary button; and the round boxes
// drawn are the `cm-choiceBox` marks. Nothing is left out.
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/box_taps.dart';
import 'package:ghost_md/editor/items/choices.dart';
import 'package:ghost_md/editor/items/task_toggle.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

/// The note laid out on a grid, since a view that is not drawn lays nothing out: every character 10 px wide and
/// every line 20 px tall, so the box of `- [ ] milk` on the first line spans 20 to 50 px across.
class _Grid extends EditorView {
  _Grid(EditorState state) : super(state: state, wholeDocument: true);

  Rect _box(int pos) {
    final line = state.doc.lineAt(pos);
    final left = (pos - line.from) * 10.0, top = (line.number - 1) * 20.0;
    return Rect.fromLTRB(left, top, left + 10, top + 20);
  }

  // Leaning back (`side` -1), a position is the character before it.
  @override
  Rect? coordsAtPos(int pos, [int side = 1]) => side < 0 && pos > 0 ? _box(pos - 1) : _box(pos);

  @override
  int? posAtCoords(Offset global, {bool precise = true}) {
    final line = state.doc.line(math.min(state.doc.lines, (global.dy / 20).floor() + 1));
    return math.min(line.to, line.from + (global.dx / 10).floor());
  }
}

EditorView open(String doc, List<Extension> extensions, [bool readOnly = false]) {
  final view = _Grid(EditorState.create(doc: doc, extensions: Extension.list(<Extension>[...extensions, EditorState.readOnlyFacet.of(readOnly)])));
  addTearDown(view.destroy);
  return view;
}

/// A press at a point; true when a box took it, and so kept it from the editor.
bool tap(EditorView on, double x, double y, {PointerDeviceKind kind = PointerDeviceKind.touch, int buttons = 0}) =>
    on.eventHandlers.any((h) => h.mouseDown?.call(PointerDownEvent(position: Offset(x, y), kind: kind, buttons: buttons), on) ?? false);

/// Each key that makes a press not a plain one.
const Map<String, LogicalKeyboardKey> modifiers = <String, LogicalKeyboardKey>{
  'shift': LogicalKeyboardKey.shiftLeft,
  'meta': LogicalKeyboardKey.metaLeft,
  'ctrl': LogicalKeyboardKey.controlLeft,
  'alt': LogicalKeyboardKey.altLeft,
};

/// Each press that is not a plain one, made at a point: a modifier held, one at a time, or another button. Each is
/// checked on its own, so two that did answer could not tick and untick the box back to where it was.
Future<void> expectNotPlain(WidgetTester tester, EditorView on, double x, double y, String doc) async {
  for (final MapEntry(key: what, value: key) in modifiers.entries) {
    await tester.sendKeyDownEvent(key);
    tap(on, x, y);
    await tester.sendKeyUpEvent(key);
    expect(on.state.doc.toString(), doc, reason: what);
  }
  tap(on, x, y, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  expect(on.state.doc.toString(), doc, reason: 'the other button');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a tap on a to-do’s box', () {
    const doc = '- [ ] milk\n- [x] eggs';

    test('ticks it, and another clears it, the caret left where it was', () {
      final on = open(doc, <Extension>[taskToggle()]);
      on.dispatch(TransactionSpec(selection: EditorSelection.single(doc.length)));
      expect(tap(on, 35, 10), isTrue);
      expect(on.state.doc.line(1).text, '- [x] milk');
      expect(on.state.selection.main.head, doc.length);
      tap(on, 35, 30);
      expect(on.state.doc.line(2).text, '- [ ] eggs');
    });

    test('counts a thumb a little off the box, and leaves a tap on the words to the editor', () {
      final on = open(doc, <Extension>[taskToggle()]);
      // Six pixels short of the box's left edge.
      tap(on, 14, 10);
      expect(on.state.doc.line(1).text, '- [x] milk');
      expect(tap(on, 80, 10), isFalse);
      expect(on.state.doc.line(1).text, '- [x] milk');
    });

    testWidgets('is only a plain press: no modifier, the main button, and a note that can be changed', (tester) async {
      final on = open(doc, <Extension>[taskToggle()]);
      await expectNotPlain(tester, on, 35, 10, doc);
      // A mouse's main button is a plain press, as a finger is.
      tap(on, 35, 10, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      expect(on.state.doc.line(1).text, '- [x] milk');
      final locked = open(doc, <Extension>[taskToggle()], true);
      tap(locked, 35, 10);
      expect(locked.state.doc.toString(), doc);
    });
  });

  group('a tap on a choice’s round box', () {
    const doc = 'Where do we stay?\n- ( ) Tent\n- (x) Cabin\n- ( ) Hotel';

    test('picks it and clears the one picked before, and a second tap clears it', () {
      final on = open(doc, <Extension>[choices()]);
      tap(on, 35, 30);
      expect(on.state.doc.toString(), 'Where do we stay?\n- (x) Tent\n- ( ) Cabin\n- ( ) Hotel');
      tap(on, 35, 30);
      expect(on.state.doc.toString(), 'Where do we stay?\n- ( ) Tent\n- ( ) Cabin\n- ( ) Hotel');
    });

    testWidgets('leaves the words, a press that is not a plain one, and a note that cannot be changed, alone', (tester) async {
      final on = open(doc, <Extension>[choices()]);
      expect(tap(on, 90, 30), isFalse);
      expect(on.state.doc.toString(), doc);
      await expectNotPlain(tester, on, 35, 30, doc);
      final locked = open(doc, <Extension>[choices()], true);
      tap(locked, 35, 30);
      expect(locked.state.doc.toString(), doc);
    });

    test('picks one in a view that cannot be typed in but whose boxes take a tap: the Academy’s preview', () {
      final on = open(doc, <Extension>[choices(), taskToggle(), boxTapsWhileReadOnly.of(true)], true);
      tap(on, 35, 30);
      expect(on.state.doc.line(2).text, '- (x) Tent');
      expect(on.state.doc.line(3).text, '- ( ) Cabin');
    });

    test('draws each round box as one, the picked one marked', () {
      final on = open(doc, <Extension>[choices()]);
      final boxes = <({int from, String text, bool picked})>[];
      for (final set in on.decorations) {
        set.between(0, on.state.doc.length, (from, to, value) {
          final classes = (value.spec.className ?? '').split(' ');
          if (classes.contains('cm-choiceBox')) boxes.add((from: from, text: on.state.sliceDoc(from, to), picked: classes.contains('cm-choicePicked')));
          return null;
        });
      }
      boxes.sort((a, b) => a.from - b.from);
      expect(boxes.map((box) => box.text), <String>['( )', '(x)', '( )']);
      expect(boxes.map((box) => box.picked), <bool>[false, true, false]);
    });
  });
}
