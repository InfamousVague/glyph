/// Boards, shown as boards (docs/BOARDS.md, core/boards.dart). Ports `src/app/editor/boards.ts`.
///
/// A ```board fence is columns; the items it names are anywhere in the note, each with its anchor. The fence is
/// drawn as a board of cards, the way a table is drawn as a table (tables/tables.dart): the markdown is what is kept
/// and what is edited, and the caret in the fence steps the drawing aside so the lines can be typed.
///
/// A card IS its item, which is what Matt asked for ("linking the tasks in the board to a task on the page"):
///
/// - Its tick box is the item's box. Ticking it ticks the line in the note, and moves the card to Done when the
///   board has such a column. An item with no box - a bullet, a numbered step - is drawn as a card with no box.
/// - Its words are the item's words. Tapping them puts the caret on that line, so the board is a way around the
///   note.
/// - Press and hold picks the card up and it is dragged to where it goes, in its own column or another (Matt: "add
///   a way to tap and drag to re organize items in lanes"). The chevrons do the same a tap at a time, for a hand
///   that would rather not drag.
/// - A card whose item is gone is drawn with its anchor and nothing else, so it can be seen and taken out.
///
/// The rest is the phone it is used on (Matt: "make the UI / UX of these boards friendlier on mobile"): columns
/// that snap as they scroll, an empty column that says it will take a card, a + that writes a new item into the
/// note, and targets big enough for a thumb.
///
/// This is the extension and what decides where a board is drawn. Its parts: the board as drawn from the markdown
/// (drawn.dart), the widget (board_box.dart, board_card.dart) and what a card does to the note (card_edits.dart),
/// the card's menu, the kit's (card_menu.dart), the + field (composer.dart), the board's height remembered
/// (height.dart) and set by the line under it (divider.dart), getting around from a card (navigate.dart), the icons
/// (icons.dart) and the look (board_look.dart, board_words.dart). What the note offers to do with boards where the
/// caret is, the band's rows, is board_actions.dart.
///
/// The note screen adds [drawnBoards] to its extensions, as Editor.tsx lists `drawnBoards(cardActions)`:
/// `noteExtensions(more: [drawnBoards(actions: …)])`. With it in, the press-and-hold band's board rows and the +
/// list's board can be switched on (`ContextBand.boards`, `AddGates.board`).
///
/// What differs:
/// - `boardRoom`, the view plugin that told a board how much room it has and how far the page's margin reaches
///   (`--cm-board-room`, `--cm-board-bleed`), has no counterpart: a block widget is laid out in the editor's own
///   width, never wider, and the indent is the look's gutter (board_look.dart).
/// - `itemAnchors` (boards/anchors.ts) was ported with the items (items/anchors.dart), and `settleFences` lives
///   with the tick it settles (commands/task_toggle.dart). Both are handed on from here under their own file's
///   name, and [drawnBoards] lists the anchors as the page's does: a note that has them from its items already
///   holds them once (a state keeps one of an extension given twice).
/// - `ignoreEvent` let the + field and the line under the board keep their events; here the whole board keeps its
///   pointers ([BoardWidget.takesPointer]), since every part of it answers a press itself or leaves it alone. A
///   press on a board never moves the caret: the fence's lines are reached with the caret from the lines round it,
///   or from the band's rows.
/// - `cardMenuGoes` closed a menu whose button a redraw took off the page a microtask after the update; the
///   board's widget does that as it is rebuilt.
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import '../items/anchors.dart' show itemAnchors;
import '../view/blocks.dart';
import '../view/drawn_block.dart';
import 'board_box.dart';
import 'card_menu.dart';
import 'drawn.dart';
import 'height.dart';

export '../commands/task_toggle.dart' show settleFences;
export '../items/anchors.dart' show itemAnchors;
export 'board_actions.dart';
export 'board_box.dart' show DrawnBoardBox, LaneSnap, LaneSnapPhysics;
export 'board_card.dart' show BoardCard, BoardEmpty, BoardGap, CardDoes, cardChips, cardSaid, chipPage, onCard;
export 'board_look.dart' show BoardLook, buttonType;
export 'board_words.dart' show BoardWords, LaidWords, RenderBoardWords;
export 'card_edits.dart';
export 'card_menu.dart';
export 'composer.dart' show BoardComposer, BoardComposerState;
export 'divider.dart' show BoardSplit;
export 'drawn.dart';
export 'height.dart';
export 'icons.dart';
export 'navigate.dart';

/// A board drawn in place of its fence.
class BoardWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  const BoardWidget(this.board, this.face);

  final DrawnBoard board;

  /// What the board shows ([faceOf]).
  final String face;

  @override
  String get className => 'cm-boardWrap';

  /// The same face in the same place, with every card's item on the line it was: the page compared the face alone
  /// and kept a drawing whose cards could name lines the note had since moved. A board that only moved is still
  /// redrawn in place, its lanes' scroll, its + field and its held height kept ([DrawnBoardBox]'s state).
  @override
  bool eq(BoardWidget other) {
    if (other.face != face || other.board.from != board.from || other.board.to != board.to || other.board.cards.length != board.cards.length) return false;
    for (var index = 0; index < board.cards.length; index += 1) {
      if (other.board.cards[index] != board.cards[index]) return false;
    }
    return true;
  }

  /// How tall the board is before it is drawn (height.dart).
  @override
  double get estimatedHeight => estimatedBoardHeight(board, face);

  @override
  Widget build(BuildContext context) => DrawnBoardBox(board: board, face: face);

  /// Every pointer on a board is the board's: a control's, a card's to be lifted by, a lane's to scroll.
  @override
  bool takesPointer(PointerEvent event) => true;
}

DecorationSet _decorate(EditorState state) {
  final ranges = <Range<Decoration>>[];
  for (final board in boardsOn(state)) {
    // The caret in the fence: the lines themselves, to edit. Elsewhere, and in a view with no caret, the board.
    if (caretIn(state, board.from, board.to)) continue;
    ranges.add(Decoration.replace(widget: BoardWidget(board, faceOf(board)), block: true).range(board.from, board.to));
  }
  return ranges.isEmpty ? Decoration.none : Decoration.set(ranges);
}

final StateField<DecorationSet> _boardField = StateField.define<DecorationSet>(
  create: _decorate,
  update: (value, tr) => tr.docChanged || tr.selection != null || focusMoved(tr) || tr.reconfigured ? _decorate(tr.state) : value,
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// The boards drawn in `state` now: one block replacement for each board the caret is not in.
DecorationSet drawnBoardsIn(EditorState state) => state.fieldOrNull(_boardField) ?? Decoration.none;

/// Boards drawn in a note, the fence still there to edit (`drawnBoards`). `actions` is what the note's plugins
/// offer a card's menu, where the note is one a plugin acts on.
Extension drawnBoards({CardActions? actions}) =>
    Extension.list(<Extension>[trackFocus, _boardField, itemAnchors, cardMenuGoes, if (actions != null) cardActions.of(actions)]);

/// [drawnBoards], under the name the stage's plan gives it.
Extension boards({CardActions? actions}) => drawnBoards(actions: actions);
