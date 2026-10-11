/// A tick, carried to the boards: what every fence in the note says once a box is ticked or cleared in the note's
/// list, or a batch of tasks goes Done in Notion (editor/doneSync.ts). A port of `src/app/core/boards/settle.ts`, one
/// to one.
///
/// A column called Done means done. `settleColumns` (columns.dart) is how a board DRAWS that, whatever its fence says;
/// these bring the markdown round to agree, since the markdown is the note. They answer the fences to write, and the
/// lines that gained an anchor to join a board; the editor applies both in the same transaction as the tick
/// (editor/boards.ts `settleFences`).
///
/// What differs: the shapes. `FenceEdit` is an immutable class with value equality, `SettledTicks` a class, and each
/// of its `lines` a `({number, anchor})` record. The ticks are a `Map<int, bool>` read in the order it was filled,
/// as a JavaScript `Map` is. `Array.splice` is written out ([_splice]) with JavaScript's clamping.
library;

import 'columns.dart' show columnOf, doneColumn, putCard, settleColumns;
import 'fence.dart' show boardsIn, writeBoard;
import 'items.dart' show Item, isItemLine, itemOnLine, itemsIn;
import 'make.dart' show addToBoard, listAround;

/// A fence to be written again: the lines it is on, counting from 1, and its new body (`FenceEdit`).
class FenceEdit {
  const FenceEdit({required this.from, required this.to, required this.body});

  /// The line the opening fence is on.
  final int from;

  /// The line the closing fence is on.
  final int to;
  final String body;

  @override
  bool operator ==(Object other) => other is FenceEdit && other.from == from && other.to == to && other.body == body;

  @override
  int get hashCode => Object.hash(from, to, body);

  @override
  String toString() => 'FenceEdit($from-$to, ${body.replaceAll('\n', r'\n')})';
}

/// `Array.prototype.splice(start, count, ...items)` for a start that is not negative: the start and the count are
/// held to what the list has.
void _splice(List<String> lines, int start, int count, List<String> items) {
  final at = start > lines.length ? lines.length : start;
  final most = lines.length - at;
  final taken = count < 0 ? 0 : (count > most ? most : count);
  lines.replaceRange(at, at + taken, items);
}

/// Every fence in the note that has something to say again, given the boxes about to change: [ticks] is each item's
/// line and the state its box is being set to. One box tapped in the list, or a batch of them arriving from Notion,
/// are the same thing here.
///
/// A box ticked puts its card in Done; a box cleared takes its card out of Done and back to the first lane, as
/// unticking a card on the board does. Any other card whose item is already ticked is settled at the same time, so a
/// note that has drifted comes right with the next change rather than staying wrong. Nothing else about the fence
/// moves, and a board with no Done lane leaves its ticks alone.
List<FenceEdit> settleBoards(String doc, [Map<int, bool> ticks = const {}]) {
  final items = [
    for (final item in itemsIn(doc))
      ticks.containsKey(item.line) ? Item(id: item.id, text: item.text, done: ticks[item.line] ?? item.done, line: item.line) : item,
  ];
  final cleared = <Item>[];
  for (final MapEntry(key: line, value: on) in ticks.entries) {
    if (on) continue;
    for (final item in items) {
      if (item.line == line) {
        cleared.add(item);
        break;
      }
    }
  }
  final edits = <FenceEdit>[];
  for (final board in boardsIn(doc)) {
    if (board.to <= board.from + 1) continue;
    var columns = settleColumns(board.columns, items);
    final done = doneColumn(columns);
    for (final item in cleared) {
      if (done >= 0 && columnOf(columns, item.id) == done) columns = putCard(columns, item.id, 0);
    }
    final body = writeBoard(columns);
    if (body != writeBoard(board.columns)) edits.add(FenceEdit(from: board.from, to: board.to, body: body));
  }
  return edits;
}

/// A tick that had to write more than a fence: the lines that gained an anchor so they could join a board
/// (`SettledTicks`).
class SettledTicks {
  const SettledTicks({required this.fences, required this.lines});

  final List<FenceEdit> fences;

  /// The item's line, counting from 1, and the anchor to put at the end of it.
  final List<({int number, String anchor})> lines;

  @override
  String toString() => 'SettledTicks(fences: $fences, lines: $lines)';
}

/// Everything a tick changes, when the box is turned somewhere other than the board.
///
/// [settleBoards] moves cards that exist. This adds the one thing it cannot: an item that is **not** a card, ticked in
/// a list whose other items are on a board, joins that board and lands in Done (found in Matt's own note -
/// three ticked items with no anchor, so ticking them moved nothing, while the other 57 worked). From where a person
/// sits, two identical-looking to-dos behaved differently and nothing said why.
///
/// Scoped to the item's own list on purpose: docs/BOARDS.md says a board never has to hold every item in the note, so
/// a to-do in some unrelated list further down must not leap onto the board because it was ticked. It joins the board
/// its neighbours are already on, and nothing else does.
SettledTicks settleTicks(String doc, Map<int, bool> ticks) {
  final lines = doc.split('\n');
  final joined = <({int number, String anchor})>[];
  for (final MapEntry(key: line, value: on) in ticks.entries) {
    if (!on) continue;
    final working = lines.join('\n');
    if (line < 1 || line > lines.length) continue;
    final text = lines[line - 1];
    if (!isItemLine(text)) continue;
    final item = itemOnLine(text);
    // Already a card: moving it is `settleBoards`' job, not this one.
    if (item != null && boardsIn(working).any((board) => columnOf(board.columns, item.id) >= 0)) continue;
    if (!_listOnBoard(working, line)) continue;
    final added = addToBoard(working, line);
    if (added == null) continue;
    final written = added.line;
    if (written != null) {
      lines[written.number - 1] = written.text;
      joined.add((number: written.number, anchor: added.id));
    }
    // The fence keeps its number of lines, so every line number above stays good for the next tick in the batch.
    _splice(lines, added.fence.from, added.fence.to - added.fence.from - 1, added.fence.body.split('\n'));
  }
  // Then the ordinary settling - ticked cards into Done, cleared ones back out - over the note as it now stands.
  for (final edit in settleBoards(lines.join('\n'), ticks)) {
    _splice(lines, edit.from, edit.to - edit.from - 1, edit.body.split('\n'));
  }
  final now = boardsIn(lines.join('\n'));
  final fences = <FenceEdit>[];
  final before = boardsIn(doc);
  for (var at = 0; at < before.length; at += 1) {
    final board = before[at];
    final body = at < now.length ? now[at].body : board.body;
    if (board.to > board.from + 1 && body != board.body) fences.add(FenceEdit(from: board.from, to: board.to, body: body));
  }
  return SettledTicks(fences: fences, lines: joined);
}

/// Whether the list [line] stands in has any item that is already a card on a board.
bool _listOnBoard(String doc, int line) {
  final around = listAround(doc, line);
  if (around == null) return false;
  final boards = boardsIn(doc).where((board) => board.to > board.from).toList();
  if (boards.isEmpty) return false;
  return itemsIn(doc).any(
    (item) => item.line != line && item.line >= around.from && item.line <= around.to && boards.any((board) => columnOf(board.columns, item.id) >= 0),
  );
}
