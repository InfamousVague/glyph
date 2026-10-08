/// A canvas's lines as they are drawn: each a curve out of one card's side and into another's, with its arrow heads
/// and its label. A port of `src/app/canvas/lines.ts`. Drawn together rather than one by one, because where one
/// line's end sits depends on the others' (docs/DESIGN.md §62): ends that share a side are set along it so they
/// leave without crossing, heads on neighbouring cards that would meet are moved apart, and a label sits over open
/// canvas rather than over a card, broken onto two or three lines where one will not fit down the gap. Pure, in
/// the canvas's own pixels; the screen only draws what this answers.
///
/// What differs: nothing in what it answers. The paths are the web's SVG path strings, character for character
/// (tool/canvas_fixtures.mjs holds them), which is why the sums here are written in the web's order and through
/// js.dart; the painter reads the strings back (path.dart).
library;

import 'dart:math' as math;

import 'geometry.dart';
import 'js.dart';
import 'json_canvas.dart';

/// The size of an arrow head, in the canvas's pixels; the line stops short of the tip by this much (`HEAD`).
const double head = 10;

/// One line as it is drawn, by [edgePaths].
class EdgePath {
  const EdgePath({required this.d, required this.fromHead, required this.toHead, required this.mid, required this.lines});

  /// The curve, as an SVG path: from one anchor to the other, stopping short of any arrow head.
  final String d;

  /// The head at each end, as an SVG path of a filled triangle, where that end is an arrow.
  final String? fromHead;
  final String? toHead;

  /// Where its label sits: along the curve, over open canvas rather than over a card.
  final Point mid;

  /// The label's words as lines, broken where one line would not fit between the cards; none without a label.
  final List<String> lines;
}

String _n(double value) => jsNumber(value);

String _head(Point tip, Side side) {
  final n = normalOf(side);
  // The base of the head sits back along the side's normal; the wings sit across it.
  final base = (x: tip.x + n.x * head, y: tip.y + n.y * head);
  const wing = head * 0.55;
  final a = (x: base.x - n.y * wing, y: base.y + n.x * wing);
  final b = (x: base.x + n.y * wing, y: base.y - n.x * wing);
  return 'M${_n(tip.x)} ${_n(tip.y)}L${_n(a.x)} ${_n(a.y)}L${_n(b.x)} ${_n(b.y)}Z';
}

/// How far apart two line ends on the same side of a card are set (`END_SPREAD`).
const double endSpread = 28;

/// How close two arrow heads on different cards may come before they are moved apart along their sides
/// (`HEAD_CLEAR`). Two lines into the facing sides of neighbouring cards landed at the same height, their heads base
/// to base in the gap, and read as one shape (Matt: "they look joined like a diamond").
const double headClear = 56;

/// A line end keeps this far from a side's corners.
const double _endMargin = 16;

/// A unit step along a side: the way an end moves when it is set apart from another.
Point _alongOf(Side side) => side == Side.top || side == Side.bottom ? (x: 1, y: 0) : (x: 0, y: 1);

/// One end of one line: which card and side it is on, how far along the side it has been set, and where it goes.
class _LineEnd {
  _LineEnd({required this.edge, required this.node, required this.side, required this.arrow, required this.other});
  final CanvasEdge edge;
  final CanvasNode node;
  final Side side;

  /// Whether a head is drawn at this end.
  final bool arrow;

  /// How far along the side from its middle this end sits, in the canvas's pixels.
  double offset = 0;

  /// The centre of the card at the line's other end, for ordering ends along a side so lines do not cross.
  final Point other;
}

double _sideLength(Box node, Side side) => side == Side.top || side == Side.bottom ? node.width : node.height;

/// A point's coordinate along a side's axis.
double _along(Point p, Side side) => side == Side.top || side == Side.bottom ? p.x : p.y;

/// A point's coordinate across a side's axis.
double _across(Point p, Side side) => side == Side.top || side == Side.bottom ? p.y : p.x;

double _keptOnSide(_LineEnd end, double offset) {
  final half = math.max(0.0, _sideLength(end.node, end.side) / 2 - _endMargin);
  return math.max(-half, math.min(half, offset));
}

/// Where an end is now: the side's middle, moved along it by the end's offset.
Point _pointOf(_LineEnd end) {
  final a = anchorOf(end.node, end.side);
  final step = _alongOf(end.side);
  return (x: a.x + step.x * end.offset, y: a.y + step.y * end.offset);
}

