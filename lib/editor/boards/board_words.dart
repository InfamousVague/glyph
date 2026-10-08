/// Words on a board, set as the page sets them: on lines of the face's own height, each baseline where Blink puts
/// it, cut to a number of lines with an ellipsis where the stylesheet says so (`-webkit-line-clamp: 3` on a card's
/// words, `text-overflow: ellipsis` on a lane's name).
///
/// The setting of one line is the tables' ([SetWords], tables/table_layout.dart); this breaks the words into lines
/// and cuts them. Blink's clamp ends the last line it shows where that line would have ended anyway and puts the
/// ellipsis after it, taking letters off only if the ellipsis does not fit; Flutter's own `maxLines` with an
/// ellipsis fills the line with as many letters of the next word as fit, so the lines are cut here instead.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../looks/look.dart' show layoutUnitCeil;
import '../tables/table_layout.dart';

final RegExp _trailing = RegExp(r'\s+$');

/// Words broken into lines of `width` and cut to `maxLines`.
class LaidWords {
  LaidWords(this.text, this.face, {required double width, this.maxLines, bool wrap = true, TextAlign align = TextAlign.left}) {
    final shown = <String>[];
    if (!wrap) {
      shown.add(_cut(text, width, cut: measureWords(text, face) > width));
    } else {
      final fixed = fixBreaks(text);
      final painter = TextPainter(text: TextSpan(text: fixed, style: face.style), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)..layout(maxWidth: width);
      final count = painter.computeLineMetrics().length;
      var start = 0;
      for (var index = 0; index < count && start < fixed.length; index += 1) {
        final range = painter.getLineBoundary(TextPosition(offset: start));
        final line = fixed.substring(range.start, range.end).replaceFirst(_trailing, '');
        start = range.end > start ? range.end : fixed.length;
        final last = maxLines != null && index == maxLines! - 1;
        if (last && index < count - 1) {
          shown.add(_cut(line, width, cut: true));
          break;
        }
        shown.add(line);
      }
      painter.dispose();
      if (shown.isEmpty) shown.add('');
    }
    var widest = 0.0;
    for (final (index, line) in shown.indexed) {
      final set = SetWords(line, face);
      final left = switch (align) {
        TextAlign.center => (width.isFinite ? (width - set.width) / 2 : 0.0),
        TextAlign.right || TextAlign.end => (width.isFinite ? width - set.width : 0.0),
        _ => 0.0,
      };
      _lines.add((words: set, left: left));
      if (set.width > widest) widest = set.width;
      boxes.add(Rect.fromLTWH(left, index * face.lineHeight + face.lead, set.width, face.ascent + face.descent));
    }
    this.width = widest;
  }

  /// `line` with an ellipsis after it, letters taken off until it fits `width`; as it is when `cut` is false.
  String _cut(String line, double width, {required bool cut}) {
    if (!cut) return line;
    var kept = line.replaceFirst(_trailing, '');
    while (kept.isNotEmpty && measureWords('$kept…', face) > width) {
      kept = kept.substring(0, kept.length - 1).replaceFirst(_trailing, '');
    }
    return '$kept…';
  }

  final String text;
  final WordsFace face;
  final int? maxLines;
  final List<({SetWords words, double left})> _lines = <({SetWords words, double left})>[];

  /// Each line's words' box, from the top left of the first line: what a `Range` over them answers on the page.
  final List<Rect> boxes = <Rect>[];

  /// The longest line's words.
  late final double width;

  int get lines => _lines.length;
  double get height => lines * face.lineHeight;

  /// What each line says, the ellipsis included.
  List<String> get said => <String>[for (final line in _lines) line.words.text];

  void paint(Canvas canvas, Offset at, {Offset screen = Offset.zero}) {
    for (final (index, line) in _lines.indexed) {
      line.words.paint(canvas, at + Offset(line.left, index * face.lineHeight), screen: screen);
    }
  }

  void dispose() {
    for (final line in _lines) {
      line.words.dispose();
    }
  }
}

/// Words in a box of their own: as wide as it is given (or, with [shrink], as its longest line) and as tall as its
/// lines.
class BoardWords extends LeafRenderObjectWidget {
  const BoardWords(this.text, {super.key, required this.face, this.maxLines, this.wrap = true, this.shrink = false, this.align = TextAlign.left});

  final String text;
  final WordsFace face;
  final int? maxLines;

  /// False keeps the words on one line, cut with an ellipsis where they do not fit.
  final bool wrap;

  /// The box is as wide as the words rather than as the room.
  final bool shrink;
  final TextAlign align;

  @override
  RenderBoardWords createRenderObject(BuildContext context) => RenderBoardWords(text, face, maxLines, wrap, shrink, align);

  @override
  void updateRenderObject(BuildContext context, RenderBoardWords renderObject) => renderObject.update(text, face, maxLines, wrap, shrink, align);
}

class RenderBoardWords extends RenderBox {
  RenderBoardWords(this._text, this._face, this._maxLines, this._wrap, this._shrink, this._align);

  String _text;
  WordsFace _face;
  int? _maxLines;
  bool _wrap;
  bool _shrink;
  TextAlign _align;
  LaidWords? _laid;
  double _laidWidth = -1;

  void update(String text, WordsFace face, int? maxLines, bool wrap, bool shrink, TextAlign align) {
    if (text == _text && face.same(_face) && maxLines == _maxLines && wrap == _wrap && shrink == _shrink && align == _align) return;
    _text = text;
    _face = face;
    _maxLines = maxLines;
    _wrap = wrap;
    _shrink = shrink;
    _align = align;
    _drop();
    markNeedsLayout();
  }

  void _drop() {
    _laid?.dispose();
    _laid = null;
  }

  LaidWords _lay(double width) {
    final laid = _laid;
    if (laid != null && width == _laidWidth) return laid;
    _drop();
    _laidWidth = width;
    return _laid = LaidWords(_text, _face, width: width, maxLines: _maxLines, wrap: _wrap, align: _shrink ? TextAlign.left : _align);
  }

  /// The words as they were last laid out.
  LaidWords get laid => _laid!;

  /// Each line's words' box on the screen.
  List<Rect> get wordBoxes {
    final at = localToGlobal(Offset.zero);
    return <Rect>[for (final box in laid.boxes) box.shift(at)];
  }

  @override
  double computeMinIntrinsicWidth(double height) => _shrink || !_wrap ? layoutUnitCeil(measureWords(_text, _face)) : 0;

  @override
  double computeMaxIntrinsicWidth(double height) => layoutUnitCeil(measureWords(_text, _face));

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    if (!_wrap || !width.isFinite) return _face.lineHeight;
    final laid = LaidWords(_text, _face, width: width, maxLines: _maxLines, wrap: _wrap);
    final height = laid.height;
    laid.dispose();
    return height;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final laid = LaidWords(_text, _face, width: constraints.maxWidth, maxLines: _maxLines, wrap: _wrap);
    final size = constraints.constrain(Size(_shrink || !constraints.hasBoundedWidth ? layoutUnitCeil(laid.width) : constraints.maxWidth, laid.height));
    laid.dispose();
    return size;
  }

  @override
  void performLayout() {
    final laid = _lay(constraints.maxWidth);
    size = constraints.constrain(Size(_shrink || !constraints.hasBoundedWidth ? layoutUnitCeil(laid.width) : constraints.maxWidth, laid.height));
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) => _laid?.paint(context.canvas, offset, screen: localToGlobal(Offset.zero) - offset);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..textDirection = TextDirection.ltr
      ..label = _text;
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }
}
