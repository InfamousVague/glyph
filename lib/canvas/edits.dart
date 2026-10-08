/// Making and changing a canvas: the cards and lines the view adds, and the edits it makes to them - moved, resized,
/// named, written in, taken off. A port of `src/app/canvas/edits.ts`. Every edit is a new [Canvas], the old one
/// left as it was, so the view can hold the canvas as it was when a finger took hold and measure a drag from there
/// (canvas_view.dart), and hand the note the whole canvas to write back (json_canvas.dart `withCanvas`).
///
/// The node list is the z-order: a new card goes last, so it is drawn on top, and an edit keeps every other node
/// where it was in the list, since sorting them would change both the drawing and the file Obsidian reads.
///
/// What differs: nothing in what they answer, and that is held to the file's last byte (tool/canvas_fixtures.mjs).
/// One thing is kept that reads like a slip in the web's: [withNode], [withEdge], [withoutEdge], [movedWithHeld]
/// and [withGroup] answer a canvas of nodes and edges alone, so a canvas's threads (`comments`) are not carried
/// through them. They are ported as they are; the view puts the threads back (canvas_view.dart `_change`).
library;

import 'dart:math' as math;

import '../core/bytes.dart';
import 'js.dart';
import 'json_canvas.dart';

final math.Random _random = math.Random.secure();

/// An id for a new node or edge: sixteen hex characters, the shape Obsidian gives its own.
String newCanvasId() => toHex([for (var n = 0; n < 8; n += 1) _random.nextInt(256)]);

/// The canvas's grid: the dots under the cards are this far apart, in the canvas's pixels, with one at the canvas's
/// own corner, and with snapping on, a card's corner and its sides land on them (`GRID`).
const double grid = 24;

/// The nearest line of the grid to a place, across or down.
double onGrid(double place) => jsRound(place / grid) * grid;

/// A point at the nearest dot.
({double x, double y}) atDot(double x, double y) => (x: onGrid(x), y: onGrid(y));

/// The size a new card of words starts at, in the canvas's pixels: Obsidian's (`NEW_CARD`).
const ({double width, double height}) newCard = (width: 260, height: 120);

/// A new card of words, empty, with its top-left corner at (x, y). It goes last, so it is drawn on top.
CanvasNode newTextNode(double x, double y, [String? id]) =>
    CanvasNode({'id': id ?? newCanvasId(), 'type': 'text', 'x': jsRound(x), 'y': jsRound(y), 'width': newCard.width, 'height': newCard.height, 'text': ''});

final RegExp _slashes = RegExp(r'[\\/]');

/// A new card that is a note, by its title: the spec's file node, named as Obsidian names a note's file.
CanvasNode newFileNode(String title, double x, double y, [String? id]) {
  final cleaned = title.trim().replaceAll(_slashes, '-');
  final name = cleaned.isEmpty ? 'Untitled' : cleaned;
  return CanvasNode({'id': id ?? newCanvasId(), 'type': 'file', 'x': jsRound(x), 'y': jsRound(y), 'width': newCard.width, 'height': 160.0, 'file': '$name.md'});
}

/// A new card that is one of Ghost.md's own pictures, by the name the picture store keeps it under.
CanvasNode newPictureNode(String name, double x, double y, [String? id]) =>
    CanvasNode({'id': id ?? newCanvasId(), 'type': 'file', 'x': jsRound(x), 'y': jsRound(y), 'width': newCard.width, 'height': 200.0, 'file': name});

/// What a new chart card starts with: a small Mermaid diagram to change (`CHART_CARD`).
const String chartCard = '```mermaid\nflowchart LR\n  A[Start] --> B[Then]\n  B --> C[Done]\n```\n';

/// What a new table card starts with (`TABLE_CARD`).
const String tableCard = '| Thing | Note |\n| --- | --- |\n| One | |\n| Two | |\n';

final RegExp _scheme = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false);

/// A new card that is a web address; a bare address is given https. Null for no address at all.
CanvasNode? newLinkNode(String url, double x, double y, [String? id]) {
  final given = url.trim();
  if (given.isEmpty) return null;
  final address = _scheme.hasMatch(given) ? given : 'https://$given';
  return CanvasNode({'id': id ?? newCanvasId(), 'type': 'link', 'x': jsRound(x), 'y': jsRound(y), 'width': newCard.width, 'height': 100.0, 'url': address});
}

