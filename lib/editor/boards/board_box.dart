/// A board drawn in place of its fence: a row of columns, each a heading, its cards and an empty place, with the
/// line under it that sets its height. Ports `BoardWidget.toDOM`/`updateDOM`/`fill` of
/// `src/app/editor/boards/widget.ts`, the drag of `boards/drag.ts`, the held height of `boards/height.ts` and the
/// showing of a landed card of `boards/navigate.ts`.
///
///     .cm-boardWrap          [DrawnBoardBox]: the room above and below
///       .cm-board            the columns, scrolling sideways, one settling at a time
///         .cm-boardColumn    a lane: its head, the + field while a card is typed, and its stack
///           .cm-boardName    the lane's name, how many cards it holds, and the +
///           .cm-boardCompose composer.dart
///           .cm-boardStack   the cards (board_card.dart), scrolling inside a lane with more than it shows
///       .cm-boardSplit       divider.dart
///
/// **The height it is held at** (Matt: "Clicking an item to toggle the done state on and off is now super laggy and
/// doesn't actually change the state off"). The lanes are as tall as the tallest lane's cards, so moving a card
/// between lanes changed the board's height, and everything under it jumped; the second tap then landed on whatever
/// had slid under the finger. So a board's height is settled when it is drawn and held there: ticking, dragging,
/// adding and taking off all leave it exactly where it is, and the lanes scroll inside it as a board with a set
/// height does. It is measured once, from the height the board would have chosen for itself, and let go when the
/// board is built again - the note reopened, its columns changed, its type resized - or when the line under it is
/// dragged, which sets a real height in the fence.
///
/// **A card carried** is the app's one carry (core/hold_drag.dart): a finger rests on a card to lift it; before the
/// hold is up it is still scrolling the board. Lifted, the card stays in its lane as the gap it would leave, a copy
/// follows the finger overhead, and the board, a lane or the note rolls along when the card is held near an edge.
/// Where it is let go is written by `landCard`.
///
/// What differs:
/// - **The pin takes a frame.** The page measured the lanes after its first layout and set the pin in the same
///   frame's write phase. Here the first frame lays the lanes out at their own height, unseen, and the second
///   draws the board pinned at that height rounded; a board whose fence sets a height is drawn at once.
/// - **The gap is a widget of its own**, placed by where the carry says the card would land, where the page moved
///   the card's own element from lane to lane. The spot under the finger is worked out the same way: the lane under
///   it, or the nearest, above the first card whose middle the finger is over.
/// - **The copy in the air is the card as it is drawn**, where the page's clone came out a few pixels shorter or
///   taller than its card (its chips and buttons lose their place in the cascade outside the editor).
/// - **A lane hands the finger on to the note at either end** by passing its overscroll to the note's own scroller
///   (see [_DrawnBoardBoxState._laneScrolled]); a lane that shows every card takes no drag at all. The page had
///   this from the browser's scroll chaining.
/// - **Sideways, a swipe settles on a column** by a scroll physics of its own ([LaneSnapPhysics]) for
///   `scroll-snap-type: x mandatory`. One physics for the board's whole life, told through [LaneSnap] when a card
///   is held: handed physics of another kind, a scroller makes itself a new position and drops the one a carry is
///   rolling.
/// - **A landed card is brought into view by steps of the board's own** ([_DrawnBoardBoxState._glide]) for
///   `scrollTo({ behavior: 'smooth' })`: a scroller animating itself keeps every pointer off what is in it until it
///   rests, and a second card ticked straight after the first would be a tap on nothing.
/// - **A note that cannot be changed** draws its boards with nothing to press but a card's words; the page built
///   every control regardless and would have written to a read-only note.
/// - The smoke at a lane's foot stays on while the line under the board is dragged; the page fell back to the plain
///   fade until the finger lifted, to save making a filter for every pixel, which a shader does not cost.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../art/wisp_foot.dart';
import '../../core/boards.dart';
import '../../core/hold_drag.dart';
import '../../core/task_fields.dart' show FieldSpan;
import '../items/field_menu.dart';
import '../items/task_fields.dart' show fieldsLocale, fieldsToday;
import '../looks/look.dart';
import '../view/editor_view.dart';
import '../view/plugin.dart';
import 'board_card.dart';
import 'board_look.dart';
import 'board_press.dart';
import 'board_words.dart';
import 'card_edits.dart';
import 'card_menu.dart';
import 'composer.dart';
import 'divider.dart';
import 'drawn.dart';
import 'height.dart';
import 'icons.dart';
import 'navigate.dart';

