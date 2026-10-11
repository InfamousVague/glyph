/// A board as the editor draws it: where its fence is in the document, the columns the fence names, and the cards
/// those columns hold, each card the note's own item (core/boards.dart reads all of it from the markdown). Ports
/// `src/app/editor/boards/drawn.ts`.
///
/// What differs: a document's boards are read once for that document and kept with it ([boardsOn]), where the page
/// reads the note's whole text again on every change and every move of the caret; a [DrawnBoard] is still made
/// again for every document a change makes.
library;

import 'dart:math' as math;

import '../../core/boards.dart';
import '../state/state.dart';
import '../state/text.dart';
import '../view/line_facts.dart';

class DrawnBoard {
  const DrawnBoard({required this.from, required this.to, required this.columns, required this.items, required this.cards, required this.height});

  /// The whole fence, from the first backtick to the last.
  final int from;
  final int to;
  final List<BoardColumn> columns;
  final List<Item> items;
  final List<Card> cards;

  /// How tall the lanes are set, in ems (core/boards.dart), or null for their own height.
  final double? height;

  /// The cards lane `column` holds, in the order they sit.
  List<Card> held(int column) => <Card>[
    for (final card in cards)
      if (card.column == column) card,
  ];
}

/// Every board of a document that has a body, in order: read from the lines the tree keeps of it
/// (lib/editor/view/line_facts.dart), once for each document, so a caret moved in a note with a board, and a letter
/// typed in a note with none, read nothing again.
final DocMemo<List<DrawnBoard>> _drawn = DocMemo<List<DrawnBoard>>((doc) {
  final all = boardsOf(doc);
  if (all.isEmpty) return const <DrawnBoard>[];
  final items = itemsOf(doc);
  // Every anchor any board names: an item one of them names is never taken for a card whose anchor has slipped.
  final named = <String>{
    for (final board in all)
      for (final column in board.columns) ...column.cards,
  };
  return <DrawnBoard>[
    for (final board in all)
      if (board.to > board.from)
        DrawnBoard(
          from: doc.line(board.from).from,
          to: doc.line(board.to).to,
          columns: board.columns,
          items: items,
          // A ticked item sits in Done wherever the fence has it, so the board never disagrees with the note.
          cards: <Card>[
            for (final card in cardsOf(board.columns, items, named))
              card.item == null ? card : Card(id: card.id, column: math.max(0, columnFor(board.columns, card.item!)), item: card.item),
          ],
          height: board.height,
        ),
  ];
});

/// Every board in the note that has a body, in order (`boardsOn`).
List<DrawnBoard> boardsOn(EditorState state) => _drawn.of(state.doc);

String _number(double? value) => value == null ? '' : (value == value.truncateToDouble() ? value.toStringAsFixed(0) : value.toString());

final Expando<String> _faces = Expando<String>();

/// What a board looks like now, so the widget is rebuilt only when something on it changed (`faceOf`). Said once
/// for each board read.
String faceOf(DrawnBoard board) => _faces[board] ??= _faceOf(board);

String _faceOf(DrawnBoard board) => <String>[
  <String>[for (final column in board.columns) '${column.name}:${column.cards.join(',')}'].join('|'),
  <String>[
    for (final card in board.cards)
      '${card.id}@${card.column}:${card.item == null ? 'gone' : '${card.item!.done == null ? '-' : (card.item!.done! ? 'x' : ' ')}${card.item!.text}'}',
  ].join('|'),
  // A height set, or taken off, redraws the board at it.
  'h${_number(board.height)}',
].join('||');