/// Ends that share one side of one card are set along it, evenly about the middle, in the order their far ends
/// come along that axis so the lines leave without crossing. A side too short for the spread packs them closer.
void _spreadShared(List<_LineEnd> ends) {
  final shared = <String, List<_LineEnd>>{};
  for (final end in ends) {
    (shared['${end.node.id}/${end.side.name}'] ??= []).add(end);
  }
  for (final group in shared.values) {
    if (group.length < 2) continue;
    stableSort(group, (a, b) => _along(a.other, a.side) - _along(b.other, b.side));
    final first = group[0];
    final room = math.max(0.0, _sideLength(first.node, first.side) - 2 * _endMargin);
    final step = math.min(endSpread, room / (group.length - 1));
    for (var i = 0; i < group.length; i += 1) {
      group[i].offset = _keptOnSide(group[i], (i - (group.length - 1) / 2) * step);
    }
  }
}

/// Two heads on different cards nearer each other than [headClear] are moved apart, each along its own side,
/// until they are that far apart or a side runs out. Which goes which way: away from the other along the side's
/// axis; when they are level, the one whose line comes from further along that axis goes that way. Two passes
/// settle what one move undoes.
void _partHeads(List<_LineEnd> ends) {
  final heads = [
    for (final end in ends)
      if (end.arrow) end,
  ];
  for (var pass = 0; pass < 2; pass += 1) {
    for (var i = 0; i < heads.length; i += 1) {
      for (var j = i + 1; j < heads.length; j += 1) {
        final a = heads[i];
        final b = heads[j];
        if (a.node.id == b.node.id || a.edge.id == b.edge.id) continue;
        final pa = _pointOf(a);
        final pb = _pointOf(b);
        if (jsHypot(pa.x - pb.x, pa.y - pb.y) >= headClear) continue;
        for (final (self, other, selfAt, otherAt) in [(a, b, pa, pb), (b, a, pb, pa)]) {
          // Along this end's own side: how far apart they are already, and how far they need to be, given how far
          // apart they are across it, which moving along the side cannot change.
          final gapAcross = (_across(selfAt, self.side) - _across(otherAt, self.side)).abs();
          final have = _along(selfAt, self.side) - _along(otherAt, self.side);
          final need = math.sqrt(math.max(0.0, headClear * headClear - gapAcross * gapAcross));
          final short = need - have.abs();
          if (short <= 0) continue;
          var way = jsSign(have);
          if (way == 0) {
            way = jsSign(_along(self.other, self.side) - _along(other.other, self.side));
            if (way == 0) way = identical(self, a) ? -1 : 1;
          }
          self.offset = _keptOnSide(self, self.offset + (way * short) / 2);
        }
      }
    }
  }
}

/// Where along the curve a label is tried, the middle first and then either way from it.
const _labelTries = [0.5, 0.45, 0.55, 0.4, 0.6, 0.35, 0.65, 0.3, 0.7, 0.25, 0.75, 0.2, 0.8, 0.15, 0.85];

/// About what a label's letters take at the label's size (13px), and a line's height (`LABEL_LINE`).
const double _labelLetter = 6.8;
const double labelLine = 15;

/// How many lines a label may be broken into to fit between cards.
const int _labelLinesMost = 3;

bool _overlaps(Box a, Box b) => a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

final RegExp _space = RegExp(r'\s+');

