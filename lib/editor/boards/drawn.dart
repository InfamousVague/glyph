/// A board as the editor draws it: where its fence is in the document, the columns the fence names, and the cards
/// those columns hold, each card the note's own item (core/boards.dart reads all of it from the markdown). Ports
/// `src/app/editor/boards/drawn.ts`.
///
/// What differs: nothing. A [DrawnBoard] is made again on every change that could move it, as on the page.
library;

import 'dart:math' as math;

import '../../core/boards.dart';
import '../state/state.dart';

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

/// Every board in the note that has a body, in order (`boardsOn`).
List<DrawnBoard> boardsOn(EditorState state) {
  final doc = state.doc.toString();
  final items = itemsIn(doc);
  final all = boardsIn(doc);
  // Every anchor any board names: an item one of them names is never taken for a card whose anchor has slipped.
  final named = <String>{
    for (final board in all)
      for (final column in board.columns) ...column.cards,
  };
  return <DrawnBoard>[
    for (final board in all)
      if (board.to > board.from)
        DrawnBoard(
          from: state.doc.line(board.from).from,
          to: state.doc.line(board.to).to,
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
}

String _number(double? value) => value == null ? '' : (value == value.truncateToDouble() ? value.toStringAsFixed(0) : value.toString());

/// What a board looks like now, so the widget is rebuilt only when something on it changed (`faceOf`).
String faceOf(DrawnBoard board) => <String>[
  <String>[for (final column in board.columns) '${column.name}:${column.cards.join(',')}'].join('|'),
  <String>[
    for (final card in board.cards)
      '${card.id}@${card.column}:${card.item == null ? 'gone' : '${card.item!.done == null ? '-' : (card.item!.done! ? 'x' : ' ')}${card.item!.text}'}',
  ].join('|'),
  // A height set, or taken off, redraws the board at it.
  'h${_number(board.height)}',
].join('||');
