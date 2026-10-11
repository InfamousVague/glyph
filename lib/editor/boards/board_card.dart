/// A card on a board, and the place a lane keeps for one: what `BoardWidget.drawCard` and the foot of `fill` build
/// in `src/app/editor/boards/widget.ts`, with a card's fields from `boards/fields.ts`.
///
///     .cm-boardCard        [BoardCard]: the tick or the dot, the words, and under them a footer
///       .cm-boardTick      the item's box, the card's; a dot (.cm-boardDot) for an item with none
///       .cm-boardWords     the item's words without their markdown, three lines at most; a way into the note
///       .cm-boardFields    the item's due day, priority and people, as chips of the card's own
///       .cm-boardLinked    the plugin its item is linked to, as its mark
///       .cm-boardMoves     the card's menu, and the chevrons that step it a lane along
///     .cm-boardEmpty       [BoardEmpty]: what an empty lane shows, and where a held card may be dropped
///
/// A card is a small grid on the page (Matt: "the cards themselves can have the text go full width and we can move
/// the notion icon to the right more"): the tick and the words on the first row, the words taking every bit of
/// width the card has, and under them a footer that sits right - the plugin's mark, then the menu and the two
/// arrows - with the item's fields at its start, under the words.
///
/// What differs:
/// - `press(button, run)` (boards/press.ts) kept the editor from taking a tap on a control as a caret move, and a
///   phone from placing a caret from the touch itself. Here a board keeps its pointers (`takesPointer`), so the
///   editor never joins the gesture, and each control is a tap in the arena: it answers when the finger lifts on
///   it, once, and not for a finger that slid off.
/// - The card's own `pointerdown` asked the DOM whether the press was on a control; here a control says so itself
///   ([BoardCard.onControl]) before the card hears the same pointer.
/// - A chip is drawn by the note's own [FieldChip], at the height a button's line gives it on the page.
library;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import '../../core/boards.dart';
import '../../core/item_links.dart' show markOf, unmarked;
import '../../core/task_fields.dart';
import '../items/field_chips.dart';
import '../items/field_menu.dart';
import '../looks/look.dart';
import '../view/line.dart' show EditorRunScope;
import 'board_look.dart';
import 'board_press.dart';
import 'board_words.dart';
import 'icons.dart';

/// What a card says: its item's words without their markdown and without the plugin's link, "New card" for one the
/// + has just written with no words yet, and its anchor for a card whose item is gone.
({String said, bool empty}) cardSaid(Card card) {
  final item = card.item;
  if (item == null) return (said: '^${card.id}', empty: false);
  // What the item is linked to rides at the end of its line as `[notion](…)`, and read as words the card said
  // "notion" after every single item. The link is taken off the words and shown as its plugin's mark instead.
  final written = cardText(markOf(item.text) != null ? unmarked(item.text) : item.text);
  return (said: written.isEmpty ? 'New card' : written, empty: written.isEmpty);
}

/// Whether a card shows this field (`onCard`): only its due day, its priority and its people. A card is a glance,
/// and a recurrence, a start day or a named field is the line's to show.
bool onCard(FieldSpan span) => span.kind == FieldKind.priority || span.kind == FieldKind.person || (span.kind == FieldKind.date && span.key == 'due');

/// The page a card's chip opens (`pageOf`).
FieldPage chipPage(FieldSpan span) => switch (span.kind) {
  FieldKind.priority => const PriorityPage(),
  FieldKind.person => PersonPage(span.value),
  _ => const DatePage('due'),
};

/// The card's chips, in the order its line has them (`cardFields`).
List<({ChipLook look, FieldSpan span})> cardChips(Item item, {required String today, String? locale}) {
  final done = item.done == true;
  return <({ChipLook look, FieldSpan span})>[
    for (final span in fieldsIn(item.text))
      if (onCard(span))
        if (chipLook(span, today: today, done: done, locale: locale) case final look?) (look: look, span: span),
  ];
}

/// What a card's controls do; all null on a card that only shows itself (the copy in the air, a note that cannot
/// be changed).
class CardDoes {
  const CardDoes({this.tick, this.goTo, this.step, this.more, this.chip});

  final VoidCallback? tick;
  final VoidCallback? goTo;
  final void Function(int by)? step;
  final VoidCallback? more;

  /// A chip pressed: its field, and the chip's box on the screen.
  final void Function(FieldSpan span, Rect box)? chip;