/// The words broken into [count] lines of about equal length, never inside a word; fewer where there are not the
/// words. Each line is aimed at an equal share of what is still to be placed, and takes the next word when that
/// lands nearer the aim than stopping short does.
List<String> brokenInto(String words, int count) {
  final parts = words.split(_space).where((part) => part.isNotEmpty).toList();
  final lines = <String>[];
  var line = '';
  for (var i = 0; i < parts.length; i += 1) {
    final part = parts[i];
    if (line.isEmpty) {
      line = part;
      continue;
    }
    final linesLeft = count - lines.length;
    if (linesLeft <= 1) {
      line = '$line $part';
      continue;
    }
    final rest = parts.sublist(i).join(' ').length;
    final aim = (line.length + 1 + rest) / linesLeft;
    final taken = line.length + 1 + part.length;
    if ((taken - aim).abs() <= (line.length - aim).abs()) {
      line = '$line $part';
    } else {
      lines.add(line);
      line = part;
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines;
}

/// Where a label sits, and on how many lines: the first point along the curve, trying the middle and then either
/// way from it, where the label's box is over open canvas and not over a card (Matt: "the text that's on arrow
/// paths sometimes overlaps content and we can't read the boxes below"); on one line first, and where one line fits
/// nowhere, on two, then three. Groups are open canvas. Where nothing fits anywhere, one line at the middle.
({Point at, List<String> lines}) _labelPlace(Point p0, Point c1, Point c2, Point p3, String? label, List<Box> cards) {
  Point at(double t) {
    final u = 1 - t;
    return (
      x: u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x,
      y: u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y,
    );
  }

  final has = label != null && label.isNotEmpty;
  final whole = has ? [label] : <String>[];
  for (var count = 1; count <= _labelLinesMost; count += 1) {
    final lines = has ? brokenInto(label, count) : <String>[];
    if (count > 1 && lines.length < count) break;
    var longest = 6;
    for (final line in lines) {
      longest = math.max(longest, line.length);
    }
    final width = math.max(40.0, longest * _labelLetter + 8);
    final height = math.max(1, lines.length) * labelLine + 5;
    for (final t in _labelTries) {
      final p = at(t);
      final box = BoxOf(p.x - width / 2, p.y - height / 2, width, height);
      if (!cards.any((card) => _overlaps(box, card))) return (at: p, lines: has ? lines : <String>[]);
    }
  }
  return (at: at(0.5), lines: whole);
}

/// The curve between two ends as they have been set, its heads, and its label's place.
EdgePath _pathBetween(_LineEnd from, _LineEnd to, CanvasEdge edge, List<Box> cards) {
  final a = _pointOf(from);
  final b = _pointOf(to);
  final na = normalOf(from.side);
  final nb = normalOf(to.side);
  // The curve ends at the base of a head, not its tip, so the line never pokes through the point.
  final start = from.arrow ? (x: a.x + na.x * head, y: a.y + na.y * head) : a;
  final end = to.arrow ? (x: b.x + nb.x * head, y: b.y + nb.y * head) : b;
  final reach = math.max(30.0, math.min(jsHypot(end.x - start.x, end.y - start.y) * 0.4, 200.0));
  final c1 = (x: start.x + na.x * reach, y: start.y + na.y * reach);
  final c2 = (x: end.x + nb.x * reach, y: end.y + nb.y * reach);
  final label = _labelPlace(start, c1, c2, end, edge.label, cards);
  return EdgePath(
    d: 'M${_n(start.x)} ${_n(start.y)}C${_n(c1.x)} ${_n(c1.y)} ${_n(c2.x)} ${_n(c2.y)} ${_n(end.x)} ${_n(end.y)}',
    fromHead: from.arrow ? _head(a, from.side) : null,
    toHead: to.arrow ? _head(b, to.side) : null,
    mid: label.at,
    lines: label.lines,
  );
}

/// The lines of a canvas, by edge id, in the edges' order: each a curve out of one side and into the other, bowing
/// further the further apart the nodes are, the way Obsidian draws one; the heads the edge asks for (an arrow at
/// the end unless it says otherwise); and where its label sits. An edge whose node is missing is left out.
Map<String, EdgePath> edgePaths(Canvas canvas) {
  final byId = {for (final node in canvas.nodes) node.id: node};
  final ends = <_LineEnd>[];
  final lines = <({CanvasEdge edge, _LineEnd from, _LineEnd to})>[];
  for (final edge in canvas.edges) {
    final from = byId[edge.fromNode];
    final to = byId[edge.toNode];
    if (from == null || to == null) continue;
    final sides = sidesOf(from, to, fromSide: edge.fromSide, toSide: edge.toSide);
    final start = _LineEnd(edge: edge, node: from, side: sides.from, arrow: (edge.fromEnd ?? End.none) == End.arrow, other: centre(to));
    final finish = _LineEnd(edge: edge, node: to, side: sides.to, arrow: (edge.toEnd ?? End.arrow) == End.arrow, other: centre(from));
    ends
      ..add(start)
      ..add(finish);
    lines.add((edge: edge, from: start, to: finish));
  }
  _spreadShared(ends);
  _partHeads(ends);
  final cards = <Box>[
    for (final node in canvas.nodes)
      if (!node.isGroup) node,
  ];
  return {for (final line in lines) line.edge.id: _pathBetween(line.from, line.to, line.edge, cards)};
}
