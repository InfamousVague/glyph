import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/band/band.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

/// `editor/ContextMenu.test.tsx`, case for case, over a real editor: the words the band offers, what Paste says
/// when nothing can be pasted, the actions, the Style page, where it sits, and what closes it.
///
/// What a press is - the `contextmenu` kept from the phone, the hold timed on empty paper, the drawn board and the
/// mouse left alone - is the input layer's to hear and to test (lib/editor/input); the band is opened here as that
/// layer will open it, through its controller. Those four cases of the web's are named below and skipped.
void main() {
  setUpAll(loadAppFonts);

  group('what opens the menu', () {
    testWidgets('opens on a press in the note', (tester) async {
      final rig = await pumpBand(tester, doc: 'some words', anchor: 0, head: 4);
      expect(find.byType(MenuBand), findsNothing);
      await hold(tester, rig);
      expect(rig.controller.page.label, 'Note actions');
      expect(find.bySemanticsLabel('Note actions'), findsOneWidget);
      expect(words(tester), containsAll(<String>['Cut', 'Copy', 'Select all', 'Style']));
      await away(tester);
    });

    testWidgets('does not open over a drawn board or diagram, which have menus of their own', (tester) async {}, skip: true); // The input layer's: which press asks for the menu.
    testWidgets('opens after a held press on empty paper, putting the caret where the finger is', (tester) async {}, skip: true); // The input layer's.
    testWidgets('leaves a held press on a drawn board or diagram to it, and a mouse to its right click', (tester) async {}, skip: true); // The input layer's.
    testWidgets('leaves a held press on a word to the phone, and one that moves to the scroll', (tester) async {}, skip: true); // The input layer's.

    // Not the web's: what the input layer is handed in their place.
    testWidgets('is asked for over the caret, and where the finger was when the view cannot say', (tester) async {
      final rig = await pumpBand(tester, doc: 'some words', anchor: 0, head: 4);
      final caret = rig.view.coordsAtPos(4)!;
      expect(heldAt(rig.view, const Offset(20, 20)), Held(x: (caret.left + caret.right) / 2, y: caret.top, from: 0, to: 4));
      rig.controller.open(const Held(x: 100, y: 500, from: 2, to: 2));
      await settle(tester);
      expect(rig.controller.isOpen, isTrue);
      expect(rig.controller.contains(rig.controller.rect!.center), isTrue);
      expect(rig.controller.contains(const Offset(100, 700)), isFalse);
      // No selection in what it was asked with: no Cut, whatever the editor's own selection is.
      expect(words(tester), isNot(contains('Cut')));
      await away(tester);
    });

    testWidgets('draws nothing without an editor, or before it is asked for', (tester) async {
      final controller = ContextBandController();
      addTearDown(controller.dispose);
      await pumpApp(tester, home: ContextBand(view: null, controller: controller));
      controller.open(const Held(x: 10, y: 10, from: 0, to: 0));
      await settle(tester);
      expect(find.byType(MenuBand), findsNothing);
      await away(tester);
    });
  });

  group('Paste', () {
    testWidgets('is offered only where something can read the clipboard', (tester) async {
      final rig = await pumpBand(tester, doc: 'words', clipboard: FakeClipboard(readable: false));
      await hold(tester, rig);
      expect(words(tester), isNot(contains('Paste')));
      await away(tester);
    });

    testWidgets('puts in the words the clipboard held, over the selection', (tester) async {
      final rig = await pumpBand(tester, doc: 'buy milk', anchor: 4, head: 8, clipboard: FakeClipboard(answer: (clip: const Clip(text: 'oat milk'), read: true)));
      await hold(tester, rig);
      await choose(tester, 'Paste');
      expect(rig.text, 'buy oat milk');
      expect(rig.view.state.selection.main.head, 12);
      expect(find.byType(MenuBand), findsNothing);
      await away(tester);
    });

    testWidgets('hands a picture the reader copied out to the screen, by its path', (tester) async {
      final pasted = <String>[];
      final rig = await pumpBand(
        tester,
        doc: 'words',
        clipboard: FakeClipboard(answer: (clip: const Clip(path: '/cache/shot.png'), read: true)),
        onPasteImage: (path) async => pasted.add(path),
      );
      await hold(tester, rig);
      await choose(tester, 'Paste');
      expect(pasted, <String>['/cache/shot.png']);
      await away(tester);
    });

    testWidgets('says what the reader said when it could not read', (tester) async {
      final rig = await pumpBand(tester, doc: 'words', clipboard: FakeClipboard(answer: (clip: const Clip(error: 'The clipboard is locked.'), read: true)));
      await hold(tester, rig);
      await choose(tester, 'Paste');
      expect(rig.said, <String>['The clipboard is locked.']);
      await away(tester);
    });

    testWidgets('does not call a clipboard it could not read empty', (tester) async {
      final rig = await pumpBand(tester, doc: 'words', clipboard: FakeClipboard(answer: (clip: const Clip(), read: false)));
      await hold(tester, rig);
      await choose(tester, 'Paste');
      expect(rig.said, <String>['Nothing came back from the clipboard. Copy it again, or tap into the note and paste from your keyboard.']);
      await away(tester);
    });

    testWidgets('calls it empty when the reader read it and found nothing', (tester) async {
      final rig = await pumpBand(tester, doc: 'words', clipboard: FakeClipboard(answer: (clip: const Clip(), read: true)));
      await hold(tester, rig);
      await choose(tester, 'Paste');
      expect(rig.said, <String>['Nothing on the clipboard to paste. Copy the words again, then hold here.']);
      await away(tester);
    });

    testWidgets('says it could not reach the clipboard when the reader refuses', (tester) async {
      final rig = await pumpBand(tester, doc: 'words', clipboard: FakeClipboard(refuses: true));
      await hold(tester, rig);
      await choose(tester, 'Paste');
      expect(rig.said, <String>['Ghost.md couldn’t reach the clipboard here. Tap into the note and paste from your keyboard instead.']);
      expect(rig.text, 'words');
      await away(tester);
    });
  });

  group('the actions', () {
    testWidgets('cuts the selection onto the clipboard', (tester) async {
      final rig = await pumpBand(tester, doc: 'buy oat milk', anchor: 4, head: 8);
      var focused = 0;
      rig.view.focusRequest = () => focused += 1;
      await hold(tester, rig);
      await choose(tester, 'Cut');
      expect(rig.clipboard.written, <String>['oat ']);
      expect(rig.text, 'buy milk');
      // Every action closes the menu before it runs, says its tick, and gives the editor its focus back after.
      expect(find.byType(MenuBand), findsNothing);
      expect(rig.felt, <HapticKind>[HapticKind.selection]);
      expect(focused, 1);
      await away(tester);
    });

    testWidgets('opens find with the selected words', (tester) async {
      final found = <String>[];
      final rig = await pumpBand(tester, doc: 'buy oat milk', anchor: 4, head: 7, onFind: found.add);
      await hold(tester, rig);
      await choose(tester, 'Find');
      expect(found, <String>['oat']);
      await away(tester);
    });

    testWidgets('offers Comment right after Cut and Copy, on the selection it was opened over, and gives the focus to its sheet', (tester) async {
      final asked = <({int from, int to})>[];
      final rig = await pumpBand(tester, doc: 'buy oat milk', anchor: 4, head: 7, onComment: asked.add);
      var focused = 0;
      rig.view.focusRequest = () => focused += 1;
      await hold(tester, rig);
      expect(words(tester).take(3), <String>['Cut', 'Copy', 'Comment']);
      await choose(tester, 'Comment');
      expect(asked, <({int from, int to})>[(from: 4, to: 7)]);
      expect(find.byType(MenuBand), findsNothing);
      expect(focused, 0);
      await away(tester);
    });

    testWidgets('offers Comment with no selection, for the caret’s line, and not at all without a way to start one', (tester) async {
      final asked = <({int from, int to})>[];
      var rig = await pumpBand(tester, doc: 'buy oat milk', anchor: 2, onComment: asked.add, clipboard: FakeClipboard(readable: false));
      await hold(tester, rig);
      expect(words(tester).first, 'Comment');
      await choose(tester, 'Comment');
      expect(asked, <({int from, int to})>[(from: 2, to: 2)]);
      await away(tester);
      rig = await pumpBand(tester, doc: 'buy oat milk', anchor: 2);
      await hold(tester, rig);
      expect(words(tester), isNot(contains('Comment')));
      await away(tester);
    });

    testWidgets('makes a board of the list the press is in, and says so', (tester) async {
      final rig = await pumpBand(tester, doc: '- [ ] milk\n- [x] eggs', anchor: 2, boards: true);
      await hold(tester, rig);
      await choose(tester, 'Board from list');
      expect(rig.text, contains('```board'));
      expect(rig.said, <String>['2 items are now a board, 1 in Done.']);
      expect(rig.felt, <HapticKind>[HapticKind.selection, HapticKind.success]);
      await away(tester);
    });

    testWidgets('adds an item to its list’s board, and copies the board whole', (tester) async {
      final rig = await pumpBand(tester, doc: '- [ ] milk\n- [ ] eggs', anchor: 2, boards: true);
      await hold(tester, rig);
      await choose(tester, 'Board from list');
      final end = rig.view.state.doc.length;
      rig.view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: '\n- [ ] bread'), selection: EditorSelection.single(end + 4)));
      await tester.pump();
      await hold(tester, rig);
      await choose(tester, 'Add to board');
      expect(rig.said.last, 'Added to To do.');
      rig.view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      await hold(tester, rig);
      await choose(tester, 'Copy board');
      expect(rig.clipboard.written.single, contains('```board'));
      await away(tester);
    });

    testWidgets('adds the line it was offered for, wherever the caret has gone while the menu was open', (tester) async {
      final rig = await pumpBand(tester, doc: '# List\n\n- [ ] milk\n- [ ] eggs', anchor: 10, boards: true);
      await hold(tester, rig);
      await choose(tester, 'Board from list');
      final end = rig.view.state.doc.length;
      rig.view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: '\n- [ ] bread'), selection: EditorSelection.single(end + 4)));
      await tester.pump();
      final bread = rig.view.state.doc.lines;
      await hold(tester, rig);
      // A keyboard on a desktop keeps the editor's focus while the menu is up, so the caret can move under it.
      rig.view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      await choose(tester, 'Add to board');
      expect(rig.said.last, 'Added to To do.');
      expect(rig.view.state.doc.line(bread).text, matches(RegExp(r'^- \[ \] bread \^\S+$')));
      await away(tester);
    });

    testWidgets('takes the whole of a board for a row that works on lines, not the one line pressed in it', (tester) async {
      final rig = await pumpBand(tester, doc: '- [ ] milk\n- [ ] eggs', anchor: 2, boards: true);
      await hold(tester, rig);
      await choose(tester, 'Board from list');
      expect(rig.text, contains('```board'));
      // Pressed on a column line inside the fence, as a press on a drawn board lands.
      rig.view.dispatch(TransactionSpec(selection: EditorSelection.single(rig.view.state.doc.line(2).from)));
      await tester.pump();
      await hold(tester, rig);
      await choose(tester, 'Delete');
      expect(rig.text, isNot(contains('```')));
      expect(rig.text, contains('milk'));
      expect(rig.text, contains('eggs'));
      await away(tester);
    });

    testWidgets('sends the line’s words, without the item’s marks, where a plugin takes them', (tester) async {
      final sent = <String>[];
      final rig = await pumpBand(tester, doc: '- [ ] Buy milk ^milk', anchor: 3, send: BandSend(label: 'Notion', run: sent.add));
      await hold(tester, rig);
      await choose(tester, 'Notion');
      expect(sent, <String>['Buy milk']);
      await away(tester);
    });

    // Not the web's cases: the rows its tests left to the commands' own (format.test.ts), run from the band once.
    testWidgets('selects all, duplicates, deletes and moves the caret’s line', (tester) async {
      final rig = await pumpBand(tester, doc: 'one\ntwo\nthree', anchor: 5);
      Future<void> press(String label) async {
        await hold(tester, rig);
        await choose(tester, label);
      }

      await press('Move up');
      expect(rig.text, 'two\none\nthree');
      await press('Move down');
      expect(rig.text, 'one\ntwo\nthree');
      await press('Duplicate');
      expect(rig.text, 'one\ntwo\ntwo\nthree');
      await press('Delete');
      expect(rig.text, 'one\ntwo\nthree');
      await press('Select all');
      expect((rig.view.state.selection.main.from, rig.view.state.selection.main.to), (0, 13));
      await away(tester);
    });

    testWidgets('leaves out the rows it was given no way to do, and keeps the web’s order with every one', (tester) async {
      var rig = await pumpBand(tester, doc: 'buy oat milk', anchor: 4, head: 7);
      await hold(tester, rig);
      expect(words(tester), <String>['Cut', 'Copy', 'Paste', 'Select all', 'Duplicate', 'Delete', 'Move up', 'Move down', 'Style']);
      await away(tester);
      rig = await pumpBand(tester, doc: '- [ ] buy oat milk', anchor: 10, head: 13, onComment: (_) {}, onFind: (_) {}, onAddImage: () {}, send: BandSend(label: 'Notion', run: (_) {}), fields: BandFields(items: (_, _) => const <Widget>[]), boards: true);
      await hold(tester, rig);
      expect(words(tester), <String>['Cut', 'Copy', 'Comment', 'Paste', 'Find', 'Select all', 'Duplicate', 'Delete', 'Move up', 'Move down', 'Due date', 'Priority', 'Assign', 'Board from list', 'Notion', 'Style', 'Add image']);
      await away(tester);
    });

    testWidgets('offers no Find for more than 120 characters, and no Comment on a note that cannot be written', (tester) async {
      final long = 'word ' * 30;
      var rig = await pumpBand(tester, doc: long, anchor: 0, head: 121, onFind: (_) {});
      await hold(tester, rig);
      expect(words(tester), isNot(contains('Find')));
      await away(tester);
      rig = await pumpBand(tester, doc: 'words', readOnly: true, onComment: (_) {}, fields: BandFields(items: (_, _) => const <Widget>[]));
      await hold(tester, rig);
      expect(words(tester), isNot(contains('Comment')));
      await away(tester);
    });
  });

  group('the Style page', () {
    testWidgets('keeps a pressed style on the page, lit, and goes back', (tester) async {
      final rig = await pumpBand(tester, doc: 'buy milk', anchor: 4, head: 8);
      await hold(tester, rig);
      await choose(tester, 'Style');
      expect(rig.controller.page.label, 'Styles');
      expect(find.bySemanticsLabel('Styles'), findsOneWidget);
      await choose(tester, 'Bold');
      expect(rig.text, 'buy **milk**');
      expect(tester.widget<BandItemBox>(row('Bold')).lit, isTrue);
      await choose(tester, "Back to the note's actions");
      expect(rig.controller.page.label, 'Note actions');
      expect(words(tester), contains('Style'));
      await away(tester);
    });

    testWidgets('ticks for its Back, as for every other row on the page', (tester) async {
      final rig = await pumpBand(tester, doc: 'buy milk', anchor: 4, head: 8);
      await hold(tester, rig);
      await choose(tester, 'Style');
      rig.felt.clear();
      await choose(tester, "Back to the note's actions");
      expect(rig.felt, <HapticKind>[HapticKind.selection]);
      await away(tester);
    });

    testWidgets('ticks for a field page’s Back too', (tester) async {
      final asked = <FieldItemsRequest>[];
      final fields = BandFields(
        items: (context, request) {
          asked.add(request);
          return <Widget>[
            if (request.onBack != null) MenuItem(icon: Lucide.chevronLeft, label: 'Back', onPress: request.onBack!, name: backName),
            MenuItem(icon: Lucide.calendarDays, label: 'Today', onPress: request.onClose),
          ];
        },
      );
      final rig = await pumpBand(tester, doc: '- [ ] Fix the login loop', anchor: 3, fields: fields);
      await hold(tester, rig);
      await choose(tester, 'Due date');
      expect(rig.controller.page.label, 'Fields');
      expect(asked.last.page, const FieldDatePage('due'));
      expect(asked.last.line, 1);
      rig.felt.clear();
      await choose(tester, "Back to the note's actions");
      expect(rig.controller.page.label, 'Note actions');
      expect(rig.felt, <HapticKind>[HapticKind.selection]);
      await away(tester);
    });

    testWidgets('wears nothing the kit’s tap tick would answer, since its rows say their own', (tester) async {
      final rig = await pumpBand(tester, doc: 'words');
      await hold(tester, rig);
      expect(find.descendant(of: find.byType(MenuBand), matching: find.byType(HapticTarget)), findsNothing);
      await away(tester);
    });

    testWidgets('closes the menu for an insert, which leaves nothing to keep lit', (tester) async {
      final rig = await pumpBand(tester, doc: 'words', anchor: 5);
      await hold(tester, rig);
      await choose(tester, 'Style');
      await choose(tester, 'Rule');
      expect(find.byType(MenuBand), findsNothing);
      expect(rig.text, contains('---'));
      await away(tester);
    });

    // Not the web's cases.
    testWidgets('lights the line’s form and a plugin’s formatting, and takes them off again', (tester) async {
      final rig = await pumpBand(tester, doc: 'buy milk', anchor: 4, head: 8, formats: pageFormats());
      await hold(tester, rig);
      await choose(tester, 'Style');
      expect(words(tester), <String>[for (final item in BandFixture.read('style').items) item['label'] as String]);
      await choose(tester, 'Spoiler');
      expect(rig.text, 'buy ||milk||');
      expect(tester.widget<BandItemBox>(row('Spoiler')).lit, isTrue);
      await choose(tester, 'To-do');
      expect(rig.text, '- [ ] buy ||milk||');
      expect(tester.widget<BandItemBox>(row('To-do')).lit, isTrue);
      await choose(tester, 'Spoiler');
      await choose(tester, 'To-do');
      expect(rig.text, 'buy milk');
      expect(rows(tester).where((one) => one.lit), isEmpty);
      // One tick a press, and the page still up.
      expect(rig.felt.length, 5);
      expect(rig.controller.page, BandPage.styles);
      await away(tester);
    });

    testWidgets('comes in out of smoke one row after another, and all at once with reduced motion', (tester) async {
      final rig = await pumpBand(tester, doc: 'buy milk', anchor: 4, head: 8);
      await hold(tester, rig);
      tester.widget<BandItemBox>(row('Style')).onPress();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      double seen(String label) {
        final fade = find.ancestor(of: row(label), matching: find.byType(Opacity));
        return fade.evaluate().isEmpty ? 1 : tester.widget<Opacity>(fade.first).opacity;
      }

      // Back is the menu's own row, there from the start; Bold is ahead of Rule.
      expect(seen("Back to the note's actions"), 1);
      expect(seen('Bold'), greaterThan(seen('Rule')));
      expect(seen('Rule'), 0);
      await settle(tester);
      expect(seen('Rule'), 1);
      await away(tester);
    });
  });

  group('where it sits', () {
    // The web's four cases are sums over sizes jsdom was told, and are in menu_room_test.dart; the band itself is
    // held to the page's rectangles in band_reference_test.dart. Here, the keyboard, which the page could not raise.
    testWidgets('never past the keyboard’s top', (tester) async {
      final rig = await pumpBand(tester, doc: 'some words', anchor: 0, head: 4, top: 0, inset: 36, size: const Size(390, 600), keyboard: 480);
      await hold(tester, rig);
      final band = rig.controller.rect!;
      // The window's 600 less a keyboard of 480 leaves 120: above the caret would reach the status bar, under it
      // would pass the keyboard, so the band's foot is held 8 over the keyboard's top.
      expect(band.bottom, closeTo(120 - 8, 0.5));
      expect(band.left, 8);
      await away(tester);
    });

    testWidgets('by the caret at a larger interface size too', (tester) async {
      final rig = await pumpBand(tester, doc: 'some words\n\nmore words here', anchor: 14, top: 300, uiScale: 1.25);
      await hold(tester, rig);
      final band = rig.controller.rect!;
      final caret = rig.view.coordsAtPos(14)!;
      // In the window's own pixels the 12 between the band's foot and the caret's top is 12 of the scaled ones
      // (less what rounding the band's height to a whole pixel leaves).
      expect((caret.top - band.bottom) / 1.25, inInclusiveRange(11.4, 12.6));
      expect(band.left, closeTo(8 * 1.25, 0.01));
      expect(rig.controller.contains(band.center), isTrue);
      await away(tester);
    });

    testWidgets('places the Style page again, by the same rule', (tester) async {
      final rig = await pumpBand(tester, doc: 'some words', anchor: 0, head: 4);
      await hold(tester, rig);
      final before = rig.controller.rect!;
      await choose(tester, 'Style');
      final after = rig.controller.rect!;
      expect(after.top, closeTo(before.top, 0.5));
      expect(after.size, before.size);
      await away(tester);
    });
  });

  group('what closes the menu', () {
    testWidgets('a touch anywhere else, but not on the menu', (tester) async {
      final rig = await pumpBand(tester, doc: 'words');
      await hold(tester, rig);
      final on = await tester.startGesture(rig.controller.rect!.center);
      await tester.pump();
      expect(find.byType(MenuBand), findsOneWidget);
      await on.cancel();
      await tester.pump();
      expect(find.byType(MenuBand), findsOneWidget);
      final off = await tester.startGesture(const Offset(200, 700));
      await tester.pump();
      expect(find.byType(MenuBand), findsNothing);
      expect(rig.controller.isOpen, isFalse);
      await off.up();
      await away(tester);
    });

    testWidgets('a scroll of the note, but not of the menu’s own band', (tester) async {
      final rig = await pumpBand(tester, doc: List<String>.filled(60, 'a line of the note').join('\n'), top: 0);
      await hold(tester, rig);
      final band = tester.state<MenuBandState>(find.byType(MenuBand));
      band.scroll.jumpTo(40);
      await tester.pump();
      await tester.pump();
      expect(find.byType(MenuBand), findsOneWidget);
      expect(band.more, 'start end');
      final note = Scrollable.of(tester.element(find.byType(ContextBand))).position;
      note.jumpTo(120);
      await tester.pump();
      expect(find.byType(MenuBand), findsNothing);
      await away(tester);
    });

    // Not the web's: the band round a note that scrolls, where the web heard every scroll on the document.
    testWidgets('a scroll of what it is wrapped round', (tester) async {
      final rig = await pumpBand(tester, doc: 'words');
      final controller = ContextBandController();
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        home: ContextBand(
          view: rig.view,
          controller: controller,
          child: ListView(children: <Widget>[for (var i = 0; i < 60; i++) const SizedBox(height: 40)]),
        ),
      );
      controller.open(const Held(x: 100, y: 400, from: 0, to: 0));
      await settle(tester);
      expect(find.byType(MenuBand), findsOneWidget);
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(80);
      await tester.pump();
      expect(find.byType(MenuBand), findsNothing);
      await away(tester);
    });

    testWidgets('the back gesture', (tester) async {
      final rig = await pumpBand(tester, doc: 'words');
      final stack = BackScope.of(tester.element(find.byType(ContextBand)));
      final depth = stack.depth;
      await hold(tester, rig);
      expect(stack.depth, depth + 1);
      expect(stack.goBack(), isTrue);
      await tester.pump();
      expect(find.byType(MenuBand), findsNothing);
      expect(stack.depth, depth);
      await away(tester);
    });

    // Not the web's: a row pressed with a finger, through the gesture arena, as the phone will press it.
    testWidgets('a row tapped does its work and closes it; a row held shows it is pressed', (tester) async {
      final rig = await pumpBand(tester, doc: 'buy oat milk', anchor: 4, head: 8);
      await hold(tester, rig);
      final at = tester.getCenter(row('Copy'));
      final finger = await tester.startGesture(at, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 150));
      final t = tester.element(find.byType(MenuBand)).tokens;
      final pressed = tester.widget<DecoratedBox>(find.descendant(of: row('Copy'), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
      expect(pressed.color, t.color('app-paper-3'));
      await finger.up();
      await settle(tester);
      expect(rig.clipboard.written, <String>['oat ']);
      expect(find.byType(MenuBand), findsNothing);
      await away(tester);
    });

    testWidgets('a chip tapped opens it on that field’s page, with nothing to go back to', (tester) async {
      final asked = <FieldItemsRequest>[];
      final fields = BandFields(
        items: (context, request) {
          asked.add(request);
          return <Widget>[MenuItem(icon: Lucide.flag, label: 'High', onPress: request.onClose)];
        },
      );
      final rig = await pumpBand(tester, doc: '- [ ] Fix the login loop', anchor: 3, fields: fields);
      rig.controller.openFields(rig.view, page: const FieldPriorityPage(), line: 1, at: const Offset(120, 400));
      await settle(tester);
      expect(rig.controller.page, BandPage.fields);
      expect(words(tester), <String>['High']);
      expect(asked.last.onBack, isNull);
      expect(asked.last.page, isA<FieldPriorityPage>());
      await choose(tester, 'High');
      expect(find.byType(MenuBand), findsNothing);
      await away(tester);
    });
  });
}
