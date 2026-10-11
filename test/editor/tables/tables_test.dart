// Ports the drawn cases of tauri/src/app/editor/tables.test.ts ("a table drawn in a note") case for case, then
// what tables.ts does that its test leaves to the eye: the grow buttons, alignment, sideways scrolling. The cases
// that only read and grow a table's text are test/editor/commands/tables_test.dart.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/tables.dart' show TableAlign;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/tables/tables.dart';
import 'package:ghost_md/editor/markdown_view.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/sliver.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

String _shown(WidgetTester tester) => drawnLines(tester).map((line) => line.spec.projection.display).join('\n');

/// A test that draws the app: the switch for shadows `pumpApp` turned on is put back before the binding checks it.
void drawing(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    debugDisableShadows = true;
  });
}

void main() {
  setUpAll(loadAppFonts);

  // What every drawn block shares (view/drawn_block.dart), proven on the simplest of them.
  group('a table drawn in a note', () {
    final doc = ['Before', '', '| Bug | Owner |', '| --- | --- |', '| Seek **bar** | Matt |', '', 'After'].join('\n');
    final tableAt = doc.indexOf('| Bug');

    Future<EditorView> open(WidgetTester tester, {bool readOnly = false}) => pumpTables(tester, doc, readOnly: readOnly);
    Future<void> press(WidgetTester tester) async {
      await tester.tap(find.byType(GlyphTable));
      await tester.pump();
    }

    drawing('is drawn with its header and rows, their markup as words, in a view that has never had focus', (tester) async {
      final on = await open(tester);
      on.dispatch(TransactionSpec(selection: EditorSelection.single(tableAt + 3)));
      await tester.pump();
      // Not focused: a caret in the table's range still leaves it drawn, since nobody is typing.
      final table = drawnTable(tester)!.table;
      expect(table.cells[0][0].text, 'Bug');
      expect(table.cells[0][0].head, isTrue);
      expect(table.cells[1][0].text, 'Seek bar');
      expect(table.cells[1][0].head, isFalse);
    });

    drawing('steps aside for its pipes when a press puts the caret in it, and is drawn again when the caret leaves', (tester) async {
      final on = await open(tester);
      await press(tester);
      expect(on.hasFocus, isTrue);
      expect(on.state.selection.main.head, tableAt);
      expect(drawnTable(tester), isNull);
      expect(drawnTablesIn(on.state).size, 0);
      expect(_shown(tester), contains('| Bug | Owner |'));

      on.dispatch(TransactionSpec(selection: EditorSelection.single(doc.length)));
      await tester.pump();
      expect(drawnTable(tester), isNotNull);
    });

    drawing('is drawn again when the note loses focus, wherever the caret was left', (tester) async {
      final on = await open(tester);
      on.focus();
      on.dispatch(TransactionSpec(selection: EditorSelection.single(tableAt + 3)));
      await tester.pump();
      expect(drawnTable(tester), isNull);
      on.setFocused(false);
      await tester.pump();
      expect(drawnTable(tester), isNotNull);
    });

    drawing('stays drawn in a view that cannot be edited, where a press does not open it', (tester) async {
      final on = await open(tester, readOnly: true);
      await press(tester);
      // Opening would have put the caret at the table's first line; the view's own handling of the press is its own.
      expect(on.state.selection.main.head, isNot(tableAt));
      expect(drawnTable(tester), isNotNull);
      // And nothing to grow it with.
      expect(find.byType(TableGrowButton), findsNothing);
    });

    drawing('a caret at either edge of the table is in it, and a line away is not', (tester) async {
      final on = await open(tester);
      on.focus();
      for (final (at, drawn) in <(int, bool)>[(tableAt, false), (doc.indexOf('\n\nAfter'), false), (tableAt - 1, true), (doc.indexOf('After') - 1, true)]) {
        on.dispatch(TransactionSpec(selection: EditorSelection.single(at)));
        await tester.pump();
        expect(drawnTable(tester) != null, drawn, reason: 'caret at $at');
      }
    });

    drawing('is one block over its lines: the lines either side are all that is drawn as text', (tester) async {
      final on = await open(tester);
      expect(_shown(tester), 'Before\n\n\nAfter');
      final found = <(int, int)>[];
      final cursor = drawnTablesIn(on.state).iter();
      while (cursor.value != null) {
        found.add((cursor.from, cursor.to));
        expect((cursor.value! as PointDecoration).widget, isA<TableWidget>());
        cursor.next();
      }
      expect(found, [(tableAt, doc.indexOf('\n\nAfter'))]);
    });
  });

  group('growing a table from its drawing', () {
    const table = '| Bug | Owner |\n| --- | --- |\n| Seek bar | Matt |';
    const doc = 'Before\n\n$table\n\nAfter';

    Future<EditorView> open(WidgetTester tester) => pumpTables(tester, doc, more: <Extension>[history()]);
    Future<void> tap(WidgetTester tester, String label) async {
      await tester.tap(find.byWidgetPredicate((w) => w is TableGrowButton && w.label == label));
      await tester.pump();
    }

    drawing('+ Column adds a column as one undo, and the table stays drawn with its new cells', (tester) async {
      final on = await open(tester);
      await tap(tester, '+ Column');
      expect(on.state.doc.toString(), 'Before\n\n| Bug | Owner | Column |\n| --- | --- | --- |\n| Seek bar | Matt |  |\n\nAfter');
      // The caret stays out: the press was the button's, not the table's.
      expect(on.hasFocus, isFalse);
      final drawn = drawnTable(tester)!.table;
      expect(drawn.cells[0].map((cell) => cell.text), ['Bug', 'Owner', 'Column']);
      expect(drawn.cells[1].map((cell) => cell.text), ['Seek bar', 'Matt', '']);
      expect(undoDepth(on.state), 1);
      expect(undo(on), isTrue);
      expect(on.state.doc.toString(), doc);
    });

    drawing('+ Row adds an empty row as one undo', (tester) async {
      final on = await open(tester);
      await tap(tester, '+ Row');
      expect(on.state.doc.toString(), 'Before\n\n$table\n|  |  |\n\nAfter');
      expect(drawnTable(tester)!.table.cells.length, 3);
      expect(undoDepth(on.state), 1);
      expect(undo(on), isTrue);
      expect(on.state.doc.toString(), doc);
    });

    drawing('each press is a step of its own, said as input.table, even straight after typing', (tester) async {
      final on = await open(tester);
      on.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x'), userEvent: 'input.type'));
      await tester.pump();
      final before = on.state;
      await tap(tester, '+ Row');
      await tap(tester, '+ Column');
      expect(undoDepth(on.state), 3);
      expect(undo(on), isTrue);
      expect(on.state.doc.toString(), 'xBefore\n\n$table\n|  |  |\n\nAfter');
      expect(undo(on), isTrue);
      expect(on.state.doc.toString(), before.doc.toString());
    });

    drawing('the rewrite is said as the web says it: input.table', (tester) async {
      final seen = <Transaction>[];
      final view = EditorView(
        wholeDocument: true,
        state: EditorState.create(doc: doc),
        onDispatch: (trs, view) {
          seen.addAll(trs);
          view.update(trs);
        },
      );
      addTearDown(view.destroy);
      growTable(view, doc.indexOf('| Bug'), table, (text) => '$text\n| x | y |');
      expect(seen.single.isUserEvent(tableUserEvent), isTrue);
      expect(tableUserEvent, 'input.table');
      expect(view.state.doc.toString(), 'Before\n\n$table\n| x | y |\n\nAfter');
    });

    drawing('a press on a drawing the note has moved under writes nothing, rather than over other words', (tester) async {
      final on = await open(tester);
      // A change and a press in the same frame: the button still holds where its table was.
      on.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x')));
      await tap(tester, '+ Row');
      expect(on.state.doc.toString(), 'x$doc');
      await tap(tester, '+ Row');
      expect(on.state.doc.toString(), 'xBefore\n\n$table\n|  |  |\n\nAfter');
    });

    drawing('with the caret in another line of a focused note, the table grows and stays drawn', (tester) async {
      final on = await open(tester);
      on.focus();
      on.dispatch(TransactionSpec(selection: EditorSelection.single(2)));
      await tester.pump();
      await tap(tester, '+ Row');
      expect(on.state.selection.main.head, 2);
      expect(drawnTable(tester)!.table.cells.length, 3);
    });
  });

  group('what a drawn table looks like', () {
    drawing('columns are aligned as their divider says, the header with them', (tester) async {
      await pumpTables(tester, '| Left | Middle | Right | None |\n| :--- | :---: | ---: | --- |\n| a | b | c | d |');
      final table = drawnTable(tester)!.table;
      expect(table.cells[0].map((cell) => cell.align), [TableAlign.left, TableAlign.center, TableAlign.right, null]);
      for (final row in table.cells) {
        final left = row[0], middle = row[1], right = row[2], none = row[3];
        final pad = table.look.padX + table.look.rule / 2;
        expect(left.wordBoxes.single.left, closeTo(left.rect.left + pad, 0.1));
        expect(middle.wordBoxes.single.center.dx, closeTo(middle.rect.center.dx, 0.1));
        expect(right.wordBoxes.single.right, closeTo(right.rect.right - pad, 0.1));
        expect(none.wordBoxes.single.left, closeTo(none.rect.left + pad, 0.1));
      }
    });

    drawing('a table wider than the screen keeps the note its width and scrolls sideways in its wrap', (tester) async {
      await pumpTables(tester, 'Before\n\n| Monday | Tuesday | Wednesday | Thursday | Friday | Saturday | Sunday |\n| --- | --- | --- | --- | --- | --- | --- |\n| 1 | 2 | 3 | 4 | 5 | 6 | 7 |\n\nAfter');
      final table = drawnTable(tester)!;
      expect(table.size.width, greaterThan(390));
      expect(tester.getSize(find.byType(DrawnTable)).width, 390);
      for (final line in drawnLines(tester)) {
        expect(line.size.width, 390);
      }
      final before = table.localToGlobal(Offset.zero).dx;
      await tester.drag(find.byType(GlyphTable), const Offset(-120, 0));
      await tester.pump();
      expect(table.localToGlobal(Offset.zero).dx, closeTo(before - 120, 20));
    });

    drawing('scrolling it sideways does not open it', (tester) async {
      final on = await pumpTables(tester, '| Monday | Tuesday | Wednesday | Thursday | Friday | Saturday | Sunday |\n| --- | --- | --- | --- | --- | --- | --- |\n| 1 | 2 | 3 | 4 | 5 | 6 | 7 |');
      await tester.drag(find.byType(GlyphTable), const Offset(-120, 0));
      await tester.pump();
      expect(on.hasFocus, isFalse);
      expect(drawnTable(tester), isNotNull);
    });

    drawing('the widget keeps a press where the note can be changed, and leaves it to the view where it cannot', (tester) async {
      const down = PointerDownEvent(), move = PointerMoveEvent();
      expect(const TableWidget('| a |\n| - |', 0, true).takesPointer(down), isTrue);
      expect(const TableWidget('| a |\n| - |', 0, false).takesPointer(down), isFalse);
      expect(const TableWidget('| a |\n| - |', 0, false).takesPointer(move), isTrue);
      // The same table is the same drawing: nothing is built again as the caret moves elsewhere.
      expect(const TableWidget('| a |\n| - |', 4, true).compare(const TableWidget('| a |\n| - |', 4, true)), isTrue);
      expect(const TableWidget('| a |\n| - |', 4, true).compare(const TableWidget('| a |\n| - |', 5, true)), isFalse);
      expect(const TableWidget('| a |\n| - |', 4, true).compare(const TableWidget('| b |\n| - |', 4, true)), isFalse);
      expect(const TableWidget('| a |\n| - |', 4, true).compare(const TableWidget('| a |\n| - |', 4, false)), isFalse);
    });

    drawing('typing elsewhere in the note moves the drawing with its table', (tester) async {
      const doc = 'Before\n\n| a | b |\n| - | - |\n| 1 | 2 |';
      final on = await pumpTables(tester, doc);
      final top = drawnTable(tester)!.localToGlobal(Offset.zero).dy;
      on.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'One more line\n')));
      await tester.pump();
      expect(drawnTable(tester)!.localToGlobal(Offset.zero).dy, greaterThan(top + 20));
      expect(drawnTablesIn(on.state).iter().from, doc.indexOf('| a') + 'One more line\n'.length);
    });
  });

  group('where a table is drawn', () {
    const table = '| Bug | Owner |\n| --- | --- |\n| Seek bar | Matt |';

    // The note's own screen: the editor as a sliver of the page's scroll view, only what is on screen built.
    drawing('in a note that scrolls: laid out among its lines, opened by a press, grown by its buttons', (tester) async {
      final doc = '${List<String>.filled(12, 'A line of the note.').join('\n')}\n\n$table\n\n${List<String>.filled(60, 'A line after it.').join('\n')}';
      final view = EditorView(state: EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[drawnTables(), history()])));
      view.focusRequest = () => view.setFocused(true);
      final controller = ScrollController();
      addTearDown(view.destroy);
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        ratio: 2,
        home: Builder(
          builder: (context) => ColoredBox(
            color: context.tokens.color('glacier-bg'),
            child: CustomScrollView(controller: controller, slivers: <Widget>[EditorSliver(view: view)]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final drawn = drawnTable(tester)!;
      expect(drawn.table.cells.length, 2);
      // Under the line before it and over the line after, with its room above and below.
      final lines = drawnLines(tester);
      final before = lines.lastWhere((line) => line.from < doc.indexOf('| Bug')), after = lines.firstWhere((line) => line.from > doc.indexOf('Matt |'));
      final wrap = tester.getRect(find.byType(DrawnTable));
      expect(wrap.top, closeTo(before.localToGlobal(Offset.zero).dy + before.size.height, 0.01));
      expect(wrap.bottom, closeTo(after.localToGlobal(Offset.zero).dy, 0.01));

      await tester.tap(find.byWidgetPredicate((w) => w is TableGrowButton && w.label == '+ Row'));
      await tester.pump();
      await tester.pump();
      expect(drawnTable(tester)!.table.cells.length, 3);
      expect(view.state.doc.toString(), doc.replaceFirst('| Matt |', '| Matt |\n|  |  |'));

      await tester.tap(find.byType(GlyphTable));
      await tester.pump();
      await tester.pump();
      expect(view.state.selection.main.head, doc.indexOf('| Bug'));
      expect(drawnTable(tester), isNull);
      expect(drawnLines(tester).map((line) => line.spec.projection.display), contains('| Bug | Owner |'));

      // Scrolled away and back, it is built again where it was.
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      controller.jumpTo(900);
      await tester.pump();
      await tester.pump();
      expect(drawnTable(tester), isNull);
      controller.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(drawnTable(tester)!.table.cells.length, 3);
    });

    // notes/NotePeek.module.css: `.peek .cm-editor .cm-glyphTable th { background: transparent }`.
    drawing('on a card, small and read-only: no buttons, and the header has no ground of its own', (tester) async {
      const extensions = <Extension>[];
      final more = <Extension>[...extensions, drawnTables()];
      await pumpApp(
        tester,
        ratio: 2,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, child: MarkdownView(markdown: 'A card\n\n$table', extensions: more, lines: null)),
        ),
      );
      await tester.pump();
      final drawn = drawnTable(tester)!;
      expect(drawn.table.look.headGround, isNull);
      expect(find.byType(TableGrowButton), findsNothing);
      // At the card's own text size, not the page's.
      final context = tester.element(find.byType(GlyphTable));
      expect(drawn.table.look.body.size, lessThan(0.92 * context.tokens.len('app-body')));
      expect(drawn.size.width, lessThanOrEqualTo(300));
    });

    drawing('on a page that is only read, at the page\'s own size, the header keeps its ground', (tester) async {
      final more = <Extension>[drawnTables()];
      await pumpApp(
        tester,
        ratio: 2,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 390, child: MarkdownView(markdown: table, extensions: more, peek: false)),
        ),
      );
      await tester.pump();
      final drawn = drawnTable(tester)!;
      final context = tester.element(find.byType(GlyphTable));
      expect(drawn.table.look.headGround, context.tokens.color('app-paper-2'));
      expect(drawn.table.look.body.size, closeTo(0.92 * context.tokens.len('app-body'), 0.001));
      expect(find.byType(TableGrowButton), findsNothing);
    });
  });
}
