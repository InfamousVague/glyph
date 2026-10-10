/// The ```board fence: a board's columns read from its body and written back, its settings (`height=18`), where each
/// board in a note is, and a board taken away as words. A port of `src/app/core/boards/fence.ts`, one to one.
///
/// A fence's lines are its columns, `To do: ship-page, ask-sam`, each naming anchors. The ids are read against the
/// note's own anchors (items.dart), so a lane written or dictated by hand still finds its cards, and written back the
/// one way a person would type them. The fence is known here and nowhere else (docs/BOARDS.md). So is the question
/// every reader of a note's lists asks first, which lines sit inside a fenced block at all and are code rather than a
/// list.
///
/// What differs: the names and the shapes. The web's `BOARD_HEIGHT` is [boardHeight], a record of two doubles;
/// `BoardColumn` and `Board` are immutable classes with value equality; a height is a `double`, written into a fence
/// the way JavaScript writes a number (`18`, not `18.0`).
library;

import 'dart:math' as math;

import '../item_syntax.dart' show anchorNamePattern, jsTrim;
import 'items.dart';

bool _sameList<T>(List<T> one, List<T> two) {
  if (one.length != two.length) return false;
  for (var i = 0; i < one.length; i += 1) {
    if (one[i] != two[i]) return false;
  }
  return true;
}

/// One column of a board (`BoardColumn`).
class BoardColumn {
  const BoardColumn({required this.name, required this.cards});

  final String name;

  /// The anchors of the cards in it, in the order they sit.
  final List<String> cards;

  @override
  bool operator ==(Object other) => other is BoardColumn && other.name == name && _sameList(other.cards, cards);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(cards));

  @override
  String toString() => 'BoardColumn($name: ${cards.join(', ')})';
}

/// An anchor name alone: what a lane's id must be to be read as it is written.
final RegExp _named = RegExp('^$anchorNamePattern\$');

/// The fence that opens a board, and what follows the word: `board`, or `board height=18`. What follows is the
/// board's settings as `name=value` words, which any other renderer takes as part of the block's info string.
final RegExp _open = RegExp(r'^\s*(`{3,}|~{3,})\s*board(?:\s+([^\n]*?))?\s*$', caseSensitive: false);

/// `height=18`: how tall a board's lanes are, in the lanes' own ems (Matt: "make board height configurable").
final RegExp _height = RegExp(r'(?:^|\s)height=(\d+(?:\.\d+)?)(?:em)?(?=\s|$)', caseSensitive: false);

/// The shortest and tallest a board's lanes can be set, in ems: a card and a half, and a long screen
/// (`BOARD_HEIGHT`).
const ({double min, double max}) boardHeight = (min: 5, max: 60);

/// The columns a board fence's body lays out. A line with no colon is a column with no cards.
List<BoardColumn> readBoard(String body, [Set<String> known = const {}]) {
  final names = <String>[];
  final held = <List<String>>[];
  // An anchor names one item, and a card is one card: an id is read into the first lane that has it, and a second
  // mention of it, in that lane or another, is dropped. Written by hand into two lanes, it used to be drawn twice in
  // the first of them, and the lane a person had put it in showed nothing at all.
  final taken = <String>{};
  for (final line in body.split('\n')) {
    final text = jsTrim(line);
    if (text.isEmpty) continue;
    final at = text.indexOf(':');
    final name = jsTrim(at >= 0 ? text.substring(0, at) : text);
    if (name.isEmpty) continue;
    final cards = <String>[];
    for (final said in (at >= 0 ? text.substring(at + 1) : '').split(',')) {
      final id = _anchorRead(said, known);
      if (id.isEmpty || !taken.add(id)) continue;
      cards.add(id);
    }
    final already = names.indexWhere((other) => other.toLowerCase() == name.toLowerCase());
    if (already >= 0) {
      held[already].addAll(cards);
    } else {
      names.add(name);
      held.add(cards);
    }
  }
  return [for (var i = 0; i < names.length; i += 1) BoardColumn(name: names[i], cards: held[i])];
}

final RegExp _caret = RegExp(r'^\^');
final RegExp _notAnchor = RegExp('[^a-z0-9_-]+');
final RegExp _edges = RegExp(r'^[-_]+|[-_]+$');