/// How a board's columns are settled on: how far it is from one column's start to the next, and whether a card is
/// held (the board is then scrolled for the finger at its edges, and settles on nothing). Kept by the board and
/// read by its scroll physics as they are needed: a scroller holds on to the physics it was made with, and makes
/// itself a new position, dropping the old one mid-gesture, if it is given physics of another kind.
class LaneSnap {
  double step = 0;
  bool held = false;
}

/// `scroll-snap-type: x mandatory` with `scroll-snap-align: start` on each column: a swipe settles on a column
/// rather than between two. '.cm-board[data-holding]': { scrollSnapType: 'none' }.
class LaneSnapPhysics extends ScrollPhysics {
  const LaneSnapPhysics({required this.snap, super.parent});

  final LaneSnap snap;

  @override
  LaneSnapPhysics applyTo(ScrollPhysics? ancestor) => LaneSnapPhysics(snap: snap, parent: buildParent(ancestor));

  /// Where a board let go at `pixels`, moving at `velocity`, comes to rest.
  double target(ScrollMetrics position, double velocity, Tolerance tolerance) {
    var lane = position.pixels / snap.step;
    if (velocity < -tolerance.velocity) {
      lane -= 0.5;
    } else if (velocity > tolerance.velocity) {
      lane += 0.5;
    }
    return (lane.roundToDouble() * snap.step).clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if (snap.held || snap.step <= 0 || (velocity <= 0 && position.pixels <= position.minScrollExtent) || (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final to = target(position, velocity, tolerance);
    if ((to - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, to, velocity, tolerance: tolerance);
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// `.cm-boardWrap`: a board drawn in place of its fence.
class DrawnBoardBox extends StatefulWidget {
  const DrawnBoardBox({super.key, required this.board, required this.face});

  final DrawnBoard board;

  /// What the board shows ([faceOf]), for remembering its height by.
  final String face;

  @override
  State<DrawnBoardBox> createState() => _DrawnBoardBoxState();
}

class _DrawnBoardBoxState extends State<DrawnBoardBox> with TickerProviderStateMixin {
  final ScrollController _across = ScrollController();
  final GlobalKey _boardKey = GlobalKey(debugLabel: 'board');
  final GlobalKey _wrapKey = GlobalKey(debugLabel: 'board wrap');
  final GlobalKey<BoardComposerState> _composerKey = GlobalKey<BoardComposerState>();
  final Map<int, ScrollController> _laneScrolls = <int, ScrollController>{};
  final Map<int, GlobalKey> _laneKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _measureKeys = <int, GlobalKey>{};
  final Map<String, GlobalKey> _cardKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _moreKeys = <String, GlobalKey>{};
  final LaneSnap _snap = LaneSnap();
  late final LaneSnapPhysics _physics = LaneSnapPhysics(snap: _snap, parent: const ClampingScrollPhysics());
  final Set<int> _more = <int>{};
  final Set<int> _handing = <int>{};

  late final Carry<Card> _carry = Carry<Card>(spotAt: _spotAt, onDrop: _dropped, scrollers: _rollers, window: () => MediaQuery.sizeOf(context).height);

  EditorViewLike? _view;
  BoardLook? _look;

  /// The lanes' height the board is pinned at, the type it was measured in and the columns it had.
  double? _pin;
  double? _pinType;

  /// The lanes' height, in ems, while the line under the board is dragged.
  double? _dragHeight;

  /// The column whose + field is open.
  int? _composing;

  /// The card that has just landed, lit for a moment.
  String? _arrived;
  Timer? _arrivedTimer;

  /// The pointer that went down on one of a card's controls.
  int _controlPointer = -1;
  bool _measuring = false;
  bool _checking = false;

  DrawnBoard get board => widget.board;
  bool get _editable => _view?.state.facet(EditorViewLike.editable) ?? false;

  ScrollController _laneScroll(int column) => _laneScrolls[column] ??= ScrollController();
  GlobalKey _laneKey(int column) => _laneKeys[column] ??= GlobalKey(debugLabel: 'lane $column');
  GlobalKey _cardKey(String id) => _cardKeys[id] ??= GlobalKey(debugLabel: 'card $id');
  GlobalKey _moreKey(String id) => _moreKeys[id] ??= GlobalKey(debugLabel: 'more $id');

  @override
  void initState() {
    super.initState();
    _carry.addListener(_redraw);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = EditorViewScope.maybeOf(context);
    if (!identical(view, _view)) {
      _unlisten();
      _view = view;
      if (view != null) {
        revealed(view).addListener(_revealAsked);
        openCardMenuOf(view).addListener(_redraw);
      }
    }
  }

  @override
  void didUpdateWidget(DrawnBoardBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.board;
    // A board whose columns changed is built again: the pin, the + field and a card in the air all go.
    if (was.columns.length != board.columns.length) {
      _pin = null;
      _composing = null;
      _carry.abandon();
    }
    // The height the drag set is the fence's now, or the fence's height changed under it.
    if (was.height != board.height) _dragHeight = null;
    // A card in the air whose board changed under it is put down where it was.
    final carried = _carry.carried;
    if (carried != null && !board.cards.any((card) => card.id == carried.item.id)) _carry.abandon();
    // A card's menu hangs from a button that may be gone.
    final view = _view;
    final open = view == null ? null : openCardMenuOf(view).value;
    if (open != null && _moreKeys.values.any((key) => identical(key, open.more)) && !board.cards.any((card) => card.id == open.card)) closeCardMenu(view!);
    _cardKeys.removeWhere((id, _) => !board.cards.any((card) => card.id == id));
    _moreKeys.removeWhere((id, _) => !board.cards.any((card) => card.id == id));
    _revealAsked();
  }

  void _unlisten() {
    final view = _view;
    if (view == null) return;
    revealed(view).removeListener(_revealAsked);
    openCardMenuOf(view).removeListener(_redraw);
  }

  @override
  void dispose() {
    _unlisten();
    for (final glide in _glides.values.toList()) {
      glide.dispose();
    }
    _glides.clear();
    _arrivedTimer?.cancel();
    _carry
      ..removeListener(_redraw)
      ..dispose();
    _across.dispose();
    for (final scroll in _laneScrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _redraw() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redraw());
      return;
    }
    setState(() {});
  }

  // -- the height it is held at ------------------------------------------------------------------------------------

  /// How tall the lanes are set, in ems: by the drag, or by the fence.
  double? get _sized => _dragHeight ?? board.height;

  /// After the frame that laid the lanes out at their own height: the tallest, to the pixel, is the pin (`pin`).
  void _measure(BoardLook look) {
    _measuring = false;
    if (!mounted || _pin != null || _sized != null) return;
    var tall = look.laneLeast;
    for (var column = 0; column < board.columns.length; column += 1) {
      final box = _measureKeys[column]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) tall = math.max(tall, box.size.height);
    }
    setState(() {
      _pin = tall.roundToDouble();
      _pinType = look.em;
    });
  }

  /// After a frame drawn at its held height: which lanes have more below than they show, and the height to
  /// remember the board at.
  void _afterFrame(BoardLook look) {
    _checking = false;
    if (!mounted) return;
    final more = <int>{};
    if (_sized != null) {
      for (final entry in _laneScrolls.entries) {
        final scroll = entry.value;
        if (!scroll.hasClients) continue;
        final position = scroll.position;
        // `scrollHeight - clientHeight - scrollTop > 4`
        if (position.hasContentDimensions && position.maxScrollExtent - position.pixels > 4) more.add(entry.key);
      }
    }
    if (more.length != _more.length || !more.containsAll(_more)) {
      setState(() {
        _more
          ..clear()
          ..addAll(more);
      });
    }
    // A board being typed into, having a card dragged, or having its height dragged is not at its own height.
    if (_composing != null || _carry.carried != null || _dragHeight != null) return;
    final wrap = _wrapKey.currentContext?.findRenderObject();
    if (wrap is RenderBox && wrap.hasSize) rememberBoardHeight(widget.face, wrap.size.height, note: look.note);
  }

  // -- a lane and the note ------------------------------------------------------------------------------------------

  /// A lane scrolled. At either end of it the finger goes on to the note (the stylesheet's "no
  /// `overscroll-behavior`: a lane that kept the scroll to itself stopped the note dead under a finger that landed
  /// on it"): what the lane could not take is given to the note's own scroller, and a fling that ends there is the
  /// note's to carry on.
  bool _laneScrolled(ScrollNotification notification, int column) {
    if (notification.depth != 0) return false;
    final note = noteScroller(context)?.position;
    if (notification is OverscrollNotification && note != null) {
      if (notification.dragDetails != null) {
        _handing.add(column);
        note.jumpTo((note.pixels + notification.overscroll).clamp(note.minScrollExtent, note.maxScrollExtent));
      } else if (notification.velocity != 0 && note is ScrollActivityDelegate) {
        (note as ScrollActivityDelegate).goBallistic(notification.velocity);
      }
    } else if (notification is ScrollEndNotification) {
      final velocity = notification.dragDetails?.primaryVelocity;
      if (_handing.remove(column) && velocity != null && velocity != 0 && note is ScrollActivityDelegate) {
        (note as ScrollActivityDelegate).goBallistic(-velocity);
      }
    } else if (notification is ScrollStartNotification) {
      _handing.remove(column);
    }
    if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) _checkSoon();
    return false;
  }

  void _checkSoon() {
    final look = _look;
    if (_checking || look == null) return;
    _checking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame(look));
    WidgetsBinding.instance.scheduleFrame();
  }

  // -- what the controls do -----------------------------------------------------------------------------------------

  void _goTo(Card card) {
    final view = _view, item = card.item;
    if (view == null || item == null || hushed()) return;
    goToLine(view, item.line);
  }

  void _openMenu(Card card) {
    final view = _view;
    if (view == null) return;
    openCardMenu(
      view,
      card,
      _moreKey(card.id),
      CardMoves(
        columns: board.columns,
        // Into the lane, at its foot.
        land: (column) => landCard(view, widget.board, card, column, 0x7fffffff),
        tick: () => tickCard(view, widget.board, card),
        takeOff: () => takeOffCard(view, widget.board, card),
      ),
    );
  }

  void _chip(Card card, FieldSpan span, Rect box) {
    final view = _view, item = card.item;
    if (view == null || item == null) return;
    tapField(view, FieldTap(page: chipPage(span), line: item.line, x: (box.left + box.right) / 2, y: box.top));
  }

  /// The + on a column: its field opened, or gone back to if it is open already (`openComposer`).
  void _compose(int column) {
    if (_composing == column) {
      _composerKey.currentState?.focus();
      return;
    }
    setState(() => _composing = column);
  }

  bool _add(int column, String words) {
    final view = _view;
    if (view == null || !boardStands(view, board)) return false;
    // Read where the board is now, not where it was when the field opened: the note may have changed above it.
    return addCard(view, view.state.doc.lineAt(board.from).number, column, words);
  }

  // -- a card carried -----------------------------------------------------------------------------------------------

  Rect? _boxOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The lane under the finger gets the gap, above the first card whose middle the finger is over (`placeGap`).
  Spot? _spotAt(Offset at) {
    int? lane;
    var nearest = double.infinity;
    for (var column = 0; column < board.columns.length; column += 1) {
      final box = _boxOf(_laneKeys[column]);
      if (box == null) continue;
      // The column under the finger, or the nearest one when the finger is past the end of the board.
      final away = at.dx < box.left ? box.left - at.dx : (at.dx > box.right ? at.dx - box.right : 0.0);
      if (away < nearest) {
        nearest = away;
        lane = column;
      }
    }
    if (lane == null) return null;
    final carried = _carry.carried?.item.id;
    var index = 0;
    for (final card in board.held(lane)) {
      if (card.id == carried) continue;
      final box = _boxOf(_cardKeys[card.id]);
      if (box != null && at.dy < box.top + box.height / 2) break;
      index += 1;
    }
    return Spot('$lane', index);
  }

  /// What rolls under a held card: the board, across; and up and down, the lane it is over when that has more cards
  /// than it shows, else the note, near the top or foot of the screen (drag.ts `dragTo`, `leanAt`).
  List<CarryScroller> _rollers(Offset at) {
    final rollers = <CarryScroller>[];
    if (_across.hasClients) rollers.add(CarryScroller(position: _across.position, axis: Axis.horizontal, box: () => _boxOf(_boardKey), zone: boardEdge));
    final lane = int.tryParse(_carry.over?.lane ?? '');
    final scroll = lane == null ? null : _laneScrolls[lane];
    if (scroll != null && scroll.hasClients && scroll.position.hasContentDimensions && scroll.position.maxScrollExtent > 1) {
      rollers.add(CarryScroller(position: scroll.position, axis: Axis.vertical, box: () => _boxOf(_laneKeys[lane]), zone: boardEdge));
    } else {
      final note = noteScroller(context);
      if (note != null && note.position.hasContentDimensions && note.position.maxScrollExtent > 1) {
        // The note's top is under its header, so the zone starts below that, and is wider, since the finger is near
        // the edge of the screen.
        var under = 0.0;
        final view = _view;
        if (view != null) {
          for (final source in view.state.facet(EditorViewLike.scrollMargins)) {
            under = math.max(under, source(view)?.top ?? 0);
          }
        }
        rollers.add(
          CarryScroller(
            position: note.position,
            axis: Axis.vertical,
            box: () {
              final box = note.context.findRenderObject();
              return box is RenderBox && box.attached ? box.localToGlobal(Offset.zero) & box.size : null;
            },
            zone: boardEdge * 2,
            under: under,
          ),
        );
      }
    }
    return rollers;
  }

  void _dropped(Card card, Spot from, Spot to) {
    final view = _view;
    if (view == null) return;
    // Put down first, then written: the note's change draws the board again from what it says.
    landCard(view, board, card, int.parse(to.lane), math.max(0, to.index));
  }

  void _pressCard(PointerDownEvent event, BuildContext context, Card card, int index, BoardLook look, Widget Function() copy) {
    // A press on one of the card's controls is that control's: a finger resting on the tick box a little past the
    // hold used to lift the card instead of ticking it, so a slow tap did nothing and the next landed on the words.
    if (event.pointer == _controlPointer || !_editable) return;
    // A card's menu closes on a press on another card, which keeps its press to itself for its drag.
    final view = _view;
    if (view != null && cardMenuIn(view)) closeCardMenu(view);
    _carry.press(event, context, card, Spot('${card.column}', index), ghost: (_) => copy(), radius: BorderRadius.circular(look.cardRadius));
  }

  // -- a card shown where it landed ---------------------------------------------------------------------------------

  final Map<ScrollPosition, AnimationController> _glides = <ScrollPosition, AnimationController>{};

  /// `scrollTo({ behavior: 'smooth' })`: `position` taken to `to` over a moment. Stepped here rather than handed to
  /// the scroller, which would keep every pointer off its cards until it came to rest: a second card ticked while
  /// the board was still coming across would be a tap on nothing.
  void _glide(ScrollPosition position, double to) {
    _glides.remove(position)?.dispose();
    final from = position.pixels;
    if ((to - from).abs() < 0.5) return;
    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
    _glides[position] = controller;
    controller.addListener(() {
      if (!position.hasPixels || !position.hasContentDimensions) return;
      final at = from + (to - from) * Curves.easeOut.transform(controller.value);
      position.jumpTo(at.clamp(position.minScrollExtent, position.maxScrollExtent));
    });
    controller.forward().whenCompleteOrCancel(() {
      if (identical(_glides[position], controller)) _glides.remove(position)?.dispose();
    });
  }

  void _revealAsked() {
    final view = _view;
    final id = view == null ? null : revealed(view).value;
    if (id == null || !board.cards.any((card) => card.id == id)) return;
    // Once the board has drawn the change that moved the card, and the card is in its lane.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The card where it landed, shown: its lane brought across the board and the card brought into its lane, then a
  /// short flash so the eye finds it. The note is moved only as far as it takes to show the card, when a lane that
  /// shows every card has put it past the top or foot of the screen (`reveal`).
  void _reveal(String id) {
    final view = _view;
    if (!mounted || view == null || revealed(view).value != id) return;
    Card? card;
    for (final one in board.cards) {
      if (one.id == id) card = one;
    }
    final cardBox = _boxOf(_cardKeys[id]);
    final boardBox = _boxOf(_boardKey);
    if (card == null || cardBox == null || boardBox == null) return;
    revealed(view).value = null;
    final laneBox = _boxOf(_laneKeys[card.column]);
    final look = _look;
    if (laneBox != null && look != null && _across.hasClients) {
      final left = laneBox.left - look.columnSide, right = laneBox.right + look.columnSide;
      if (left < boardBox.left || right > boardBox.right) {
        final position = _across.position;
        final to = (position.pixels + left - boardBox.left - look.bleed).clamp(position.minScrollExtent, position.maxScrollExtent);
        _glide(position, to);
      }
    }
    final scroll = _laneScrolls[card.column];
    if (laneBox != null && scroll != null && scroll.hasClients && scroll.position.maxScrollExtent > 1) {
      if (cardBox.top < laneBox.top || cardBox.bottom > laneBox.bottom) {
        final position = scroll.position;
        _glide(position, (position.pixels + cardBox.top - laneBox.top - 8).clamp(position.minScrollExtent, position.maxScrollExtent));
      }
    } else {
      final note = noteScroller(context);
      final noteBox = note?.context.findRenderObject();
      if (note != null && noteBox is RenderBox && noteBox.attached) {
        final shown = noteBox.localToGlobal(Offset.zero) & noteBox.size;
        var under = 0.0;
        for (final source in view.state.facet(EditorViewLike.scrollMargins)) {
          under = math.max(under, source(view)?.top ?? 0);
        }
        final top = math.max(shown.top, 0.0) + under;
        final bottom = math.min(shown.bottom, MediaQuery.sizeOf(context).height);
        final by = cardBox.bottom > bottom - boardEdge ? cardBox.bottom - bottom + boardEdge : (cardBox.top < top + 8 ? cardBox.top - top - 8 : 0.0);
        if (by != 0) {
          final position = note.position;
          _glide(position, (position.pixels + by).clamp(position.minScrollExtent, position.maxScrollExtent));
        }
      }
    }
    _arrivedTimer?.cancel();
    setState(() => _arrived = id);
    _arrivedTimer = Timer(arrivedTime, () {
      if (mounted) setState(() => _arrived = null);
    });
  }

  // -- the drawing --------------------------------------------------------------------------------------------------

  Widget _head(BoardLook look, int column, int count) {
    final name = board.columns[column].name;
    // A card is added where the eye already is, at the top of the column it belongs in.
    Widget add = Container(
      key: ValueKey<String>('add$column'),
      width: look.addSize,
      height: look.addSize,
      decoration: ShapeDecoration(color: look.addGround, shape: const CircleBorder()),
      child: Center(child: BoardIcon('plus', size: look.addIcon, color: look.ink2)),
    );
    add = Semantics(
      container: true,
    button: true,
      enabled: _editable,
      label: 'Add a card to $name',
      onTap: _editable ? () => _compose(column) : null,
      excludeSemantics: true,
      child: BoardPress(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _editable ? () => _compose(column) : null, child: add)),
    );
    return SizedBox(
      key: ValueKey<String>('head$column'),
      height: look.headHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: look.headSide),
        child: Row(
          // `margin-inline-start: auto` on the +: it sits at the head's far end.
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // `text-transform: uppercase`; one line, cut with an ellipsis.
                  Flexible(child: BoardWords(name.toUpperCase(), key: ValueKey<String>('name$column'), face: look.nameFace, wrap: false, shrink: true)),
                  SizedBox(width: look.headGap),
                  Container(
                    key: ValueKey<String>('count$column'),
                    constraints: BoxConstraints(minWidth: look.countLeast),
                    padding: EdgeInsets.symmetric(horizontal: look.countSide, vertical: look.countEnds),
                    decoration: ShapeDecoration(color: look.countGround, shape: const StadiumBorder()),
                    child: Align(widthFactor: 1, heightFactor: 1, child: BoardWords('$count', face: look.countFace, wrap: false, shrink: true)),
                  ),
                ],
              ),
            ),
            add,
          ],
        ),
      ),
    );
  }

  BoardCard _card(BoardLook look, Card card, {required bool live, LineLook? line, String? today, String? locale}) {
    final view = _view;
    final can = live && _editable && view != null;
    return BoardCard(
      look: look,
      card: card,
      column: card.column,
      columns: board.columns.length,
      today: today ?? todayIs(),
      locale: locale,
      lineLook: line,
      arrived: live && _arrived == card.id,
      moreKey: live ? _moreKey(card.id) : null,
      onControl: live ? (pointer) => _controlPointer = pointer : null,
      chipButtons: _editable && view != null,
      does: !live
          ? CardDoes.nothing
          : CardDoes(
              tick: can ? () => tickCard(view, widget.board, card) : null,
              // The words are a way into the note: the caret lands on the item, and the note scrolls to it.
              goTo: card.item == null ? null : () => _goTo(card),
              step: can ? (by) => stepCard(view, widget.board, card, by) : null,
              more: can ? () => _openMenu(card) : null,
              chip: can ? (span, box) => _chip(card, span, box) : null,
            ),
    );
  }

  /// A lane's cards, the gap a held card would leave among them, and its empty place.
  List<Widget> _laneChildren(BoardLook look, int column, {required double? room, LineLook? line, String? today, String? locale}) {
    // Laid out only to be measured: nothing to press, and no place of its own in the page to be found by.
    final measuring = room == null;
    final held = board.held(column);
    final carried = _carry.carried;
    final over = _carry.over;
    final holding = carried != null;
    final children = <Widget>[];
    void add(Widget child) {
      if (children.isNotEmpty) children.add(SizedBox(height: look.gap));
      children.add(child);
    }

    var index = 0;
    var placed = false;
    void gapHere() {
      if (carried == null || over == null || over.lane != '$column' || placed || over.index != index) return;
      placed = true;
      add(BoardGap(key: const ValueKey<String>('gap'), look: look, height: carried.height));
    }

    // The carried card's id is read once, here, and not in the loop's test: Dart 3.13.5's native compiler lifted
    // `carried.item.id` out of the loop past its `carried != null`, read it of null, and the app ended with SIGSEGV
    // whenever a board was opened in a compiled build (android/gradle.properties, `--no-load_cse`).
    final carriedId = carried?.item.id;
    for (final (at, card) in held.indexed) {
      if (carriedId != null && card.id == carriedId) continue;
      gapHere();
      if (measuring) {
        add(_card(look, card, live: false, line: line, today: today, locale: locale));
        index += 1;
        continue;
      }
      add(
        Builder(
          key: _cardKey(card.id),
          builder: (context) => Listener(
            onPointerDown: (event) => _pressCard(event, context, card, at, look, () => _card(look, card, live: false, line: line, today: today, locale: locale)),
            child: _card(look, card, live: true, line: line, today: today, locale: locale),
          ),
        ),
      );
      index += 1;
    }
    gapHere();
    if (carried != null && over != null && over.lane == '$column' && !placed) add(BoardGap(key: const ValueKey<String>('gap'), look: look, height: carried.height));

    final name = board.columns[column].name;
    final isOver = over != null && over.lane == '$column';
    if (held.isEmpty) {
      // An empty lane's place fills it, and its picture and words sit in the middle of it (Matt: "vertically center
      // the icons in the swimlanes"): a lane beside a full one is as tall as that one.
      var used = 0.0;
      if (children.isNotEmpty && carried != null) used = carried.height + look.gap;
      final tall = room == null ? look.emptyNatural : math.max(look.dropHeight, room - used);
      add(SizedBox(height: tall, child: BoardEmpty(look: look, name: name, holding: holding, over: isOver)));
    } else if (holding) {
      add(BoardEmpty(look: look, name: name, holding: true, over: isOver, fills: false));
    }
    return children;
  }

  Widget _lane(BoardLook look, int column, double height, {LineLook? line, String? today, String? locale}) {
    final held = board.held(column);
    final children = _laneChildren(look, column, room: height, line: line, today: today, locale: locale);
    Widget lane = NotificationListener<ScrollNotification>(
      onNotification: (notification) => _laneScrolled(notification, column),
      child: SingleChildScrollView(
        controller: _laneScroll(column),
        // An empty lane's place reaches to the lane's foot; a lane of cards keeps room under the last
        // (`paddingBlockEnd: '0.9em'`).
        padding: EdgeInsets.only(bottom: held.isEmpty ? 0 : look.laneFootHeld),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
    // More cards below than the lane shows: its foot fades, and goes to smoke where the app's wisp is on. Only a
    // board with a set height has lanes that say so.
    if (_sized != null) lane = WispFoot(more: _more.contains(column), plainFade: look.laneFade, child: lane);
    return SizedBox(key: _laneKey(column), height: height, child: KeyedSubtree(key: ValueKey<String>('stack$column'), child: lane));
  }

  Widget _column(BoardLook look, int column, {required double? laneHeight, required double? rowHeight, LineLook? line, String? today, String? locale}) {
    final name = board.columns[column].name;
    final held = board.held(column);
    final composing = _composing == column;
    final Widget stack;
    if (laneHeight == null) {
      // Left to itself, to be measured: every card, and room under the last.
      final cards = _laneChildren(look, column, room: null, line: line, today: today, locale: locale);
      stack = ConstrainedBox(
        key: _measureKeys[column] ??= GlobalKey(debugLabel: 'measure $column'),
        constraints: BoxConstraints(minHeight: look.laneLeast),
        child: Padding(
          padding: EdgeInsets.only(bottom: held.isEmpty ? 0 : look.laneFootOwn),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: cards),
        ),
      );
    } else {
      // A lane beside the one being typed into is as tall as that one's field and lane together.
      final own = rowHeight! - look.columnChrome - (composing ? look.composeHeight + look.gap : 0);
      stack = _lane(look, column, own, line: line, today: today, locale: locale);
    }
    return Semantics(
      container: true,
      label: '$name, ${held.length} ${held.length == 1 ? 'card' : 'cards'}',
      child: Container(
        key: ValueKey<String>('column$column'),
        width: look.columnWidth,
        height: rowHeight,
        padding: EdgeInsets.fromLTRB(look.columnSide, look.columnTop, look.columnSide, look.columnBottom),
        decoration: BoxDecoration(color: look.columnGround, borderRadius: BorderRadius.circular(look.columnRadius)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _head(look, column, held.length),
            SizedBox(height: look.gap),
            if (composing) ...<Widget>[
              BoardPress(child: BoardComposer(key: _composerKey, look: look, name: name, onAdd: (words) => _add(column, words), onClose: () => setState(() => _composing = null))),
              SizedBox(height: look.gap),
            ],
            stack,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final drawn = view is EditorView ? view.look : null;
    final look = BoardLook.of(context, drawn);
    _look = look;
    final line = drawn?.line(LookElement(null));
    final today = view?.state.facet(fieldsToday)?.call();
    final locale = view?.state.facet(fieldsLocale);
    // A pinned board whose words have changed size is measured again: the pin is px, and a px height ages.
    if (_pin != null && _pinType != look.em) _pin = null;
    final sized = _sized;
    // A height from the fence is the height: no pin under it.
    if (sized != null) _pin = null;
    final laneHeight = sized != null ? look.laneHeight(sized) : _pin;
    final holding = _carry.carried != null;

    final double? rowHeight = laneHeight == null ? null : look.columnChrome + laneHeight + (_composing != null ? look.composeHeight + look.gap : 0);
    Widget lanes = Row(
      key: const ValueKey<String>('lanes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var column = 0; column < board.columns.length; column += 1) ...<Widget>[
          if (column > 0) SizedBox(width: look.columnGap),
          _column(look, column, laneHeight: laneHeight, rowHeight: rowHeight, line: line, today: today, locale: locale),
        ],
      ],
    );
    if (laneHeight == null) {
      // The frame the lanes are measured in is not one to look at, to press or to read out.
      lanes = IgnorePointer(child: ExcludeSemantics(child: Opacity(opacity: 0, child: lanes)));
      if (!_measuring) {
        _measuring = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure(look));
        WidgetsBinding.instance.scheduleFrame();
      }
    } else if (!_checking) {
      _checking = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame(look));
    }

    _snap
      ..step = look.columnWidth + look.columnGap
      ..held = holding;
    final scroller = Semantics(
      container: true,
      label: 'Board',
      child: SingleChildScrollView(
        key: _boardKey,
        controller: _across,
        scrollDirection: Axis.horizontal,
        // One column at a time on a phone; held, the board is scrolled for the finger at its edges instead.
        physics: _physics,
        padding: EdgeInsets.fromLTRB(look.bleed, look.boardTop, look.bleed, look.boardBottom),
        child: lanes,
      ),
    );

    final now = sized ?? (laneHeight == null ? boardHeight.min : laneHeight / look.em);
    final live = _editable && view != null;
    final split = BoardSplit(
      look: look,
      now: now,
      onDrag: live ? (height) => setState(() => _dragHeight = height) : null,
      onDone: live
          ? (from, to, write) {
              if (write) {
                // Kept as the drag left it until the fence says the same.
                writeHeight(view, board, to);
                if (board.height == to) setState(() => _dragHeight = null);
              } else {
                // Let go where it started, or called off: the board as it was.
                setState(() => _dragHeight = null);
              }
            }
          : null,
      onReset: live ? () => writeHeight(view, board, null) : null,
      onStep: live ? (height) => writeHeight(view, board, height) : null,
    );

    final open = view == null ? null : openCardMenuOf(view).value;
    final mine = open != null && identical(_moreKeys[open.card], open.more);
    final below = look.splitAbove + look.splitLine + look.splitBelow;
    return Padding(
      key: _wrapKey,
      padding: EdgeInsets.only(top: look.wrapTop, bottom: look.wrapBottom),
      child: Stack(
        children: <Widget>[
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[scroller, SizedBox(height: below)]),
          // A finger's width of touch: down to the next line, and up into the board's own padding but not onto its
          // cards.
          Positioned(left: look.bleed, right: look.bleed, bottom: 0, height: look.splitReachAbove + look.splitLine + look.splitBelow, child: split),
          if (mine) CardMenu(open: open, onDismiss: () => closeCardMenu(view!)),
        ],
      ),
    );
  }
}
