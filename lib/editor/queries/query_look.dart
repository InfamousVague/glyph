/// How a query's answer looks: the lengths and colours of `src/app/editor/QueryView.module.css`, worked out once
/// for the tokens the note is drawn in, each rule cited beside what it sets where it is used (query_view.dart,
/// query_parts.dart, query_board.dart). A card in the page's tinted surface, in the app's own face and size, since
/// it is the app's drawing and not the note's words.
///
/// An em in that stylesheet is one of three: the card's (`font-size: var(--glacier-font-size-sm)`), a small part's
/// (`--glacier-font-size-xs`), and a `<button>`'s own where the rule does not say `font: inherit` (the browser's
/// 13.333px: a to-do's box, a lane's +).
///
/// What differs: `:hover`, `:focus-visible` and `cursor` rules have no counterpart on a phone and are left out.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../boards/board_look.dart' show BoardLook;
import '../looks/look.dart' show Look, LookElement, layoutUnitFloor;
import '../tables/table_layout.dart' show WordsFace, blinkLineHeight;
import 'query_layout.dart' show pageLine;

export '../boards/board_look.dart' show buttonType;

class QueryLook {
  QueryLook(this.t, {required this.bleed, required this.note, this.coding = true, this.tabular = false})
    : em = t.fontSize('sm'),
      xs = t.fontSize('xs'),
      ink = t.color('app-ink'),
      ink2 = t.color('app-ink-2'),
      ink3 = t.color('app-ink-3'),
      ink4 = t.color('app-ink-4'),
      paper = t.color('app-paper'),
      paper2 = t.color('app-paper-2'),
      rule = t.color('app-rule');

  /// The look for the editor [context] is in: its gutter and its note's type ([Look.env]), or the page's own.
  factory QueryLook.of(BuildContext context, Look? look) {
    final t = context.tokens;
    final env = look?.env;
    return QueryLook(t, bleed: layoutUnitFloor(env?.gutter ?? t.len('app-gutter')), note: env?.body ?? t.len('app-body'), coding: look?.line(LookElement(null)).base.props.mono ?? true);
  }

  final Tokens t;

  /// The note's indent, given back as the block's padding so the card lines up with the words
  /// (`--cm-board-bleed`).
  final double bleed;

  /// The note's own type: the em of the block's `padding-block: 0.4em`.
  final double note;

  /// Whether the note is set in a coding face. The app's stylesheet (`typefaces.css`) takes two things off
  /// everything drawn in such a note's editor, the app's own drawings in it included: every letter-spacing
  /// (`.cm-editor * { letter-spacing: 0 !important }`), and the face's optical sizes
  /// (`font-optical-sizing: none`).
  final bool coding;

  /// Whether every figure is set as wide as every other, whatever is asked: a table's
  /// (`.table { font-variant-numeric: tabular-nums }`, which every word in it inherits, and which in the app's face
  /// sets its spaces a touch narrower too).
  final bool tabular;

  /// This look inside a table.
  QueryLook get tabled => QueryLook(t, bleed: bleed, note: note, coding: coding, tabular: true);

  /// `font-size: var(--glacier-font-size-sm)`, the card's; and `--glacier-font-size-xs`, a small part's.
  final double em;
  final double xs;

  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color ink4;
  final Color paper;
  final Color paper2;
  final Color rule;

  /// `var(--glacier-space-n)`, as Blink takes a padding: down to the sixty-fourth below.
  double space(int step) => layoutUnitFloor(t.space(step));

  /// `line-height: 1.4`, the card's.
  static const double leading = 1.4;

  /// A line of the card's own words, and of a small part's.
  double get line => pageLine(em, leading);
  double get lineXs => pageLine(xs, leading);

  static Color mix(Color color, double part) => color.withValues(alpha: color.a * part);

  /// The app's face at [px].
  TextStyle sans(double px, {String weight = 'regular', Color? color, double tracking = 0, bool struck = false, Color? strike, bool tabular = false}) {
    final style = t.textAt(px, weight: weight, color: color ?? ink, height: leading, tracking: coding ? 0 : tracking);
    return style.copyWith(
      // Without optical sizing the face is drawn at its own cut, Inter's 14.
      fontVariations: coding ? <FontVariation>[for (final variation in style.fontVariations ?? const <FontVariation>[]) variation.axis == 'opsz' ? const FontVariation('opsz', 14) : variation] : style.fontVariations,
      decoration: struck ? TextDecoration.lineThrough : TextDecoration.none,
      decorationColor: strike,
      fontFeatures: tabular || this.tabular ? <FontFeature>[...?style.fontFeatures, const FontFeature.tabularFigures()] : style.fontFeatures,
    );
  }

  /// The coding face at [px]: a ticket's key, a query's lines.
  TextStyle mono(double px, {String weight = 'regular', Color? color, double tracking = 0}) => t.textAt(px, weight: weight, mono: true, color: color ?? ink, height: leading, tracking: coding ? 0 : tracking);

  // '.cm-query': { paddingBlock: '0.4em', paddingInline: 'var(--cm-board-bleed, var(--app-gutter, 1rem))' }
  double get blockEnds => layoutUnitFloor(0.4 * note);

  // .query { margin-block: var(--glacier-space-1) var(--glacier-space-3);
  //   padding: var(--glacier-space-2) var(--glacier-space-3) var(--glacier-space-3);
  //   border: 1px solid var(--app-rule); border-radius: var(--glacier-radius-lg); background: var(--app-paper-2) }
  double get cardRadius => t.radius('lg');

  /// The room inside the card, across: the block's width less the note's indent, the card's border and its padding.
  double inner(double block) => block - 2 * bleed - 2 - 2 * space(3);
}

/// The ```board's own look ([BoardLook]) for the parts a query's board borrows from it whole: the line under the
/// board ([BoardSplit]) and the room it reaches. Its em is the query's, since the height a query's fence holds is in
/// its lanes' ems, and the line's margins are `QueryView.module.css`'s `.split`.
class QuerySplitLook extends BoardLook {
  QuerySplitLook(this.query, {required super.window}) : super(t: query.t, base: null, note: query.note, gutter: 0);

  final QueryLook query;

  @override
  double get em => query.em;

  @override
  Color get ink => query.ink;

  // .split { block-size: var(--glacier-hairline, 1px); margin-block: var(--glacier-space-3) var(--glacier-space-1) }
  @override
  double get splitAbove => query.space(3);

  @override
  double get splitBelow => query.space(1);

  // .split::before { inset-block: -0.9em }
  @override
  double get splitReachAbove => 0.9 * query.em;

  @override
  TextStyle style(double size, {double weight = 400, Color? color, bool italic = false, bool struck = false, double tracking = 0}) =>
      query.sans(size, weight: weight >= 600 ? 'semibold' : 'regular', color: color).copyWith(height: kTextHeightNone);

  @override
  WordsFace face(double size, double lineHeight, {double weight = 400, Color? color, bool italic = false, bool struck = false, double tracking = 0}) =>
      WordsFace(style(size, weight: weight, color: color), blinkLineHeight(lineHeight, size));
}
