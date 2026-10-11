/// A drawn table's geometry: the browser's automatic table layout for the one kind of table
/// `src/app/editor/tables.ts` makes, worked out here because Flutter has no `<table>`.
///
/// The page's table is `border-collapse: collapse` with `min-inline-size: 60%`, its cells padded `0.35em 0.7em`
/// inside a `1px` rule, a header cell `white-space: nowrap`, a body cell `pre-wrap` that breaks between words and
/// never inside one, and no cell wider than `18em`. Chromium lays that out so (every number measured on the page,
/// test/editor/tables/fixtures/reference.mjs):
///
/// - a cell's box is its words, its padding and one rule's width (half of the rule each side is the cell's, the
///   table's own box has the outer halves);
/// - a column's least width is its widest cell's least (a header's whole words, a body cell's longest unbreakable
///   piece), its most its widest cell's words on one line, and both stop at `18em`, padding and rule INCLUDED: a
///   header longer than that keeps the cell at `18em` and runs out of it over its neighbour;
/// - the table is as wide as its columns' most, held between its columns' least and the room there is, and never
///   under sixty parts in a hundred of the room;
/// - room over the columns' most is shared in proportion to each one's most; room between least and most in
///   proportion to what each still wants (most less least);
/// - a row is as tall as its tallest cell's lines, `1.35` of the size each, with the padding and a rule; a row of
///   nothing but empty cells is the padding and the rule alone.
///
/// Words are set by Flutter's paragraph, told where the page's lines may break (`view/line_breaks.dart`), and each
/// line is then drawn where Blink puts it: lines the face's line height apart (the paragraph's own are a whole
/// number of pixels), the box's top on a whole pixel and the baseline the font's ascent, rounded, under it.
///
/// A cell may hold a box of its own in place of its words ([CellHost]): a blank's square or a filled answer, which
/// are widgets (lib/editor/ai/blanks.dart `drawCell`). The table then takes that box's width as the cell's words'
/// and its height as the cell's lines', and says where it goes; the box is laid out and drawn by whoever holds it.
///
/// What differs:
/// - A cell holding a box of its own asks for its whole width, up to `18em`, where the page would let its words
///   wrap between a least and a most: a box's least is not a thing a render object can be asked for when it holds
///   squares set on the words' baseline.
/// - Widths are doubles here and sixty-fourths of a pixel there; the columns' shares are within a twentieth of a
///   pixel of the page's (the worst of any rectangle measured is an eighth).
/// - In Maple Mono the words' pixels are on the page's rows exactly. In Inter the boxes are the page's but the
///   glyphs sit one pixel lower than Chromium draws them at this size (0.92em), for a reason not found: the page's
///   own lines in Inter, at the body's size, agree with the same rule.
/// - A single word wider than `18em` in a body cell runs out of its cell on the page; the paragraph here breaks it
///   inside the word.
/// - Only left-to-right tables: `text-align: start` is the left.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../commands/tables.dart' show TableAlign;
import '../looks/look.dart';
import '../view/line_breaks.dart';

/// A unitless `line-height` as Blink resolves it: the font size taken to the nearest sixty-fourth, times the
/// number, down to the sixty-fourth below. (16.0546px at 1.35 is 21.65625 on the page, not 21.671875; 20.5143px
/// is 27.6875; 13.9606px at 1.6 is 22.3125.)
///
/// A phone's page is laid out in the phone's own pixels: [ratio] of them to a CSS one, and the sixty-fourths are
/// of those. (A row of a table at 16.2458px on a screen at 2.625 is a line of 57.5625 device pixels, 21.9286px.)
double blinkLineHeight(double factor, double size, [double ratio = 1]) => layoutUnitFloor(factor * layoutUnit(size * ratio)) / ratio;

/// A length of [value] CSS pixels as a page laid out at [ratio] device pixels to one has it: down to the
/// sixty-fourth of a device pixel.
double deviceFloor(double value, double ratio) => layoutUnitFloor(value * ratio) / ratio;

/// `border: 1px solid` as a page laid out at [ratio] draws it: a whole number of device pixels, down, and never
/// under one (2 of them at 2.625, which is 0.762px).
double deviceRule(double width, double ratio) {
  final device = (width * ratio + 1e-6).floorToDouble();
  return (device < 1 ? 1 : device) / ratio;
}

