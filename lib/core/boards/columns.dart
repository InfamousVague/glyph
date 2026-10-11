/// A board's columns as data: which one holds a card and which is Done, a card moved along, dropped between two
/// others or taken off, the columns as the board draws them with every ticked card in Done, and each card paired with
/// the item it names - or the one it meant, when its anchor slipped. A port of `src/app/core/boards/columns.ts`, one
/// to one.
///
/// Every write here answers new columns and never changes the ones it is given (`_copy`): the editor hands over state
/// it must not see change, and columns_test.dart holds these to it.
///
/// What differs: `Card` is an immutable class with value equality (a Flutter caller that also imports material hides
/// one of the two); `Number.MAX_SAFE_INTEGER`, "the end of the lane", is the same number written out.
library;

import '../item_syntax.dart' show isDoneName;
import 'fence.dart' show BoardColumn;
import 'items.dart' show Item;

/// JavaScript's `Number.MAX_SAFE_INTEGER`: an index past the end of any lane.
const int _theEnd = 9007199254740991;

/// Which column holds [id], or -1.
int columnOf(List<BoardColumn> columns, String id) => columns.indexWhere((column) => column.cards.contains(id));

/// The column a board calls Done, or -1: the one a ticked item belongs in.
int doneColumn(List<BoardColumn> columns) => columns.indexWhere((column) => isDoneName(column.name));

/// A copy nothing shares with the columns given: every write here answers new columns, never the ones passed in.
List<BoardColumn> _copy(List<BoardColumn> columns) => [for (final column in columns) BoardColumn(name: column.name, cards: [...column.cards])];

/// The columns with [id] moved [by] columns along, as far as there are columns to move it to.
List<BoardColumn> moveCard(List<BoardColumn> columns, String id, int by) {
  final from = columnOf(columns, id);
  if (from < 0) return _copy(columns);
  final along = from + by;
  final to = along < 0 ? 0 : (along > columns.length - 1 ? columns.length - 1 : along);
  // Already at the end it was pushed against: nothing moves, and the card stays where it is.
  if (to == from) return _copy(columns);
  return putCard(columns, id, to);
}

/// The columns with [id] at the end of [to], wherever it was.
List<BoardColumn> putCard(List<BoardColumn> columns, String id, int to) => putCardAt(columns, id, to, _theEnd);

/// The columns with [id] in [to] at [index], wherever it was: what a card dropped between two others becomes
/// (Matt: "add a way to tap and drag to re organize items in lanes").
///
/// The index counts the column as it will be, the card taken out of wherever it was first, so dragging a card down
/// its own column lands it where the gap was shown and not one place short.
List<BoardColumn> putCardAt(List<BoardColumn> columns, String id, int to, int index) {
  if (to < 0 || to >= columns.length) return _copy(columns);
  final without = [for (final column in columns) column.cards.where((card) => card != id).toList()];
  final target = without[to];
  final at = index < 0 ? 0 : (index > target.length ? target.length : index);
  target.insert(at, id);
  return [for (var i = 0; i < columns.length; i += 1) BoardColumn(name: columns[i].name, cards: without[i])];
}

/// The ticks and the lanes, brought back together.
///
/// A column called Done means done, so an item ticked anywhere is DRAWN in the Done lane whatever its fence says
/// ([columnFor]). Ticking a box in the note's list, or a task going Done in Notion (editor/doneSync.ts), never moved
/// the id, so a note could drift until a lane held seventeen ids and drew two of them (Matt, of his Task Management
/// note: "items are in the Doing swimlane in the board code" while the lane drew nothing). The board was right and the
/// markdown was stale, which is the wrong way round: the markdown is the note.
///
/// `settleColumns` gives the columns as the board draws them: every ticked item's card in Done. [moved] is a card the
/// person has just moved by hand, which is left exactly where they put it.
List<BoardColumn> settleColumns(List<BoardColumn> columns, List<Item> items, [String? moved]) {
  final done = doneColumn(columns);
  if (done < 0) return _copy(columns);
  var next = _copy(columns);
  for (final item in items) {
    if (item.id == moved || item.done != true) continue;
    final at = columnOf(next, item.id);
    if (at >= 0 && at != done) next = putCard(next, item.id, done);
  }
  return next;
}

/// The columns without [id]: the card taken off the board, its item left exactly where it is in the note (Matt: "Add
/// context menu to board items for moving lanes and adding to notion etc."). A board never has to hold every item.
List<BoardColumn> withoutCard(List<BoardColumn> columns, String id) => [
  for (final column in columns) BoardColumn(name: column.name, cards: column.cards.where((card) => card != id).toList()),
];

/// A board's cards, each with the item it names: the ones whose item is gone are answered too, so nothing vanishes
/// (`Card`).
class Card {
  const Card({required this.id, required this.column, required this.item});

  final String id;
  final int column;
  final Item? item;

  @override
  bool operator ==(Object other) => other is Card && other.id == id && other.column == column && other.item == item;

  @override
  int get hashCode => Object.hash(id, column, item);

  @override
  String toString() => 'Card($id, column: $column, $item)';
}

/// Every card of [columns] with its item. [named] is every anchor some board names, which is this board's own when
/// it is not given.
List<Card> cardsOf(List<BoardColumn> columns, List<Item> items, [Set<String>? named]) {
  final all = named ?? {for (final column in columns) ...column.cards};
  // The last of a repeated anchor, as a JavaScript Map made from pairs keeps it.
  final byId = {for (final item in items) item.id: item};
  // Items no board names: where a card's anchor matches no item, one of these may be the item it meant.
  final loose = items.where((item) => !all.contains(item.id)).toList();
  return [
    for (var index = 0; index < columns.length; index += 1)
      for (final id in columns[index].cards) Card(id: id, column: index, item: byId[id] ?? _slipOf(id, loose)),
  ];
}

/// The item a card meant when its anchor matches none: the one item, named by no board, whose anchor is a slip of
/// the card's (Matt: "the second item got glitched out on the board" - the fence said `blur-bottom-swimlanes`, the
/// line `^blur-bottom-swimlaness`). Only a single such item counts, and only for an anchor long enough to be sure.
Item? _slipOf(String id, List<Item> loose) {
  if (id.length < 4) return null;
  final near = loose.where((item) => nearAnchor(id, item.id)).toList();
  return near.length == 1 ? near.first : null;
}

/// Two anchors a slip apart: one letter added, dropped or changed, or up to two letters more or fewer at the end.
bool nearAnchor(String one, String two) {
  if (one == two) return false;
  final short = one.length <= two.length ? one : two;
  final long = one.length <= two.length ? two : one;
  final more = long.length - short.length;
  if (more <= 2 && long.startsWith(short)) return true;
  if (more > 1) return false;
  var at = 0;
  while (at < short.length && short.codeUnitAt(at) == long.codeUnitAt(at)) {
    at += 1;
  }
  return more == 0 ? _from(short, at + 1) == _from(long, at + 1) : _from(short, at) == _from(long, at + 1);
}

/// `String.prototype.slice(at)`, which forgives an index past the end.
String _from(String text, int at) => at >= text.length ? '' : text.substring(at);

/// An item's own column: the Done one when it is ticked, else where the board has it.
int columnFor(List<BoardColumn> columns, Item item) {
  final done = doneColumn(columns);
  if (item.done == true && done >= 0) return done;
  return columnOf(columns, item.id);
}