/// The canvas with this node in place of the one with its id, or added at the end where there was none.
Canvas withNode(Canvas canvas, CanvasNode node) {
  final there = canvas.nodes.any((n) => n.id == node.id);
  return Canvas(nodes: there ? [for (final n in canvas.nodes) n.id == node.id ? node : n] : [...canvas.nodes, node], edges: canvas.edges);
}

/// The canvas without this node, and without any edge that joined it. Its threads go with it (docs/SHARED.md,
/// S9): a comment on a card that is gone has nothing to be on.
Canvas withoutNode(Canvas canvas, String id) {
  final comments = canvas.comments?.where((thread) => thread.node != id).toList();
  return Canvas(
    nodes: [
      for (final n in canvas.nodes)
        if (n.id != id) n,
    ],
    edges: [
      for (final e in canvas.edges)
        if (e.fromNode != id && e.toNode != id) e,
    ],
    comments: comments != null && comments.isNotEmpty ? comments : null,
  );
}

/// A new line from one card to another: an arrow at its end, its sides chosen from where the cards are.
CanvasEdge newEdge(String fromNode, String toNode, [String? id]) => CanvasEdge({'id': id ?? newCanvasId(), 'fromNode': fromNode, 'toNode': toNode});

/// The canvas with this line in place of the one with its id, or added at the end where there was none.
Canvas withEdge(Canvas canvas, CanvasEdge edge) {
  final there = canvas.edges.any((e) => e.id == edge.id);
  return Canvas(nodes: canvas.nodes, edges: there ? [for (final e in canvas.edges) e.id == edge.id ? edge : e] : [...canvas.edges, edge]);
}

/// The canvas without this line; the cards it joined stay.
Canvas withoutEdge(Canvas canvas, String id) => Canvas(
  nodes: canvas.nodes,
  edges: [
    for (final e in canvas.edges)
      if (e.id != id) e,
  ],
);

/// The line with these words on it, or with none: the spec has no empty label, so blank takes the label off.
CanvasEdge labelledEdge(CanvasEdge edge, String label) {
  final words = label.trim();
  final rest = edge.without('label');
  return words.isEmpty ? rest : rest.put({'label': words});
}

/// Whether a line already joins these two cards, either way round: a second one would only lie on the first.
bool joined(Canvas canvas, String a, String b) => canvas.edges.any((e) => (e.fromNode == a && e.toNode == b) || (e.fromNode == b && e.toNode == a));

/// The smallest a card can be made, in the canvas's pixels: room for a word and the cross (`LEAST_CARD`).
const ({double width, double height}) leastCard = (width: 120, height: 60);

/// The node made this size, to the pixel and no smaller than [leastCard]; its top-left corner stays put.
CanvasNode resizedNode(CanvasNode node, double width, double height) =>
    node.put({'width': math.max(leastCard.width, jsRound(width)), 'height': math.max(leastCard.height, jsRound(height))});

/// The nodes a group holds: every other node whose box is wholly inside the group's, as Obsidian counts them.
List<CanvasNode> heldBy(Canvas canvas, CanvasNode group) => [
  for (final n in canvas.nodes)
    if (n.id != group.id && n.x >= group.x && n.y >= group.y && n.x + n.width <= group.x + group.width && n.y + n.height <= group.y + group.height) n,
];

/// The canvas with this node moved to (x, y) - and, for a group, everything it holds moved with it by the same
/// amount (choice 5: "cards inside move with it"). A card moved on its own leaves its group where it is.
Canvas movedWithHeld(Canvas canvas, CanvasNode node, double x, double y) {
  final dx = jsRound(x) - node.x;
  final dy = jsRound(y) - node.y;
  final moving = {node.id, if (node.isGroup) ...heldBy(canvas, node).map((n) => n.id)};
  return Canvas(nodes: [for (final n in canvas.nodes) moving.contains(n.id) ? movedNode(n, n.x + dx, n.y + dy) : n], edges: canvas.edges);
}

/// The group with these words as its name, or with none.
CanvasNode labelledGroup(CanvasNode node, String label) {
  if (!node.isGroup) return node;
  final words = label.trim();
  final rest = node.without('label');
  return words.isEmpty ? rest : rest.put({'label': words});
}

/// The node moved so its top-left corner is at (x, y), to the pixel, as the spec keeps positions.
CanvasNode movedNode(CanvasNode node, double x, double y) => node.put({'x': jsRound(x), 'y': jsRound(y)});

