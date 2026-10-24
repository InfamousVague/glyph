/// How tall a board is on the page before it is drawn: the height it is remembered at, by what it shows, and a
/// guess from its cards for one never drawn. Ports the remembering half of `src/app/editor/boards/height.ts`.
///
/// Left to the editor, a board not yet on the screen was one line tall, and grew by a screenful as it came into
/// view; the editor then moved the note to keep its place, and on a phone that move stops a fling dead (Matt:
/// "scrolling past boards is glitchy and stops scroll momentum").
///
/// What differs:
/// - The other halves of height.ts are the board's own widget's (board_box.dart): the height it is held at while it
///   is on the screen (`pin`, `repin`), which is state there, and the smoke at a lane's foot (`laneFoot`), which is
///   a blur here, `BlurFoot` of lib/art round each lane. `watch`/`unwatch` and their `ResizeObserver` have no counterpart: the
///   widget remembers its height after each layout.
/// - `drawnType`, the type a board was last drawn in, is given by whoever asks ([estimatedBoardHeight]'s `note`),
///   since a widget here is described before it is built and cannot read a stylesheet; the page's own default
///   stands in until a board has been drawn.
/// - The memory can be switched off ([rememberBoardHeights]), for tests that end before its write would.
library;

import 'dart:math' as math;

import '../../core/boards.dart';
import '../../core/item_links.dart' show markOf, unmarked;
import '../../note/height_memory.dart';
import 'drawn.dart';

/// A board's type, against the note's (`BOARD_TYPE`).
const double boardType = 0.86;

/// Room under a lane's last card, in the lane's ems; the set-height lanes keep more, for the smoke (`LANE_FOOT`).
const double laneFoot = 0.25;

const String _heightsKey = 'glyph-board-heights';

/// How tall boards are drawn, remembered by what they show ([faceOf]), in memory and across launches
/// (note/height_memory.dart). A board being typed into, having a card dragged, or having its height dragged is not
/// at its own height, and is not remembered.
final HeightMemory boardHeights = HeightMemory(HeightStore.kept(_heightsKey), 300, (px) => (px * 10).roundToDouble() / 10);

/// Whether boards remember their heights and read them back.
bool rememberBoardHeights = true;

/// The type a board and the note around it were last drawn in, in px, for guessing at a board not yet drawn
/// (`drawnType`).
({double board, double note}) drawnBoardType = (board: 16.64, note: 19.35);

/// A board drawn `height` tall, showing `face`, in a note set at `note` px.
void rememberBoardHeight(String face, double height, {required double note}) {
  if (!(height > 0)) return;
  drawnBoardType = (board: boardType * note, note: note);
  if (rememberBoardHeights) boardHeights.keep(face, height);
}

/// The room above a board, the line under it and the space around that, in the note's ems (`WRAP_ROOM`).
const double _wrapRoom = 0.4 * boardType + 0.3 + 1 + 0.5;

/// A board's height before it has ever been drawn, worked out the way it is laid out (board_look.dart): its lanes'
/// heads, the tallest lane's cards at one to three lines each by how many words they have, and the line under it.
/// Near enough that the editor's correction, when the board is drawn, is small (`guessHeight`).
double guessBoardHeight(DrawnBoard board, {double? window, double rem = 16}) {
  final em = drawnBoardType.board;
  // A column is min(78vw, 16rem) across.
  final across = window == null ? 16 * rem : math.min(window * 0.78, 16 * rem);
  // A card's words have its width less the tick, the gaps and the padding, at about 0.45em a letter.
  final perLine = math.max(8.0, (across - 3.7 * em) / (0.45 * em));
  double lane(int column) {
    final cards = board.held(column);
    // An empty lane: its picture and its words.
    if (cards.isEmpty) return 4.95;
    var tall = -0.4;
    for (final card in cards) {
      final text = card.item?.text ?? '';
      final words = card.item != null ? cardText(markOf(text) != null ? unmarked(text) : text).length : card.id.length + 1;
      final lines = math.min(3, math.max(1, (words / perLine).ceil()));
      tall += 2.41 + 1.35 * lines + 0.4;
    }
    return tall + laneFoot;
  }

  var lanes = board.height;
  if (lanes == null) {
    lanes = 2.5;
    for (var index = 0; index < board.columns.length; index += 1) {
      lanes = math.max(lanes!, lane(index));
    }
  }
  // The board's padding, a column's padding, its head and the gap under it; then the lanes; then the room around.
  return ((em * (0.6 + 0.7 + 1.6 + 0.4 + lanes!) + drawnBoardType.note * _wrapRoom + 1) * 10).roundToDouble() / 10;
}

/// How tall the board is before it is drawn: the height it was last drawn at, or a guess from its cards
/// (`estimatedHeight`).
double estimatedBoardHeight(DrawnBoard board, String face) => (rememberBoardHeights ? boardHeights.known(face) : null) ?? guessBoardHeight(board);
