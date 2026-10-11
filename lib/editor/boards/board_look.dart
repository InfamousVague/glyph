/// How a board looks: its columns, cards, controls, the + field and the line under it, as lengths and colours worked
/// out once for the type the note is set in. Ports `src/app/editor/boards/theme.ts`, each rule cited beside what it
/// sets; the anchors' and pointers' rules at its foot were ported with them (items/anchors.dart).
///
/// The stylesheet is in ems, and an em on a board is one of three: the note's (the wrap and the line under it), the
/// board's (`BOARD_TYPE` of the note's) and a control's own. A `<button>` does not take its parent's type unless it
/// is told to (`font: inherit`): the +, the chevrons and the more button are sized in the browser's own 13.333px
/// whatever the note is set in, and so here ([buttonType]).
///
/// What differs:
/// - **A lane's name is not spaced out in a coding face.** The rule says `letter-spacing: 0.07em`, and in the
///   note's own face (Maple Mono) the page does not draw it: measured, "TO DO" at 11.7px is five advances of 7.02
///   wide, where in Inter it is 4.1px wider, five spacings of 0.82. The name is set as the page draws it.
/// - `:hover`, `:focus-visible` and `cursor` rules have no counterpart on a phone and are left out; the grip is
///   white while the line is dragged, as the rule for `[data-dragging]` has it.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../looks/look.dart';
import '../tables/table_layout.dart' show WordsFace, blinkLineHeight;
import 'height.dart' show boardType, laneFoot;

/// A `<button>`'s own type where the stylesheet gives it none: the browser's 13.3333px.
const double buttonType = 40 / 3;

/// The device pixels to a CSS one the page is laid out in (the tokens' `css.lineDpr`): 1 on a desktop, a phone's
/// own on a phone, where a padding is a sixty-fourth of a DEVICE pixel and a face's ascent a whole one. One for
/// the whole app, as the screen is; said as a look is made.
double _ratio = 1;

double _fl(double value) => layoutUnitFloor(value * _ratio) / _ratio;

/// [_fl] for the first length a look works out, which says the ratio for the rest.
double _flAt(double value, Tokens t) {
  _ratio = t.css.lineDpr > 0 ? t.css.lineDpr : 1;
  return _fl(value);
}

class BoardLook {
  BoardLook({required this.t, required this.base, required this.note, required double gutter, required this.window})
    : em = boardType * note,
      bleed = _flAt(gutter, t),
      ink = base?.color ?? t.color('app-ink'),
      ink2 = t.color('app-ink-2'),
      ink3 = t.color('app-ink-3'),
      paper = t.color('app-paper'),
      rule = t.color('app-rule');

  /// The look for the editor `context` is in: the sizes its editor was given (a card's preview sets its own), or
  /// the page's.
  factory BoardLook.of(BuildContext context, Look? look) {
    final t = context.tokens;
    final env = look?.env;
    return BoardLook(
      t: t,
      base: look?.line(LookElement(null)).base,
      note: env?.body ?? t.len('app-body'),
      gutter: env?.gutter ?? t.len('app-gutter'),
      window: MediaQuery.sizeOf(context),
    );
  }

  final Tokens t;

  /// The note's own run, for its face.
  final RunLook? base;

  /// The note's type, and the board's: `fontSize: '0.86em'`.
  final double note;
  final double em;

  /// The note's indent, given back as the board's padding so the first column lines up with the words
  /// (`--cm-board-bleed`).
  final double bleed;
  final Size window;

  /// `currentColor` on the board: the note's ink.
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color paper;
  final Color rule;

  /// Whether `other` draws the same board.
  bool same(BoardLook other) => identical(other.t, t) && identical(other.base, base) && other.note == note && other.bleed == bleed && other.window == window;

  Color _mix(Color color, double part) => color.withValues(alpha: color.a * part);

  /// A face in the note's family at `size`.
  TextStyle style(double size, {double weight = 400, Color? color, bool italic = false, bool struck = false, double tracking = 0}) {
    final ink = color ?? this.ink;
    final from = base;
    final decoration = struck ? TextDecoration.lineThrough : TextDecoration.none;
    if (from == null) {
      return t
          .textAt(size, mono: true, weight: weight >= 600 ? 'bold' : 'regular', color: ink)
          .copyWith(height: kTextHeightNone, fontStyle: italic ? FontStyle.italic : FontStyle.normal, decoration: decoration, decorationColor: ink);
    }
    return from.style.copyWith(
      fontSize: size,
      fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
      fontVariations: <FontVariation>[FontVariation('wght', weight), if (from.props.optical) FontVariation('opsz', size)],
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: ink,
      letterSpacing: tracking,
      decoration: decoration,
      decorationColor: ink,
    );
  }

