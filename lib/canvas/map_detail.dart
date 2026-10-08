/// What a card looks like small (minimap.dart): its words as the bars a page of text makes when it is too far away
/// to read - a heavier bar for a heading, a dot and a bar for a list's line, a paragraph as the lines it wraps to,
/// a table as its rows. A port of `src/app/canvas/mapDetail.ts` (Matt: "the canvas minimap could also be far more
/// detailed with modern displays").
///
/// Pure, and in the card's own box: every bar is placed from the card's top-left corner, in the canvas's pixels, so
/// the map draws them inside the same transform as the card and nothing is measured on the screen.
library;

import 'dart:math' as math;

import 'js.dart';

class MapBar {
  const MapBar({required this.x, required this.y, required this.width, required this.height, this.strong = false});
  final double x;
  final double y;
  final double width;
  final double height;

  /// A heading, or a note's title: drawn heavier.
  final bool strong;
}

/// The room inside a card, the pitch of its lines and the weight of a line, in the canvas's pixels: about what the
/// card itself draws.
const double _pad = 14;
const double _pitch = 20;
const double _bar = 8;
const double _heading = 12;

/// A character's width, near enough, at the size a card's words are drawn.
const double _char = 7;

/// No card is drawn with more bars than this: past it they are a grey, and a canvas may hold hundreds of cards.
const int _most = 28;

final RegExp _fence = RegExp(r'^(```|~~~)');
final RegExp _headingLine = RegExp(r'^#{1,6}\s+(.*)$');
final RegExp _tableRow = RegExp(r'^\|.*\|$');
final RegExp _tableRule = RegExp(r'^\|[\s:|-]+\|$');
final RegExp _item = RegExp(r'^(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?(.*)$');

/// The bars for a card of words this size. Nothing for a card too small to hold a line.
List<MapBar> wordBars(String text, double width, double height) {
  final room = width - _pad * 2;
  final bars = <MapBar>[];
  if (room < 24) return bars;
  var y = _pad;
  bool fits(double h) => y + h <= height - _pad / 2 && bars.length < _most;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      // A blank line is a paragraph's gap, half a line of air.
      if (bars.isNotEmpty) y += _pitch / 2;
      continue;
    }
    // A fence's own lines draw nothing: what is inside it does.
    if (_fence.hasMatch(line)) continue;
    final heading = _headingLine.firstMatch(line);
    if (heading != null) {
      if (!fits(_heading)) break;
      bars.add(MapBar(x: _pad, y: y, width: math.min(room, math.max(40.0, heading.group(1)!.length * _char * 1.35)), height: _heading, strong: true));
      y += _pitch + 6;
      continue;
    }
    // A table's row runs the card's width; its rule under the head is the row's own line.
    if (_tableRow.hasMatch(line)) {
      if (_tableRule.hasMatch(line)) continue;
      if (!fits(_bar)) break;
      bars.add(MapBar(x: _pad, y: y, width: room, height: _bar));
      y += _pitch;
      continue;
    }
    final item = _item.firstMatch(line);
    final words = item != null ? item.group(1)! : line;
    final indent = item != null ? 16.0 : 0.0;
    if (item != null) {
      if (!fits(_bar)) break;
      bars.add(MapBar(x: _pad, y: y, width: _bar, height: _bar));
    }
    // A paragraph wraps: full lines, then what is left over, three lines of it at the most.
    var left = math.max(24.0, words.length * _char);
    final across = room - indent;
    for (var wrapped = 0; left > 0 && wrapped < 3; wrapped += 1) {
      if (!fits(_bar)) return bars;
      final w = math.min(across, left);
      bars.add(MapBar(x: _pad + indent, y: y, width: math.max(16.0, w), height: _bar));
      left -= across;
      y += _pitch;
    }
  }
  return bars;
}

/// The bars for a note card: its title, heavier, and a few lines of the note under it.
List<MapBar> noteBars(String title, double width, double height) {
  final room = width - _pad * 2;
  if (room < 24 || height < _pad * 2 + _heading) return const [];
  final bars = <MapBar>[MapBar(x: _pad, y: _pad, width: math.min(room, math.max(40.0, title.length * _char * 1.2)), height: _heading, strong: true)];
  const widths = [1, 0.86, 0.62];
  for (var n = 0; n < widths.length; n += 1) {
    final y = _pad + _heading + 12 + n * _pitch;
    if (y + _bar > height - _pad / 2) break;
    bars.add(MapBar(x: _pad, y: y, width: room * widths[n], height: _bar));
  }
  return bars;
}

/// A rectangle with round corners as an SVG path, for cutting the screen's box out of the map's shade.
String roundedBox(double x, double y, double width, double height, double radius) {
  final r = math.max(0.0, math.min(radius, math.min(width / 2, height / 2)));
  String n(double value) => jsNumber(value);
  return 'M${n(x + r)} ${n(y)}h${n(width - r * 2)}a${n(r)} ${n(r)} 0 0 1 ${n(r)} ${n(r)}v${n(height - r * 2)}a${n(r)} ${n(r)} 0 0 1 ${n(-r)} ${n(r)}h${n(-(width - r * 2))}a${n(r)} ${n(r)} 0 0 1 ${n(-r)} ${n(-r)}v${n(-(height - r * 2))}a${n(r)} ${n(r)} 0 0 1 ${n(r)} ${n(-r)}Z';
}
