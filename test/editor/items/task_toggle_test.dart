// A tap on a to-do's box (lib/editor/items/task_toggle.dart). `src/app/editor/taskToggle.test.ts` is ported whole,
// its nine cases of `boxAt` and `toggleBox`, in test/editor/commands/task_toggle_test.dart, and the taps of
// `boxTaps.test.ts` on a grid are box_taps_test.dart. None of those is said again here. What is here is what neither
// holds, the handler of this file over a note that is really drawn and what its one edit carries:
// - the functions this file says again are the commands' own;
// - a tap on the box as it is laid out ticks it and leaves the caret, and a tap on the words is the editor's;
// - a tap on a box that is also a card moves the card in the same edit, an `input` one that one undo takes back.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/commands/task_toggle.dart' as commands;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/task_toggle.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

Future<EditorView> draw(WidgetTester tester, String doc, {bool readOnly = false}) async {
  final updates = <Transaction>[];
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(doc: doc, extensions: noteExtensions(readOnly: readOnly, more: <Extension>[taskToggle(), history(), EditorViewLike.updateListener.of((update) => updates.addAll(update.transactions))])),
  );
  addTearDown(view.destroy);
  _heard[view] = updates;
  await pumpApp(
    tester,
    prefs: const AppPreferences(theme: 'light'),
    home: Builder(
      builder: (context) => ColoredBox(
        color: context.tokens.color('glacier-bg'),
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view)))),
      ),
    ),
  );
  await tester.pump();
  return view;
}

/// The transactions each view has had.
final Expando<List<Transaction>> _heard = Expando<List<Transaction>>();

/// A press on the middle of the characters `from`-`to` as they are drawn; true when the box took it.
bool press(EditorView view, int from, int to) {
  final start = view.coordsAtPos(from, 1)!, end = view.coordsAtPos(to, -1)!;
  final at = Offset((start.left + end.right) / 2, (start.top + start.bottom) / 2);
  return view.eventHandlers.any((h) => h.mouseDown?.call(PointerDownEvent(position: at), view) ?? false);
}

void main() {
  setUpAll(loadAppFonts);

  test('says the commands’ own boxAt and toggleBox again', () {
    expect(identical(boxAt, commands.boxAt), isTrue);
    expect(identical(toggleBox, commands.toggleBox), isTrue);
  });

  group('a tap on a to-do’s box, in a note that is drawn', () {
    testWidgets('ticks the box where it is laid out, and another clears it, the caret left where it was', (tester) async {
      const doc = 'Shopping\n\n- [ ] milk\n  - [x] eggs';
      final view = await draw(tester, doc);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(3)));
      final milk = view.state.doc.line(3).from + 2, eggs = view.state.doc.line(4).from + 4;
      expect(press(view, milk, milk + 3), isTrue);
      expect(view.state.doc.line(3).text, '- [x] milk');
      expect(press(view, eggs, eggs + 3), isTrue);
      expect(view.state.doc.line(4).text, '  - [ ] eggs');
      expect(view.state.selection.main.head, 3);
      // The words beside the box are for writing, and so is a line with no box.
      expect(press(view, milk + 4, milk + 8), isFalse);
      expect(press(view, 0, 8), isFalse);
      expect(view.state.doc.toString(), 'Shopping\n\n- [x] milk\n  - [ ] eggs');
      debugDisableShadows = true;
    });

    testWidgets('leaves a note that cannot be changed alone', (tester) async {
      const doc = '- [ ] milk';
      final view = await draw(tester, doc, readOnly: true);
      expect(press(view, 2, 5), isFalse);
      expect(view.state.doc.toString(), doc);
      debugDisableShadows = true;
    });

    testWidgets('moves a card with its box in the one edit, which one undo takes back', (tester) async {
      final doc = <String>['Chores', '', '- [ ] Milk ^milk', '- [ ] Eggs ^eggs', '- [x] Bread ^bread', '', '```board', 'To do: milk, eggs', 'Done: bread', '```', ''].join('\n');
      final view = await draw(tester, doc);
      final heard = _heard[view]!..clear();
      final milk = view.state.doc.line(3).from + 2;
      expect(press(view, milk, milk + 3), isTrue);
      expect(view.state.doc.toString(), contains('- [x] Milk ^milk'));
      expect(view.state.doc.toString(), contains('To do: eggs\nDone: bread, milk'));
      final edits = heard.where((tr) => tr.docChanged).toList();
      expect(edits, hasLength(1));
      expect(edits.single.isUserEvent('input'), isTrue);
      expect(undo(view), isTrue);
      expect(view.state.doc.toString(), doc);
      debugDisableShadows = true;
    });
  });
}