  WordsFace face(double size, double lineHeight, {double weight = 400, Color? color, bool italic = false, bool struck = false, double tracking = 0}) =>
      WordsFace(style(size, weight: weight, color: color, italic: italic, struck: struck, tracking: tracking), blinkLineHeight(lineHeight, size, _ratio), ratio: _ratio);

  /// Whether the note is set in a coding face, whose letters are never spaced out.
  bool get coding => base?.props.mono ?? true;

  // '.cm-boardWrap': { paddingBlock: `calc(0.4em * ${BOARD_TYPE}) 0.5em` }
  double get wrapTop => _fl(0.4 * em);
  double get wrapBottom => _fl(0.5 * note);

  // '.cm-board': { display: 'flex', gap: '0.7em', inlineSize: 'var(--cm-board-room, 100%)',
  //   paddingInline: 'var(--cm-board-bleed, 0px)', overflowX: 'auto', overflowY: 'hidden',
  //   scrollSnapType: 'x mandatory', paddingBlock: '0.1em 0.5em', fontSize: `${BOARD_TYPE}em` }
  double get boardTop => _fl(0.1 * em);
  double get boardBottom => _fl(0.5 * em);
  double get columnGap => _fl(0.7 * em);

  // '.cm-boardColumn': { flex: '0 0 auto', inlineSize: 'min(78vw, 16rem)', scrollSnapAlign: 'start',
  //   display: 'flex', flexDirection: 'column', gap: '0.4em', padding: '0.5em 0.45em 0.2em',
  //   borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
  //   background: 'color-mix(in oklch, currentColor 4%, transparent)' }
  double get columnWidth => _fl(t.lenOf('min(78vw, 16rem)'));
  double get columnTop => _fl(0.5 * em);
  double get columnSide => _fl(0.45 * em);
  double get columnBottom => _fl(0.2 * em);
  double get columnRadius => t.len('glacier-radius-lg');
  Color get columnGround => _mix(ink, 0.04);

  /// The room a lane's cards have across.
  double get laneWidth => columnWidth - 2 * columnSide;

  /// The gap between a column's head, its + field and its lane, and between a lane's cards: both `0.4em`.
  double get gap => _fl(0.4 * em);

  // '.cm-boardName': { display: 'flex', alignItems: 'center', gap: '0.45em', margin: '0', padding: '0 0.15em',
  //   minBlockSize: '1.9em', fontSize: '0.78em', fontWeight: '700', letterSpacing: '0.07em',
  //   textTransform: 'uppercase', color: 'var(--app-ink-3, var(--glacier-text-muted))' }
  double get headType => 0.78 * em;
  double get headSide => _fl(0.15 * headType);
  double get headGap => _fl(0.45 * headType);
  WordsFace get nameFace => face(headType, 1.6, weight: 700, color: ink3, tracking: coding ? 0 : 0.07 * headType);

  // '.cm-boardCount': { flex: 'none', minInlineSize: '1.6em', padding: '0.05em 0.45em', borderRadius: '999px',
  //   background: 'color-mix(in oklch, currentColor 10%, transparent)', textAlign: 'center',
  //   letterSpacing: '0', fontWeight: '600' }
  WordsFace get countFace => face(headType, 1.6, weight: 600, color: ink3);
  double get countLeast => _fl(1.6 * headType);
  double get countSide => _fl(0.45 * headType);
  double get countEnds => _fl(0.05 * headType);
  Color get countGround => _mix(ink3, 0.1);

  // '.cm-boardAdd': { flex: 'none', display: 'grid', placeItems: 'center', marginInlineStart: 'auto',
  //   inlineSize: '2em', blockSize: '2em', padding: '0', border: 'none', borderRadius: '999px',
  //   background: 'color-mix(in oklch, currentColor 8%, transparent)', color: 'var(--app-ink-2, inherit)' }
  double get addSize => _fl(2 * buttonType);
  double get addIcon => _fl(1.05 * buttonType);
  Color get addGround => _mix(ink2, 0.08);