  static const CardDoes nothing = CardDoes();
}

class BoardCard extends StatelessWidget {
  BoardCard({
    super.key,
    required this.look,
    required this.card,
    required this.column,
    required this.columns,
    required this.today,
    this.locale,
    this.lineLook,
    this.does = CardDoes.nothing,
    this.arrived = false,
    this.moreKey,
    this.onControl,
    bool? chipButtons,
  }) : chipButtons = chipButtons ?? does.chip != null;

  final BoardLook look;
  final Card card;

  /// The lane it is drawn in, and how many the board has: the chevrons stop at either end.
  final int column;
  final int columns;

  /// The day a due day is counted from, and the language it is named in.
  final String today;
  final String? locale;

  /// The note's own line, for the chips to be drawn against.
  final LineLook? lineLook;
  final CardDoes does;

  /// Just landed: lit for a moment so the eye finds it.
  final bool arrived;
  final GlobalKey? moreKey;

  /// A pointer has gone down on one of the card's controls: the press is the control's, not the card's to lift by.
  final void Function(int pointer)? onControl;

  /// Whether the chips are drawn as the buttons they are where the note can be changed, on a button's taller line:
  /// so of a card that only shows itself (the copy in the air, a card being measured) when its card on the board is.
  final bool chipButtons;

  Widget _control({required String label, required bool enabled, required VoidCallback? onTap, required Widget child, Key? key}) => Semantics(
    key: key,
    container: true,
    button: true,
    enabled: enabled,
    label: label,
    onTap: enabled ? onTap : null,
    excludeSemantics: true,
    child: BoardPress(
      child: Listener(
        onPointerDown: (event) => onControl?.call(event.pointer),
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: enabled ? onTap : null, child: child),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = card.item;
    final gone = item == null;
    final done = item?.done == true;
    final (:said, :empty) = cardSaid(card);
    final mark = item == null ? null : markOf(item.text);
    final boxed = gone || item.done != null;
    final first = column == 0, last = column == columns - 1;

    // A to-do's box is the card's. An item with no box - a bullet, a step - is a card with nothing to tick.
    final Widget lead;
    final double leadWidth;
    if (boxed) {
      leadWidth = look.tickSize;
      Widget box = Container(
        key: const ValueKey<String>('tick'),
        width: look.tickSize,
        height: look.tickSize,
        decoration: BoxDecoration(
          color: done ? look.tickDone : null,
          borderRadius: BorderRadius.circular(look.tickRadius),
          border: Border.all(color: done ? look.tickDone : look.tickEdge, width: 1.5),
        ),
        // '.cm-boardTick svg': { visibility: 'hidden' }, shown on a card that is done.
        child: done ? Center(child: BoardIcon('check', size: look.tickCheck, color: look.paper)) : null,
      );
      // '.cm-boardTick:disabled': { opacity: '0.4' }
      if (gone) box = Opacity(opacity: 0.4, child: box);
      lead = Padding(padding: EdgeInsets.only(top: look.tickDrop), child: box);
    } else {
      leadWidth = look.dotSize + 2 * look.dotSide;
      lead = Padding(
        padding: EdgeInsets.fromLTRB(look.dotSide, look.dotDrop, look.dotSide, 0),
        child: Container(key: const ValueKey<String>('dot'), width: look.dotSize, height: look.dotSize, decoration: BoxDecoration(color: look.ink3, shape: BoxShape.circle)),
      );
    }

    final words = Semantics(
      container: true,
    button: true,
      label: gone ? '${card.id}: this item is not in the note' : 'Go to $said in the note',
      onTap: does.goTo,
      excludeSemantics: true,
      child: BoardPress(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: does.goTo,
          child: BoardWords(said, key: const ValueKey<String>('words'), face: look.wordsFace(done: done, quiet: gone || empty), maxLines: 3),
        ),
      ),
    );

    // The item's due day, priority and people, as chips of the card's own under its words.
    final chips = item == null ? const <({ChipLook look, FieldSpan span})>[] : cardChips(item, today: today, locale: locale);
    Widget? fields;
    if (chips.isNotEmpty) {
      final live = does.chip;
      // A button where a press can change the line (`font: inherit` gives it the editor's line of 1.6); on a page
      // that cannot be edited, only what it says, on the chip's own line of 1.35.
      fields = Wrap(
        key: const ValueKey<String>('fields'),
        spacing: look.fieldsGap,
        runSpacing: look.fieldsGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          for (final chip in chips)
            // A chip longer than the room under the words is not cut to it: it runs on under the arrows, as a flex
            // item that will not shrink below its words does on the page.
            OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              fit: OverflowBoxFit.deferToChild,
              alignment: AlignmentDirectional.centerStart,
              child: BoardPress(child: FieldChip(chip.look, lineHeight: chipButtons ? 1.6 : 1.35, onTap: live == null ? null : (box) => live(chip.span, box))),
            ),
        ],
      );
      final base = look.base, line = lineLook;
      if (base != null && line != null) {
        final size = look.fieldsType;
        final scale = size / base.fontSize;
        fields = EditorRunScope(
          line: line,
          look: RunLook(
            style: look.style(size),
            fontSize: size,
            color: look.ink,
            ascent: base.ascent * scale,
            descent: base.descent * scale,
            above: base.above * scale,
            below: base.below * scale,
            shift: 0,
            backgrounds: const <Color>[],
            painter: null,
            props: base.props,
          ),
          child: fields,
        );
      }
    }

    // The plugin a card's item is linked to, as its mark: quiet, beside the words, never read as one of them.
    final linked = mark == null
        ? null
        : Semantics(
            container: true,
            label: 'Linked to ${mark.name}',
            child: BoardIcon(mark.name == 'notion' ? 'notion' : 'link', key: const ValueKey<String>('linked'), size: look.linkedIcon, color: look.linkedInk),
          );

    Widget move(String name, String label, int by, bool off) => _control(
      key: ValueKey<String>('move$by'),
      label: '$label: $said',
      enabled: !off && does.step != null,
      onTap: () => does.step?.call(by),
      child: SizedBox.square(dimension: look.moveSize, child: Center(child: BoardIcon(name, size: look.moveIcon, color: off ? look.moveInkOff : look.moveInk))),
    );

    // The card's own menu: lanes to move to, the line in the note, what a plugin offers, and off the board. A press
    // and hold is already the drag, so the menu needs a button of its own, and it hangs from the button.
    final moves = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _control(
          key: moreKey,
          label: 'More for $said',
          enabled: does.more != null,
          onTap: does.more,
          child: SizedBox.square(key: const ValueKey<String>('more'), dimension: look.moveSize, child: Center(child: BoardIcon('more', size: look.moreIcon, color: look.moveInk))),
        ),
        move('left', 'Move left', -1, first),
        move('right', 'Move right', 1, last),
      ],
    );
    final movesWidth = 3 * look.moveSize;

    final gap = look.cardColumnGap;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[lead, SizedBox(width: gap), Expanded(child: words)]),
        SizedBox(height: look.cardRowGap),
        // The footer: the fields and the mark set on the row's middle, the menu and the arrows at its top, reaching
        // a breath past the card's own padding (`marginInlineEnd: '-0.1em'`).
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(width: leadWidth + gap),
                Expanded(child: fields ?? const SizedBox.shrink()),
                SizedBox(width: gap),
                ?linked,
                SizedBox(width: gap),
                SizedBox(width: movesWidth - look.movesOut, height: look.moveSize),
              ],
            ),
            Positioned(top: 0, right: -look.movesOut, child: moves),
          ],
        ),
      ],
    );

    Widget box = Container(
      constraints: BoxConstraints(minHeight: look.cardLeast),
      padding: EdgeInsets.fromLTRB(look.cardStart, look.cardTop, look.cardEnd, look.cardBottom),
      decoration: BoxDecoration(color: look.paper, borderRadius: BorderRadius.circular(look.cardRadius), boxShadow: const <BoxShadow>[BoardLook.cardShadow]),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(look.cardRadius),
        border: Border.all(color: arrived ? look.arrivedRing : look.cardRing, width: arrived ? 1.5 : 1, strokeAlign: BorderSide.strokeAlignInside),
      ),
      child: content,
    );
    if (boxed) {
      // The box is small; the place to tap it is not. An invisible margin around it takes a finger that lands a
      // little off, which otherwise hit the words beside it and went to the line.
      final enabled = !gone && does.tick != null;
      box = Stack(
        children: <Widget>[
          box,
          Positioned(
            left: look.cardStart - look.tickReach,
            top: look.cardTop + look.tickDrop - look.tickReach,
            width: look.tickSize + look.tickReach + look.tickReachEnd,
            height: look.tickSize + 2 * look.tickReach,
            child: _control(label: done ? 'Untick $said' : 'Tick $said', enabled: enabled, onTap: does.tick, child: const SizedBox.expand()),
          ),
        ],
      );
    }
    // '.cm-boardCard[data-done]': { opacity: '0.62' }
    return done ? Opacity(opacity: BoardLook.doneOpacity, child: box) : box;
  }
}