/// A face at a size on a line of a height: what a run of words needs to be set as the page sets it.
class WordsFace {
  WordsFace(this.style, this.lineHeight, {this.ratio = 1}) : size = style.fontSize ?? 16 {
    final metrics = FaceMetrics.of(style);
    if (ratio == 1) {
      ascent = (metrics.ascent * size).roundToDouble();
      descent = (metrics.descent * size).roundToDouble();
    } else {
      // In the phone's own pixels, and a descent rounded down takes a pixel from the ascent (looks/look.dart
      // `_box`, measured beside a phone's page).
      final exact = metrics.descent * size * ratio;
      var up = (metrics.ascent * size * ratio).roundToDouble(), down = exact.roundToDouble();
      if (down < exact - 1e-4) {
        down += 1;
        up -= 1;
      }
      ascent = up / ratio;
      descent = down / ratio;
    }
  }

  final TextStyle style;
  final double size;
  final double lineHeight;

  /// The device pixels to a CSS one the page is laid out in: the whole pixels below are of those.
  final double ratio;

  /// The font's ascent and descent at this size, each a whole pixel, as Blink rounds them.
  late final double ascent;
  late final double descent;

  /// From the top of a line to the top of its words' box: the half-leading, floored.
  double get lead => ((lineHeight - (ascent + descent)) * ratio / 2 + 1e-6).floorToDouble() / ratio;

  /// Whether `other` sets words the same way.
  bool same(WordsFace other) => other.style == style && other.lineHeight == lineHeight && other.ratio == ratio;
}

bool _space(int unit) => unit == 0x20 || unit == 0x09;

// The scripts written without spaces, where a line may break between any two characters.
bool _wide(int unit) => (unit >= 0x2e80 && unit <= 0x9fff) || (unit >= 0xac00 && unit <= 0xd7af) || (unit >= 0xf900 && unit <= 0xfaff) || (unit >= 0xff00 && unit <= 0xffef);

/// The pieces of `text` a line cannot break inside, its spaces dropped: what a body cell's least width is the
/// widest of. A line may break after a run of spaces and wherever Blink's own table says it may between two ASCII
/// characters (after a hyphen, after a `?`, never at a `/`).
List<String> breakPieces(String text) {
  final pieces = <String>[];
  var start = 0;
  for (var i = 0; i < text.length; i += 1) {
    final unit = text.codeUnitAt(i);
    if (_space(unit)) {
      if (i > start) pieces.add(text.substring(start, i));
      start = i + 1;
      continue;
    }
    if (i + 1 >= text.length) continue;
    final next = text.codeUnitAt(i + 1);
    if (_space(next)) continue;
    final may = blinkBreaks(i > 0 ? text.codeUnitAt(i - 1) : -1, unit, next) ?? (_wide(unit) || _wide(next));
    if (may) {
      pieces.add(text.substring(start, i + 1));
      start = i + 1;
    }
  }
  if (start < text.length) pieces.add(text.substring(start));
  return pieces;
}

/// `text` with the paragraph told where the page breaks a line and it would not, and the other way round.
String fixBreaks(String text) {
  StringBuffer? out;
  var from = 0;
  for (var i = 0; i + 1 < text.length; i += 1) {
    final fix = breakFix(i > 0 ? text.codeUnitAt(i - 1) : -1, text.codeUnitAt(i), text.codeUnitAt(i + 1));
    if (fix == BreakFix.none) continue;
    (out ??= StringBuffer())
      ..write(text.substring(from, i + 1))
      ..write(fix == BreakFix.allow ? zeroWidthSpace : wordJoiner);
    from = i + 1;
  }
  if (out == null) return text;
  out.write(text.substring(from));
  return out.toString();
}