/// Which handle of a card is held (selection.dart): a corner, which moves two sides, or the middle of a side,
/// which moves one. Named by the compass, as a cursor is; in the web's order (`HANDLES`).
enum Handle {
  nw,
  n,
  ne,
  e,
  se,
  s,
  sw,
  w;

  bool get east => name.contains('e');
  bool get south => name.contains('s');
  bool get west => name.contains('w');
  bool get north => name.contains('n');
}

/// The node with the sides this handle holds moved by (dx, dy), in the canvas's pixels: the opposite sides stay
/// where they are, so a card dragged by its top-left corner grows up and to the left. No smaller than [leastCard]:
/// a side dragged past that stops there, and the card does not start to slide the other way. A group resized this
/// way keeps its cards where they are; only its box changes.
///
/// With [snap], the sides that move land on the grid's lines: the side itself, not the size, so a card that was
/// off the grid is brought onto it side by side as it is resized, and the sides not held stay where they were.
CanvasNode resizedBy(CanvasNode node, Handle handle, double dx, double dy, [bool snap = false]) {
  var x = node.x;
  var y = node.y;
  var width = node.width;
  var height = node.height;
  double to(double place) => snap ? onGrid(place) : place;
  if (handle.east) width = math.max(leastCard.width, to(node.x + node.width + dx) - node.x);
  if (handle.south) height = math.max(leastCard.height, to(node.y + node.height + dy) - node.y);
  if (handle.west) {
    width = math.max(leastCard.width, node.x + node.width - to(node.x + dx));
    x = node.x + node.width - width;
  }
  if (handle.north) {
    height = math.max(leastCard.height, node.y + node.height - to(node.y + dy));
    y = node.y + node.height - height;
  }
  return node.put({'x': jsRound(x), 'y': jsRound(y), 'width': jsRound(width), 'height': jsRound(height)});
}

/// How far a copy, or a new card that would land exactly on another, is set down and to the right (`STEP_ASIDE`).
const double stepAside = 24;

/// Where a new box goes so that it does not land exactly on a card already there: stepped down and to the right
/// until its corner is clear of every other corner.
({double x, double y}) clearSpot(Canvas canvas, double x, double y) {
  var at = (x: jsRound(x), y: jsRound(y));
  bool taken(({double x, double y}) p) => canvas.nodes.any((n) => !n.isGroup && (n.x - p.x).abs() < stepAside / 2 && (n.y - p.y).abs() < stepAside / 2);
  for (var tries = 0; tries < 40 && taken(at); tries += 1) {
    at = (x: at.x + stepAside, y: at.y + stepAside);
  }
  return at;
}

/// A copy of a card, a step down and to the right of it, under an id of its own. A group is copied as its box alone.
CanvasNode duplicated(Canvas canvas, CanvasNode node, [String? id]) {
  final at = clearSpot(canvas, node.x + stepAside, node.y + stepAside);
  return node.put({'id': id ?? newCanvasId(), 'x': at.x, 'y': at.y});
}

/// The node wearing one of the spec's six presets ("1" to "6", the page's hues: card_looks.dart), or none.
CanvasNode colouredNode(CanvasNode node, String? color) {
  final rest = node.without('color');
  return color == null || color.isEmpty ? rest : rest.put({'color': color});
}

/// The room a new group leaves round the card it is made about: one square of the grid (`GROUP_ROOM`).
const double groupRoom = grid;

/// The size a group starts at when it is made about nothing (`NEW_GROUP`).
const ({double width, double height}) newGroup = (width: 480, height: 320);

/// A new group: about a card, with room round it, when there is one to make it about; otherwise a box of its own
/// with its top-left corner at (x, y). A group is drawn under the cards, so it goes first in the file, not last.
CanvasNode newGroupNode(CanvasNode? about, double x, double y, [String? id]) {
  final named = id ?? newCanvasId();
  if (about != null) return CanvasNode({'id': named, 'type': 'group', 'x': about.x - groupRoom, 'y': about.y - groupRoom, 'width': about.width + groupRoom * 2, 'height': about.height + groupRoom * 2});
  return CanvasNode({'id': named, 'type': 'group', 'x': jsRound(x), 'y': jsRound(y), 'width': newGroup.width, 'height': newGroup.height});
}

/// The canvas with a new group in it, under every card: first among the nodes, which are drawn in order.
Canvas withGroup(Canvas canvas, CanvasNode group) => Canvas(nodes: [group, ...canvas.nodes], edges: canvas.edges);