/// An id in a fence read as the anchor it means: the caret a person may write in front of it taken off, and then, for
/// anything that is not an anchor already, upper case down and everything an anchor cannot hold turned into the hyphen
/// it would have been. `Fix Login` is `fix-login`.
///
/// That second reading is only taken when the note really has an item with that anchor ([known]), so a lane written or
/// dictated by hand still finds its cards, while words after a colon that name nothing are left alone rather than
/// drawn as a card of their own. Read loosely, written back the one way ([writeBoard]), as an item's own anchor is
/// (docs/BOARDS.md). Empty for an id this board cannot use.
String _anchorRead(String said, Set<String> known) {
  final plain = jsTrim(said).replaceFirst(_caret, '');
  if (_named.hasMatch(plain)) return plain;
  final id = plain.toLowerCase().replaceAll(_notAnchor, '-').replaceAll(_edges, '');
  return _named.hasMatch(id) && known.contains(id) ? id : '';
}

final RegExp _bareColon = RegExp(r':\s+$');

/// The columns written back as a fence's body, exactly as a person would type them.
String writeBoard(List<BoardColumn> columns) =>
    columns.map((column) => '${column.name}: ${column.cards.join(', ')}'.replaceFirst(_bareColon, ':')).join('\n');

/// One board in a note (`Board`).
class Board {
  const Board({required this.from, required this.to, required this.body, required this.columns, required this.height});

  /// The line the opening fence is on, counting from 1.
  final int from;

  /// The line the closing fence is on; the same as [from] when the fence never closes.
  final int to;

  /// The fence's body: the lines between.
  final String body;
  final List<BoardColumn> columns;

  /// How tall the lanes are set, in ems, or null for the board's own height.
  final double? height;

  @override
  bool operator ==(Object other) =>
      other is Board && other.from == from && other.to == to && other.body == body && _sameList(other.columns, columns) && other.height == height;

  @override
  int get hashCode => Object.hash(from, to, body, Object.hashAll(columns), height);

  @override
  String toString() => 'Board($from-$to, $columns, height: $height)';
}

/// The lanes' height a fence's settings name, held between the shortest and tallest a board can be; or null.
double? _heightOf(String settings) {
  final found = _height.firstMatch(settings);
  final value = found != null ? (double.tryParse(found.group(1) ?? '') ?? double.nan) : double.nan;
  return value.isFinite ? clampHeight(value) : null;
}

/// A height kept within what a board can be, to the half em.
double clampHeight(num ems) => (math.min(boardHeight.max, math.max(boardHeight.min, ems.toDouble())) * 2).roundToDouble() / 2;

/// A number as JavaScript writes one into a string: `18`, `21.5`.
String _number(double value) => value.isFinite && value == value.truncateToDouble() ? value.toStringAsFixed(0) : value.toString();

final RegExp _openStart = RegExp(r'^\s*(?:`{3,}|~{3,})\s*board', caseSensitive: false);
final RegExp _spaces = RegExp(r'\s+');

/// A board's opening fence with its lanes' height set, or taken off with null: the rest of the line - the fence, the
/// word, any other settings - as it was. A line that does not open a board comes back as it is.
String withBoardHeight(String openLine, num? height) {
  final open = _open.firstMatch(openLine);
  if (open == null) return openLine;
  final start = _openStart.firstMatch(openLine)?.group(0) ?? '${open.group(1)}board';
  final rest = jsTrim((open.group(2) ?? '').replaceFirst(_height, ' ').replaceAll(_spaces, ' '));
  final settings = [height == null ? '' : 'height=${_number(clampHeight(height))}', rest].where((part) => part.isNotEmpty).join(' ');
  return '$start${settings.isNotEmpty ? ' $settings' : ''}';
}

/// What a line that opens a board says: the fence it opens with and the settings after the word; null for any
/// other line. With [closesBoardFence] and [boardRead] it is [boardsIn] a line at a time, for a reader that keeps
/// what it has read of a note's lines (lib/editor/view/line_facts.dart) rather than splitting the note again.
({String fence, String settings})? boardOpening(String line) {
  final open = _open.firstMatch(line);
  return open == null ? null : (fence: open.group(1) ?? '```', settings: open.group(2) ?? '');
}

/// A line that is a run of backticks or of tildes and nothing else: what may close a fence. Its mark and how many.
final RegExp _bare = RegExp(r'^\s*(`{3,}|~{3,})\s*$');

/// The run a bare fence line is, or null for any other line.
String? bareFence(String line) => _bare.firstMatch(line)?.group(1);

