/// A query drawn as a board, at a height of its own, as a ```board is: the lanes are as tall as the fence's
/// `height=`, or a screenful left to themselves, and each scrolls inside it with the wisp at its foot. Ports
/// `BoardView`, `laneAdd`, `LaneComposer`, `LaneCards` and `HeightSplit` of `src/app/editor/QueryView.tsx` with
/// their rules of `QueryView.module.css`.
///
/// A card is dragged between lanes where the board can be written (lane_carry.dart `boardMovable`; Matt: "be able
/// to click and drag items between lanes"), by the app's one drag, as a ```board's card is: press and hold to lift,
/// a copy of the card in the air, the card itself the gap it would leave in the lane it would land in, the lanes and
/// the board rolling at their edges. Dropped on another lane, its grouped field is set to that lane's value.
///
/// What is the ```board's own, used here and not written again (lib/editor/boards): the line under the board that
/// sets its height ([BoardSplit], with this board's margins and em through [QuerySplitLook]); the physics that
/// settle a swipe on a lane ([LaneSnapPhysics], [LaneSnap]); the blur at a lane's foot ([BlurFoot]); the carry
/// ([Carry]) and what rolls under it.
///
/// What differs:
/// - **The field a lane's new ticket is typed into** is this file's own ([LaneComposer]), drawn to the same rules
///   as the ```board's (`.compose` is `.cm-boardCompose` to the em) and hung from the page's focus as that one is
///   (boards/composer.dart says why at length): the ```board's says "New card" and writes at once, and this one
///   says "New ticket" and hands the words to the screen.
/// - **A lane keeps its scroll to itself** (`overscroll-behavior-y: contain`), which is a scroller's way here
///   without being asked; a lane that shows every card takes no drag at all.
/// - The smoke at a lane's foot stays on while the line under the board is dragged, as the ```board's does.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/blur_box.dart';
import '../../core/boards.dart' show boardHeight;
import '../../core/hold_drag.dart';
import '../../core/properties.dart' show StatusCategory;
import '../../core/query/query.dart';
import '../boards/board_box.dart' show LaneSnap, LaneSnapPhysics;
import '../boards/divider.dart' show BoardSplit;
import '../boards/navigate.dart' show boardEdge, noteScroller;
import 'lane_carry.dart';
import 'query_layout.dart';
import 'query_look.dart';
import 'query_parts.dart';
import 'query_view.dart' show QueryViewState;
import 'ticket_marks.dart';

/// What a lane's + makes a ticket with, or null where it makes none: a lane of a status or of words, whose value
/// the ticket is given so it lands where it was typed, or the one lane of a board that is not grouped. The "No …"
/// lane, a lane of days, people or priorities, are drawn from values a lane's name cannot write back (`laneAdd`).
void Function(String title)? laneAdd(QueryResult result, QueryGroup group, void Function(String? lane, String title) onAdd) {
  if (result.group == null) return (title) => onAdd(null, title);
  final value = laneValue(group);
  return value == null ? null : (title) => onAdd(value, title);
}

class QueryBoard extends StatefulWidget {
  const QueryBoard({super.key, required this.look, required this.result, required this.acts, required this.state, this.height, this.onHeight});

  final QueryLook look;
  final QueryResult result;
  final QueryActs acts;
  final QueryViewState state;
  final double? height;
  final void Function(double? height)? onHeight;

  @override
  State<QueryBoard> createState() => _QueryBoardState();
}

class _QueryBoardState extends State<QueryBoard> {
  final ScrollController _across = ScrollController();
  final GlobalKey _boardKey = GlobalKey(debugLabel: 'query board');
  final GlobalKey<LaneComposerState> _composerKey = GlobalKey<LaneComposerState>();
  final Map<String, ScrollController> _laneScrolls = <String, ScrollController>{};
  final LaneSnap _snap = LaneSnap();
  late final LaneSnapPhysics _physics = LaneSnapPhysics(snap: _snap, parent: const ClampingScrollPhysics());
  final Set<String> _more = <String>{};
  late final LaneCarry _lanes = LaneCarry(context: () => context, redraw: _redraw, scrollers: _rollers);