/// The card where it would land (`.cm-boardCard[data-lifted]`): its own shape, emptied out, so the column opens
/// exactly the space it takes.
///
/// The rule says only `border-style: dashed`, on a card that has no border: a style with no width given is the
/// browser's medium, three pixels, in the card's own ink. So the gap is ringed in heavy dashes, which is what the
/// page has always shown (Matt: "shows the dotted lines very briefly").
class BoardGap extends StatelessWidget {
  const BoardGap({super.key, required this.look, required this.height});

  final BoardLook look;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _Outline(look.ink, look.cardRadius, dashed: true, width: 3),
    // No shadow under it: a box's shadow is never drawn behind the box on the page, and this one can be seen
    // through.
    child: Container(
      height: height,
      decoration: BoxDecoration(color: look.liftedGround, borderRadius: BorderRadius.circular(look.cardRadius)),
    ),
  );
}

/// What a lane with no cards shows, and where a held card may be dropped (`.cm-boardEmpty`).
///
/// An empty column is a place, not a blank: at rest it shows what it would hold and says it holds nothing, and
/// while a card is held it is a target, outlined, in this column and every other, and says so instead.
class BoardEmpty extends StatelessWidget {
  const BoardEmpty({super.key, required this.look, required this.name, required this.holding, required this.over, this.fills = true});