  /// A column's head: as tall as the tallest thing in it, and never under `1.9em`.
  double get headHeight {
    final count = countFace.lineHeight + 2 * countEnds;
    final least = _fl(1.9 * headType);
    return <double>[least, addSize, count, nameFace.lineHeight].reduce((a, b) => a > b ? a : b);
  }

  // '.cm-boardStack': { display: 'flex', flexDirection: 'column', flex: '1 1 auto', gap: '0.4em',
  //   minBlockSize: '2.5em', paddingBlockEnd: `${LANE_FOOT}em` }
  double get laneLeast => _fl(2.5 * em);
  double get laneFootOwn => _fl(laneFoot * em);

  // '.cm-board[data-sized] .cm-boardStack', '.cm-board[data-pinned]:not([data-sized]) .cm-boardStack':
  //   { blockSize: …, overflowY: 'auto', scrollbarWidth: 'none', paddingBlockEnd: '0.9em' }
  double get laneFootHeld => _fl(0.9 * em);

  /// A lane a fence sets `height` ems tall: `--cm-lane-height`.
  double laneHeight(double height) => _fl(height * em);

  // '.cm-boardStack[data-more]': { maskImage: 'linear-gradient(to bottom, #000 calc(100% - var(--cm-lane-fade,
  //   1.2em)), transparent)' }
  double get laneFade => 1.2 * em;

  // '.cm-boardCard': { display: 'grid', gridTemplateColumns: 'auto 1fr auto auto',
  //   gridTemplateAreas: '"tick words words words" ". fields linked moves"', alignItems: 'start',
  //   columnGap: '0.55em', rowGap: '0.15em', flex: 'none', minBlockSize: '2.6em',
  //   padding: '0.6em 0.4em 0.3em 0.65em', borderRadius: '0.7em', background: 'var(--app-paper, …)',
  //   boxShadow: 'inset 0 0 0 1px color-mix(in oklch, currentColor 9%, transparent), 0 1px 2px rgba(0, 0, 0, 0.12)' }
  double get cardTop => _fl(0.6 * em);
  double get cardEnd => _fl(0.4 * em);
  double get cardBottom => _fl(0.3 * em);
  double get cardStart => _fl(0.65 * em);
  double get cardLeast => _fl(2.6 * em);
  double get cardColumnGap => _fl(0.55 * em);
  double get cardRowGap => _fl(0.15 * em);
  double get cardRadius => 0.7 * em;
  Color get cardRing => _mix(ink, 0.09);
  static const BoxShadow cardShadow = BoxShadow(color: Color(0x1f000000), offset: Offset(0, 1), blurRadius: (1 - 0.5) / 0.57735);

  // '.cm-boardCard[data-done]': { opacity: '0.62' }
  static const double doneOpacity = 0.62;

  // '.cm-boardCard[data-lifted]': { background: 'color-mix(in oklch, currentColor 4%, transparent)',
  //   borderStyle: 'dashed', overflow: 'hidden' }
  Color get liftedGround => _mix(ink, 0.04);

  // '.cm-boardCard[data-arrived]': { boxShadow: 'inset 0 0 0 1.5px color-mix(in oklch, var(--app-ink,
  //   currentColor) 55%, transparent), 0 1px 2px rgba(0, 0, 0, 0.12)' }
  Color get arrivedRing => _mix(t.color('app-ink'), 0.55);

  // '.cm-boardTick': { gridArea: 'tick', position: 'relative', display: 'grid', placeItems: 'center',
  //   fontSize: 'inherit', lineHeight: '1', inlineSize: '1.15em', blockSize: '1.15em',
  //   marginBlockStart: 'calc((1.35em - 1.15em) / 2)', padding: '0', borderRadius: '0.32em',
  //   border: '1.5px solid color-mix(in oklch, var(--app-ink, var(--glacier-text)) 45%, transparent)',
  //   background: 'none', color: 'var(--app-paper, var(--glacier-bg))' }
  double get tickSize => _fl(1.15 * em);
  double get tickDrop => _fl((1.35 * em - 1.15 * em) / 2);
  double get tickRadius => 0.32 * em;
  double get tickCheck => _fl(0.85 * em);
  Color get tickEdge => _mix(t.color('app-ink'), 0.45);

  // '.cm-boardCard[data-done] .cm-boardTick': { background: 'var(--app-ink, currentColor)',
  //   borderColor: 'var(--app-ink, currentColor)' }
  Color get tickDone => t.color('app-ink');

