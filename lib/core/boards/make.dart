/// Boards and cards made from a note's own lists: a whole note's items made into a board, one list made into a board
/// of its own, an item put on the board its neighbours are already on, and a new card written from the board itself.
/// A port of `src/app/core/boards/make.ts`, one to one.
///
/// Each answers the note's own markdown - anchors added to the ends of lines, a fence set in - and leaves every other
/// word where it was, which is the point of the standard (docs/BOARDS.md). None of them writes anything: the caller
/// applies what comes back, the editor in one transaction, the recorder to the note it is filing into.
///
/// What differs: the names and the shapes. `NEW_COLUMNS` is [newColumns]; `BoardMade`, `ListBoard`, `CardAdded` and
/// `CardMade` are immutable classes, and the object literals inside them (`line`, `fence`, a list's span) are records
/// under the web's field names. `Array.splice` is written out ([_splice]) with JavaScript's forgiving of a start
/// outside the list, and the neighbours' sort is made stable by hand, as JavaScript's is.
library;

import '../item_syntax.dart' show isDoneName, jsTrim, listLead;
import 'columns.dart' show columnOf, doneColumn, putCardAt;
import 'fence.dart' show Board, BoardColumn, boardAt, boardsIn, fencedLines, writeBoard;
import 'items.dart' show Item, anchorFor, isItemLine, itemOnLine, itemWords, itemsIn, withAnchor;

/// The columns a note is given when its items are made into a board (`NEW_COLUMNS`).
const List<String> newColumns = ['To do', 'Doing', 'Done'];

/// JavaScript's `Number.MAX_SAFE_INTEGER`: an index past the end of any lane.
const int _theEnd = 9007199254740991;

/// `lines[index] ?? ''`: the line there, or nothing where the list has none.
String _lineAt(List<String> lines, int index) => index >= 0 && index < lines.length ? lines[index] : '';

/// `Array.prototype.splice(start, 0, ...items)`: a start before the list's own start counts from its end, and one
/// past its end is its end.
void _splice(List<String> lines, int start, List<String> items) {
  final at = start < 0 ? (lines.length + start < 0 ? 0 : lines.length + start) : (start > lines.length ? lines.length : start);
  lines.insertAll(at, items);
}

/// A note turned into a board: the words it becomes, and what it took (`BoardMade`).
class BoardMade {
  const BoardMade({required this.doc, required this.cards, required this.done});

  final String doc;

  /// How many items became cards.
  final int cards;

  /// How many of them were already ticked, and so went straight to Done.
  final int done;
}

/// A list made into a board (Matt: "transform the task management note i have into kanban format").
///
/// Every list item in the note is given an anchor if it has none, and a fence of columns goes in under the note's
/// title naming them all: the ticked ones in Done, the rest in the first column. Nothing else about the note is
/// touched - the words, the headings and the order stay exactly as they were, which is the point of the standard.
///
/// Null when there is nothing to do: a note with no list, or one that is a board already.
BoardMade? boardFrom(String doc, [List<String> columns = newColumns]) {
  if (boardsIn(doc).any((board) => board.to > board.from)) return null;
  final lines = doc.split('\n');
  final cards = _anchorItems(lines, doc, 1, lines.length);
  if (cards.isEmpty) return null;
  final fence = _fenceFor(cards, columns);
  // Under the note's title, where a board is read first; a note that opens with words takes the board above them.
  final title = _title.hasMatch(_lineAt(lines, 0));
  final blank = title && jsTrim(_lineAt(lines, 1)).isEmpty;
  _splice(lines, blank ? 2 : (title ? 1 : 0), title && !blank ? ['', ...fence] : fence);
  return BoardMade(doc: lines.join('\n'), cards: cards.length, done: cards.where((card) => card.done).length);
}

final RegExp _title = RegExp(r'^#\s+\S');

/// Every list item from line [from] to line [to] given an anchor where it has none, in place in [lines], and each
/// one's anchor and whether it is ticked, in order. A list inside a block of code is code, not a list: its lines are
/// left exactly as they are.
List<({String id, bool done})> _anchorItems(List<String> lines, String doc, int from, int to) {
  final taken = [for (final item in itemsIn(doc)) item.id];
  final inside = fencedLines(lines);
  final cards = <({String id, bool done})>[];
  final last = to < lines.length ? to : lines.length;
  for (var index = from - 1 < 0 ? 0 : from - 1; index < last; index += 1) {
    final text = lines[index];
    if (inside.contains(index + 1) || !isItemLine(text)) continue;
    final already = itemOnLine(text);
    final id = already?.id ?? anchorFor(itemWords(text) ?? text, taken);
    if (already == null) {
      taken.add(id);
      lines[index] = withAnchor(text, id);
    }
    cards.add((id: id, done: listLead(text)?.done == true));
  }
  return cards;
}