/// The width of `text` on one line in `face`.
double measureWords(String text, WordsFace face) {
  final painter = TextPainter(text: TextSpan(text: text, style: face.style), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling, maxLines: 1)..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Words set as the page sets them: on lines of the face's line height, each baseline where Blink puts it.
class SetWords {
  /// `width` null sets the words on one line however long (`white-space: nowrap`); otherwise they wrap in it and
  /// are aligned in it.
  SetWords(this.text, this.face, {double? width, TextAlign align = TextAlign.left}) {
    final wraps = width != null;
    final shown = wraps ? fixBreaks(text) : text;
    _painter = TextPainter(
      text: TextSpan(text: shown, style: face.style),
      textDirection: TextDirection.ltr,
      textAlign: wraps ? align : TextAlign.left,
      textScaler: TextScaler.noScaling,
      maxLines: wraps ? null : 1,
    )..layout(minWidth: width ?? 0, maxWidth: width ?? double.infinity);
    final metrics = _painter.computeLineMetrics();
    lines = metrics.length;
    var widest = 0.0, start = 0;
    for (final line in metrics) {
      if (line.width > widest) widest = line.width;
      final top = line.lineNumber * face.lineHeight + face.lead;
      // A line's words, the space a wrap left hanging at its end aside: what a `Range` over them answers.
      boxes.add(Rect.fromLTWH(line.left, top, line.width, face.ascent + face.descent));
      // The paragraph's own lines are a whole number of pixels tall; the page's are the face's line height apart,
      // the ascent rounded and the half-leading floored. So where there are several, each line is set again by
      // itself, to be drawn where the page has it: by where the paragraph inks its baseline, which is not where
      // it says its baseline is (`inkBaseline`).
      if (metrics.length == 1) {
        _lines.add((painter: _painter, left: 0, baseline: inkBaseline(line.ascent), to: top + face.ascent));
      } else {
        final range = _painter.getLineBoundary(TextPosition(offset: start));
        final one = TextPainter(text: TextSpan(text: shown.substring(range.start, range.end), style: face.style), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling, maxLines: 1)..layout();
        final own = one.computeLineMetrics();
        _lines.add((painter: one, left: line.left, baseline: own.isEmpty ? face.ascent : inkBaseline(own.first.ascent), to: top + face.ascent));
        start = range.end;
      }
    }
    this.width = widest;
  }

  final String text;
  final WordsFace face;
  late final TextPainter _painter;

  // Each line to draw: its own paragraph, where it starts across, its baseline in that paragraph, and how far down
  // the words' box the page has it.
  final List<({TextPainter painter, double left, double baseline, double to})> _lines = <({TextPainter painter, double left, double baseline, double to})>[];

  /// How many lines the words took.
  late final int lines;

  /// The longest line's words.
  late final double width;

  /// Each line's words' box, from the top left of the first line.
  final List<Rect> boxes = <Rect>[];

  double get height => lines * face.lineHeight;

  /// Draws the words with their first line's top left at `at`. `screen` is how far the canvas's own origin is
  /// from the screen's, which a box inside a scroll view's layer has to be told.
  void paint(Canvas canvas, Offset at, {Offset screen = Offset.zero}) {
    for (final line in _lines) {
      // The page sets a line's baseline on a whole pixel.
      final baseline = (screen.dy + at.dy + line.to).roundToDouble() - screen.dy;
      line.painter.paint(canvas, Offset(at.dx + line.left, baseline - line.baseline));
    }
  }

  void dispose() {
    for (final line in _lines) {
      if (!identical(line.painter, _painter)) line.painter.dispose();
    }
    _painter.dispose();
  }
}

/// The lengths and colours a table is drawn with: the rules of `tableTheme` in tables.ts, resolved.
class TableLook {
  const TableLook({
    required this.head,
    required this.body,
    required this.padX,
    required this.padY,
    required this.rule,
    required this.most,
    required this.ruleColor,
    required this.headGround,
    this.least = 0.6,
    this.devicePixelRatio = 1,
  });

  /// A header cell's face (`font-weight: 700`) and a body cell's.
  final WordsFace head;
  final WordsFace body;

  /// `padding: 0.35em 0.7em`.
  final double padX;
  final double padY;

  /// `border: 1px solid`: its width.
  final double rule;

  /// `max-inline-size: 18em`: the most a cell's box is wide.
  final double most;

  /// `var(--glacier-border-subtle)`.
  final Color ruleColor;

  /// A header cell's ground, `var(--app-paper-2)`; null for none (a card's preview).
  final Color? headGround;

  /// `min-inline-size: 60%`.
  final double least;

  /// Device pixels to the logical one, for the rules to sit on whole ones.
  final double devicePixelRatio;

  bool same(TableLook other) =>
      head.same(other.head) &&
      body.same(other.body) &&
      padX == other.padX &&
      padY == other.padY &&
      rule == other.rule &&
      most == other.most &&
      ruleColor == other.ruleColor &&
      headGround == other.headGround &&
      least == other.least &&
      devicePixelRatio == other.devicePixelRatio;
}

/// A cell's own box in place of its words: how wide it is on one line, and a way to lay it out in a width that
/// answers how tall it then is (`drawCell` of editor/blanks.ts, which filled the cell's element).
class CellHost {
  const CellHost({required this.width, required this.layout});

  /// Its width with nothing wrapped.
  final double width;

  /// Lays the box out no wider than `width`, and answers its size.
  final Size Function(double width) layout;
}

/// One cell, laid out.
class DrawnCell {
  DrawnCell(this.row, this.column, this.text, this.align);

  /// Its own box, where it holds one in place of its words, and that box's size once it is laid out.
  CellHost? host;
  Size hosted = Size.zero;

  final int row;
  final int column;

  /// The words drawn: the cell's markdown without its marks (`plainCell`).
  final String text;
  final TableAlign? align;

  bool get head => row == 0;

  /// Its box in the table: the rules' halves that are its own included, as the page measures a `<td>`.
  Rect rect = Rect.zero;

  /// Its words, set; null for an empty cell, which has no line.
  SetWords? words;

  /// Where the words' first line starts in the table.
  Offset at = Offset.zero;

  /// Each line of its words, in the table.
  List<Rect> get wordBoxes => <Rect>[for (final box in words?.boxes ?? const <Rect>[]) box.shift(at)];
}

TextAlign _textAlign(TableAlign? align) => switch (align) {
  TableAlign.center => TextAlign.center,
  TableAlign.right => TextAlign.right,
  _ => TextAlign.left,
};

/// A table laid out in `room`, the width its wrap has for it. `rows` are the header's cells and then each body
/// row's, every row as wide as the header.
class TableLayout {
  TableLayout(List<List<String>> rows, List<TableAlign?> align, this.look, this.room, {CellHost? Function(int row, int column)? hosts}) {
    final count = rows.isEmpty ? 0 : rows.first.length;
    // What a cell's box is beside its words.
    final extra = 2 * look.padX + look.rule;
    final least = List<double>.filled(count, extra), most = List<double>.filled(count, extra);
    final measured = <String, double>{};
    for (var r = 0; r < rows.length; r += 1) {
      final row = <DrawnCell>[];
      for (var c = 0; c < count; c += 1) {
        final cell = DrawnCell(r, c, c < rows[r].length ? rows[r][c] : '', c < align.length ? align[c] : null);
        row.add(cell);
        final host = cell.host = hosts?.call(r, c);
        if (host != null) {
          // A box of its own: as wide as it is, up to the most a cell may be.
          final wide = math.min(layoutUnitCeil(host.width) + extra, look.most);
          least[c] = math.max(least[c], wide);
          most[c] = math.max(most[c], wide);
          continue;
        }
        if (cell.text.isEmpty) continue;
        final face = cell.head ? look.head : look.body;
        // A cell's words' width is taken down to the sixty-fourth, as the page's columns have it.
        final whole = layoutUnitFloor(measureWords(cell.text, face));
        var narrow = whole;
        if (!cell.head) {
          narrow = 0;
          for (final piece in breakPieces(cell.text)) {
            final width = measured[piece] ??= layoutUnitFloor(measureWords(piece, face));
            if (width > narrow) narrow = width;
          }
        }
        least[c] = math.max(least[c], math.min(narrow + extra, look.most));
        most[c] = math.max(most[c], math.min(whole + extra, look.most));
      }
      cells.add(row);
    }

    // The columns' widths.
    final sumLeast = least.fold<double>(0, (a, b) => a + b), sumMost = most.fold<double>(0, (a, b) => a + b);
    final inside = math.max(math.max(sumLeast, math.min(sumMost, room - look.rule)), layoutUnitFloor(look.least * room) - look.rule);
    final columns = List<double>.filled(count, 0);
    for (var c = 0; c < count; c += 1) {
      if (inside >= sumMost) {
        columns[c] = most[c] + (sumMost > 0 ? (inside - sumMost) * most[c] / sumMost : 0);
      } else {
        final wanted = sumMost - sumLeast;
        columns[c] = least[c] + (wanted > 0 ? (most[c] - least[c]) * (inside - sumLeast) / wanted : 0);
      }
    }
    // The cells' edges across: the first half a rule in, the table's own half.
    columnEdges = <double>[look.rule / 2];
    for (var c = 0; c < count; c += 1) {
      columnEdges.add(layoutUnit(columnEdges.last + columns[c]));
    }

    // The words, wrapped in their columns, and the rows' heights from them.
    rowEdges = <double>[look.rule / 2];
    for (final row in cells) {
      var lines = 0;
      var tall = 0.0;
      for (final cell in row) {
        final host = cell.host;
        if (host != null) {
          cell.hosted = host.layout(math.max(0, columnEdges[cell.column + 1] - columnEdges[cell.column] - extra));
          if (cell.hosted.height > tall) tall = cell.hosted.height;
          continue;
        }
        if (cell.text.isEmpty) continue;
        final width = columnEdges[cell.column + 1] - columnEdges[cell.column] - extra;
        final face = cell.head ? look.head : look.body;
        // A twentieth of a pixel to spare: a column at exactly its words' width must not wrap them for a rounding.
        final words = cell.words = cell.head ? SetWords(cell.text, face) : SetWords(cell.text, face, width: math.max(0, width) + 0.05, align: _textAlign(cell.align));
        if (words.lines > lines) lines = words.lines;
      }
      final height = math.max(lines * look.body.lineHeight, layoutUnitCeil(tall)) + 2 * look.padY + look.rule;
      rowEdges.add(rowEdges.last + height);
    }
    for (final row in cells) {
      for (final cell in row) {
        cell.rect = Rect.fromLTRB(columnEdges[cell.column], rowEdges[cell.row], columnEdges[cell.column + 1], rowEdges[cell.row + 1]);
        final words = cell.words;
        if (cell.host != null) {
          // Its own box, at the start of the cell or where the column's alignment puts it.
          final free = cell.rect.width - extra - cell.hosted.width;
          final shift = free <= 0 ? 0.0 : (cell.align == TableAlign.center ? free / 2 : (cell.align == TableAlign.right ? free : 0.0));
          cell.at = Offset(cell.rect.left + look.rule / 2 + look.padX + shift, cell.rect.top + look.rule / 2 + look.padY);
          continue;
        }
        if (words == null) continue;
        var across = cell.rect.left + look.rule / 2 + look.padX;
        if (cell.head) {
          // On one line, however long: placed by hand, and from the start when it runs over.
          final free = cell.rect.width - extra - words.width;
          if (free > 0 && cell.align == TableAlign.center) across += free / 2;
          if (free > 0 && cell.align == TableAlign.right) across += free;
        }
        cell.at = Offset(across, cell.rect.top + look.rule / 2 + look.padY);
      }
    }
    size = Size(columnEdges.last + look.rule / 2, rowEdges.last + look.rule / 2);
  }

  final TableLook look;
  final double room;

  /// The cells, by row and column; row 0 is the header.
  final List<List<DrawnCell>> cells = <List<DrawnCell>>[];

  /// Where the cells meet, across and down, from the table's corner: one more than there are columns, and rows.
  late final List<double> columnEdges;
  late final List<double> rowEdges;

  /// The table's own box.
  late final Size size;

  /// Draws the table with its corner at `offset`; `screen` as [SetWords.paint] takes it.
  void paint(Canvas canvas, Offset offset, {Offset screen = Offset.zero}) {
    final ground = look.headGround;
    if (ground != null && cells.isNotEmpty) {
      canvas.drawRect(Rect.fromLTRB(offset.dx + columnEdges.first, offset.dy + rowEdges[0], offset.dx + columnEdges.last, offset.dy + rowEdges[1]), Paint()..color = ground);
    }
    for (final row in cells) {
      for (final cell in row) {
        cell.words?.paint(canvas, offset + cell.at, screen: screen);
      }
    }
    // The rules, each on whole device pixels as the page's are.
    final ratio = look.devicePixelRatio;
    double snapX(double value) => ((screen.dx + value) * ratio).roundToDouble() / ratio - screen.dx;
    double snapY(double value) => ((screen.dy + value) * ratio).roundToDouble() / ratio - screen.dy;
    final rule = Paint()
      ..color = look.ruleColor
      ..isAntiAlias = false;
    final left = snapX(offset.dx), top = snapY(offset.dy);
    final right = snapX(offset.dx + size.width), bottom = snapY(offset.dy + size.height);
    for (final edge in columnEdges) {
      final x = snapX(offset.dx + edge - look.rule / 2);
      canvas.drawRect(Rect.fromLTRB(x, top, x + look.rule, bottom), rule);
    }
    for (final edge in rowEdges) {
      final y = snapY(offset.dy + edge - look.rule / 2);
      canvas.drawRect(Rect.fromLTRB(left, y, right, y + look.rule), rule);
    }
  }

  void dispose() {
    for (final row in cells) {
      for (final cell in row) {
        cell.words?.dispose();
      }
    }
  }
}