  // '.cm-boardTick::before': { content: '""', position: 'absolute', inset: '-0.6em -0.45em -0.6em -0.6em' }
  double get tickReach => 0.6 * em;
  double get tickReachEnd => 0.45 * em;

  // '.cm-boardDot': { gridArea: 'tick', justifySelf: 'center', flex: 'none', inlineSize: '0.4em',
  //   blockSize: '0.4em', marginBlockStart: '0.55em', marginInline: '0.45em', borderRadius: '50%',
  //   background: 'var(--app-ink-3, currentColor)' }
  double get dotSize => _fl(0.4 * em);
  double get dotDrop => _fl(0.55 * em);
  double get dotSide => _fl(0.45 * em);

  // '.cm-boardWords': { gridArea: 'words', minInlineSize: '0', display: '-webkit-box', WebkitLineClamp: '3',
  //   WebkitBoxOrient: 'vertical', overflow: 'hidden', font: 'inherit', lineHeight: '1.35', textAlign: 'start' }
  // '.cm-boardCard[data-done] .cm-boardWords': { textDecoration: 'line-through', color: 'var(--app-ink-3, …)' }
  // '.cm-boardCard[data-gone] .cm-boardWords', '.cm-boardCard[data-empty] .cm-boardWords':
  //   { fontStyle: 'italic', color: 'var(--app-ink-3, …)' }
  WordsFace wordsFace({bool done = false, bool quiet = false}) => face(em, 1.35, color: done || quiet ? ink3 : ink, italic: quiet, struck: done);

  // '.cm-boardFields': { gridArea: 'fields', alignSelf: 'center', display: 'flex', flexWrap: 'wrap',
  //   alignItems: 'center', gap: '0.3em', minInlineSize: '0', fontSize: '0.88em' }
  double get fieldsType => 0.88 * em;
  double get fieldsGap => _fl(0.3 * fieldsType);

  // '.cm-boardLinked': { gridArea: 'linked', alignSelf: 'center', display: 'grid', placeItems: 'center',
  //   color: 'var(--app-ink-3, …)', opacity: '0.8' }
  double get linkedIcon => _fl(0.95 * em);
  Color get linkedInk => _mix(ink3, 0.8);

  // '.cm-boardMoves': { gridArea: 'moves', display: 'flex', gap: '0', marginInlineEnd: '-0.1em' }
  // '.cm-boardMove', '.cm-boardMore': { display: 'grid', placeItems: 'center', inlineSize: '1.7em',
  //   blockSize: '1.7em', padding: '0', border: 'none', borderRadius: '999px', background: 'none',
  //   color: 'var(--app-ink-3, …)', opacity: '0.7' }
  // '.cm-boardMove:disabled': { opacity: '0.25' }
  double get moveSize => _fl(1.7 * buttonType);
  double get movesOut => _fl(0.1 * em);
  double get moveIcon => _fl(buttonType);
  double get moreIcon => _fl(1.1 * buttonType);
  Color get moveInk => _mix(ink3, 0.7);
  Color get moveInkOff => _mix(ink3, 0.25);

  // '.cm-boardEmpty': { display: 'none', margin: '0', padding: '0.8em 0.6em',
  //   borderRadius: 'var(--glacier-radius-lg, 0.75rem)', border: '1px dashed transparent', textAlign: 'center',
  //   fontSize: '0.9em', color: 'var(--app-ink-3, …)' }
  // '.cm-boardEmpty[data-none]': { display: 'grid', flex: '1 1 auto', alignContent: 'center',
  //   paddingBlock: '1.1em', marginBlockEnd: `calc(${-LANE_FOOT}em / 0.9)` }
  // '.cm-boardEmptyRest': { display: 'grid', justifyItems: 'center', gap: '0.45em' }
  // '.cm-boardEmptyIcon': { opacity: '0.55' }
  double get emptyType => 0.9 * em;
  WordsFace get emptyFace => face(emptyType, 1.6, color: ink3);
  double get emptyEnds => _fl(0.8 * emptyType);
  double get emptyEndsNone => _fl(1.1 * emptyType);
  double get emptySide => _fl(0.6 * emptyType);
  double get emptyIcon => _fl(1.5 * emptyType);
  double get emptyGap => _fl(0.45 * emptyType);
  Color get emptyIconInk => _mix(ink3, 0.55);