/// A board fence laying [cards] out in [columns]: the ticked ones in the column called Done, the rest in the first.
List<String> _fenceFor(List<({String id, bool done})> cards, List<String> columns) {
  final named = columns.isNotEmpty ? [...columns] : [...newColumns];
  final called = named.indexWhere(isDoneName);
  final last = called >= 0 ? called : named.length - 1;
  final board = [
    for (var index = 0; index < named.length; index += 1)
      BoardColumn(
        name: named[index],
        cards: [
          for (final card in cards)
            if ((card.done ? last : 0) == index) card.id,
        ],
      ),
  ];
  return ['```board', writeBoard(board), '```', ''];
}

final RegExp _indented = RegExp(r'^\s{2,}\S');

/// The list line [line] is in, from its first item to its last, counting from 1; or null where the line is in no list
/// (Matt: "add ability to auto list a section of list items into a board").
///
/// A list is the run of item lines around the line, with the indented lines that belong to its items and a single
/// blank line between two of them. A heading, a paragraph, a block of code, or two blank lines end it.
({int from, int to})? listAround(String doc, int line) {
  final lines = doc.split('\n');
  final inside = fencedLines(lines);
  bool member(int index) {
    if (index < 0 || index >= lines.length || inside.contains(index + 1)) return false;
    final text = lines[index];
    return isItemLine(text) || _indented.hasMatch(text);
  }

  bool blank(int index) => index >= 0 && index < lines.length && jsTrim(lines[index]).isEmpty;
  var first = line - 1;
  if (!member(first)) return null;
  var last = first;
  for (;;) {
    if (member(first - 1)) {
      first -= 1;
    } else if (blank(first - 1) && member(first - 2)) {
      first -= 2;
    } else {
      break;
    }
  }
  for (;;) {
    if (member(last + 1)) {
      last += 1;
    } else if (blank(last + 1) && member(last + 2)) {
      last += 2;
    } else {
      break;
    }
  }
  // A list starts and ends with an item: indented lines outside those belong to something else.
  while (first <= last && !isItemLine(_lineAt(lines, first))) {
    first += 1;
  }
  while (last >= first && !isItemLine(_lineAt(lines, last))) {
    last -= 1;
  }
  return first <= last ? (from: first + 1, to: last + 1) : null;
}

/// One list made into a board: what changes, where, and the board's opening line once it is in (`ListBoard`).
class ListBoard extends BoardMade {
  const ListBoard({required super.doc, required super.cards, required super.done, required this.lines, required this.fence, required this.open});

  /// Item lines that gained an anchor, each with its new words, numbered as the note was.
  final List<({int number, String text})> lines;

  /// The fence, and the line of the note as it was that it goes in above.
  final ({int before, String text}) fence;

  /// The line the board opens on, in the note as it becomes.
  final int open;
}

/// The items from line [from] to line [to] made into a board of their own, set in just above them: each item named,
/// the ticked ones in Done. The rest of the note, other boards included, is left as it is, so a note can hold one
/// board per list.
///
/// Null where there is nothing to make: no items in the lines, or a board already sitting right above them.
ListBoard? boardFromList(String doc, int from, int to, [List<String> columns = newColumns]) {
  final lines = doc.split('\n');
  var above = from - 2;
  while (above >= 0 && jsTrim(_lineAt(lines, above)).isEmpty) {
    above -= 1;
  }
  if (above >= 0 && boardsIn(doc).any((board) => board.to > board.from && board.to == above + 1)) return null;
  final before = [...lines];
  final cards = _anchorItems(lines, doc, from, to);
  if (cards.isEmpty) return null;
  final changed = [
    for (var index = 0; index < lines.length; index += 1)
      if (lines[index] != before[index]) (number: index + 1, text: lines[index]),
  ];
  final fence = _fenceFor(cards, columns);
  // A line of words straight above the list keeps a blank line between it and the board.
  final gap = from > 1 && jsTrim(_lineAt(lines, from - 2)).isNotEmpty;
  final block = gap ? ['', ...fence] : fence;
  _splice(lines, from - 1, block);
  return ListBoard(
    doc: lines.join('\n'),
    cards: cards.length,
    done: cards.where((card) => card.done).length,
    lines: changed,
    fence: (before: from, text: '${block.join('\n')}\n'),
    open: from + (gap ? 1 : 0),
  );
}

/// What putting the item on line `line` onto a board changes: the line itself, when it needs an anchor, and the fence
/// (`CardAdded`).
class CardAdded {
  const CardAdded({required this.id, required this.line, required this.fence, required this.column});

  final String id;

  /// The item's line rewritten with its anchor, or null when it already had one.
  final ({int number, String text})? line;

  /// The board's fence body rewritten, and which lines it lies between.
  final ({int from, int to, String body}) fence;

  /// The column it went into.
  final String column;
}

