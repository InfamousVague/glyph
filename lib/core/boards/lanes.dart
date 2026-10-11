/// Lanes: a board's columns found by name, and a card added to one or moved into one, in the note's own markdown. A
/// port of `src/app/core/boards/lanes.ts`.
///
/// "Hey Ghost, add call Sam to Doing", said on the board's own Speak, puts a card in Doing as it is said: the live
/// reader names the lane and the recorder's placing adds to it (with [lanesOf] and [addToLane]). Matt: "add voice
/// commands and cues for adding to swimlanes on the board".
///
/// [matchLane] and [moveToLane] weighed a lane by the name a person says and moved a card into it as a drag would,
/// for the phrase-at-a-time reader's "move fix login to the Done column". That reader has gone (../glyph
/// docs/DESIGN.md §127), and nothing in the app calls them now; they are kept, tested, until it is decided whether
/// moving a card by voice comes back. A lane is weighed the way a note's name is, and a card moved has its box
/// ticked going into Done and cleared coming out.
///
/// What differs: `similarity`, the weighing, is `capture/route.ts`'s, the recorder's, which is a later stage of the
/// port (8G); it is written out here, word for word, until that file lands and can hand its own on. What
/// [addToLane] and [moveToLane] answer are records.
library;

import 'dart:math' as math;

import '../item_syntax.dart' show isDoneName, jsTrim, listLead;
import 'columns.dart' show doneColumn, putCard;
import 'fence.dart' show Board, BoardColumn, boardAt, boardsIn, fencedLines, writeBoard;
import 'items.dart' show anchorFor, isItemLine, itemOnLine, itemWords, itemsIn, setItemDone, withAnchor;
import 'make.dart' show newCard;

/// A board's column, found by name in the note's markdown.
class Lane {
  const Lane({required this.name, required this.board, required this.column});
  final String name;

  /// The line the lane's board opens on, counting from 1.
  final int board;

  /// Which of that board's columns.
  final int column;

  @override
  bool operator ==(Object other) => other is Lane && other.name == name && other.board == board && other.column == column;

  @override
  int get hashCode => Object.hash(name, board, column);

  @override
  String toString() => 'Lane($name, board $board, column $column)';
}

/// Every lane of every board in the note, in order.
List<Lane> lanesOf(String body) => [
      for (final board in boardsIn(body))
        if (board.to > board.from)
          for (var index = 0; index < board.columns.length; index += 1) Lane(name: board.columns[index].name, board: board.from, column: index),
    ];

// ---- capture/route.ts `similarity` --------------------------------------------------------------------------------

final RegExp _notWord = RegExp(r'[^a-z0-9\s]');
final RegExp _spaces = RegExp(r'\s+');
const Set<String> _filler = {'the', 'my', 'a', 'our', 'note', 'notes'};

/// Lowercase words with punctuation and filler gone, and a plural's s dropped.
List<String> _wordsOf(String text) => [
      for (final w in text.toLowerCase().replaceAll(_notWord, ' ').split(_spaces))
        if (w.isNotEmpty && !_filler.contains(w)) w.length > 3 && w.endsWith('s') && !w.endsWith('ss') ? w.substring(0, w.length - 1) : w,
    ];

Map<String, int> _bigrams(String text) {
  final squashed = text.replaceAll(_spaces, '');
  final counts = <String, int>{};
  for (var i = 0; i < squashed.length - 1; i += 1) {
    final pair = squashed.substring(i, i + 2);
    counts[pair] = (counts[pair] ?? 0) + 1;
  }
  return counts;
}

/// Sørensen-Dice over letter pairs, spaces ignored: "week end trip" and "weekend trip" score 1.
double _dice(String a, String b) {
  final x = _bigrams(a);
  final y = _bigrams(b);
  var total = 0;
  for (final n in x.values) {
    total += n;
  }
  for (final n in y.values) {
    total += n;
  }
  if (total == 0) return a == b ? 1 : 0;
  var shared = 0;
  x.forEach((pair, n) => shared += math.min(n, y[pair] ?? 0));
  return (2 * shared) / total;
}

/// How well a spoken [name] fits a [title], 0 to 1.
double _similarity(String name, String title) {
  final said = _wordsOf(name);
  final titled = _wordsOf(title);
  if (said.isEmpty || titled.isEmpty) return 0;
  final letters = _dice(said.join(' '), titled.join(' '));
  final shared = said.where(titled.contains).length;
  final words = shared / math.max(said.length, titled.length);
  // A name that is the whole start of the title ("weekend" for "Weekend trip to the lake") is a fair pick, a little
  // below an exact one.
  final prefix = titled.take(said.length).join(' ') == said.join(' ') ? 0.85 : 0.0;
  return math.max(letters, math.max(words, prefix));
}

// ---- lanes --------------------------------------------------------------------------------------------------------

final RegExp _stops = RegExp(r'[.,;:!?"“”]+');
final RegExp _leadIn = RegExp(r'^(?:(?:the|my|our)\s+)+', caseSensitive: false);
final RegExp _laneWord = RegExp(r'\s+(?:swim\s?lanes?|lanes?|columns?)$', caseSensitive: false);

/// A lane's name as it is said: no "the" in front, and no "lane", "column" or "swimlane" after it.
String _spokenLane(String text) => jsTrim(jsTrim(text.replaceAll(_stops, ' ').replaceAll(_spaces, ' ')).replaceFirst(_leadIn, '').replaceFirst(_laneWord, ''));

