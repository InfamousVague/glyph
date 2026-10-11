/// What the note offers to do with boards, where the caret is: a port of `src/app/editor/boardActions.ts`
/// (core/boards.dart has the syntax). Copy a board, add an item to its list's board, make a board of a list. The
/// press-and-hold band offers these (context_band.dart).
///
/// Each change is one dispatch, so one Undo takes it back, and each is marked `input.board`, so the typing smoke
/// leaves it alone: none of it is a letter someone wrote.
///
/// What differs: nothing in what is written. The functions take the view as the web's do (`EditorViewLike`), since
/// each reads the document and dispatches at once. It sits with the band until the boards themselves are drawn
/// (stage 5), which is why the band offers these rows only when asked to (`ContextBand.boards`).
library;

import '../../core/boards.dart';
import '../editor.dart';

/// The lines of a list, first and last, counting from 1 (`LineRange`).
typedef LineRange = ({int from, int to});

/// What can be done with boards at the caret (`BoardOffers`).
class BoardOffers {
  const BoardOffers({this.fence, this.copy, this.joinable = false, this.list});

  /// The board the caret is on, by its fence's first and last lines, or null.
  final LineRange? fence;

  /// That board as words - the fence and the items it names - to copy, since a board drawn as columns cannot be
  /// dragged over.
  final String? copy;

  /// The caret's item could join its list's board: other items in the list are on one already.
  final bool joinable;

  /// The lines that would become a board of their own: the selection when it spans lines, else the list the caret
  /// is in.
  final LineRange? list;
}

/// What can be done with boards at the caret in `view`.
BoardOffers boardOffers(EditorViewLike view) {
  final doc = view.state.doc;
  final text = doc.toString();
  final caret = doc.lineAt(view.state.selection.main.head).number;
  final board = boardAt(text, caret);
  final LineRange? fence = board == null ? null : (from: board.from, to: board.to);
  // Not offered on a board, or on a list that already has one above it (boardFromList says so).
  LineRange? list;
  if (fence == null) {
    final main = view.state.selection.main;
    final first = doc.lineAt(main.from).number;
    final last = doc.lineAt(main.to).number;
    list = last > first ? (from: first, to: last) : listAround(text, caret);
  }
  return BoardOffers(
    fence: fence,
    copy: boardCopy(text, caret),
    joinable: addToBoard(text, caret) != null,
    list: list != null && boardFromList(text, list.from, list.to) != null ? list : null,
  );
}

/// Selects the whole of the board on `fence`, so a row that works on lines works on all of it: pressed on a drawn
/// board the caret is on one of its column lines, and duplicating or deleting that alone would leave half a board
/// behind.
void selectBoard(EditorViewLike view, LineRange fence) {
  final open = view.state.doc.line(fence.from);
  final close = view.state.doc.line(fence.to);
  view.dispatch(TransactionSpec(selection: EditorSelection.single(open.from, close.to)));
}

/// The list on `lines` as a board of its own, set in just above it (core/boards `boardFromList`; Matt: "add ability
/// to auto list a section of list items into a board"). Answers what it made, or null when those lines make none.
({int cards, int done})? makeListBoard(EditorViewLike view, LineRange lines) {
  final made = boardFromList(view.state.doc.toString(), lines.from, lines.to);
  if (made == null) return null;
  final doc = view.state.doc;
  // The item lines, and the fence put in at the start of the list's first line: where that line changes too, the
  // fence goes in front of its new words, as one change.
  final changes = <ChangeSpec>[
    for (final (:number, :text) in made.lines)
      ChangeSpec(from: doc.line(number).from, to: doc.line(number).to, insert: number == made.fence.before ? '${made.fence.text}$text' : text),
  ];
  if (!made.lines.any((line) => line.number == made.fence.before)) {
    final at = doc.line(made.fence.before).from;
    changes.add(ChangeSpec(from: at, to: at, insert: made.fence.text));
  }
  view.dispatch(TransactionSpec(changes: changes, userEvent: 'input.board'));
  return (cards: made.cards, done: made.done);
}

/// The item on line `lineNumber` (counting from 1) joins its list's board: the line gains its anchor, and the fence
/// gains the card (core/boards `addToBoard`; Matt: "add an 'add to board' option when other items in the list are
/// in a board already"). The line is the one the row was offered for, not wherever the caret has gone since.
/// Answers the column it went into, since the board may be well off the screen and where it went is said aloud;
/// null for none.
String? joinBoard(EditorViewLike view, int lineNumber) {
  final doc = view.state.doc;
  final added = addToBoard(doc.toString(), lineNumber);
  if (added == null) return null;
  final open = doc.line(added.fence.from);
  final close = doc.line(added.fence.to);
  final changes = <ChangeSpec>[ChangeSpec(from: open.to + 1, to: close.from - 1, insert: added.fence.body)];
  final line = added.line;
  if (line != null) {
    final at = doc.line(line.number);
    changes.add(ChangeSpec(from: at.from, to: at.to, insert: line.text));
  }
  view.dispatch(TransactionSpec(changes: changes, userEvent: 'input.board'));
  return added.column;
}

/// What a board made of a list is said as: "3 items are now cards, 1 in Done." - `becomes` is "cards" or
/// "a board" (`boardMadeWords`).
String boardMadeWords(({int cards, int done}) made, String becomes) =>
    '${made.cards} ${made.cards == 1 ? 'item is' : 'items are'} now $becomes${made.done != 0 ? ', ${made.done} in Done' : ''}.';
