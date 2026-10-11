// The + beside the line (lib/editor/plus/insert_plus.dart, drawn by plus_layer.dart): where it lives, when it comes
// and goes, and what its press does and does not reach. The cases of tauri/src/app/editor/insertPlus.test.ts,
// one for one; the rules for which line are plus_line_test.dart, and the timings run on the test's own clock.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/editor/view/line.dart';

import 'support.dart';

/// The lines that carry the +'s class.
List<RenderEditorLine> marked(WidgetTester tester) => tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).where((line) => line.spec.projection.className.split(' ').contains('cm-plusLine')).toList();

Finder get button => find.byType(PlusButton);

void main() {
  setUpAll(loadAppFonts);

  group('the + beside the line', () {
    plusTest('is a button over the editor, outside the lines the editor listens on', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch\n');
      expect(button, findsOneWidget);
      // It is no part of a line: nothing of the editor's lines is above it in the tree.
      expect(find.ancestor(of: button, matching: find.byType(EditorLine)), findsNothing);
      final semantics = tester.getSemantics(button);
      expect(semantics.label, 'Add to this note');
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(plusOf(view).expanded, isFalse);
    });

    plusTest('comes once the caret has rested on an empty line, and not a moment before', (tester) async {
      final view = editorOf('Lunch\n', insertPlus(Hooked().hooks));
      await pumpPlus(tester, view, focused: false);
      view.setFocused(true);
      expect(plusOf(view).look, PlusLook.waiting);
      await tester.pump(settle - const Duration(milliseconds: 1));
      expect(plusOf(view).look, PlusLook.waiting);
      await tester.pump(const Duration(milliseconds: 1));
      expect(plusOf(view).look, PlusLook.shown);
    });

    test('settles for about 150ms: long enough for Enter, Enter, and no pause to wait out', () {
      expect(settleMs, 150);
    });

    plusTest('never comes on a line with words, however long the caret rests', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch at the harbour');
      await tester.pump(settle * 10);
      expect(plusOf(view).look, PlusLook.off);
      // Not there to be pressed, and nothing of it painted.
      expect(followerOf(tester).plusRect, isNull);
      expect(button.hitTestable(), findsNothing);
    });

    plusTest('does not flicker through Enter, Enter typed in a run', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch');
      type(view, '\n');
      await tester.pump(settle ~/ 2);
      type(view, '\n');
      await tester.pump(settle ~/ 2);
      type(view, 'N');
      await tester.pump(settle * 4);
      expect(plusOf(view).look, PlusLook.off);
    });

    plusTest('settles afresh on each empty line a run of Enters passes, so the first line’s wait never shows it on the last', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch');
      type(view, '\n');
      await tester.pump(settle - const Duration(milliseconds: 50));
      type(view, '\n');
      // Were the first line's wait still running, the + would come 50ms after the second Enter.
      await tester.pump(settle - const Duration(milliseconds: 1));
      expect(plusOf(view).look, PlusLook.waiting);
      await tester.pump(const Duration(milliseconds: 1));
      expect(plusOf(view).look, PlusLook.shown);
    });

    plusTest('stays through a change that leaves the caret on the same empty line, rather than blinking out and back', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch\n- ');
      await tester.pump(settle + const Duration(seconds: 1));
      expect(plusOf(view).look, PlusLook.shown);
      type(view, ' ');
      expect(plusOf(view).look, PlusLook.shown);
      // Enter on an empty item ends the list: the lead goes, and the caret stays on the line.
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 'Lunch\n'.length, to: view.state.doc.length), selection: EditorSelection.single('Lunch\n'.length), userEvent: 'input'));
      expect(plusOf(view).look, PlusLook.shown);
      await tester.pump(settle);
      expect(plusOf(view).look, PlusLook.shown);
    });

    plusTest('keeps clear of a lead’s own mark, and sits in the middle of an empty line', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch\n- ');
      await tester.pump(settle);
      expect(plusOf(view).lead, isTrue);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 'Lunch\n'.length, to: view.state.doc.length), userEvent: 'input'));
      expect(plusOf(view).lead, isFalse);
    });

    plusTest('comes at once under a fine pointer over its place while it waits', (tester) async {
      final view = editorOf('Lunch\n', insertPlus(Hooked().hooks));
      await pumpPlus(tester, view, focused: false);
      view.setFocused(true);
      await tester.pump();
      final plus = plusOf(view);
      expect(plus.look, PlusLook.waiting);
      final row = plus.measure()!;
      final inside = Offset(10, row.top + row.height / 2);
      plus.hover(PointerDeviceKind.touch, inside);
      plus.hover(PointerDeviceKind.mouse, Offset(60, inside.dy));
      expect(plus.look, PlusLook.waiting);
      plus.hover(PointerDeviceKind.mouse, inside);
      expect(plus.look, PlusLook.shown);
    });

    plusTest('comes under a mouse that moves over the editor, through the layer', (tester) async {
      final view = editorOf('Lunch\n', insertPlus(Hooked().hooks));
      await pumpPlus(tester, view, focused: false);
      view.setFocused(true);
      await tester.pump();
      final plus = plusOf(view);
      final row = plus.measure()!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(200, 400));
      await mouse.moveTo(Offset(10, row.top + row.height / 2));
      expect(plus.look, PlusLook.shown);
      await mouse.removePointer();
    });

    plusTest('goes at once with the first letter, with no fade when it had not finished arriving', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch\n');
      await tester.pump(settle);
      final plus = plusOf(view);
      expect(plus.look, PlusLook.shown);
      final cuts = plus.cuts;
      type(view, 'W');
      expect(plus.look, PlusLook.off);
      expect(plus.cuts, cuts + 1);
      await tester.pump();
      // Cut: clear in the very next frame, with no fade to run.
      expect(tester.widget<Opacity>(find.descendant(of: button, matching: find.byType(Opacity))).opacity, 0);
    });

    plusTest('fades on a deleted letter’s beat once it had arrived, and then waits beside the new line', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch\n');
      await tester.pump(settle + const Duration(seconds: 1));
      type(view, '\n');
      expect(plusOf(view).look, PlusLook.leaving);
      await tester.pump(settle);
      expect(plusOf(view).look, PlusLook.shown);
    });

    plusTest('goes when the note loses the focus, and when the screen says no', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      await tester.pump(settle);
      hooked.allow = false;
      view.dispatch(TransactionSpec(effects: plusRecheck.of(null)));
      await tester.pump(const Duration(seconds: 1));
      expect(plusOf(view).look, PlusLook.off);
      hooked.allow = true;
      view.dispatch(TransactionSpec(effects: plusRecheck.of(null)));
      await tester.pump(const Duration(seconds: 1));
      expect(plusOf(view).look, PlusLook.shown);
      view.setFocused(false);
      await tester.pump(const Duration(seconds: 1));
      expect(plusOf(view).look, PlusLook.off);
    });

    plusTest('is placed beside the line it comes to before it is seen, never where it last stood', (tester) async {
      final (view, _) = await mountPlus(tester, 'A\n\nB\n\nC', caret: 'A\n'.length);
      await tester.pump(settle + const Duration(seconds: 1));
      final plus = plusOf(view);
      final lines = tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);
      double topOf(int index) => lines[index].localToGlobal(Offset.zero).dy;
      final follower = followerOf(tester);
      expect(plus.look, PlusLook.shown);
      expect(follower.plusRect!.top, closeTo(topOf(1), 0.01));
      view.dispatch(TransactionSpec(selection: EditorSelection.single('A\n\nB\n'.length)));
      final seen = <double>[];
      void watch() {
        if (plus.look == PlusLook.shown) seen.add(plus.measure()!.top);
      }

      plus.addListener(watch);
      await tester.pump(settle + const Duration(milliseconds: 100));
      plus.removeListener(watch);
      expect(plus.look, PlusLook.shown);
      expect(seen.toSet(), <double>{topOf(3)});
      expect(follower.plusRect!.top, closeTo(topOf(3), 0.01));
    });

    plusTest('is level with the words of a line whose box runs on below them, as a quote’s last line’s does', (tester) async {
      final (view, _) = await mountPlus(tester, '> quote\n> ');
      await tester.pump(settle);
      final line = tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).reduce((a, b) => a.from > b.from ? a : b);
      final look = line.spec.look;
      final box = plusOf(view).measure()!;
      // The quote's last line carries padding below its words: the + is as tall as the words' row, not the box.
      expect(look.paddingBottom + look.borderBottom, greaterThan(0));
      final top = line.localToGlobal(Offset.zero).dy;
      expect(box.top, closeTo(top + look.borderTop + look.paddingTop, 0.001));
      expect(box.height, closeTo(line.size.height - look.borderTop - look.paddingTop - look.paddingBottom - look.borderBottom, 0.001));
      expect(box.height, lessThan(line.size.height));
    });

    plusTest('marks its own line only, for the bookmark’s edge to step aside', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch §§\n\nMore');
      view.dispatch(TransactionSpec(selection: EditorSelection.single('Lunch §§\n'.length)));
      await tester.pump(settle);
      await tester.pump();
      final lines = marked(tester);
      expect(lines, hasLength(1));
      expect(lines.single.spec.projection.display, '');
    });
  });

  group('its line’s mark, under a composition', () {
    plusTest('is left as it is while the keyboard composes, and changed once it has finished', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      await tester.pump(settle);
      await tester.pump();
      expect(marked(tester), hasLength(1));
      view.setComposing(true);
      hooked.allow = false;
      view.dispatch(TransactionSpec(effects: plusRecheck.of(null)));
      await tester.pump(const Duration(seconds: 1));
      expect(plusOf(view).look, PlusLook.off);
      // Rebuilding the line under a live composition breaks typing on a phone (glyph_lines.dart).
      expect(marked(tester), hasLength(1));
      view.setComposing(false);
      view.dispatch(TransactionSpec(effects: plusRecheck.of(null)));
      await tester.pump();
      await tester.pump();
      expect(marked(tester), isEmpty);
    });
  });

  group('its press', () {
    plusTest('is the +’s own, and a long press too: nothing under it hears either', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      await tester.pump(settle);
      final at = tester.getCenter(button);
      // The first thing a press there lands on is the +, and no line of the editor is behind it in the path.
      final result = tester.hitTestOnBinding(at);
      final path = result.path.map((entry) => entry.target).toList();
      expect(path.whereType<RenderEditorLine>(), isEmpty);
      expect(find.byType(PlusButton).hitTestable(), findsOneWidget);
      final caret = view.state.selection.main.head;
      await tester.longPressAt(at);
      await tester.pump();
      expect(view.state.selection.main.head, caret);
      expect(hooked.opened, isEmpty);
      // While it waits or leaves it is never under a finger.
      type(view, '\n');
      expect(plusOf(view).look, PlusLook.leaving);
      await tester.pump();
      expect(find.byType(PlusButton).hitTestable(), findsNothing);
    });

    plusTest('asks for the list against its line, and says how it was pressed', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      await tester.pump(settle);
      await tester.tap(button);
      expect(hooked.opened, hasLength(1));
      expect(hooked.opened.single.line, 2);
      expect(hooked.opened.single.by, PlusBy.touch);
      // Its box is the gutter's width and its row's height, at the row.
      expect(apart(hooked.opened.single.rect()!, tester.getRect(button)), lessThan(0.01));
      expect(view.hasFocus, isTrue);
      await tester.tap(button, kind: PointerDeviceKind.mouse);
      expect(hooked.opened.last.by, PlusBy.pointer);
    });

    plusTest('closes the list on a second press, as a ×', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      await tester.pump(settle);
      view.dispatch(TransactionSpec(effects: plusMenu.of(const PlusMenu(list: 'add-list'))));
      await tester.pump();
      expect(plusOf(view).expanded, isTrue);
      expect(tester.getSemantics(button).flagsCollection.isExpanded.toString(), 'Tristate.isTrue');
      await tester.tap(button);
      expect(hooked.closed, 1);
      expect(hooked.opened, isEmpty);
    });

    plusTest('shows at once when the keyboard reaches it, and opens with the keyboard', (tester) async {
      final view = editorOf('Lunch\n', insertPlus(Hooked().hooks));
      final hooked = Hooked();
      final other = editorOf('Lunch\n', insertPlus(hooked.hooks));
      await pumpPlus(tester, other, focused: false);
      other.setFocused(true);
      await tester.pump();
      final plus = plusOf(other);
      expect(plus.look, PlusLook.waiting);
      plus.buttonFocus(true);
      expect(plus.look, PlusLook.shown);
      plus.press(PlusBy.keyboard);
      expect(hooked.opened.single.line, 2);
      expect(hooked.opened.single.by, PlusBy.keyboard);
      // Enter on a + that still waits shows it and opens it in one.
      view.setFocused(true);
      expect(plusOf(view).look, PlusLook.waiting);
      plusOf(view).press(PlusBy.touch);
      expect(plusOf(view).look, PlusLook.waiting);
      plusOf(view).press(PlusBy.keyboard);
      expect(plusOf(view).look, PlusLook.shown);
    });
  });

  group('the list open from the editor', () {
    const keys = <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ];

    plusTest('takes Up, Down, Enter, Escape, Left and Right from the editor', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      view.dispatch(TransactionSpec(effects: plusMenu.of(const PlusMenu(list: 'add-list', active: 'add-picture'))));
      for (final key in keys) {
        expect(sendKey(view, key), isTrue, reason: key.keyLabel);
      }
      expect(hooked.keys, [PlusKey.up, PlusKey.down, PlusKey.enter, PlusKey.escape, PlusKey.left, PlusKey.right]);
      expect(hooked.closed, 0);
    });

    plusTest('closes on any other key, which then does what it always does', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      view.dispatch(TransactionSpec(effects: plusMenu.of(const PlusMenu(list: 'add-list', active: 'add-picture'))));
      expect(sendKey(view, LogicalKeyboardKey.shiftLeft), isFalse);
      expect(hooked.closed, 0);
      expect(sendKey(view, LogicalKeyboardKey.keyA, character: 'a'), isFalse);
      expect(hooked.closed, 1);
      // A key the list says it does not take closes it too, and is the editor's.
      hooked.take = false;
      expect(sendKey(view, LogicalKeyboardKey.arrowRight), isFalse);
      expect(hooked.closed, 2);
    });

    plusTest('closes on a change or a caret move in the note', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      view.dispatch(TransactionSpec(effects: plusMenu.of(const PlusMenu(list: 'add-list'))));
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      expect(hooked.closed, 1);
    });

    plusTest('names the lit row for a screen reader, and nothing once it closes', (tester) async {
      final (view, _) = await mountPlus(tester, 'Lunch\n');
      view.dispatch(TransactionSpec(effects: plusMenu.of(const PlusMenu(list: 'add-list', active: 'add-place'))));
      expect(plusMenuOf(view.state)?.active, 'add-place');
      expect(plusMenuOf(view.state)?.list, 'add-list');
      expect(plusOpen(view), isTrue);
      view.dispatch(TransactionSpec(effects: plusMenu.of(null)));
      expect(plusMenuOf(view.state), isNull);
      expect(plusOpen(view), isFalse);
    });

    plusTest('leaves the keys alone while it is closed', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      expect(sendKey(view, LogicalKeyboardKey.arrowUp), isFalse);
      expect(hooked.keys, isEmpty);
    });
  });

  group('/ typed on an empty line', () {
    plusTest('opens the list as a palette at the caret, and is not written', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      expect(sendKey(view, LogicalKeyboardKey.slash, character: '/'), isTrue);
      expect(hooked.opened.single.by, PlusBy.slash);
      expect(hooked.opened.single.line, 2);
      expect(view.state.doc.toString(), 'Lunch\n');
      // Placed against the caret: no wider than a caret, as tall as its row.
      final at = hooked.opened.single.rect()!;
      final caret = view.coordsAtPos(view.state.selection.main.head)!;
      expect(at.width, 0);
      expect(at.left, caret.left);
      expect(at.top, caret.top);
      expect(at.height, caret.height);
    });

    plusTest('is the note’s own on a line with words, with a selection, where the screen says no, and while the list is open', (tester) async {
      final (view, hooked) = await mountPlus(tester, 'Lunch\n');
      view.dispatch(TransactionSpec(selection: EditorSelection.single(2)));
      expect(sendKey(view, LogicalKeyboardKey.slash, character: '/'), isFalse);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0, 6)));
      expect(sendKey(view, LogicalKeyboardKey.slash, character: '/'), isFalse);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(6)));
      hooked.allow = false;
      expect(sendKey(view, LogicalKeyboardKey.slash, character: '/'), isFalse);
      expect(openPlusSlash(view), isFalse);
      hooked.allow = true;
      expect(openPlusSlash(view), isTrue);
      view.dispatch(TransactionSpec(effects: plusMenu.of(const PlusMenu(list: 'add-list'))));
      expect(openPlusSlash(view), isFalse);
      expect(hooked.opened, hasLength(1));
    });
  });
}