final RegExp _finished = RegExp(r'^(?:done|finished|complete|completed)$', caseSensitive: false);

/// The lane [spoken] names, and how well, 0 to 1, on the same footing as a note's name, so the recorder can weigh a
/// lane against a note of the same name. Null when no lane is a clear match: the best must reach 0.72 and beat the
/// next by 0.08, as a note's name must. "Finished" and "complete" find the board's Done lane.
({Lane lane, double score})? matchLane(String spoken, List<Lane> lanes) {
  final said = _spokenLane(spoken);
  if (said.length < 2) return null;
  ({Lane lane, double score})? best;
  var second = 0.0;
  for (final lane in lanes) {
    var score = _similarity(said, lane.name);
    if (_finished.hasMatch(said) && isDoneName(lane.name)) score = math.max(score, 0.95);
    if (best == null || score > best.score) {
      second = best?.score ?? second;
      best = (lane: lane, score: score);
    } else if (score > second) {
      second = score;
    }
  }
  if (best == null || best.score < 0.72) return null;
  if (best.score - second < 0.08 && best.score < 0.99) return null;
  return best;
}

/// The board a lane belongs to in [body] as it is now, or null when that board or column is not there any more.
Board? _boardOfLane(String body, Lane lane) {
  final board = boardAt(body, lane.board);
  if (board == null || board.from != lane.board) return null;
  if (lane.column < 0 || lane.column >= board.columns.length) return null;
  return board.columns[lane.column].name == lane.name ? board : null;
}

/// The page's `lines.splice(start, count, ...items)`, with its clamping.
void _splice(List<String> lines, int start, int count, List<String> items) {
  final at = start > lines.length ? lines.length : (start < 0 ? 0 : start);
  final most = lines.length - at;
  final taken = count < 0 ? 0 : (count > most ? most : count);
  lines.replaceRange(at, at + taken, items);
}

/// [lines] with a board's fence body rewritten: the lines between its two fence lines.
void _withFence(List<String> lines, Board board, List<BoardColumn> columns) => _splice(lines, board.from, board.to - board.from - 1, writeBoard(columns).split('\n'));

/// A new to-do with [words], on the lane: the line written under the board's last item (make.dart `newCard`) and its
/// card put at the top of the lane. Null for no words, or a lane that is not in [body].
({String body, String line})? addToLane(String body, Lane lane, String words) {
  if (_boardOfLane(body, lane) == null) return null;
  final made = newCard(body, lane.board, lane.column, words);
  if (made == null) return null;
  final lines = body.split('\n');
  // The item first, since it goes in below the board and so moves none of the board's lines.
  _splice(lines, math.min(made.at - 1, lines.length), 0, [made.text]);
  _splice(lines, made.fence.from, made.fence.to - made.fence.from - 1, made.fence.body.split('\n'));
  return (body: lines.join('\n'), line: made.text);
}

final RegExp _notToken = RegExp('[^a-z0-9]+');

/// The words worth matching an item on: lower case, letters and digits, three characters or more.
List<String> _tokensOf(String text) => jsTrim(text.toLowerCase().replaceAll(_notToken, ' ')).split(' ').where((token) => token.length >= 3).toList();

/// A list item's words, box and anchor off; '' for a line that is not one.
String _wordsOn(String line) => itemWords(line) ?? '';

/// The list item [words] names, moved to the lane: named with an anchor if it has none, its card taken from wherever
/// it was on that board and put at the end of the lane. Moved into the Done lane its box is ticked, and out of it
/// unticked, as a card dragged there would be; `ticked` says which happened, or null when the box was left alone.
///
/// The item is the note's list item whose words best match - three words in five, as a lost mark is found again -
/// anywhere in the note but a block of code. Null when none matches that well, or the lane is not in [body].
({String body, ({String id, String text, int line}) item, bool? ticked})? moveToLane(String body, String words, Lane lane) {
  final board = _boardOfLane(body, lane);
  if (board == null) return null;
  final wanted = _tokensOf(words);
  if (wanted.isEmpty) return null;
  final lines = body.split('\n');
  final inside = fencedLines(lines);
  var best = -1;
  var bestScore = 0.0;
  for (var index = 0; index < lines.length; index += 1) {
    final text = lines[index];
    if (inside.contains(index + 1) || !isItemLine(text)) continue;
    final have = _tokensOf(_wordsOn(text)).toSet();
    final score = wanted.where(have.contains).length / wanted.length;
    if (score > bestScore) {
      bestScore = score;
      best = index;
    }
  }
  if (best < 0 || bestScore < 0.6) return null;

  final original = lines[best];
  final already = itemOnLine(original);
  final id = already?.id ?? anchorFor(_wordsOn(original), itemsIn(body).map((item) => item.id));
  var line = withAnchor(original, id);
  final columns = putCard(board.columns, id, lane.column);
  final done = doneColumn(columns);
  final box = listLead(line)?.done;
  bool? ticked;
  if (box != null && done >= 0) {
    final into = lane.column == done;
    if (into != box) {
      line = setItemDone(line, into);
      ticked = into;
    }
  }
  lines[best] = line;
  _withFence(lines, board, columns);
  return (body: lines.join('\n'), item: (id: id, text: _wordsOn(line), line: best + 1), ticked: ticked);
}
