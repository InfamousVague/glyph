/// What the editor's extensions read from a note's lines, each kept once for every line of a document (`LineFact`,
/// lib/editor/state/text.dart) and shared by whoever asks: the films' cards and the pictures both ask whether a
/// line is a film's, and it is read once.
///
/// The web app's extensions read the whole note again for each of these on every keystroke, which a browser's
/// compiled regular expressions carry and a phone's interpreted ones do not: typing in a note of twelve thousand
/// letters was a late frame for every letter. Kept with the tree, a keystroke reads the lines of the leaf it made.
///
/// Each reader asks something cheap first (whether the line has the few letters the thing is written with), so a
/// note's first reading is a search of each line and not a pattern put to it.
library;

import '../../core/boards/fence.dart' show Board, bareFence, boardOpening, boardRead, closesBoardFence;
import '../../core/boards/items.dart' show Item, ItemRef, itemOnLine, refsIn;
import '../../core/images.dart' show imageRef;
import '../../core/item_syntax.dart' show anchorSpan;
import '../../core/place_refs.dart' show PlaceLine, placeOfLine;
import '../../core/video_refs.dart' show VideoLine, videoOfLine;
import '../state/text.dart';

/// The film a line is (`videoOfLine`).
final LineFact<VideoLine> filmFacts = LineFact<VideoLine>(videoOfLine);

/// The place a line is (`placeOfLine`).
final LineFact<PlaceLine> placeFacts = LineFact<PlaceLine>(placeOfLine);

/// A line's first picture, its name and its caption; none for a film's line, whose poster its card draws.
final LineFact<({String name, String caption})> pictureFacts = LineFact<({String name, String caption})>((text) {
  if (!text.contains('](image/')) return null;
  if (videoOfLine(text) != null) return null;
  for (final match in imageRef.allMatches(text)) {
    final name = match.group(2) ?? '';
    if (name.isEmpty) continue;
    return (name: name, caption: match.group(1) ?? '');
  }
  return null;
});

/// The anchored item a line is (`itemOnLine`): a list item that ends with its `^anchor`. Its `line` is 0, as
/// `itemOnLine` answers it; the line's number is the fact's own.
final LineFact<Item> itemFacts = LineFact<Item>((text) => text.contains('^') ? itemOnLine(text) : null);

/// Where the `^anchor` naming a line's item sits in the line (`anchorSpan` of an item's line).
final LineFact<({String id, int from, int to})> itemAnchorFacts = LineFact<({String id, int from, int to})>((text) {
  if (!text.contains('^') || itemOnLine(text) == null) return null;
  return anchorSpan(text);
});

/// The pointers at anchors on a line, `[[#^ask-sam]]`, counted from the line's start (`refsIn`).
final LineFact<List<ItemRef>> itemRefFacts = LineFact<List<ItemRef>>((text) {
  if (!text.contains('[[#^')) return null;
  final refs = refsIn(text);
  return refs.isEmpty ? null : refs;
});

/// A line with a link to a web address in it: the only lines an item's mark, or a link a plugin reads, can be on.
/// Which of them a plugin reads is asked of the plugins each time, since that changes; this is only where to look.
final LineFact<bool> webLinkFacts = LineFact<bool>((text) => text.contains('](http') ? true : null);

/// A line with a web address anywhere in it: the only lines that can be a link's alone (media/link_cards.dart).
final LineFact<bool> webAddressFacts = LineFact<bool>((text) => text.contains('http') ? true : null);

/// A line with a voice memo's mark in it (media/clips.dart).
final LineFact<bool> tapeFacts = LineFact<bool>((text) => text.contains('](tape:') ? true : null);

/// A line that is a fence's run and nothing else, which may close a board or a query (`bareFence`).
final LineFact<String> bareFenceFacts = LineFact<String>((text) {
  if (!text.contains('```') && !text.contains('~~~')) return null;
  return bareFence(text);
});

/// Every anchored item in a document, the first of a repeated anchor winning: `itemsIn` of its words, from the
/// lines the tree keeps, worked out once for each document.
final DocMemo<List<Item>> _items = DocMemo<List<Item>>((doc) {
  final items = <Item>[];
  final seen = <String>{};
  for (final line in itemFacts.of(doc)) {
    final item = line.fact;
    if (!seen.add(item.id)) continue;
    items.add(Item(id: item.id, text: item.text, done: item.done, line: line.number));
  }
  return items;
});

/// `itemsIn(doc.toString())`, without the string and without the scan. Not to be changed.
List<Item> itemsOf(Doc doc) => _items.of(doc);

/// The item an anchor names in a document, or null: `itemAt(doc.toString(), id)`.
Item? itemOf(Doc doc, String id) {
  for (final item in itemsOf(doc)) {
    if (item.id == id) return item;
  }
  return null;
}

/// A line that opens a board: its fence and its settings (`boardOpening`).
final LineFact<({String fence, String settings})> _boardOpenings = LineFact<({String fence, String settings})>((text) {
  if (!text.contains('```') && !text.contains('~~~')) return null;
  return boardOpening(text);
});

final DocMemo<List<Board>> _boards = DocMemo<List<Board>>((doc) {
  final openings = _boardOpenings.of(doc);
  if (openings.isEmpty) return const <Board>[];
  final closers = bareFenceFacts.of(doc);
  final boards = <Board>[];
  Set<String>? anchors;
  var after = 0, closer = 0;
  for (final open in openings) {
    // An opening inside the board before it is that board's words.
    if (open.number <= after) continue;
    var end = open.number;
    while (closer < closers.length && closers[closer].number <= open.number) {
      closer += 1;
    }
    for (var at = closer; at < closers.length; at += 1) {
      if (closesBoardFence(closers[at].fact, open.fact.fence)) {
        end = closers[at].number;
        break;
      }
    }
    final body = end > open.number + 1 ? doc.sliceString(open.to + 1, doc.line(end - 1).to) : '';
    anchors ??= <String>{for (final item in itemsOf(doc)) item.id};
    boards.add(boardRead(from: open.number, to: end, body: body, settings: open.fact.settings, anchors: anchors));
    after = end;
  }
  return boards;
});

/// Every board in a document, in order: `boardsIn(doc.toString())`, from the lines the tree keeps, worked out
/// once for each document. Not to be changed.
List<Board> boardsOf(Doc doc) => _boards.of(doc);

/// The board line [line] of a document is inside, fence lines included, or null: `boardAt(doc.toString(), line)`.
Board? boardOf(Doc doc, int line) {
  for (final board in boardsOf(doc)) {
    if (board.to > board.from && line >= board.from && line <= board.to) return board;
  }
  return null;
}
