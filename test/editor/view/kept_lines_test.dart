// The lines the sliver keeps built are built again only where something they show has changed
// (lib/editor/view/editor_view.dart `takeDirty`, `buildEntry`): a line nothing touched keeps the look it had. Held
// here to the plain way, which is to build every line again: after each of a few hundred changes made by chance
// (letters, lines made and joined, marks and lists typed and taken away, the caret moved, a selection drawn, the
// page scrolled), every line on screen is compared with the line a fresh build of it gives, its words, its marks,
// its widgets, where it is and what is selected on it. A line left stale by a change that should have reached it
// fails here, whatever made the change.
import 'dart:math';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/editor/boards/boards.dart' show drawnBoards;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/items.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/media/media.dart';
import 'package:ghost_md/editor/tables/tables.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/projection.dart';

import '../../support/render.dart';
import '../input/support.dart';

/// The line a fresh build of the entry at `number` draws, or null where the entry is a block widget alone.
EditorLine? fresh(EditorView view, int number) {
  Widget? built = view.buildEntry(number);
  if (built is EditorLine) return built;
  if (built is Column) {
    for (final child in built.children) {
      if (child is EditorLine) return child;
    }
  }
  return null;
}

/// Every line on screen against a fresh build of it.
void expectAsFresh(WidgetTester tester, EditorView view, String after) {
  final doc = view.state.doc;
  final lines = drawn(tester);
  expect(lines, isNotEmpty, reason: 'lines are drawn ($after)');
  for (final line in lines) {
    final at = doc.lineAt(line.from);
    expect(at.from, line.from, reason: 'a drawn line starts where a line of the document does ($after)');
    final again = fresh(view, at.number);
    expect(again, isNotNull, reason: 'line ${at.number} is still a line ($after)');
    expect(again!.from, line.from, reason: 'line ${at.number} is where it is drawn ($after)');
    expect(
      line.spec.same(again.spec),
      isTrue,
      reason: 'line ${at.number} shows what a fresh build of it shows ($after)\n  drawn: ${line.spec.projection}\n  fresh: ${again.spec.projection}\n  drawn class: ${line.spec.projection.className}\n  fresh class: ${again.spec.projection.className}',
    );
    expect(line.selection.same(again.selection), isTrue, reason: 'line ${at.number} draws the selection it has ($after)');
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('through changes made by chance, a kept line is the line a fresh build gives', (tester) async {
    final random = Random(11);
    final rig = await pumpEditor(
      tester,
      sampleNoteBody,
      more: <Extension>[
        markExtensions(marks),
        itemExtensions(wiki: WikiOptions(known: (title) => title.length.isEven, open: (title, [anchor]) {}), openHeading: true, doneSyncs: true),
        drawnTables(),
        drawnBoards(),
        mediaExtensions(places: PlaceMode.live),
      ],
    );
    final view = rig.view;
    expectAsFresh(tester, view, 'opening');

    const typed = <String>['a', ' ', '**', '==', '- ', '- [ ] ', '# ', '> ', '`', '[[', ']]', '^x', '#tag ', '```', '\n', '\n\n', '| a | b |\n| - | - |\n| 1 | 2 |\n', ':smile:', r'$x$', '[^1]', '§§', '![[A]]', '](http://a.test)'];
    var projectedByCarets = 0, carets = 0;
    for (var round = 0; round < 260; round++) {
      final doc = view.state.doc;
      // Where on screen: a drawn line, so what is changed is what is looked at.
      final lines = drawn(tester);
      final line = lines[random.nextInt(lines.length)];
      final here = line.from + random.nextInt(line.to - line.from + 1);
      final String did;
      switch (random.nextInt(9)) {
        case 0:
        case 1:
          final text = typed[random.nextInt(typed.length)];
          view.dispatch(TransactionSpec(changes: ChangeSpec(from: here, insert: text), selection: EditorSelection.single(here + text.length), userEvent: 'input.type'));
          did = 'typing ${text.replaceAll('\n', r'\n')} at $here';
        case 2:
          final to = min(doc.length, here + 1 + random.nextInt(6));
          view.dispatch(TransactionSpec(changes: ChangeSpec(from: here, to: to), selection: EditorSelection.single(here), userEvent: 'delete.forward'));
          did = 'deleting $here to $to';
        case 3:
          // Two lines joined, or a line taken whole.
          final to = min(doc.length, line.to + 1 + (random.nextBool() ? 0 : random.nextInt(40)));
          view.dispatch(TransactionSpec(changes: ChangeSpec(from: line.to, to: to), userEvent: 'delete.forward'));
          did = 'deleting ${line.to} to $to';
        case 4:
          // A change above the screen: every drawn line moves and none changes.
          view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: random.nextBool() ? 'x' : 'a line\n')));
          did = 'typing at the top';
        case 5:
          final before = LineProjection.builds;
          await rig.place(here);
          projectedByCarets += LineProjection.builds - before;
          carets += 1;
          did = 'the caret at $here';
        case 6:
          final other = lines[random.nextInt(lines.length)];
          await rig.place(here, other.from + random.nextInt(other.to - other.from + 1));
          did = 'a selection from $here';
        case 7:
          rig.scroll.jumpTo((rig.scroll.offset + (random.nextInt(900) - 300)).clamp(0.0, rig.scroll.position.maxScrollExtent));
          did = 'scrolling';
        default:
          // Undone, where there is something to undo.
          undo(view);
          did = 'undoing';
      }
      await tester.pump();
      expectAsFresh(tester, view, 'round $round, $did');
      if (round % 20 == 19) {
        // And once what comes after the frame has come (heights measured, the + beside the line).
        await tester.pump(const Duration(milliseconds: 400));
        expectAsFresh(tester, view, 'round $round, settled');
      }
    }
    // A caret put somewhere projects the lines it left and came to, not the screen: two or three lines each,
    // where every line on screen (thirty of them) was projected for each.
    expect(carets, greaterThan(10));
    expect(projectedByCarets / carets, lessThan(6), reason: 'a caret moved projects the lines it touches: $projectedByCarets for $carets');
    await finish(tester);
  });
}
