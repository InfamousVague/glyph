// `src/app/editor/FindBar.test.tsx`, case for case, and then what the page's test could not ask of jsdom: the marks
// in the note, the scroll to the current match, the keyboard's own search key and the bar's entrance.
//
// Find and replace, as the bar on the keyboard: the count read back from the editor's own state, the arrows and
// Enter between matches, Replace and All, and Done, Escape or the back gesture ending the search.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/find_bar/find_bar.dart';
import 'package:ghost_md/editor/find_bar/find_marks.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';
import 'support.dart';

/// The marks in the note as `from-to class`, in order.
List<String> marksOf(EditorState state) {
  final out = <String>[];
  final cursor = findDecorations(state).iter();
  while (cursor.value != null) {
    out.add('${cursor.from}-${cursor.to} ${cursor.value!.spec.className}');
    cursor.next();
  }
  return out;
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey name, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(name);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('the find bar', () {
    testWidgets('finds as it is typed, and says which match of how many, or None', (tester) async {
      await pumpBar(tester, 'milk, eggs, milk');
      expect(countSaid(tester), '');
      await typeInto(tester, FindBarKeys.find, 'milk');
      expect(countSaid(tester), '1 of 2');
      await typeInto(tester, FindBarKeys.find, 'bread');
      expect(countSaid(tester), 'None');
      expect(enabled(tester, FindBarKeys.next), isFalse);
      await away(tester);
    });

    testWidgets('opens on the words it was given, with them chosen to type over', (tester) async {
      await pumpBar(tester, 'milk, eggs, milk', initial: 'eggs');
      final field = tester.widget<EditableText>(editableOf(FindBarKeys.find));
      expect(field.controller.text, 'eggs');
      expect(countSaid(tester), '1 of 1');
      expect(field.focusNode.hasPrimaryFocus, isTrue);
      expect(field.controller.selection, const TextSelection(baseOffset: 0, extentOffset: 4));
      await away(tester);
    });

    testWidgets('steps forward on Enter and the down arrow, and back on Shift+Enter and the up arrow', (tester) async {
      await pumpBar(tester, 'milk, milk, milk', initial: 'milk');
      await key(tester, LogicalKeyboardKey.enter);
      expect(countSaid(tester), '2 of 3');
      await press(tester, FindBarKeys.next);
      expect(countSaid(tester), '3 of 3');
      await key(tester, LogicalKeyboardKey.enter, shift: true);
      expect(countSaid(tester), '2 of 3');
      await press(tester, FindBarKeys.previous);
      expect(countSaid(tester), '1 of 3');
      await away(tester);
    });

    testWidgets('replaces one, then all, and says how many all was', (tester) async {
      final (view, _) = await pumpBar(tester, 'milk, eggs, milk, milk', initial: 'milk');
      await press(tester, FindBarKeys.replace);
      await typeInto(tester, FindBarKeys.replaceWith, 'cream');
      await press(tester, FindBarKeys.replaceOne);
      expect(view.state.doc.toString(), 'cream, eggs, milk, milk');
      await press(tester, FindBarKeys.all);
      expect(view.state.doc.toString(), 'cream, eggs, cream, cream');
      expect(find.text('Replaced 2. Undo takes it back.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('ends the search on Done, on Escape and on the back gesture', (tester) async {
      final leaves = <Future<void> Function()>[
        () => press(tester, FindBarKeys.done),
        () => key(tester, LogicalKeyboardKey.escape),
        () async {
          BackScope.of(tester.element(find.byKey(FindBarKeys.bar))).goBack();
          await settle(tester);
        },
      ];
      for (final leave in leaves) {
        var closed = 0;
        final (view, _) = await pumpBar(tester, 'milk, eggs, milk', initial: 'milk', onClose: () => closed += 1);
        expect(findOf(view.state).matches.length, 2);
        await leave();
        expect(closed, 1);
        expect(findOf(view.state).matches.length, 0);
        await away(tester);
      }
    });
  });

  group('what the page drew and jsdom could not be asked', () {
    testWidgets('every match is marked in the note, the current one as the current one, and the marks follow the steps', (tester) async {
      final (view, _) = await pumpBar(tester, 'milk, eggs, Milk', initial: 'milk');
      expect(marksOf(view.state), <String>['0-4 cm-findCurrent', '12-16 cm-findMatch']);
      await press(tester, FindBarKeys.next);
      expect(marksOf(view.state), <String>['0-4 cm-findMatch', '12-16 cm-findCurrent']);
      // The words change under the search: found again.
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'oat ')));
      await settle(tester);
      expect(marksOf(view.state), <String>['4-8 cm-findMatch', '16-20 cm-findCurrent']);
      expect(countSaid(tester), '2 of 2');
      await typeInto(tester, FindBarKeys.find, '');
      expect(marksOf(view.state), isEmpty);
      await away(tester);
    });

    testWidgets('the marks are there with the bar gone too: the extension draws them, not the bar', (tester) async {
      final (view, _) = await pumpBar(tester, 'milk, eggs, milk', bar: false);
      expect(marksOf(view.state), isEmpty);
      searchIn(view, 'eggs');
      await settle(tester);
      expect(marksOf(view.state), <String>['6-10 cm-findCurrent']);
      final line = view.lines.single;
      final classes = <String>[for (final seg in line.spec.projection.segments) seg.marks.map((m) => m.attrs['class']).join(' ')];
      expect(classes, <String>['', 'cm-findCurrent', '']);
      endSearchIn(view);
      await settle(tester);
      expect(marksOf(view.state), isEmpty);
      expect(view.state.selection.main.from, 6);
      expect(view.state.selection.main.to, 10);
      await away(tester);
    });

    testWidgets('a search, a step and a replacement each bring the current match to the middle of the page', (tester) async {
      final lines = <String>[for (var n = 1; n <= 600; n++) n == 200 || n == 400 || n == 590 ? 'line $n has the needle in it' : 'line $n of the note'];
      final doc = lines.join('\n');
      final (view, controller) = await pumpBar(tester, doc, scrolls: true);
      expect(controller!.offset, 0);

      double middleOf(int pos) {
        final at = view.coordsAtPos(pos);
        expect(at, isNotNull, reason: 'the match is laid out');
        return (at!.top + at.bottom) / 2;
      }

      await typeInto(tester, FindBarKeys.find, 'needle');
      expect(countSaid(tester), '1 of 3');
      final first = currentMatch(view.state)!;
      expect(first.from, doc.indexOf('needle'));
      expect(controller.offset, greaterThan(2000));
      expect(middleOf(first.from), closeTo(422, 24));

      await press(tester, FindBarKeys.next);
      final second = currentMatch(view.state)!;
      expect(second.from, greaterThan(first.from));
      expect(middleOf(second.from), closeTo(422, 24));

      // Back round the start to the last: near the note's end the page cannot scroll it to the middle, only into view.
      await press(tester, FindBarKeys.previous);
      await press(tester, FindBarKeys.previous);
      expect(countSaid(tester), '3 of 3');
      expect(middleOf(currentMatch(view.state)!.from), inInclusiveRange(0, 844));

      // Replacing moves on to the next, wrapping to the first, and brings it into view.
      await press(tester, FindBarKeys.replace);
      await typeInto(tester, FindBarKeys.replaceWith, 'pin');
      await press(tester, FindBarKeys.replaceOne);
      expect(view.state.doc.line(590).text, 'line 590 has the pin in it');
      expect(countSaid(tester), '1 of 2');
      expect(currentMatch(view.state)!.from, first.from);
      expect(middleOf(first.from), closeTo(422, 24));
      await away(tester);
    });

    testWidgets('closing leaves the caret on what was current, and hands the note the focus', (tester) async {
      final (view, _) = await pumpBar(tester, 'milk, eggs, milk', initial: 'milk');
      var asked = 0;
      view.focusRequest = () => asked += 1;
      await press(tester, FindBarKeys.next);
      await press(tester, FindBarKeys.done);
      expect(view.state.selection.main.from, 12);
      expect(view.state.selection.main.to, 16);
      expect(marksOf(view.state), isEmpty);
      expect(asked, 1);
      await away(tester);
    });

    testWidgets('the keyboard\'s own search key is the next match, and the field keeps the keyboard', (tester) async {
      await pumpBar(tester, 'milk, milk, milk', initial: 'milk');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(countSaid(tester), '2 of 3');
      expect(tester.widget<EditableText>(editableOf(FindBarKeys.find)).focusNode.hasPrimaryFocus, isTrue);
      await away(tester);
    });

    testWidgets('a press on an arrow, on Replace or on All leaves the find field focused', (tester) async {
      await pumpBar(tester, 'milk, milk, milk', initial: 'milk');
      final field = tester.widget<EditableText>(editableOf(FindBarKeys.find)).focusNode;
      for (final button in <Key>[FindBarKeys.next, FindBarKeys.previous, FindBarKeys.replace, FindBarKeys.replaceOne, FindBarKeys.all]) {
        await press(tester, button);
        expect(field.hasPrimaryFocus, isTrue, reason: '$button');
      }
      await away(tester);
    });

    testWidgets('Replace and All wait for a match, and what All said goes when the search changes', (tester) async {
      final (view, _) = await pumpBar(tester, 'milk, eggs', initial: 'bread');
      await press(tester, FindBarKeys.replace);
      expect(enabled(tester, FindBarKeys.replaceOne), isFalse);
      expect(enabled(tester, FindBarKeys.all), isFalse);
      expect(enabled(tester, FindBarKeys.previous), isFalse);
      await typeInto(tester, FindBarKeys.find, 'EGGS');
      expect(countSaid(tester), '1 of 1');
      expect(enabled(tester, FindBarKeys.replaceOne), isTrue);
      await typeInto(tester, FindBarKeys.replaceWith, 'ham');
      await press(tester, FindBarKeys.all);
      expect(view.state.doc.toString(), 'milk, ham');
      expect(find.byKey(FindBarKeys.said), findsOneWidget);
      // One change, so one undo takes it all back.
      expect(undo(view), isTrue);
      expect(view.state.doc.toString(), 'milk, eggs');
      await typeInto(tester, FindBarKeys.find, 'milk');
      expect(find.byKey(FindBarKeys.said), findsNothing);
      // The row closes again.
      await press(tester, FindBarKeys.replace);
      expect(find.byKey(FindBarKeys.replaceRow), findsNothing);
      await away(tester);
    });

    testWidgets('comes in over 160ms from six pixels down, and at once where motion is reduced', (tester) async {
      await pumpBar(tester, 'milk', initial: 'milk');
      final resting = tester.getRect(find.byKey(FindBarKeys.bar));
      expect(find.ancestor(of: find.byKey(FindBarKeys.bar), matching: find.byType(Opacity)), findsNothing);
      await away(tester);
      // Again, caught on its way in.
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: 'milk', extensions: findBarExtensions));
      addTearDown(view.destroy);
      await pumpApp(tester, ratio: 2, home: Align(alignment: Alignment.bottomCenter, child: FindBar(view: view, onClose: () {})));
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
      await tester.pump(const Duration(milliseconds: 40));
      final fading = tester.widget<Opacity>(find.ancestor(of: find.byKey(FindBarKeys.bar), matching: find.byType(Opacity)));
      expect(fading.opacity, inExclusiveRange(0, 1));
      final onTheWay = tester.getRect(find.byKey(FindBarKeys.bar));
      expect(onTheWay.top - resting.top, inExclusiveRange(0, 6));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.ancestor(of: find.byKey(FindBarKeys.bar), matching: find.byType(Opacity)), findsNothing);
      expect(tester.getRect(find.byKey(FindBarKeys.bar)), resting);
      await away(tester);
    });
  });
}