  /// An empty lane's own height, left to itself: its picture and its words, the room round them and its border.
  double get emptyNatural => 2 * emptyEndsNone + emptyIcon + emptyGap + emptyFace.lineHeight + 2;

  /// The place a held card may be dropped, under a lane's cards: its words, the room round them and its border.
  double get dropHeight => 2 * emptyEnds + emptyFace.lineHeight + 2;

  // '.cm-boardCompose': { display: 'grid', gridTemplateColumns: 'auto 1fr auto', alignItems: 'center',
  //   columnGap: '0.55em', padding: '0.3em 0.3em 0.3em 0.65em', borderRadius: '0.7em',
  //   background: 'var(--app-paper, …)', boxShadow: 'inset 0 0 0 1.5px color-mix(in oklch, currentColor 30%,
  //   transparent), 0 1px 2px rgba(0, 0, 0, 0.12)' }
  double get composePad => _fl(0.3 * em);
  Color get composeRing => _mix(ink, 0.3);

  // '.cm-boardComposeTick': { inlineSize: '1.15em', blockSize: '1.15em', borderRadius: '0.32em',
  //   border: '1.5px solid color-mix(in oklch, var(--app-ink, var(--glacier-text)) 30%, transparent)' }
  Color get composeTickEdge => _mix(t.color('app-ink'), 0.3);

  // '.cm-boardComposeField': { minInlineSize: '0', blockSize: '2.1em', padding: '0', border: 'none',
  //   background: 'none', color: 'inherit', font: 'inherit', lineHeight: '2.1em', outline: 'none' }
  double get composeField => _fl(2.1 * em);
  double get composeHeight => composeField + 2 * composePad;

  // '.cm-boardComposeAdd': { blockSize: '2.1em', padding: '0 0.85em', border: 'none',
  //   borderRadius: 'calc(0.7em - 0.3em)', background: 'var(--app-ink, currentColor)',
  //   color: 'var(--app-paper, …)', font: 'inherit', fontWeight: '600', lineHeight: '1' }
  // '.cm-boardComposeAdd:disabled': { background: 'color-mix(in oklch, currentColor 10%, transparent)',
  //   color: 'var(--app-ink-3, …)' }
  double get composeAddSide => _fl(0.85 * em);
  double get composeAddRadius => 0.7 * em - 0.3 * em;
  WordsFace composeAddFace({required bool ready}) => face(em, 1, weight: 600, color: ready ? paper : ink3);
  Color composeAddGround({required bool ready}) => ready ? t.color('app-ink') : _mix(ink3, 0.1);

  // '.cm-boardSplit': { position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center',
  //   blockSize: 'var(--glacier-hairline, 1px)', marginInline: 'var(--cm-board-bleed, 0px)',
  //   marginBlock: '0.3em 1em', background: 'var(--glacier-border-subtle, …)', touchAction: 'none' }
  // '.cm-boardSplit::before': { content: '""', position: 'absolute', insetInline: '0', insetBlock: '-0.7em -1em' }
  // '.cm-boardSplit:focus-visible, .cm-boardSplit[data-dragging]': { background: 'var(--glacier-accent-solid, …)' }
  double get splitAbove => _fl(0.3 * note);
  double get splitBelow => _fl(note);
  // A height, not a border's width: one CSS pixel on any screen, where the tokens answer `--glacier-hairline` as a
  // rule is drawn (two device pixels of a phone's 2.625, 0.762px).
  double get splitLine => 1;
  double get splitReachAbove => 0.7 * note;
  Color get splitInk => t.color('glacier-border-subtle');
  Color get splitInkHeld => t.color('glacier-accent-solid');

  // '.cm-boardGrip': { position: 'relative', zIndex: '1', inlineSize: 'var(--glacier-space-6, 1.5rem)',
  //   blockSize: '6px', borderRadius: 'var(--glacier-radius-full, 999px)',
  //   background: 'color-mix(in oklch, currentColor 45%, transparent)' }
  // '.cm-boardSplit[data-dragging] .cm-boardGrip': { background: '#fff' }
  double get gripWidth => t.len('glacier-space-6');
  static const double gripHeight = 6;
  Color get gripInk => _mix(ink, 0.45);

  /// What a column has above and below its lane: its padding, its head and the gap under it.
  double get columnChrome => columnTop + headHeight + gap + columnBottom;
}
