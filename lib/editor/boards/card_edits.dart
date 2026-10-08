/// What a card does to the note: ticked, stepped a lane along, dropped somewhere, or taken off the board. Each is
/// one change and one undo, the fence rewritten and the item's box turned together where the card crosses a Done
/// column, so the note says what the board shows. Every one carries the `input.board` user event: a board's edits
/// are not typing, and the wisp does not smoke them as letters someone wrote. Ports
/// `src/app/editor/boards/cardEdits.ts`.
///
/// What differs: nothing in what is written.
/// - **One undo each, always.** On the page two edits of the same fence inside half a second could be joined into
///   one step by the history (their ranges touch); here each is marked a step of its own ([boardChange]), so Undo
///   takes back exactly the last thing done to the board.
/// - A drawing that has not been built again since the note changed under it no longer knows where its fence is;
///   each edit checks the fence is still where the board says and writes nothing otherwise (as `growTable` does
///   for a table).
/// - `addCard` (composer.ts) and `writeHeight` (divider.ts) are here with the other writes, since each widget that
///   calls them is a Flutter widget in a file of its own.
library;

import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../core/boards.dart';
import '../editor.dart';
import 'drawn.dart';
import 'navigate.dart';

/// The user event of every change a board makes.
const String boardUserEvent = 'input.board';

/// A board's change as one step of the history, with the board's user event.
TransactionSpec boardChange(Object changes) => TransactionSpec(changes: changes, userEvent: boardUserEvent, annotations: isolateHistory.of('full'));

/// Whether `board` is still the fence the note has between its two offsets.
bool boardStands(EditorViewLike view, DrawnBoard board) {
  final doc = view.state.doc;
  if (board.to > doc.length) return false;
  final open = doc.lineAt(board.from);
  final close = doc.lineAt(board.to);
  return open.from == board.from && close.to == board.to && boardAt(doc.toString(), open.number) != null && close.number > open.number;
}

/// The fence rewritten: the columns as a person would have typed them, between the two ``` lines.
ChangeSpec fenceEdit(EditorViewLike view, DrawnBoard board, List<BoardColumn> columns, [String? moved]) {
  final open = view.state.doc.lineAt(board.from);
  final close = view.state.doc.lineAt(board.to);
  // What the board shows, written down: the card the person just moved where they put it, and any other card whose
  // item is ticked in Done, where it is already drawn (core/boards.dart `settleColumns`).
  return ChangeSpec(from: open.to + 1, to: close.from - 1, insert: writeBoard(settleColumns(columns, board.items, moved)));
}

/// The card's tick box is the item's: the line is ticked, and a Done column takes the card.
void tickCard(EditorViewLike view, DrawnBoard board, Card card) {
  final item = card.item;
  if (item == null || item.done == null || !boardStands(view, board)) return;
  final line = view.state.doc.line(item.line);
  final done = !item.done!;
  final changes = <ChangeSpec>[ChangeSpec(from: line.from, to: line.to, insert: setItemDone(line.text, done))];
  final put = done ? doneColumn(board.columns) : 0;
  final columns = put >= 0 ? putCard(board.columns, card.id, put) : null;
  hushGoTo();
  if (columns != null) changes.add(fenceEdit(view, board, columns, card.id));
  view.dispatch(boardChange(changes));
  fireMotor(HapticKind.selection);
  if (columns != null) reveal(view, card.id);
}

/// The card one lane along, left or right, by its chevrons.
void stepCard(EditorViewLike view, DrawnBoard board, Card card, int by) {
  if (!boardStands(view, board)) return;
  view.dispatch(boardChange(fenceEdit(view, board, moveCard(board.columns, card.id, by), card.id)));
  fireMotor(HapticKind.selection);
}

/// Where the card was let go: the fence rewritten, and the tick box brought with it where a Done column is crossed.
void landCard(EditorViewLike view, DrawnBoard board, Card card, int column, int index) {
  final was = card.column;
  if (was == column && index == board.held(column).indexWhere((other) => other.id == card.id)) return;
  if (!boardStands(view, board)) return;
  final changes = <ChangeSpec>[fenceEdit(view, board, putCardAt(board.columns, card.id, column, index), card.id)];
  // Dragged into Done, the item is done; dragged out of it, it is not. The note says so, not only the board.
  final done = doneColumn(board.columns);
  final item = card.item;
  if (item != null && item.done != null && done >= 0 && (was == done) != (column == done)) {
    final line = view.state.doc.line(item.line);
    changes.add(ChangeSpec(from: line.from, to: line.to, insert: setItemDone(line.text, column == done)));
  }
  hushGoTo();
  view.dispatch(boardChange(changes));
  fireMotor(HapticKind.success);
  reveal(view, card.id);
}

/// The card off the board: the fence without it, and its item left exactly where it is in the note (core/boards.dart
/// `withoutCard`).
void takeOffCard(EditorViewLike view, DrawnBoard board, Card card) {
  if (!boardStands(view, board)) return;
  view.dispatch(boardChange(fenceEdit(view, board, withoutCard(board.columns, card.id), card.id)));
  fireMotor(HapticKind.selection);
}

/// A card with these words in column `column` of the board that opens on line `open`: the fence and the new line
/// together (composer.ts `addCard`).
bool addCard(EditorViewLike view, int open, int column, String words) {
  final made = newCard(view.state.doc.toString(), open, column, words);
  if (made == null) return false;
  final doc = view.state.doc;
  final top = doc.line(made.fence.from);
  final bottom = doc.line(made.fence.to);
  final end = made.at > doc.lines;
  final at = end ? doc.length : doc.line(made.at).from;
  // At the end of a note that does not end in a newline, the line needs one of its own in front of it.
  final tail = doc.length > 0 ? view.state.sliceDoc(doc.length - 1) : '\n';
  final insert = end ? '${tail == '\n' ? '' : '\n'}${made.text}' : '${made.text}\n';
  view.dispatch(
    boardChange(<ChangeSpec>[
      ChangeSpec(from: top.to + 1, to: bottom.from - 1, insert: made.fence.body),
      ChangeSpec(from: at, insert: insert),
    ]),
  );
  return true;
}

/// The lanes' height written into the board's fence, or taken out of it with null: one change, one undo
/// (divider.ts `writeHeight`).
void writeHeight(EditorViewLike view, DrawnBoard board, double? height) {
  if (!boardStands(view, board)) return;
  final open = view.state.doc.lineAt(board.from);
  final next = withBoardHeight(open.text, height);
  if (next != open.text) view.dispatch(boardChange(ChangeSpec(from: open.from, to: open.to, insert: next)));
}
