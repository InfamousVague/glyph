// Pointers on the real renderer: a tap puts the caret (and not inside what a caret steps over), two take a word,
// a press held takes the word or puts the caret on empty paper and asks for the menu, a to-do's box is turned by a
// tap, a widget that keeps its pointers keeps them, a mouse drags a selection, the handles move their ends, a
// finger at the page's edge scrolls it; and the caret blinks as a browser's does.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/input/caret.dart';
import 'package:ghost_md/editor/input/gestures.dart';
import 'package:ghost_md/editor/input/handles.dart';
import 'package:ghost_md/editor/view/decoration.dart' as cm;

import '../../support/render.dart';
import 'support.dart';

const String note =
    '# Title\n'
    '\n'
    'Some plain words to tap among, long enough that the paragraph wraps onto a second line of the screen.\n'
    '\n'
    '- [ ] a to-do\n'
    '- [x] one done\n'
    '\n'
    'last line';

class _Chip extends EditorWidget {
  const _Chip(this.onTap, {this.takes = true});
  final VoidCallback onTap;
  final bool takes;

  @override
  bool eq(_Chip other) => other.takes == takes;

  @override
  bool takesPointer(PointerEvent event) => takes;

  // A widget that leaves its pointers to the editor has no recogniser of its own to win them.
  @override
  Widget build(BuildContext context) => takes
      ? GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: const SizedBox(key: ValueKey('chip'), width: 40, height: 16),
        )
      : const SizedBox(key: ValueKey('chip'), width: 40, height: 16);
}

