// Boards drawn in a note (lib/editor/boards): the web's editor/boards.test.ts, case for case where the case is the
// board's and not the browser's, with what the port adds: one undo to an edit, the height a board is held at, a
// lane handing the finger on to the note, and a swipe settling on a column. The anchors' own cases of that file
// were ported with the anchors (test/editor/items/anchors_test.dart).
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/boards/boards.dart';
import 'package:ghost_md/art/wisp_foot.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/drawn_block.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

String docOf(EditorView view) => view.state.doc.toString();
int caretLine(EditorView view) => view.state.doc.lineAt(view.state.selection.main.head).number;

/// Past whatever a press set going: the phone's taps, a field's wait, a card's flash.
Future<void> rest(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> press(WidgetTester tester, String label) async {
  await tester.tap(said(label));
  await tester.pump();
  await tester.pump();
}

/// The + on a column pressed, and the field it opens.
Future<Finder> addTo(WidgetTester tester, String column) async {
  await press(tester, 'Add a card to $column');
  return find.byType(EditableText);
}

/// Words typed into the open field and sent with the keyboard's done key.
Future<void> typeCard(WidgetTester tester, String words) async {
  await tester.enterText(find.byType(EditableText), words);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// The board's own scroller, across.
ScrollPosition acrossOf(WidgetTester tester) =>
    tester.state<ScrollableState>(find.descendant(of: find.byType(DrawnBoardBox), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)).first).position;

/// Lane `index` brought to the board's start, as a swipe would leave it.
Future<void> showLane(WidgetTester tester, int index) async {
  final look = BoardLook.of(tester.element(find.byType(DrawnBoardBox)), null);
  final position = acrossOf(tester);
  position.jumpTo((index * (look.columnWidth + look.columnGap)).clamp(0, position.maxScrollExtent));
  await tester.pump();
}

String wordsOf(WidgetTester tester, String id) => tester.widget<BoardWords>(inCard(id, 'words')).text;
List<String> menuRows(WidgetTester tester) => <String>[for (final row in tester.widgetList<GlacierMenuItem>(find.byType(GlacierMenuItem))) (row.child as Text).data!];

Future<void> openMenu(WidgetTester tester, String words) async {
  await tester.tap(said('More for $words'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> chooseRow(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  var now = DateTime(2026, 9, 16, 12);
  setUp(() {
    now = now.add(const Duration(minutes: 5));
    boardClock = () => now;
  });
  tearDown(() {
    boardClock = DateTime.now;
    debugDisableShadows = true;
  });

  group('the + on a board column', () {
    testWidgets('asks for the words first, then writes a real task item named after them', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final field = await addTo(tester, 'To do');
      expect(field, findsOneWidget);
      // Nothing is written by opening the field.
      expect(docOf(view), boardNote);

      await typeCard(tester, 'Rename the weak anchors');
      // Under the board's last item, with a space after the box, the words, and an anchor that says what it is.
      expect(docOf(view), contains('- [x] Pick a launch date ^pick-date\n- [ ] Rename the weak anchors ^rename-weak-anchors\n'));
      // At the top of the column it was typed into.
      expect(docOf(view), contains('To do: rename-weak-anchors, ship-page\nDone: pick-date'));
      expect(docOf(view), isNot(contains('^item')));
      await rest(tester);
    });

    testWidgets('looks like the card it will be: an empty box where the tick goes, and Add waiting until there are words', (tester) async {
      // Matt: "Add task input and button dont match up".
      await pumpBoards(tester, boardNote);
      await addTo(tester, 'To do');
      final tick = boxOf(tester, keyed('compose-tick')), field = boxOf(tester, keyed('compose-field')), add = boxOf(tester, keyed('compose-add'));
      expect(tick.right, lessThan(field.left));
      expect(field.right, lessThan(add.left));
      // The words typed start where a card's words do.
      expect(field.left, closeTo(boxOf(tester, inCard('ship-page', 'words')).left, 0.01));
      final composer = tester.state<BoardComposerState>(find.byType(BoardComposer));
      expect(composer.ready, isFalse);
      expect(tester.getSemantics(find.descendant(of: find.byType(BoardComposer), matching: said('Add'))), isSemantics(isButton: true, hasEnabledState: true, isEnabled: false, label: 'Add'));
      await tester.enterText(find.byType(EditableText), 'Pack the stove');
      await tester.pump();
      expect(composer.ready, isTrue);
      await tester.tap(find.descendant(of: find.byType(BoardComposer), matching: said('Add')));
      await tester.pump();
      await tester.pump();
      // Added, the field is empty again, and so Add waits again.
      expect(composer.ready, isFalse);
      await rest(tester);
    });

    testWidgets('keeps the same field, emptied, for the next card', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await showLane(tester, 1);
      await addTo(tester, 'Done');
      final composer = tester.state<BoardComposerState>(find.byType(BoardComposer));
      await typeCard(tester, 'Book the ferry');
      // The board was redrawn in place, so the field typed into is still the one on the page, and still has the
      // keyboard.
      expect(tester.state<BoardComposerState>(find.byType(BoardComposer)), same(composer));
      expect(inColumn(1, find.byType(BoardComposer)), findsOneWidget);
      expect(composer.controller.text, '');
      expect(composer.focusNode.hasFocus, isTrue);
      expect(tester.getSemantics(keyed('column1')).label, startsWith('Done, 2 cards'));

      await typeCard(tester, 'Pack the tent');
      expect(docOf(view), contains('Done: pack-tent, book-ferry, pick-date'));
      await rest(tester);
    });

    testWidgets('adds the card on the key a phone keyboard has for it', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await addTo(tester, 'To do');
      await tester.enterText(find.byType(EditableText), 'Call the venue');
      expect(tester.testTextInput.setClientArgs!['inputAction'], 'TextInputAction.done');
      expect(tester.testTextInput.setClientArgs!['textCapitalization'], 'TextCapitalization.sentences');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(docOf(view), contains('- [ ] Call the venue ^call-venue\n'));
      expect(tester.state<BoardComposerState>(find.byType(BoardComposer)).controller.text, '');
      await rest(tester);
    });

    testWidgets('writes nothing for no words, and a second press goes back to the open field', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await addTo(tester, 'To do');
      final composer = tester.state<BoardComposerState>(find.byType(BoardComposer));
      await typeCard(tester, '   ');
      expect(docOf(view), boardNote);
      await addTo(tester, 'To do');
      expect(find.byType(BoardComposer), findsOneWidget);
      expect(tester.state<BoardComposerState>(find.byType(BoardComposer)), same(composer));
      expect(composer.focusNode.hasFocus, isTrue);
      await rest(tester);
    });

    testWidgets('closes on Escape without writing anything', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await addTo(tester, 'To do');
      await tester.enterText(find.byType(EditableText), 'Half a thought');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(BoardComposer), findsNothing);
      expect(docOf(view), boardNote);
    });

    testWidgets('closes when it is left empty, and stays when it is left with words in it', (tester) async {
      await pumpBoards(tester, boardNote);
      await addTo(tester, 'To do');
      final composer = tester.state<BoardComposerState>(find.byType(BoardComposer));
      composer.controller.text = 'Half a thought';
      composer.focusNode.unfocus();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(BoardComposer), findsOneWidget);
      composer.focus();
      await tester.pump();
      composer.controller.clear();
      composer.focusNode.unfocus();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BoardComposer), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BoardComposer), findsNothing);
    });

    testWidgets('adds under the fence of a board that names nothing yet, and at the end of a note with no last newline', (tester) async {
      final view = await pumpBoards(tester, '```board\nTo do:\n```');
      await addTo(tester, 'To do');
      await typeCard(tester, 'First thing');
      expect(docOf(view), '```board\nTo do: first-thing\n```\n- [ ] First thing ^first-thing');
      await rest(tester);
    });

    testWidgets('offers the phone nothing to fill: it is not a login', (tester) async {
      // Matt: "New Tasks are popping password manager save modal".
      await pumpBoards(tester, boardNote);
      await addTo(tester, 'To do');
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.autofillHints, isNull);
      expect(field.obscureText, isFalse);
      expect(find.byType(AutofillGroup), findsNothing);
      await rest(tester);
    });
  });

  group('a card whose item is linked to a plugin', () {
    testWidgets('shows the plugin’s mark rather than the link’s words', (tester) async {
      await pumpBoards(tester, '```board\nTo do: pack\n```\n\n- [ ] Pack the tent [notion](https://app.notion.com/p/abc) ^pack');
      expect(wordsOf(tester, 'pack'), 'Pack the tent');
      expect(find.descendant(of: cardOf('pack'), matching: said('Linked to notion')), findsOneWidget);
    });

    testWidgets('keeps an ordinary link’s words, which are part of what the item says', (tester) async {
      await pumpBoards(tester, '```board\nTo do: read\n```\n\n- [ ] Read the [docs](https://example.com/docs) first ^read');
      expect(wordsOf(tester, 'read'), 'Read the docs first');
      expect(inCard('read', 'linked'), findsNothing);
    });
  });

  group('dragging a card', () {
    Offset onWords(WidgetTester tester, String id) => boxOf(tester, inCard(id, 'words')).topLeft + const Offset(30, 8);
    bool lifted(WidgetTester tester) => keyed('gap').evaluate().isNotEmpty || find.byWidgetPredicate((w) => w is BoardCard && identical(w.does, CardDoes.nothing)).evaluate().isNotEmpty;

    testWidgets('is picked up by a finger that rests on it', (tester) async {
      await pumpBoards(tester, boardNote);
      final at = onWords(tester, 'ship-page');
      final card = boxOf(tester, cardOf('ship-page'));
      final finger = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 100));
      expect(lifted(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 130));
      await tester.pump();
      // The card is the gap it would leave, exactly its size and where it was; every lane says it will take one.
      expect(inColumn(0, cardOf('ship-page')), findsNothing);
      expect(boxOf(tester, inColumn(0, keyed('gap'))), card);
      expect(find.text('Drop a card here'), findsNothing, reason: 'set as the board sets its words, not as Text');
      expect(tester.widgetList<BoardEmpty>(find.byType(BoardEmpty)).map((place) => (place.holding, place.over)), <(bool, bool)>[(true, true), (true, false)]);
      // The copy under the finger is the card, drawn over the page where the card was.
      final copy = find.byWidgetPredicate((w) => w is BoardCard && w.card.id == 'ship-page' && identical(w.does, CardDoes.nothing));
      expect(copy, findsOneWidget);
      expect(boxOf(tester, copy), card);
      expect(find.descendant(of: find.byType(DrawnBoardBox), matching: copy), findsNothing);
      await finger.cancel();
      await tester.pump();
    });

    testWidgets('ends when it is cancelled, with nothing written', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final finger = await holdAt(tester, onWords(tester, 'ship-page'));
      await finger.moveTo(const Offset(60, 180));
      await tester.pump();
      expect(lifted(tester), isTrue);
      await finger.cancel();
      await tester.pump();
      expect(lifted(tester), isFalse);
      expect(tester.widgetList<BoardEmpty>(find.byType(BoardEmpty)), isEmpty);
      expect(inColumn(0, cardOf('ship-page')), findsOneWidget);
      expect(docOf(view), boardNote);
    });

    testWidgets('lands where the finger lets go, and the tick comes with it into Done', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final done = boxOf(tester, cardOf('pick-date'));
      final finger = await holdAt(tester, onWords(tester, 'ship-page'));
      // Across to Done, over the top half of its own card, so the card goes in above it; clear of the board's edge.
      await finger.moveTo(Offset(done.left + 30, done.top + 10));
      await tester.pump();
      expect(inColumn(1, keyed('gap')), findsOneWidget);
      expect(boxOf(tester, inColumn(1, keyed('gap'))).top, closeTo(done.top, 0.01), reason: 'the gap opens where the card would land');
      await finger.up();
      await tester.pump();
      await tester.pump();
      expect(lifted(tester), isFalse);
      expect(docOf(view), contains('```board\nTo do:\nDone: ship-page, pick-date\n```'));
      // Dragged into Done, the item is done: the note says so, not only the board.
      expect(docOf(view), contains('- [x] Ship the pricing page ^ship-page'));
      await rest(tester);
    });

    testWidgets('lands under a lane’s cards when the finger is below them', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final done = boxOf(tester, cardOf('pick-date'));
      final finger = await holdAt(tester, onWords(tester, 'ship-page'));
      await finger.moveTo(Offset(done.left + 30, done.bottom - 6));
      await tester.pump();
      await finger.up();
      await tester.pump();
      expect(docOf(view), contains('To do:\nDone: pick-date, ship-page'));
      await rest(tester);
    });

    testWidgets('writes nothing for a card put back where it was', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final at = onWords(tester, 'ship-page');
      final finger = await holdAt(tester, at);
      await finger.moveTo(at + const Offset(100, 6));
      await finger.moveTo(at + const Offset(4, 2));
      await finger.up();
      await tester.pump();
      expect(docOf(view), boardNote);
      await rest(tester);
    });

    testWidgets('pays no mind to another finger', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final finger = await tester.startGesture(onWords(tester, 'ship-page'), pointer: 5);
      await tester.pump(const Duration(milliseconds: 230));
      await tester.pump();
      final other = await tester.startGesture(const Offset(200, 500), pointer: 6);
      await other.moveTo(const Offset(320, 150));
      await other.up();
      await tester.pump();
      expect(lifted(tester), isTrue);
      expect(docOf(view), boardNote);
      await finger.cancel();
      await tester.pump();
      expect(lifted(tester), isFalse);
    });

    testWidgets('is not picked up by a finger that lets go, or moves away, before the hold is up', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      // Clear of the words' own tap, which would go to the line.
      final at = boxOf(tester, cardOf('ship-page')).bottomLeft + const Offset(40, -12);
      var finger = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 100));
      await finger.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(lifted(tester), isFalse);

      // A finger that moves first is scrolling the board: the card is left where it is.
      finger = await tester.startGesture(at);
      await finger.moveBy(const Offset(-30, 0));
      await finger.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(lifted(tester), isFalse);
      final across = tester.state<ScrollableState>(find.descendant(of: find.byType(DrawnBoardBox), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)).first);
      expect(across.position.pixels, greaterThan(0), reason: 'and the board scrolled under it');
      await finger.up();
      await tester.pumpAndSettle();
      expect(docOf(view), boardNote);
    });

    testWidgets('rolls the board along when it is held against its edge, and stops when it is let go', (tester) async {
      await pumpBoards(tester, '```board\nOne: a\nTwo:\nThree:\nFour:\n```\n\n- [ ] Card a ^a\n');
      final across = tester.state<ScrollableState>(find.descendant(of: find.byType(DrawnBoardBox), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)).first);
      final at = onWords(tester, 'a');
      final finger = await holdAt(tester, at);
      await finger.moveTo(Offset(380, at.dy));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(across.position.pixels, 3 * 14.0);
      expect(inColumn(1, keyed('gap')), findsOneWidget);
      // The gap follows what scrolls under a finger that is still: the next lane along comes under it.
      for (var frame = 0; frame < 12; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(across.position.pixels, 15 * 14.0);
      expect(inColumn(2, keyed('gap')), findsOneWidget);
      await finger.moveTo(Offset(200, at.dy));
      final rested = across.position.pixels;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(across.position.pixels, rested);
      await finger.cancel();
      await tester.pump();
    });

    testWidgets('is not picked up in a note that cannot be changed', (tester) async {
      await pumpBoards(tester, boardNote, readOnly: true);
      final finger = await holdAt(tester, onWords(tester, 'ship-page'));
      expect(lifted(tester), isFalse);
      await finger.up();
      await tester.pump();
    });
  });

  group('changing a card’s status keeps you on the board', () {
    testWidgets('ticks the card and moves it to Done without going to the line', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await press(tester, 'Tick Ship the pricing page');
      expect(docOf(view), contains('- [x] Ship the pricing page ^ship-page'));
      expect(docOf(view), contains('Done: pick-date, ship-page'));
      expect(caretLine(view), 1);
      await rest(tester);
    });

    testWidgets('ignores a press on the words that comes straight after, the one a finger a little off makes', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await press(tester, 'Tick Ship the pricing page');
      now = now.add(const Duration(milliseconds: 200));
      await tester.tap(inCard('ship-page', 'words'));
      await tester.pump();
      expect(caretLine(view), 1, reason: 'the note must not have gone to the line');
      await rest(tester);
    });

    testWidgets('shows the card where it landed with a short flash, so the eye finds it', (tester) async {
      await pumpBoards(tester, boardNote);
      await tester.tap(said('Tick Ship the pricing page'));
      // Over two frames: the board is redrawn by the change, and the card is in its new lane after that.
      await tester.pump();
      await tester.pump();
      expect(inColumn(1, cardOf('ship-page')), findsOneWidget);
      expect(tester.widget<BoardCard>(cardOf('ship-page')).arrived, isTrue);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();
      expect(tester.widget<BoardCard>(cardOf('ship-page')).arrived, isFalse);
    });

    testWidgets('still goes to the line when the words are pressed on their own, a moment later', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await press(tester, 'Tick Ship the pricing page');
      await rest(tester);
      now = now.add(const Duration(seconds: 1));
      await tester.tap(inCard('ship-page', 'words'));
      await tester.pump();
      expect(view.state.doc.line(caretLine(view)).text, contains('Ship the pricing page'));
    });

    testWidgets('unticks a card in Done and sends it back to the first lane', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await press(tester, 'Untick Pick a launch date');
      expect(docOf(view), contains('- [ ] Pick a launch date ^pick-date'));
      expect(docOf(view), contains('To do: ship-page, pick-date\nDone:'));
      await rest(tester);
    });

    testWidgets('steps a card a lane along with its arrows, which stop at either end', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      expect(tester.getSemantics(find.descendant(of: cardOf('ship-page'), matching: said('Move left: Ship the pricing page'))), isSemantics(isButton: true, hasEnabledState: true, isEnabled: false, label: 'Move left: Ship the pricing page'));
      await tester.tap(said('Move left: Ship the pricing page'));
      await tester.pump();
      expect(docOf(view), boardNote);
      await press(tester, 'Move right: Ship the pricing page');
      expect(docOf(view), contains('To do:\nDone: pick-date, ship-page'));
      // The arrows move the card, not the tick: the box is the item's own.
      expect(docOf(view), contains('- [ ] Ship the pricing page ^ship-page'));
      await rest(tester);
    });

    testWidgets('each edit is one undo, however fast they come', (tester) async {
      final view = await pumpBoards(tester, boardNote, more: <Extension>[history()]);
      await press(tester, 'Tick Ship the pricing page');
      final ticked = docOf(view);
      // No waiting for the board to finish coming across to Done: a second tap straight after is still a tap.
      await press(tester, 'Untick Pick a launch date');
      final both = docOf(view);
      expect(both, isNot(ticked));
      expect(undo(view), isTrue);
      expect(docOf(view), ticked, reason: 'one Undo takes back the last thing done to the board, and only that');
      expect(undo(view), isTrue);
      expect(docOf(view), boardNote);
      expect(undo(view), isFalse);
      await rest(tester);
    });

    testWidgets('holds its height while cards move, so nothing under the finger moves', (tester) async {
      await pumpBoards(tester, '```board\nTo do: a, b, c\nDone:\n```\n\n- [ ] Card a ^a\n- [ ] Card b ^b\n- [ ] Card c ^c\n');
      final before = boxOf(tester, find.byType(DrawnBoardBox));
      final lane = boxOf(tester, keyed('stack0'));
      // To the pixel, as the page pins it.
      expect(lane.height, lane.height.roundToDouble());
      await press(tester, 'Tick Card a');
      await press(tester, 'Tick Card b');
      await press(tester, 'Tick Card c');
      await rest(tester);
      expect(boxOf(tester, find.byType(DrawnBoardBox)), before);
      expect(boxOf(tester, keyed('stack1')).height, lane.height);
      expect(inColumn(1, find.byType(BoardCard)), findsNWidgets(3));
    });
  });

  group('a slow tap on a card’s controls', () {
    testWidgets('does not pick the card up, however long the finger rests on the tick', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final finger = await tester.startGesture(boxOf(tester, inCard('ship-page', 'tick')).center);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(keyed('gap'), findsNothing, reason: 'the card must not lift from its tick box');
      await finger.up();
      await tester.pump();
      expect(docOf(view), contains('- [x] Ship the pricing page ^ship-page'));
      await rest(tester);
    });

    testWidgets('still picks the card up from its words', (tester) async {
      await pumpBoards(tester, boardNote);
      final finger = await tester.startGesture(boxOf(tester, inCard('ship-page', 'words')).topLeft + const Offset(20, 8));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(keyed('gap'), findsOneWidget);
      await finger.cancel();
      await tester.pump();
    });

    testWidgets('takes a finger that lands a little off the box, rather than going to the line', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await tester.tapAt(boxOf(tester, inCard('ship-page', 'tick')).bottomLeft + const Offset(-5, 6));
      await tester.pump();
      expect(docOf(view), contains('- [x] Ship the pricing page ^ship-page'));
      expect(caretLine(view), 1);
      await rest(tester);
    });

    testWidgets('does nothing for a finger that slid off the control before it lifted', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final finger = await tester.startGesture(boxOf(tester, inCard('ship-page', 'tick')).center);
      await finger.moveBy(const Offset(120, 0));
      await finger.up();
      await tester.pumpAndSettle();
      expect(docOf(view), boardNote);
    });
  });

  group('the line under a board', () {
    final sizedNote = boardNote.replaceFirst('```board', '```board height=18');

    testWidgets('is a separator under every board, and draws a height the fence sets', (tester) async {
      await pumpBoards(tester, sizedNote);
      final look = BoardLook.of(tester.element(find.byType(DrawnBoardBox)), null);
      expect(tester.getSemantics(said('Board height')).value, '18');
      // A handle to take hold of, at its middle: the plain grip pill.
      final line = boxOf(tester, keyed('board-split')), grip = boxOf(tester, keyed('board-grip'));
      expect(grip.center.dx, closeTo(line.center.dx, 0.01));
      expect(grip.center.dy, closeTo(line.center.dy, 0.01));
      expect(boxOf(tester, keyed('stack0')).height, closeTo(18 * look.em, 0.02));
      expect(boxOf(tester, keyed('stack1')).height, closeTo(18 * look.em, 0.02));
    });

    testWidgets('steps for a screen reader, writing the fence each time', (tester) async {
      final view = await pumpBoards(tester, sizedNote);
      final handle = tester.ensureSemantics();
      tester.semantics.performAction(find.semantics.byLabel('Board height'), SemanticsAction.increase);
      await tester.pump();
      expect(docOf(view), contains('```board height=19\n'));
      tester.semantics.performAction(find.semantics.byLabel('Board height'), SemanticsAction.decrease);
      await tester.pump();
      tester.semantics.performAction(find.semantics.byLabel('Board height'), SemanticsAction.decrease);
      await tester.pump();
      expect(docOf(view), contains('```board height=17\n'));
      expect(tester.getSemantics(said('Board height')).value, '17');
      handle.dispose();
    });

    // Missing 15 (docs/PARITY.md): the height line by the keyboard (boards/divider.ts `keydown`): an em up or down by
    // the arrows, either end by Home and End, each written into the fence; and no other key is taken.
    testWidgets('is stepped by the arrow keys and sent to either end by Home and End, once the keyboard has reached it', (tester) async {
      final view = await pumpBoards(tester, sizedNote);
      expect(docOf(view), contains('```board height=18\n'));
      final line = Focus.of(tester.element(keyed('board-split')));
      expect(line.debugLabel, 'Board height');
      // Not until it has the focus: an arrow in the note is the caret's.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(docOf(view), contains('```board height=18\n'));
      line.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(docOf(view), contains('```board height=19\n'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(docOf(view), contains('```board height=17\n'));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(docOf(view), contains('```board height=5\n'));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(docOf(view), contains('```board height=60\n'));
      // At its end an arrow further writes nothing more, and a letter is not the line's.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(docOf(view), contains('```board height=60\n'));
      await rest(tester);
    });

    testWidgets('goes back to the board’s own height on a double tap', (tester) async {
      final view = await pumpBoards(tester, sizedNote);
      final at = boxOf(tester, keyed('board-split')).center;
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await rest(tester);
      expect(docOf(view), contains('```board\nTo do:'));
      // Its own height again: the tallest lane's cards, to the pixel.
      expect(boxOf(tester, keyed('stack0')).height, lessThan(100));
      await rest(tester);
    });

    testWidgets('follows a drag as the board’s own state and writes the height when the finger lifts, and not at all when called off', (tester) async {
      final view = await pumpBoards(tester, sizedNote);
      final look = BoardLook.of(tester.element(find.byType(DrawnBoardBox)), null);
      var at = boxOf(tester, keyed('board-split')).center;
      var finger = await tester.startGesture(at);
      // Past the slop, then five ems more.
      await finger.moveBy(const Offset(0, 20));
      await finger.moveBy(Offset(0, 5 * look.em));
      await tester.pump();
      // Drawn but not written.
      expect(tester.getSemantics(said('Board height')).value, isNot('18'));
      final drawn = boxOf(tester, keyed('stack0')).height / look.em;
      expect(drawn, greaterThan(22));
      expect(docOf(view), contains('```board height=18\n'));
      await finger.up();
      await tester.pump();
      await tester.pump();
      final written = RegExp(r'```board height=([\d.]+)\n').firstMatch(docOf(view))!.group(1)!;
      expect(double.parse(written), closeTo(drawn, 0.01));
      expect(double.parse(written) * 2, (double.parse(written) * 2).roundToDouble(), reason: 'to the half em');
      await rest(tester);

      at = boxOf(tester, keyed('board-split')).center;
      finger = await tester.startGesture(at);
      await finger.moveBy(const Offset(0, -20));
      await finger.moveBy(const Offset(0, -80));
      await tester.pump();
      expect(boxOf(tester, keyed('stack0')).height / look.em, lessThan(drawn - 3));
      await finger.cancel();
      await tester.pump();
      expect(docOf(view), contains('```board height=$written\n'));
      expect(boxOf(tester, keyed('stack0')).height / look.em, closeTo(drawn, 0.01));
      await rest(tester);
    });

    testWidgets('sets a height on a board that had none, from the height it was pinned at', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final look = BoardLook.of(tester.element(find.byType(DrawnBoardBox)), null);
      final finger = await tester.startGesture(boxOf(tester, keyed('board-split')).center);
      await finger.moveBy(const Offset(0, 20));
      await finger.moveBy(Offset(0, 6 * look.em));
      await tester.pump();
      await finger.up();
      await tester.pump();
      await tester.pump();
      await rest(tester);
      expect(docOf(view), matches(RegExp(r'```board height=1\d(\.5)?\n')));
      // A board with a set height has lanes that may say there is more below.
      expect(find.byType(WispFoot), findsNWidgets(2));
    });

    testWidgets('does not answer in a note that cannot be changed', (tester) async {
      final view = await pumpBoards(tester, sizedNote, readOnly: true);
      final finger = await tester.startGesture(boxOf(tester, keyed('board-split')).center);
      await finger.moveBy(const Offset(0, 20));
      await finger.moveBy(const Offset(0, 80));
      await finger.up();
      await tester.pumpAndSettle();
      expect(docOf(view), sizedNote);
    });
  });

  group('an empty column', () {
    // Matt: "add an icon when there are no items in a board like no todo items or no doing tasks".
    testWidgets('shows a picture and says it is empty, by what the column is for', (tester) async {
      await pumpBoards(tester, '```board\nTo do:\nDoing:\nDone: ship\nWaiting on Sam:\n```\n\n- [x] Ship it ^ship\n');
      // Only the empty ones show the place at rest.
      expect(<bool>[for (var c = 0; c < 4; c += 1) inColumn(c, find.byType(BoardEmpty)).evaluate().isNotEmpty], <bool>[true, true, false, true]);
      expect(<String>[for (final c in <int>[0, 1, 3]) tester.widget<BoardWords>(inColumn(c, keyed('empty-words'))).text], <String>['Nothing to do', 'Nothing in progress', 'Nothing to do']);
      expect(<String>[for (final c in <int>[0, 1, 3]) tester.widget<BoardIcon>(inColumn(c, keyed('empty-icon'))).name], <String>['todo', 'doing', 'todo']);
      // Held, a card is dropped on the same place, which says so.
      await showLane(tester, 1);
      final finger = await holdAt(tester, boxOf(tester, inCard('ship', 'words')).topLeft + const Offset(20, 8));
      expect(tester.widget<BoardWords>(inColumn(0, keyed('drop'))).text, 'Drop a card here');
      expect(keyed('empty-words'), findsNothing);
      await finger.cancel();
      await tester.pump();
    });

    testWidgets('stops being empty when a card arrives, and is empty again when it goes', (tester) async {
      final view = await pumpBoards(tester, '```board\nTo do:\nDone:\n```\n');
      expect(inColumn(0, find.byType(BoardEmpty)), findsOneWidget);
      await addTo(tester, 'To do');
      await typeCard(tester, 'Book the ferry');
      expect(inColumn(0, find.byType(BoardEmpty)), findsNothing);
      expect(inColumn(1, find.byType(BoardEmpty)), findsOneWidget);
      // Moved along with its arrow, the card leaves To do empty and Done not.
      await press(tester, 'Move right: Book the ferry');
      expect(docOf(view), contains('To do:\nDone: book-ferry'));
      expect(inColumn(0, find.byType(BoardEmpty)), findsOneWidget);
      expect(inColumn(1, find.byType(BoardEmpty)), findsNothing);
      await rest(tester);
    });

    test('reads the common column names, and gives any other the plain tray', () {
      expect(emptyLook('Backlog'), (icon: 'todo', words: 'Nothing to do'));
      expect(emptyLook('In progress'), (icon: 'doing', words: 'Nothing in progress'));
      expect(emptyLook('Done'), (icon: 'done', words: 'Nothing done yet'));
      expect(emptyLook('Ideas'), (icon: 'inbox', words: 'No cards'));
    });
  });

  group('a tap on a card’s words', () {
    testWidgets('puts the caret at the end of the item’s words, before its mark and anchor', (tester) async {
      const url = 'https://app.notion.com/p/x';
      final view = await pumpBoards(tester, '```board\nTo do: ship\n```\n\n- [ ] Ship it [notion]($url) ^ship\n');
      await tester.tap(inCard('ship', 'words'));
      await tester.pump();
      final head = view.state.selection.main.head;
      final line = view.state.doc.lineAt(head);
      expect(line.text.substring(0, head - line.from), '- [ ] Ship it');
      expect(view.hasFocus, isTrue);
    });

    testWidgets('goes nowhere from a card whose item is gone', (tester) async {
      final view = await pumpBoards(tester, '```board\nTo do: lost\n```\n\nwords\n');
      expect(wordsOf(tester, 'lost'), '^lost');
      expect(said('lost: this item is not in the note'), findsOneWidget);
      await tester.tap(inCard('lost', 'words'));
      await tester.pump();
      expect(view.hasFocus, isFalse);
      // Nothing to tick.
      expect(tester.getSemantics(said('Tick ^lost')), isSemantics(isButton: true, hasEnabledState: true, isEnabled: false, label: 'Tick ^lost'));
    });

    testWidgets('says New card for a card the + has just written with no words yet', (tester) async {
      await pumpBoards(tester, '```board\nTo do: item\n```\n\n- [ ]  ^item\n');
      expect(wordsOf(tester, 'item'), 'New card');
    });
  });

  group('a board not yet on the screen', () {
    // The editor sizes what it has not drawn by the widget's own guess: a board used to be one line tall until it was
    // drawn, and the note jumped by the difference as it came into view (Matt: "scrolling past boards is glitchy and
    // stops scroll momentum").
    double height(String text) {
      rememberBoardHeights = false;
      final state = EditorState.create(doc: text, extensions: drawnBoards());
      final found = <double>[];
      drawnBoardsIn(state).between(0, state.doc.length, (from, to, value) {
        found.add((value as PointDecoration).widget!.estimatedHeight);
        return null;
      });
      return found.single;
    }

    test('is as tall as its cards, not one line', () {
      final two = height(boardNote);
      expect(two, greaterThan(120));
      final more = '${boardNote.replaceFirst('To do: ship-page', 'To do: ship-page, a1, a2, a3')}- [ ] One ^a1\n- [ ] Two ^a2\n- [ ] Three ^a3\n';
      expect(height(more), greaterThan(two + 150));
    });

    test('gives long words more lines, and a set height its own', () {
      final long = boardNote.replaceFirst('Ship the pricing page', 'Ship the pricing page and the launch post and the changelog and the rest of it');
      expect(height(long), greaterThan(height(boardNote)));
      final set = height(boardNote.replaceFirst('```board', '```board height=30'));
      final taller = height(boardNote.replaceFirst('```board', '```board height=40'));
      expect((taller - set).round(), (10 * drawnBoardType.board).round());
    });

    testWidgets('is remembered at the height it was drawn, by what it shows, and guessed near it before that', (tester) async {
      await pumpBoards(tester, boardNote);
      final drawn = boxOf(tester, find.byType(DrawnBoardBox)).height;
      // The guess, in the type the board was just drawn in, is within a line of it.
      rememberBoardHeight('nothing', 1, note: BoardLook.of(tester.element(find.byType(DrawnBoardBox)), null).note);
      expect((height(boardNote) - drawn).abs(), lessThan(28));
      rememberBoardHeights = true;
      addTearDown(() => rememberBoardHeights = false);
      final state = EditorState.create(doc: boardNote, extensions: drawnBoards());
      final board = boardsOn(state).single;
      rememberBoardHeight(faceOf(board), drawn, note: 17.45);
      expect(estimatedBoardHeight(board, faceOf(board)), closeTo(drawn, 0.05));
      // Past the memory's own write.
      await tester.pump(const Duration(milliseconds: 600));
    });
  });

  group('where a board is drawn', () {
    testWidgets('steps aside for its lines while the caret is in the fence, and is drawn again when it leaves', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      expect(find.byType(DrawnBoardBox), findsOneWidget);
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(boardNote.indexOf('To do:') + 2)));
      await tester.pump();
      expect(find.byType(DrawnBoardBox), findsNothing);
      expect(drawnLines(tester).length, 10);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(DrawnBoardBox), findsOneWidget);
    });

    testWidgets('draws every board in the note, and none for a fence with no end', (tester) async {
      await pumpBoards(tester, '```board\nA: one\n```\n\n- [ ] One ^one\n\n```board\nB:\nC:\n```\n\n```board\nD:');
      expect(find.byType(DrawnBoardBox), findsNWidgets(2));
    });

    testWidgets('is redrawn in place when the note changes above it, its cards naming the lines they are on now', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final state = tester.state(find.byType(DrawnBoardBox));
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'A line\nand another\n')));
      await tester.pump();
      expect(tester.state(find.byType(DrawnBoardBox)), same(state));
      await press(tester, 'Tick Ship the pricing page');
      expect(docOf(view), contains('- [x] Ship the pricing page ^ship-page'));
      expect(docOf(view), startsWith('A line\nand another\n# Launch week'));
      await rest(tester);
    });

    testWidgets('keeps its pointers from the note: a drawn board answers a press itself', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      final hit = view.hitAt(boxOf(tester, cardOf('ship-page')).center)!;
      expect(isDrawnBlock(hit.block), isTrue);
      expect(hit.block!.takesPointer(const PointerDownEvent()), isTrue);
    });
  });

  group('lanes scrolling sideways', () {
    const wide = '```board\nOne: a\nTwo:\nThree:\nFour:\n```\n\n- [ ] Card a ^a\n';
    ScrollableState across(WidgetTester tester) =>
        tester.state<ScrollableState>(find.descendant(of: find.byType(DrawnBoardBox), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)).first);

    testWidgets('a swipe settles on a column, its start where the note’s words start', (tester) async {
      await pumpBoards(tester, wide);
      final look = BoardLook.of(tester.element(find.byType(DrawnBoardBox)), null);
      final step = look.columnWidth + look.columnGap;
      final from = boxOf(tester, keyed('head0')).center;
      await tester.dragFrom(from, const Offset(-70, 0));
      await tester.pumpAndSettle();
      expect(across(tester).position.pixels, 0, reason: 'dragged a little way: back to the column it was on');
      await tester.dragFrom(from, const Offset(-170, 0));
      await tester.pumpAndSettle();
      expect(across(tester).position.pixels, closeTo(step, 0.01), reason: 'dragged past half way: on to the next column');
      expect(boxOf(tester, keyed('column1')).left, closeTo(look.bleed, 0.01));
      await tester.dragFrom(from, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(across(tester).position.pixels, closeTo(step, 0.01), reason: 'not far enough to leave the column it is on');
      await tester.fling(find.byType(DrawnBoardBox), const Offset(-200, 0), 3000);
      await tester.pumpAndSettle();
      final rested = across(tester).position.pixels;
      expect(rested == across(tester).position.maxScrollExtent || (rested / step - (rested / step).round()).abs() < 0.001, isTrue, reason: 'a fling rests on a column or at the board’s end');
    });

    test('rests where the columns start, and at the end of a board whose last column cannot reach the start', () {
      final physics = LaneSnapPhysics(snap: LaneSnap()..step = 266.5);
      FixedScrollMetrics at(double pixels) => FixedScrollMetrics(minScrollExtent: 0, maxScrollExtent: 710, pixels: pixels, viewportDimension: 390, axisDirection: AxisDirection.right, devicePixelRatio: 2);
      const tolerance = Tolerance(velocity: 1, distance: 0.5);
      expect(physics.target(at(100), 0, tolerance), 0);
      expect(physics.target(at(140), 0, tolerance), 266.5);
      expect(physics.target(at(100), 500, tolerance), 266.5);
      expect(physics.target(at(300), -500, tolerance), 266.5 * 1 - 0, reason: 'back toward the column it was leaving');
      expect(physics.target(at(690), 0, tolerance), 710);
      expect(physics.createBallisticSimulation(at(266.5), 0), isNull);
      expect(physics.createBallisticSimulation(at(710), 100), isNull);
      // A card held: the board settles on nothing.
      physics.snap.held = true;
      expect(physics.createBallisticSimulation(at(140), 0), isNull);
    });

    testWidgets('a finger going up or down on the board scrolls the note, not the board', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpBoards(tester, '$wide${'line\n' * 60}', scroll: scroll, height: 500);
      await tester.dragFrom(boxOf(tester, keyed('head0')).center, const Offset(0, -120));
      await tester.pump();
      expect(scroll.offset, greaterThan(80));
      expect(across(tester).position.pixels, 0);
    });
  });

  group('a lane and the note', () {
    final cards = <String>[for (var n = 1; n <= 8; n += 1) 'c$n'];
    final tall = '```board height=9\nTo do: ${cards.join(', ')}\nDone:\n```\n\n${<String>[for (final id in cards) '- [ ] Card $id ^$id'].join('\n')}\n${'line\n' * 60}';
    ScrollPosition lane(WidgetTester tester, int column) => tester.state<ScrollableState>(find.descendant(of: keyed('stack$column'), matching: find.byType(Scrollable)).first).position;

    testWidgets('a lane with more cards than it shows scrolls inside itself, and says so at its foot', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpBoards(tester, tall, scroll: scroll, height: 600);
      expect(lane(tester, 0).maxScrollExtent, greaterThan(200));
      expect(tester.widget<WispFoot>(find.descendant(of: keyed('stack0'), matching: find.byType(WispFoot))).more, isTrue);
      expect(tester.widget<WispFoot>(find.descendant(of: keyed('stack1'), matching: find.byType(WispFoot))).more, isFalse);
      await tester.dragFrom(boxOf(tester, keyed('stack0')).center, const Offset(0, -60));
      await tester.pump();
      await tester.pump();
      expect(lane(tester, 0).pixels, greaterThan(30));
      expect(scroll.offset, 0, reason: 'the lane took the finger');
      // At its foot there is no more below, and the fade goes.
      lane(tester, 0).jumpTo(lane(tester, 0).maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<WispFoot>(find.descendant(of: keyed('stack0'), matching: find.byType(WispFoot))).more, isFalse);
    });

    testWidgets('at either end of a lane the finger goes on to the note', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpBoards(tester, tall, scroll: scroll, height: 600);
      final room = lane(tester, 0).maxScrollExtent;
      lane(tester, 0).jumpTo(room - 20);
      await tester.pump();
      final finger = await tester.startGesture(boxOf(tester, keyed('stack0')).center);
      await finger.moveBy(const Offset(0, -30));
      await finger.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(lane(tester, 0).pixels, room, reason: 'the lane scrolled to its foot first');
      await finger.moveBy(const Offset(0, -50));
      await finger.moveBy(const Offset(0, -50));
      await tester.pump();
      expect(scroll.offset, greaterThan(90), reason: 'and then the note took what the lane could not');
      await finger.up();
      await tester.pumpAndSettle();
      // And back up: the note first has nothing to give at its top, so the lane scrolls; at the lane's top, the note.
      scroll.jumpTo(50);
      lane(tester, 0).jumpTo(30);
      await tester.pump();
      await tester.dragFrom(boxOf(tester, keyed('stack0')).center, const Offset(0, 90));
      await tester.pump();
      expect(lane(tester, 0).pixels, 0);
      expect(scroll.offset, lessThan(20));
    });

    testWidgets('a lane that shows every card takes no drag at all: the note scrolls under a finger on it', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpBoards(tester, tall, scroll: scroll, height: 600);
      expect(lane(tester, 1).maxScrollExtent, 0);
      // The second lane, the empty one, a little way in from the board's left edge.
      final at = Offset(boxOf(tester, keyed('stack1')).left + 30, boxOf(tester, keyed('stack1')).center.dy);
      await tester.dragFrom(at, const Offset(0, -100));
      await tester.pump();
      expect(scroll.offset, greaterThan(60));
    });
  });

  group('a card’s own menu', () {
    // Matt: "Add context menu to board items for moving lanes and adding to notion etc.", and since: "Allow the header
    // to be overlapped by the popup menus use the glacierUI context menus". The kit's menu, over the page.
    testWidgets('opens over the page, hung from its card, with every other lane, the tick, the line and taking it off', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await openMenu(tester, 'Ship the pricing page');
      expect(menuRows(tester), <String>['Move to Done', 'Tick', 'Go to the line', 'Take off the board']);
      expect(cardMenuIn(view), isTrue);
      // Under its button, by the button's end.
      final more = boxOf(tester, inCard('ship-page', 'more'));
      final first = tester.getRect(find.text('Move to Done'));
      expect(first.top, greaterThan(more.bottom));
      // Opening it wrote nothing.
      expect(docOf(view), boardNote);
      closeCardMenu(view);
      await rest(tester);
    });

    testWidgets('is only ever one: another card’s menu takes its place', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await openMenu(tester, 'Ship the pricing page');
      openCardMenu(view, boardsOn(view.state).single.cards[1], GlobalKey(), CardMoves(columns: boardsOn(view.state).single.columns, land: (_) {}, tick: () {}, takeOff: () {}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(openCardMenuOf(view).value!.card, 'pick-date');
      expect(<String>[for (final row in openCardMenuOf(view).value!.rows) row.label], <String>['Move to To do', 'Untick', 'Go to the line', 'Take off the board']);
      expect(find.text('Move to Done'), findsNothing);
      closeCardMenu(view);
      await rest(tester);
    });

    testWidgets('closes on the back gesture, on a change to the note, and on a second press of its button', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await openMenu(tester, 'Ship the pricing page');
      expect(backStack.goBack(), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(cardMenuIn(view), isFalse);
      expect(find.byType(GlacierMenuItem), findsNothing);

      await openMenu(tester, 'Ship the pricing page');
      expect(cardMenuIn(view), isTrue);
      // Its rows were the card as it was: a note that changed under them closes it.
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'Monday: ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(cardMenuIn(view), isFalse);

      final board = boardsOn(view.state).single;
      final key = GlobalKey();
      final moves = CardMoves(columns: board.columns, land: (_) {}, tick: () {}, takeOff: () {});
      openCardMenu(view, board.cards.first, key, moves);
      expect(cardMenuIn(view), isTrue);
      openCardMenu(view, board.cards.first, key, moves);
      expect(cardMenuIn(view), isFalse);
      expect(docOf(view), 'Monday: $boardNote');
      await rest(tester);
    });

    testWidgets('closes on a press on another card, which keeps its press to itself for its drag, and that card lifts as ever', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await openMenu(tester, 'Ship the pricing page');
      final finger = await tester.startGesture(boxOf(tester, inCard('pick-date', 'words')).topLeft + const Offset(20, 8));
      await tester.pump();
      expect(cardMenuIn(view), isFalse);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(inColumn(1, keyed('gap')), findsOneWidget);
      await finger.cancel();
      await rest(tester);
    });

    testWidgets('moves the card to another lane, ticking it on the way into Done', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await openMenu(tester, 'Ship the pricing page');
      await chooseRow(tester, 'Move to Done');
      expect(cardMenuIn(view), isFalse);
      expect(docOf(view), contains('To do:\nDone: pick-date, ship-page'));
      expect(docOf(view), contains('- [x] Ship the pricing page ^ship-page'));
      await rest(tester);
    });

    testWidgets('takes the card off the board and leaves its item where it is in the note', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await showLane(tester, 1);
      await openMenu(tester, 'Pick a launch date');
      await chooseRow(tester, 'Take off the board');
      expect(docOf(view), contains('To do: ship-page\nDone:\n```'));
      expect(docOf(view), contains('- [x] Pick a launch date ^pick-date'));
      expect(cardOf('pick-date'), findsNothing);
      await rest(tester);
    });

    testWidgets('goes to the line, the caret at the end of the item’s words and the focus in the note', (tester) async {
      final view = await pumpBoards(tester, boardNote);
      await openMenu(tester, 'Ship the pricing page');
      await chooseRow(tester, 'Go to the line');
      expect(cardMenuIn(view), isFalse);
      final head = view.state.selection.main.head;
      final line = view.state.doc.lineAt(head);
      expect(line.text.substring(0, head - line.from), '- [ ] Ship the pricing page');
      expect(view.hasFocus, isTrue);
      await rest(tester);
    });

    testWidgets('offers only to take a card off whose item has gone from the note', (tester) async {
      final view = await pumpBoards(tester, '```board\nTo do: lost\n```\n');
      await openMenu(tester, '^lost');
      expect(menuRows(tester), <String>['Take off the board']);
      closeCardMenu(view);
      await rest(tester);
    });

    testWidgets('offers what a plugin offers the item’s own line, before what a swipe would run by its words', (tester) async {
      var offered = 0;
      final swiped = <String>[];
      final actions = CardActions(
        suggest: (_) => <({int line, String label, Future<void> Function() run})>[(line: 8, label: 'Send to Notion', run: () async => offered += 1)],
        action: () => (label: 'Make a task', run: (text) async => swiped.add(text)),
      );
      await pumpBoards(tester, boardNote, actions: actions);
      await openMenu(tester, 'Ship the pricing page');
      expect(menuRows(tester), contains('Send to Notion'));
      await chooseRow(tester, 'Send to Notion');
      expect(offered, 1);

      // A line with no offer of its own is offered the swipe's action, run on the item's words.
      await showLane(tester, 1);
      await openMenu(tester, 'Pick a launch date');
      await chooseRow(tester, 'Make a task');
      expect(swiped, <String>['Pick a launch date']);
      await rest(tester);
    });

    testWidgets('has nothing to open in a note that cannot be changed', (tester) async {
      final view = await pumpBoards(tester, boardNote, readOnly: true);
      await tester.tap(inCard('ship-page', 'more'));
      await tester.pump();
      expect(cardMenuIn(view), isFalse);
      await tester.tapAt(boxOf(tester, inCard('ship-page', 'tick')).center);
      await tester.pump();
      expect(docOf(view), boardNote);
      expect(said('Add a card to To do'), findsOneWidget);
      await tester.tap(keyed('add0'));
      await tester.pump();
      expect(find.byType(BoardComposer), findsNothing);
    });
  });
}
