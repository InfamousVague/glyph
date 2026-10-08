/// Where a canvas's cards are, in the canvas's own pixels: the box round them all, the middle of a card's side
/// where a line attaches, and which sides two cards face each other by. A port of `src/app/canvas/geometry.ts`;
/// pure, and shared by the lines (lines.dart), the view maths (viewport.dart) and the minimap (minimap.dart), so
/// all three agree on where a card's edge is.
///
/// What differs: a `Box` is an interface a node answers and [BoxOf] a box on its own, where the web has one
/// structural type; a `Point` is a record.
library;

import 'dart:math' as math;

import 'json_canvas.dart';

abstract interface class Box {
  double get x;
  double get y;
  double get width;
  double get height;
}

/// A box that is nothing else.
class BoxOf implements Box {
  const BoxOf(this.x, this.y, this.width, this.height);
  @override
  final double x;
  @override
  final double y;
  @override
  final double width;
  @override
  final double height;

  @override
  bool operator ==(Object other) => other is BoxOf && other.x == x && other.y == y && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'BoxOf($x, $y, $width, $height)';
}

typedef Point = ({double x, double y});

/// The smallest box around every node, or null for an empty canvas.
BoxOf? bounds(Canvas canvas) {
  if (canvas.nodes.isEmpty) return null;
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final node in canvas.nodes) {
    left = math.min(left, node.x);
    top = math.min(top, node.y);
    right = math.max(right, node.x + node.width);
    bottom = math.max(bottom, node.y + node.height);
  }
  return BoxOf(left, top, right - left, bottom - top);
}

/// The middle of a box.
Point centre(Box box) => (x: box.x + box.width / 2, y: box.y + box.height / 2);

/// The middle of a node's side: where an edge attaches.
Point anchorOf(Box node, Side side) => switch (side) {
  Side.top => (x: node.x + node.width / 2, y: node.y),
  Side.right => (x: node.x + node.width, y: node.y + node.height / 2),
  Side.bottom => (x: node.x + node.width / 2, y: node.y + node.height),
  Side.left => (x: node.x, y: node.y + node.height / 2),
};

/// Which way a side faces, as a unit step.
Point normalOf(Side side) => switch (side) {
  Side.top => (x: 0, y: -1),
  Side.right => (x: 1, y: 0),
  Side.bottom => (x: 0, y: 1),
  Side.left => (x: -1, y: 0),
};

/// The sides an edge leaves and arrives by when it does not say: the side of each node that faces the other, by
/// whichever of across or down the two are further apart in, across when they are as far apart each way. Obsidian
/// writes the sides it chose; another writer may not, and the spec allows it.
({Side from, Side to}) sidesOf(Box from, Box to, {Side? fromSide, Side? toSide}) {
  final a = centre(from);
  final b = centre(to);
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final across = dx.abs() >= dy.abs();
  final out = across ? (dx >= 0 ? Side.right : Side.left) : (dy >= 0 ? Side.bottom : Side.top);
  final back = across ? (dx >= 0 ? Side.left : Side.right) : (dy >= 0 ? Side.top : Side.bottom);
  return (from: fromSide ?? out, to: toSide ?? back);
}