Future<void> hold(WidgetTester tester, Offset at, {Offset? dragTo, int frames = 1}) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(EditorGestures.longPress + const Duration(milliseconds: 20));
  await tester.pump();
  if (dragTo != null) {
    await gesture.moveTo(Offset.lerp(at, dragTo, 0.5)!);
    await tester.pump();
    await gesture.moveTo(dragTo);
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a tap puts the caret, takes the focus and raises the keyboard', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    expect(rig.view.hasFocus, isFalse);
    final pos = rig.at('plain') + 2;
    final at = rig.view.coordsAtPos(pos)!;
    await tester.tapAt(at.center + const Offset(1, 0));
    await tester.pump();
    expect(rig.head, pos);
    expect(rig.events, contains('select.pointer'));
    expect(rig.view.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(rig.ime.text, rig.window);
    // The handle under the caret, which goes when something is typed.
    await tester.pump();
    expect(find.byType(CompositedTransformFollower), findsWidgets);
    await rig.ime.type('x');
    await tester.pump();
    expect(find.byType(CompositedTransformFollower), findsNothing);
    await finish(tester);
  });

  testWidgets('a tap on the empty paper under a short note puts the caret at its end', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    await tester.tapAt(const Offset(200, 800));
    await tester.pump();
    expect(rig.head, note.length);
    expect(rig.view.hasFocus, isTrue);
    // And one past a line's end, at that line's end.
    final line = rig.view.coordsAtPos(rig.at('- [ ] a to-do') + 13)!;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(Offset(380, line.center.dy));
    await tester.pump();
    expect(rig.head, rig.at('- [ ] a to-do') + 13);
    await finish(tester);
  });

  testWidgets('a tap does not put the caret inside what a caret steps over', (tester) async {
    final from = note.indexOf('plain'), to = from + 5;
    final atoms = RangeSet.of<cm.Decoration>(<Range<cm.Decoration>>[cm.Decoration.mark(className: 'x').range(from, to)]);
    final rig = await pumpEditor(tester, note, focus: false, more: [EditorViewLike.atomicRanges.of((_) => atoms)]);
    final a = rig.view.coordsAtPos(from + 1)!, b = rig.view.coordsAtPos(from + 4)!;
    await tester.tapAt(a.center + const Offset(1, 0));
    await tester.pump();
    expect(rig.head, from);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(b.center + const Offset(1, 0));
    await tester.pump();
    expect(rig.head, to);
    await finish(tester);
  });

  testWidgets('two taps take the word, three the line', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    final at = rig.point(rig.at('plain') + 2) + const Offset(1, 0);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pump();
    expect((rig.anchor, rig.head), (rig.at('plain'), rig.at('plain') + 5));
    await tester.pump();
    expect(find.byType(CompositedTransformFollower), findsNWidgets(2), reason: 'a handle at each end');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pump();
    final line = rig.view.state.doc.lineAt(rig.at('plain'));
    expect((rig.anchor, rig.head), (line.from, line.to + 1));
    // Too slow, and it is one tap again.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(at);
    await tester.pump();
    expect((rig.anchor, rig.head), (rig.at('plain') + 2, rig.at('plain') + 2));
    await finish(tester);
  });

  testWidgets('a press held on a word selects it and asks for the menu over the caret', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    await hold(tester, rig.point(rig.at('words') + 1));
    final from = rig.at('words');
    expect((rig.view.state.selection.main.from, rig.view.state.selection.main.to), (from, from + 5));
    expect(rig.view.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse, reason: 'a hold selects; it does not raise the keyboard');
    expect(rig.held.length, 1);
    final caret = rig.view.coordsAtPos(rig.head, -1)!;
    expect(rig.held.single.from, from);
    expect(rig.held.single.to, from + 5);
    expect(rig.held.single.x, closeTo(caret.center.dx, 0.5));
    expect(rig.held.single.y, closeTo(caret.top, 0.5));
    // Typed over: the word goes, and the handles with it.
    await tester.pump();
    expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
    rig.controller.focus();
    await tester.pump();
    final sel = rig.ime.value.selection;
    await rig.ime.send([rig.ime.edit(sel.start, sel.end, 'x')]);
    await tester.pump();
    expect(rig.doc, contains('Some plain x to tap'));
    expect(find.byType(CompositedTransformFollower), findsNothing);
    await finish(tester);
  });

  testWidgets('a press held 480 ms on empty paper puts the caret there and asks for the menu', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    // The empty line under the title.
    final empty = rig.view.coordsAtPos(8)!;
    final gesture = await tester.startGesture(Offset(120, empty.center.dy));
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.held, isEmpty, reason: 'not yet');
    expect(rig.head, 0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(rig.head, 8);
    expect(rig.view.state.selection.main.empty, isTrue);
    expect(rig.held.single.from, 8);
    expect(rig.held.single.to, 8);
    await gesture.up();
    await tester.pump();
    // The space past a line's last word is empty paper too.
    rig.held.clear();
    final end = rig.at('- [ ] a to-do') + 13;
    await hold(tester, Offset(360, rig.view.coordsAtPos(end)!.center.dy));
    expect(rig.head, end);
    expect(rig.view.state.selection.main.empty, isTrue);
    expect(rig.held.length, 1);
    await finish(tester);
  });

  testWidgets('a finger that wanders is not holding', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    final at = rig.point(rig.at('words') + 1);
    final gesture = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();
    expect(rig.held, isEmpty);
    expect(rig.view.state.selection.main.empty, isTrue);
    await finish(tester);
  });

  testWidgets('dragging on after a hold stretches the selection by words', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    await hold(tester, rig.point(rig.at('plain') + 1), dragTo: rig.point(rig.at('tap among') + 1));
    final sel = rig.view.state.selection.main;
    expect((sel.from, sel.to), (rig.at('plain'), rig.at('tap among') + 3));
    await finish(tester);
  });

  testWidgets('a tap on a to-do\'s box turns it and leaves the caret and the keyboard alone', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    final box = rig.at('[ ]');
    await tester.tapAt(rig.point(box + 1));
    await tester.pump();
    expect(rig.doc, contains('- [x] a to-do'));
    expect(rig.events, <String>['input.toggle']);
    expect(rig.view.hasFocus, isFalse);
    expect(rig.head, 0);
    // Within eight pixels of it counts; the words beside it are for writing.
    await tester.pump(const Duration(milliseconds: 400));
    final start = rig.view.coordsAtPos(box)!;
    await tester.tapAt(Offset(start.left - 6, start.center.dy));
    await tester.pump();
    expect(rig.doc, contains('- [ ] a to-do'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(rig.point(rig.at('to-do') + 2) + const Offset(1, 0));
    await tester.pump();
    expect(rig.doc, contains('- [ ] a to-do'));
    expect(rig.head, rig.at('to-do') + 2);
    await finish(tester);
  });

  testWidgets('a note that cannot be changed keeps its boxes, and a tap raises no keyboard', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false, readOnly: true);
    await tester.tapAt(rig.point(rig.at('[ ]') + 1));
    await tester.pump();
    expect(rig.doc, note);
    expect(tester.testTextInput.isVisible, isFalse);
    // A word can still be held and selected, to copy.
    await hold(tester, rig.point(rig.at('words') + 1));
    expect(rig.view.state.selection.main.to - rig.view.state.selection.main.from, 5);
    await finish(tester);
  });

  testWidgets('a widget that keeps its pointers keeps them; one that does not is text to the editor', (tester) async {
    var taps = 0;
    for (final takes in [true, false]) {
      taps = 0;
      final field = StateField.define<cm.DecorationSet>(
        create: (state) => cm.Decoration.set(<Range<cm.Decoration>>[cm.Decoration.widget(widget: _Chip(() => taps++, takes: takes), side: 1).range(note.indexOf('plain'))]),
        update: (value, tr) => value.map(tr.changes),
        provide: (field) => EditorViewLike.decorations.from(field),
      );
      final rig = await pumpEditor(tester, note, focus: false, more: [field]);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('chip'))));
      await tester.pump();
      if (takes) {
        expect(taps, 1);
        expect(rig.view.hasFocus, isFalse, reason: 'the editor did not join the gesture');
        expect(rig.events, isEmpty);
      } else {
        expect(rig.view.hasFocus, isTrue);
        expect(rig.head, rig.at('plain'));
      }
      await finish(tester);
    }
  });

  testWidgets('a plugin\'s handlers are asked first', (tester) async {
    final seen = <String>[];
    var take = true;
    final rig = await pumpEditor(
      tester,
      note,
      focus: false,
      more: [
        EditorViewLike.eventHandlers(EditorEventHandlers(
          tap: (tap, view) {
            seen.add('tap ${tap.pos}');
            return take;
          },
          longPress: (tap, view) {
            seen.add('hold ${tap.pos}');
            return take;
          },
          pointerDown: (event, view) {
            seen.add('down');
            return false;
          },
        )),
      ],
    );
    final pos = rig.at('plain') + 2;
    await tester.tapAt(rig.point(pos) + const Offset(1, 0));
    await tester.pump();
    expect(seen, ['down', 'tap $pos']);
    expect(rig.head, 0, reason: 'the handler took it');
    await tester.pump(const Duration(milliseconds: 400));
    await hold(tester, rig.point(pos) + const Offset(1, 0));
    expect(seen.last, 'hold $pos');
    expect(rig.held, isEmpty);
    take = false;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(rig.point(pos) + const Offset(1, 0));
    await tester.pump();
    expect(rig.head, pos);
    await finish(tester);
  });

  testWidgets('a mouse: down puts the caret, a drag selects, Shift extends, the other button asks for the menu', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    final a = rig.at('plain'), b = rig.at('tap among') + 3;
    final gesture = await tester.startGesture(rig.point(a) + const Offset(1, 0), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(rig.head, a);
    expect(rig.view.hasFocus, isTrue);
    await gesture.moveTo(rig.point(a + 8));
    await gesture.moveTo(rig.point(b) + const Offset(1, 0));
    await tester.pump();
    expect((rig.anchor, rig.head), (a, b));
    await gesture.up();
    await tester.pump();
    expect(find.byType(CompositedTransformFollower), findsNothing, reason: 'no handles for a mouse');
    // The other button, on the selection: it stays, and the menu is asked for.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(rig.point(a + 2), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pump();
    await tester.pump();
    expect((rig.anchor, rig.head), (a, b));
    expect(rig.held.single.from, a);
    expect(rig.held.single.to, b);
    await finish(tester);
  });

  testWidgets('a handle dragged moves its end of the selection, with the loupe over the finger', (tester) async {
    final rig = await pumpEditor(tester, note, focus: false);
    await hold(tester, rig.point(rig.at('plain') + 1));
    await tester.pump();
    final from = rig.at('plain');
    expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
    // The end handle hangs under the selection's end.
    final end = rig.view.coordsAtPos(from + 5, -1)!;
    final grip = end.bottomLeft + const Offset(8, 10);
    final target = rig.view.coordsAtPos(rig.at('among') + 5, -1)!;
    final gesture = await tester.startGesture(grip);
    await tester.pump();
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await gesture.moveTo(grip + (target.center - end.center));
    await tester.pump();
    expect(find.byType(EditorMagnifier), findsOneWidget);
    expect((rig.view.state.selection.main.from, rig.view.state.selection.main.to), (from, rig.at('among') + 5));
    await gesture.up();
    await tester.pump();
    expect(find.byType(EditorMagnifier), findsNothing);
    // The start handle, back to the start of the line.
    final start = rig.view.coordsAtPos(from, 1)!;
    final first = rig.view.coordsAtPos(rig.at('Some'), 1)!;
    final other = await tester.startGesture(start.bottomLeft + const Offset(-8, 10));
    await tester.pump();
    await other.moveBy(const Offset(-12, 0));
    await tester.pump();
    await other.moveTo(start.bottomLeft + const Offset(-8, 10) + (first.center - start.center));
    await tester.pump();
    await other.up();
    await tester.pump();
    expect((rig.view.state.selection.main.from, rig.view.state.selection.main.to), (rig.at('Some'), rig.at('among') + 5));
    expect(rig.events.where((e) => e.isNotEmpty), everyElement('select.pointer'));
    await finish(tester);
  });

  testWidgets('a finger holding a selection at the page\'s foot scrolls the page under it', (tester) async {
    final doc = <String>[for (var i = 0; i < 120; i++) 'line $i of the note'].join('\n');
    final rig = await pumpEditor(tester, doc, focus: false);
    final line = drawn(tester).lastWhere((l) => l.localToGlobal(Offset.zero).dy < 700);
    final start = rig.point(line.from + 2);
    await hold(tester, start, dragTo: Offset(start.dx, 838), frames: 30);
    expect(rig.scroll.offset, greaterThan(20));
    final sel = rig.view.state.selection.main;
    expect(sel.from, line.from);
    expect(rig.view.state.doc.lineAt(sel.to).number, greaterThan(rig.view.state.doc.lineAt(line.from).number + 3), reason: 'the selection grew as the page moved');
    await finish(tester);
  });

  testWidgets('the caret blinks as a browser\'s: half a second on, half off, and solid again when it moves', (tester) async {
    final rig = await pumpEditor(tester, note, caret: 3);
    final opacity = rig.view.caretOpacity;
    expect(opacity.value, 1);
    await tester.pump(CaretBlink.half + const Duration(milliseconds: 10));
    expect(opacity.value, 0);
    await tester.pump(CaretBlink.half);
    expect(opacity.value, 1);
    await tester.pump(CaretBlink.half);
    expect(opacity.value, 0);
    await rig.ime.type('x');
    expect(opacity.value, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity.value, 1, reason: 'the half second starts again from the key');
    rig.controller.unfocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(opacity.value, 1);
    await finish(tester);
  });
}