  /// The height the line under the board is being dragged to, drawn while the finger moves and written when it
  /// lifts.
  double? _dragged;

  /// The lane a ticket is being typed into at its +, by its group key; null for none.
  String? _composing;
  bool _checking = false;

  QueryLook get look => widget.look;

  ScrollController _laneScroll(String key) => _laneScrolls[key] ??= ScrollController();

  @override
  void didUpdateWidget(QueryBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The height the drag set is the fence's now, or the fence's height changed under it.
    if (oldWidget.height != widget.height) _dragged = null;
    if (_composing != null && !widget.result.groups.any((group) => group.key == _composing)) _composing = null;
  }

  @override
  void dispose() {
    _lanes.dispose();
    _across.dispose();
    for (final scroll in _laneScrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Rect? _boxOf(BuildContext? of) {
    final box = of?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Across the board at its sides, and up and down the lane the card is held in at its top and foot; the note
  /// where that lane shows every card.
  List<CarryScroller> _rollers(Offset at) {
    final rollers = <CarryScroller>[];
    if (_across.hasClients) rollers.add(CarryScroller(position: _across.position, axis: Axis.horizontal, box: () => _boxOf(_boardKey.currentContext), zone: boardEdge));
    final lane = _lanes.over?.lane;
    final scroll = lane == null ? null : _laneScrolls[lane];
    if (scroll != null && scroll.hasClients && scroll.position.hasContentDimensions && scroll.position.maxScrollExtent > 1) {
      rollers.add(CarryScroller(position: scroll.position, axis: Axis.vertical, box: () => _boxOf(scroll.position.context.storageContext), zone: boardEdge));
    } else {
      final note = noteScroller(context);
      if (note != null && note.position.hasContentDimensions && note.position.maxScrollExtent > 1) {
        rollers.add(CarryScroller(position: note.position, axis: Axis.vertical, box: () => _boxOf(note.context), zone: boardEdge * 2));
      }
    }
    return rollers;
  }

  /// After a frame: which lanes have more below than they show (`scrollHeight - clientHeight - scrollTop > 4`).
  void _afterFrame() {
    _checking = false;
    if (!mounted) return;
    final more = <String>{};
    for (final entry in _laneScrolls.entries) {
      final scroll = entry.value;
      if (!scroll.hasClients) continue;
      final position = scroll.position;
      if (position.hasContentDimensions && position.maxScrollExtent - position.pixels > 4) more.add(entry.key);
    }
    if (more.length != _more.length || !more.containsAll(_more)) {
      setState(() {
        _more
          ..clear()
          ..addAll(more);
      });
    }
  }

  void _checkSoon() {
    if (_checking) return;
    _checking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
    WidgetsBinding.instance.scheduleFrame();
  }

  Widget _card(QueryRow row, QueryActs acts) {
    final result = widget.result;
    final done = row.category == StatusCategory.done || (row.done ?? false);
    final id = row.id;
    // .card { display: grid; gap: var(--glacier-space-1); padding: var(--glacier-space-2) var(--glacier-space-3);
    //   border: 1px solid var(--app-rule); border-radius: var(--glacier-radius-md); background: var(--app-paper) }
    // .card[data-done] { background: transparent }
    final parts = <Widget>[
      if (id != null && id.isNotEmpty) QueryKeyLine(look: look, id: id),
      // .cardTop { display: flex; align-items: flex-start; gap: var(--glacier-space-2) }
      // .cardTop .box { margin-block-start: 0.15em }
      Part(
        'cardTop',
        child: Stack(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (QueryBox.has(row)) ...<Widget>[QueryBox(look: look, row: row, acts: acts, drop: 0.15 * buttonType), SizedBox(width: look.space(2))],
                Flexible(child: QueryName(look: look, row: row, acts: acts, hideKey: true)),
              ],
            ),
            if (QueryBox.has(row)) QueryBoxReach(look: look, row: row, acts: acts, drop: 0.15 * buttonType),
          ],
        ),
      ),
      if (QueryMeta.has(row, result)) QueryMeta(look: look, row: row, result: result, acts: acts, fills: true),
      if (QueryLabelLine.has(row, result, acts)) QueryLabelLine(look: look, row: row, result: result, acts: acts),
      // A ticket's lock and its sub-tickets' progress (ticket_marks.dart).
      if (acts.marks?.call(row) case final marks? when QueryTicketMarks.has(marks)) QueryTicketMarks(look: look, marks: marks),
    ];
    final card = Part(
      'card',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: look.space(3), vertical: look.space(2)),
        decoration: BoxDecoration(color: done ? null : look.paper, border: Border.all(color: look.rule, width: look.hair), borderRadius: BorderRadius.circular(look.t.radius('md'))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (index, part) in parts.indexed) ...<Widget>[if (index > 0) SizedBox(height: look.space(1)), part],
          ],
        ),
      ),
    );
    // Picked for a bulk edit, or picked by a press (lib/tickets/ui/bulk_bar.dart).
    return acts.selectable(row, card, radius: look.t.radius('md'));
  }

  QueryActs get _still => QueryActs(today: widget.acts.today, locale: widget.acts.locale, editable: false, onOpen: (_) {}, onTick: (_) {}, onMove: (_, _) {}, pickable: (_, _) => false, pick: (_, _, _) {});

  Widget _lane(QueryGroup group, double width, double? sized) {
    final result = widget.result;
    final acts = widget.acts;
    final onAdd = acts.onAdd;
    final add = onAdd == null ? null : laneAdd(result, group, onAdd);
    final radius = look.t.radius('md');
    final gap = _lanes.gapIn(group);
    final cards = <Widget>[];
    void put(Widget card) {
      // .cards { display: grid; align-content: start; gap: var(--glacier-space-2) }
      if (cards.isNotEmpty) cards.add(SizedBox(height: look.space(2)));
      cards.add(card);
    }

    for (final row in group.rows) {
      if (_lanes.hidden(row, group)) continue;
      put(_lanes.thing(row, group, key: ValueKey<String>('card ${row.key}'), radius: radius, look: look, copy: () => _card(row, _still), child: _card(row, acts)));
    }
    if (gap != null) put(DragGap(look: look, radius: radius, height: gap));
    // .laneEmpty { padding: var(--glacier-space-2); font-size: var(--glacier-font-size-xs); color: var(--app-ink-4) }
    if (_lanes.seen(group) == 0 && gap == null) {
      put(Part('laneEmpty', child: Padding(padding: EdgeInsets.all(look.space(2)), child: PageWords('Nothing here', look.sans(look.xs, color: look.ink4), line: look.lineXs))));
    }
    // .lane .cards { flex: 1 1 auto; min-block-size: 0; overflow-y: auto; overscroll-behavior-y: contain;
    //   padding-block-end: var(--glacier-space-2) }
    // .lane .cards[data-more] { mask-image: linear-gradient(to bottom, #000 calc(100% - var(--query-lane-fade,
    //   1.2em)), transparent) }
    final stack = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 && (notification is ScrollUpdateNotification || notification is ScrollEndNotification)) _checkSoon();
        return false;
      },
      child: BlurFoot(
        more: _more.contains(group.key),
        plainFade: 1.2 * look.em,
        child: SingleChildScrollView(
          controller: _laneScroll(group.key),
          padding: EdgeInsets.only(bottom: look.space(2)),
          child: Part('cards', child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: cards)),
        ),
      ),
    );
    final composing = add != null && _composing == group.key;
    final over = _lanes.isOver(group);
    // .lane { scroll-snap-align: start; display: flex; flex-direction: column;
    //   max-block-size: var(--query-lane-height, 24em);
    //   padding: var(--glacier-space-1) var(--glacier-space-2) var(--glacier-space-2);
    //   border-radius: var(--glacier-radius-md); background: color-mix(in oklch, var(--app-ink) 4%, transparent) }
    // .board[data-sized] .lane { block-size: var(--query-lane-height, 24em) }
    // .lane[data-over] { background: color-mix(in oklch, var(--app-ink) 9%, transparent);
    //   outline: 1px dashed color-mix(in oklch, var(--app-ink) 35%, transparent); outline-offset: -1px }
    final lane = Container(
      width: width,
      height: sized == null ? null : sized * look.em,
      constraints: sized == null ? BoxConstraints(maxHeight: 24 * look.em) : null,
      padding: EdgeInsets.fromLTRB(look.space(2), look.space(1), look.space(2), look.space(2)),
      decoration: BoxDecoration(color: QueryLook.mix(look.ink, over ? 0.09 : 0.04), borderRadius: BorderRadius.circular(radius)),
      foregroundDecoration: null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          QueryGroupHead(
            look: look,
            group: group,
            onAdd: add == null
                ? null
                : () {
                    // A press on the lane already open takes the focus back to its field.
                    if (_composing == group.key) {
                      _composerKey.currentState?.focus();
                    } else {
                      setState(() => _composing = group.key);
                    }
                  },
          ),
          if (composing) LaneComposer(key: _composerKey, look: look, lane: group.label, onAdd: add, onClose: () => setState(() => _composing = null)),
          Flexible(fit: FlexFit.loose, child: stack),
        ],
      ),
    );
    return _lanes.lane(
      group,
      child: Semantics(
        container: true,
        label: '${group.label}, ${group.rows.length}',
        child: Part('lane', child: over ? CustomPaint(foregroundPainter: DashedOutline(QueryLook.mix(look.ink, 0.35), radius, offset: -1), child: lane) : lane),
      ),
    );
  }

  /// How tall the lanes are drawn now, in their ems (`drawn`).
  double _now() {
    final sized = _dragged ?? widget.height;
    if (sized != null) return sized;
    final board = _boardKey.currentContext?.findRenderObject();
    final tall = board is RenderBox && board.hasSize ? board.size.height - look.space(1) : 0.0;
    return tall > 0 ? tall / look.em : boardHeight.min.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final acts = widget.acts;
    _lanes.update(result, acts, control: () => widget.state.controlPointer);
    _laneScrolls.removeWhere((key, scroll) {
      final gone = !result.groups.any((group) => group.key == key);
      if (gone) scroll.dispose();
      return gone;
    });
    if (!_checking) {
      _checking = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
    }
    final sized = _dragged ?? widget.height;
    final onHeight = widget.onHeight;
    final split = acts.editable && onHeight != null;
    final splitLook = QuerySplitLook(look, window: MediaQuery.sizeOf(context));
    final below = splitLook.splitAbove + splitLook.splitLine + splitLook.splitBelow;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The lanes' room is the card's own, inside its padding; the board runs out to the card's edges.
        final room = constraints.maxWidth - 2 * look.space(3);
        final count = math.max(1, result.groups.length);
        final gap = look.space(3);
        // .board { display: grid; grid-auto-flow: column; grid-auto-columns: minmax(13rem, 1fr);
        //   gap: var(--glacier-space-3); overflow-x: auto; margin-inline: calc(-1 * var(--glacier-space-3));
        //   padding: 0 var(--glacier-space-3) var(--glacier-space-1); scroll-snap-type: x mandatory }
        final width = math.max(look.t.lenOf('13rem'), (room - gap * (count - 1)) / count);
        _snap
          ..step = width + gap
          ..held = _lanes.carried != null;
        final board = Semantics(
          container: true,
          label: 'Board',
          child: Part(
            'board',
            child: SingleChildScrollView(
              key: _boardKey,
              controller: _across,
              scrollDirection: Axis.horizontal,
              physics: _physics,
              padding: EdgeInsets.fromLTRB(look.space(3), 0, look.space(3), look.space(1)),
              // Every lane as tall as the tallest: a grid's row.
              child: EqualHeights(gap: gap, children: <Widget>[for (final group in result.groups) _lane(group, width, sized)]),
            ),
          ),
        );
        final across = board;
        if (!split) return across;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[across, SizedBox(height: below)]),
            Positioned(
              left: look.space(3),
              right: look.space(3),
              bottom: 0,
              height: splitLook.splitReachAbove + splitLook.splitLine + splitLook.splitBelow,
              child: BoardSplit(
                look: splitLook,
                now: _now(),
                onDrag: (height) => setState(() => _dragged = height),
                onDone: (from, to, write) {
                  if (write) {
                    // Kept as the drag left it until the fence says the same.
                    onHeight(to);
                    if (widget.height == to) setState(() => _dragged = null);
                  } else {
                    setState(() => _dragged = null);
                  }
                },
                onReset: () => onHeight(null),
                onStep: onHeight,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// An answer to a text intent that hands it straight back to the field's own, set between the field and the editor
/// it is built in, which answers the same intents for the note (boards/composer.dart `_Own`).
class _Own extends Action<Intent> {
  @override
  bool isEnabled(Intent intent) => callingAction?.isActionEnabled ?? false;

  @override
  bool consumesKey(Intent intent) => callingAction?.consumesKey(intent) ?? false;

  @override
  Object? invoke(Intent intent) => callingAction?.invoke(intent);
}

final Map<Type, Action<Intent>> _ownKeys = <Type, Action<Intent>>{
  DeleteCharacterIntent: _Own(),
  DeleteToNextWordBoundaryIntent: _Own(),
  DeleteToLineBreakIntent: _Own(),
  ExtendSelectionByCharacterIntent: _Own(),
  ExtendSelectionToNextWordBoundaryIntent: _Own(),
  ExtendSelectionToNextParagraphBoundaryIntent: _Own(),
  ExtendSelectionToLineBreakIntent: _Own(),
  ExtendSelectionVerticallyToAdjacentLineIntent: _Own(),
  ExtendSelectionVerticallyToAdjacentPageIntent: _Own(),
  ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent: _Own(),
  ExtendSelectionToDocumentBoundaryIntent: _Own(),
  ExtendSelectionToNextWordBoundaryOrCaretLocationIntent: _Own(),
  ExpandSelectionToDocumentBoundaryIntent: _Own(),
  ExpandSelectionToLineBreakIntent: _Own(),
  SelectAllTextIntent: _Own(),
  CopySelectionTextIntent: _Own(),
  PasteTextIntent: _Own(),
  RedoTextIntent: _Own(),
  UndoTextIntent: _Own(),
  TransposeCharactersIntent: _Own(),
  ReplaceTextIntent: _Own(),
  UpdateSelectionIntent: _Own(),
};

/// The field a lane's new ticket is typed into, at the top of the lane, drawn as the card it is about to be
/// (`LaneComposer`; Matt: "add the ability to add new tickets to query boards from the board like we can on the
/// standard board"). The keyboard's done key or Add makes the ticket and leaves the field open and empty for the
/// next; Escape, or leaving it empty, puts it away.
class LaneComposer extends StatefulWidget {
  const LaneComposer({super.key, required this.look, required this.lane, required this.onAdd, required this.onClose});

  final QueryLook look;

  /// The lane's name, for what the field is called.
  final String lane;
  final void Function(String title) onAdd;
  final VoidCallback onClose;

  @override
  State<LaneComposer> createState() => LaneComposerState();
}

class LaneComposerState extends State<LaneComposer> implements TextSelectionGestureDetectorBuilderDelegate {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'New ticket');
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  Timer? _leaving;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  bool get ready => controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    focusNode.addListener(_focusMoved);
    focus();
  }

  @override
  void dispose() {
    _leaving?.cancel();
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  /// The field focused, and the keyboard asked for: as it opens, and at each press of its lane's + while it is open.
  void focus() {
    focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) editableTextKey.currentState?.requestKeyboard();
    });
  }

  void _focusMoved() {
    _leaving?.cancel();
    _leaving = null;
    if (focusNode.hasFocus || ready) return;
    // Left empty: put away, unless the focus is straight back (the + pressed again).
    _leaving = Timer(const Duration(milliseconds: 150), () {
      if (mounted && !focusNode.hasFocus) widget.onClose();
    });
  }

  void submit() {
    final title = controller.text.trim();
    if (title.isEmpty) return;
    widget.onAdd(title);
    controller.clear();
    fireMotor(HapticKind.selection);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final t = look.t;
    final em = look.em;
    // .composeField { block-size: 2.1em; line-height: 2.1em; color: inherit; font: inherit }
    final style = look.sans(em).copyWith(height: 2.1);
    final empty = controller.text.isEmpty;
    final tall = 2.1 * em;
    final field = EditableText(
      key: editableTextKey,
      controller: controller,
      focusNode: focusNode,
      style: style,
      cursorColor: look.ink,
      cursorWidth: 1,
      backgroundCursorColor: look.ink3,
      selectionColor: focusNode.hasFocus ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      keyboardType: TextInputType.text,
      // `enterKeyHint="done"`, `autoCapitalize="sentences"`
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      autofillHints: null,
      maxLines: 1,
      onEditingComplete: submit,
      onTapOutside: (_) {},
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
      textScaler: TextScaler.noScaling,
    );
    // .compose { display: grid; grid-template-columns: auto 1fr auto; align-items: center; column-gap: 0.55em;
    //   margin-block-end: var(--glacier-space-2); padding: 0.3em 0.3em 0.3em 0.65em; border-radius: 0.7em;
    //   background: var(--app-paper); box-shadow: inset 0 0 0 1.5px color-mix(in oklch, currentColor 30%,
    //   transparent), 0 1px 2px rgba(0, 0, 0, 0.12) }
    final radius = BorderRadius.circular(0.7 * em);
    final tick = 1.15 * em;
    return Padding(
      padding: EdgeInsets.only(bottom: look.space(2)),
      child: Part(
        'compose',
        child: Container(
          padding: EdgeInsets.fromLTRB(0.65 * em, 0.3 * em, 0.3 * em, 0.3 * em),
          decoration: BoxDecoration(color: look.paper, borderRadius: radius, boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x1f000000), offset: Offset(0, 1), blurRadius: (1 - 0.5) / 0.57735)]),
          foregroundDecoration: BoxDecoration(borderRadius: radius, border: Border.all(color: QueryLook.mix(look.ink, 0.3), width: 1.5, strokeAlign: BorderSide.strokeAlignInside)),
          child: Row(
            children: <Widget>[
              // .composeTick { inline-size: 1.15em; block-size: 1.15em; border-radius: 0.32em;
              //   border: 1.5px solid color-mix(in oklch, var(--app-ink) 30%, transparent) }
              Part('composeTick', child: Container(width: tick, height: tick, decoration: BoxDecoration(borderRadius: BorderRadius.circular(0.32 * em), border: Border.all(color: QueryLook.mix(look.ink, 0.3), width: 1.5)))),
              SizedBox(width: 0.55 * em),
              Expanded(
                child: Semantics(
                  container: true,
                  textField: true,
                  label: 'New ticket in ${widget.lane}',
                  child: Part(
                    'composeField',
                    child: SizedBox(
                      height: tall,
                      // Hung from the page's focus scope, not from the editor the board is built in.
                      child: Focus(
                        parentNode: FocusScope.of(context),
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: _key,
                        child: _gestures.buildGestureDetector(
                          behavior: HitTestBehavior.opaque,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: <Widget>[
                              // .composeField::placeholder { color: var(--app-ink-3) }
                              if (empty) IgnorePointer(child: Text('New ticket', maxLines: 1, softWrap: false, textScaler: TextScaler.noScaling, style: style.copyWith(color: look.ink3))),
                              Actions(actions: _ownKeys, child: field),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 0.55 * em),
              // .composeAdd { block-size: 2.1em; padding: 0 0.85em; border-radius: calc(0.7em - 0.3em);
              //   background: var(--app-ink); color: var(--app-paper); font-weight: 600; line-height: 1 }
              // .composeAdd:disabled { background: color-mix(in oklch, currentColor 10%, transparent);
              //   color: var(--app-ink-3) }
              Semantics(
                container: true,
                button: true,
                enabled: ready,
                label: 'Add',
                onTap: ready ? submit : null,
                excludeSemantics: true,
                // Pressed without taking the focus from the field, so the phone's keyboard stays up between tickets.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: submit,
                  child: Part(
                    'composeAdd',
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: tall,
                      padding: EdgeInsets.symmetric(horizontal: 0.85 * em),
                      decoration: BoxDecoration(color: ready ? look.ink : QueryLook.mix(look.ink3, 0.1), borderRadius: BorderRadius.circular(0.4 * em)),
                      child: Center(widthFactor: 1, child: Text('Add', softWrap: false, textScaler: TextScaler.noScaling, style: look.sans(em, weight: 'semibold', color: ready ? look.paper : look.ink3).copyWith(height: 1))),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