  final BoardLook look;

  /// The column's name, which picks the picture and the words.
  final String name;

  /// A card is held somewhere on the board: this is a target.
  final bool holding;

  /// The held card is over this lane.
  final bool over;

  /// Whether it fills the room it is given, its words in the middle (an empty lane), or is as tall as its words
  /// (the target under a lane's cards).
  final bool fills;

  @override
  Widget build(BuildContext context) {
    final face = look.emptyFace;
    final shown = emptyLook(name);
    final Widget inside;
    if (holding) {
      inside = BoardWords('Drop a card here', key: const ValueKey<String>('drop'), face: face, wrap: false, shrink: true);
    } else {
      inside = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          BoardIcon(shown.icon, key: const ValueKey<String>('empty-icon'), size: look.emptyIcon, color: look.emptyIconInk),
          SizedBox(height: look.emptyGap),
          BoardWords(shown.words, key: const ValueKey<String>('empty-words'), face: face, wrap: false, shrink: true),
        ],
      );
    }
    final ends = fills ? 0.0 : look.emptyEnds;
    Widget box = Padding(
      padding: EdgeInsets.symmetric(horizontal: 1 + look.emptySide, vertical: 1 + ends),
      child: fills ? Center(child: inside) : Align(heightFactor: 1, child: inside),
    );
    if (holding) {
      // '.cm-board[data-holding] .cm-boardEmpty': { borderColor: 'var(--app-rule, …)' }, dashed; solid on the lane
      // the card is over ('.cm-boardStack[data-over] .cm-boardEmpty').
      box = CustomPaint(foregroundPainter: _Outline(look.rule, look.columnRadius, dashed: !over), child: box);
    }
    return box;
  }
}

/// A border `width` wide, dashed or solid, round corners of `radius`.
class _Outline extends CustomPainter {
  const _Outline(this.color, this.radius, {required this.dashed, this.width = 1});

  final Color color;
  final double radius;
  final bool dashed;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    final corner = radius.clamp(0.0, size.shortestSide / 2).toDouble();
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(width / 2), Radius.circular(corner > width / 2 ? corner - width / 2 : 0)));
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    // Chromium's dashes: three of a hairline's width drawn and three left; two of a heavier border's, and one.
    final dash = width < 3 ? 3 * width : 2 * width, space = width < 3 ? 3 * width : width;
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + space) {
        canvas.drawPath(metric.extractPath(at, (at + dash).clamp(0.0, metric.length).toDouble()), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Outline oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius || oldDelegate.dashed != dashed || oldDelegate.width != width;
}
