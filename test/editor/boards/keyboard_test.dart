// The + field of a board and the note's own keyboard (lib/editor/boards/composer.dart): the editor is the one text
// input client of a note, and the field a card is typed into has to take the keyboard from it and give it back
// without either typing into the other. Drawn in the real `Editor` (test/editor/input/support.dart), with a
// scripted keyboard.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/boards/boards.dart';
import 'package:ghost_md/editor/state/state.dart' show Extension;

import '../../support/render.dart';
import '../input/support.dart';
import 'support.dart';

/// What the field's own client last told the keyboard it holds.
String fieldText(WidgetTester tester) => tester.state<BoardComposerState>(find.byType(BoardComposer)).controller.text;

void main() {
  setUpAll(loadAppFonts);
  setUp(() => rememberBoardHeights = false);

  testWidgets('the + takes the keyboard from the note: the editor lets go of it and the board stays drawn', (tester) async {
    final rig = await pumpEditor(tester, boardNote, more: <Extension>[drawnBoards()], caret: 3);
    await tester.pump();
    await tester.pump();
    expect(rig.view.hasFocus, isTrue);
    expect(rig.client.attached, isTrue);
    final attachesBefore = rig.ime.attaches;

    await tester.tap(said('Add a card to To do'));
    await tester.pump();
    await tester.pump();
    final composer = tester.state<BoardComposerState>(find.byType(BoardComposer));
    expect(composer.focusNode.hasPrimaryFocus, isTrue);
    // The editor is not focused through the field: its connection is closed, and its view says so.
    expect(rig.view.hasFocus, isFalse);
    expect(rig.client.attached, isFalse);
    expect(find.byType(DrawnBoardBox), findsOneWidget);
    // A new client has the keyboard, set up for a card's words, and the keyboard was never told to go.
    expect(rig.ime.attaches, attachesBefore + 1);
    expect(tester.testTextInput.setClientArgs!['inputAction'], 'TextInputAction.done');
    expect(tester.testTextInput.isVisible, isTrue);
    await finish(tester);
  });

  testWidgets('what is typed goes into the card, not the note, and the field keeps the keyboard from card to card', (tester) async {
    final rig = await pumpEditor(tester, boardNote, more: <Extension>[drawnBoards()], caret: 3);
    await tester.tap(said('Add a card to To do'));
    await tester.pump();
    await tester.pump();
    final client = rig.ime.client;
    tester.testTextInput.enterText('Book the ferry');
    await tester.pump();
    expect(rig.doc, boardNote, reason: 'typing in the field writes nothing to the note');
    expect(fieldText(tester), 'Book the ferry');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(rig.doc, contains('- [ ] Book the ferry ^book-ferry\n'));
    expect(rig.doc, contains('To do: book-ferry, ship-page'));
    // The same field, emptied, still the keyboard's client; the editor did not take it back to write the card.
    final composer = tester.state<BoardComposerState>(find.byType(BoardComposer));
    expect(composer.controller.text, '');
    expect(composer.focusNode.hasPrimaryFocus, isTrue);
    expect(rig.ime.client, client);
    expect(rig.client.attached, isFalse);
    expect(rig.view.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isTrue);

    tester.testTextInput.enterText('Pack the tent');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(rig.doc, contains('To do: pack-tent, book-ferry, ship-page'));
    expect(rig.events.where((event) => event == 'input.board').length, 2);
    await tester.pump(const Duration(milliseconds: 200));
    await finish(tester);
  });

  testWidgets('a key the field does not take never reaches the note', (tester) async {
    final rig = await pumpEditor(tester, boardNote, more: <Extension>[drawnBoards()], caret: 3);
    await tester.tap(said('Add a card to To do'));
    await tester.pump();
    await tester.pump();
    tester.testTextInput.enterText('ab');
    await tester.pump();
    // A hardware Backspace, arrows and Enter: the field's, or nobody's.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(rig.doc, boardNote);
    expect(rig.head, 3);
    expect(fieldText(tester), hasLength(1), reason: 'the app’s own text keys still edit the field, and it alone');
    await finish(tester);
  });

  testWidgets('a tap on the note gives the keyboard back to the editor, and the empty field closes', (tester) async {
    final rig = await pumpEditor(tester, boardNote, more: <Extension>[drawnBoards()], caret: 3);
    await tester.tap(said('Add a card to To do'));
    await tester.pump();
    await tester.pump();
    expect(rig.client.attached, isFalse);
    await tester.tapAt(rig.point(rig.at('Launch', 2)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.view.hasFocus, isTrue);
    expect(rig.client.attached, isTrue);
    expect(find.byType(BoardComposer), findsNothing);
    await rig.ime.type('x');
    expect(rig.doc, startsWith('# Lax'), reason: 'and the keyboard types in the note again');
    await finish(tester);
  });

  testWidgets('ticking a card while the note has the keyboard leaves the caret and the keyboard where they were', (tester) async {
    final rig = await pumpEditor(tester, boardNote, more: <Extension>[drawnBoards()], caret: 3);
    final attaches = rig.ime.attaches;
    await tester.tap(said('Tick Ship the pricing page'));
    await tester.pump();
    await tester.pump();
    expect(rig.doc, contains('- [x] Ship the pricing page ^ship-page'));
    expect(rig.head, 3);
    expect(rig.view.hasFocus, isTrue);
    expect(rig.client.attached, isTrue);
    expect(rig.ime.attaches, attaches);
    expect(rig.held, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await finish(tester);
  });

  testWidgets('a press held on a card lifts the card, and is never the note’s long press', (tester) async {
    final rig = await pumpEditor(tester, boardNote, more: <Extension>[drawnBoards()], caret: 3);
    final finger = await tester.startGesture(boxOf(tester, inCard('ship-page', 'words')).topLeft + const Offset(20, 8));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(keyed('gap'), findsOneWidget);
    expect(rig.held, isEmpty, reason: 'the note’s menu is for the words, not for a card');
    expect(rig.head, 3);
    await finger.cancel();
    await tester.pump();
    await finish(tester);
  });
}