/// Whether a bare fence line's run [bare] closes a board opened with [fence]: the same mark, at least as many.
bool closesBoardFence(String bare, String fence) => (bare[0] == '~') == (fence[0] == '~') && bare.length >= fence.length;

/// The board whose opening fence is on line [from] and whose closing one is on line [to] (the same line where it
/// never closes), from its opening's [settings], its [body] and the note's own [anchors].
///
/// A body's columns are kept for the anchors they were read against: a board is read again for every letter typed
/// anywhere in its note (a dozen patterns to a card), and almost always its own lines and the note's anchors are
/// what they were.
Board boardRead({required int from, required int to, required String body, required String settings, required Set<String> anchors}) {
  var read = _read[body];
  if (read == null || read.anchors.length != anchors.length || !read.anchors.containsAll(anchors)) {
    final columns = List<BoardColumn>.unmodifiable(<BoardColumn>[
      for (final column in readBoard(body, anchors)) BoardColumn(name: column.name, cards: List<String>.unmodifiable(column.cards)),
    ]);
    read = (anchors: anchors, columns: columns);
    if (_read.length >= 32) _read.clear();
    _read[body] = read;
  }
  return Board(from: from, to: to, body: body, columns: read.columns, height: _heightOf(settings));
}

final Map<String, ({Set<String> anchors, List<BoardColumn> columns})> _read = <String, ({Set<String> anchors, List<BoardColumn> columns})>{};

/// Every board in the note, in order.
List<Board> boardsIn(String doc) {
  final lines = doc.split('\n');
  final boards = <Board>[];
  // The note's own anchors, read once and only when a board is found: what a lane's ids are read against.
  Set<String>? anchors;
  for (var i = 0; i < lines.length; i += 1) {
    final open = boardOpening(lines[i]);
    if (open == null) continue;
    var end = i;
    for (var j = i + 1; j < lines.length; j += 1) {
      final bare = bareFence(lines[j]);
      if (bare != null && closesBoardFence(bare, open.fence)) {
        end = j;
        break;
      }
    }
    final body = end > i ? lines.sublist(i + 1, end).join('\n') : '';
    anchors ??= {for (final item in itemsIn(doc)) item.id};
    boards.add(boardRead(from: i + 1, to: end + 1, body: body, settings: open.settings, anchors: anchors));
    i = end;
  }
  return boards;
}

/// The board [line] is inside, fence lines included, or null.
Board? boardAt(String doc, int line) {
  for (final board in boardsIn(doc)) {
    if (board.to > board.from && line >= board.from && line <= board.to) return board;
  }
  return null;
}

/// A whole board as words to take away (Matt: "the task management board needs to be copyable but formatting is
/// splitting it up"). Drawn as columns, a board cannot be dragged over and copied a piece at a time, and its fence and
/// its items sit apart in the note anyway. This is both together, in the note's own markdown: the fence, then every
/// item it names in the order the note has them. Pasted into another note it is the same working board; pasted
/// anywhere else it reads as a list under its columns.
///
/// Null when [line] is not inside a board.
String? boardCopy(String doc, int line) {
  final lines = doc.split('\n');
  final board = boardAt(doc, line);
  if (board == null) return null;
  final named = {for (final column in board.columns) ...column.cards};
  final items = [
    for (final item in itemsIn(doc))
      if (named.contains(item.id)) lines[item.line - 1],
  ];
  final fence = lines.sublist(board.from - 1, board.to).join('\n');
  return items.isNotEmpty ? '$fence\n\n${items.join('\n')}\n' : '$fence\n';
}

final RegExp _edge = RegExp(r'^\s*(`{3,}|~{3,})');

/// Every line inside a fenced block, counting from 1: what is code and not markdown.
Set<int> fencedLines(List<String> lines) {
  final inside = <int>{};
  var fence = '';
  for (var index = 0; index < lines.length; index += 1) {
    final text = lines[index];
    final edge = _edge.firstMatch(text)?.group(1);
    if (fence.isNotEmpty) {
      inside.add(index + 1);
      if (edge != null && edge.startsWith(fence[0]) && edge.length >= fence.length && jsTrim(jsTrim(text).substring(edge.length)).isEmpty) fence = '';
      continue;
    }
    if (edge != null) {
      fence = edge;
      inside.add(index + 1);
    }
  }
  return inside;
}