/// The list item on [line] put on a board (Matt: "add an 'add to board' option when other items in the list are in a
/// board already").
///
/// The board is the one that already holds the item's neighbours - the list it stands in, [listAround] - since a list
/// with cards on a board is almost always the board it belongs to; failing that, the nearest board above it, else the
/// first in the note.
///
/// It lands in the first lane, or in Done when it is already ticked: a new card is something to do, whatever lane the
/// item next to it sits in. Within that lane it goes in beside the nearest neighbour that is already there, on the
/// same side as the note has it, so a board keeps the list's own order instead of collecting new cards at the end.
///
/// Null when the line is not a list item, there is no board to put it on, or its anchor is already a card.
CardAdded? addToBoard(String doc, int line) {
  final lines = doc.split('\n');
  if (line < 1 || line > lines.length) return null;
  final text = lines[line - 1];
  if (!isItemLine(text)) return null;
  final item = itemOnLine(text);
  final boards = boardsIn(doc).where((board) => board.to > board.from && board.columns.isNotEmpty).toList();
  if (boards.isEmpty) return null;
  final all = itemsIn(doc);
  final id = item?.id ?? anchorFor(itemWords(text) ?? text, all.map((other) => other.id));
  // The item's neighbours in its own list, nearest first: which board they are on, and where on it.
  final around = listAround(doc, line);
  final mates = around == null ? <Item>[] : all.where((other) => other.line >= around.from && other.line <= around.to && other.line != line).toList();
  // Of two as near as each other, the one the note has first comes first: they are in the note's order already.
  mates.sort((one, two) {
    final by = (one.line - line).abs() - (two.line - line).abs();
    return by != 0 ? by : one.line - two.line;
  });
  final held = <({Item mate, Board board})>[];
  for (final mate in mates) {
    for (final board in boards) {
      if (columnOf(board.columns, mate.id) >= 0) {
        held.add((mate: mate, board: board));
        break;
      }
    }
  }
  Board? above;
  for (final board in boards.reversed) {
    if (board.to < line) {
      above = board;
      break;
    }
  }
  final board = held.isNotEmpty ? held.first.board : (above ?? boards.first);
  if (columnOf(board.columns, id) >= 0) return null;
  final done = doneColumn(board.columns);
  final into = item?.done == true && done >= 0 ? done : 0;
  // Beside the nearest neighbour already in that lane, on the side the note has it: the list's order, kept.
  Item? beside;
  for (final found in held) {
    if (identical(found.board, board) && columnOf(board.columns, found.mate.id) == into) {
      beside = found.mate;
      break;
    }
  }
  final cards = board.columns[into].cards;
  final at = beside != null ? cards.indexOf(beside.id) + (beside.line < line ? 1 : 0) : _theEnd;
  final columns = putCardAt(board.columns, id, into, at);
  return CardAdded(
    id: id,
    line: item != null ? null : (number: line, text: withAnchor(text, id)),
    fence: (from: board.from, to: board.to, body: writeBoard(columns)),
    column: columns[into].name,
  );
}

/// A card made from the board itself: the new line to put in the note, where it goes, and the fence that names it
/// (`CardMade`).
class CardMade {
  const CardMade({required this.id, required this.at, required this.text, required this.fence});

  final String id;

  /// The line number the new line becomes.
  final int at;

  /// The line to write.
  final String text;
  final ({int from, int to, String body}) fence;
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _indent = RegExp(r'^(\s*)');

/// A new card in column [column] of the board whose fence opens on [open], carrying [words] (Matt: "make the UI / UX
/// of these boards friendlier on mobile", and "a button on each board to add an item, it should add the item to the
/// list the board is derived from"): typing markdown to add one is not something to do on a phone, so the board
/// writes the line itself.
///
/// The words come first and the line is made with them, so the anchor is named after what the item says from the
/// start. A card written empty and named later would be `^item`, `^item-2`, `^item-3` for as long as nobody renamed
/// it, and those are the names a person points at. No words, no card.
///
/// The item goes in under the last item the board already names, so a board's items stay together, and under the
/// fence when it names none yet. It is written as a to-do, since a column is a place work waits in. The card goes in
/// at [index] in its column: the top by default, under the field it was typed into.
CardMade? newCard(String doc, int open, int column, String words, [int index = 0]) {
  final said = jsTrim(words.replaceAll(_spaces, ' '));
  final board = boardAt(doc, open);
  if (said.isEmpty || board == null || board.columns.isEmpty || column < 0 || column >= board.columns.length) return null;
  final named = {for (final held in board.columns) ...held.cards};
  final taken = itemsIn(doc);
  Item? last;
  for (final item in taken) {
    if (named.contains(item.id) && item.line > board.to) last = item;
  }
  final id = anchorFor(said, taken.map((item) => item.id));
  // Written at the indent of the item it follows, so a card added under a nested list stays in that list.
  final under = last != null ? _lineAt(doc.split('\n'), last.line - 1) : '';
  final indent = _indent.firstMatch(under)?.group(1) ?? '';
  return CardMade(
    id: id,
    at: last != null ? last.line + 1 : board.to + 1,
    text: '$indent- [ ] $said ^$id',
    fence: (from: board.from, to: board.to, body: writeBoard(putCardAt(board.columns, id, column, index))),
  );
}
