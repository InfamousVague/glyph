/// What a card is, as it is drawn (card.dart, minimap.dart): its colour in the page's own hues, the note a file
/// card names, whether it is one of Ghost.md's own pictures, and whether a card of words is only a table. A port of
/// `src/app/canvas/cardLooks.ts`: the format says what a node holds (json_canvas.dart); this says what the screen
/// makes of it.
///
/// What differs: `paintProps` answered an element's `data-hue` or a `--app-space` on its style; here [paintOf]'s
/// answer is what a widget wears (a `GlacierScope` with the hue, or the hex put into the colour's expression,
/// paint.dart), so there is one function where the web had two.
library;

import 'json_canvas.dart';

/// The page's hues (ink.css `[data-hue]`), which are what a workspace wears too.
enum CanvasHue { rose, ember, amber, moss, sea, violet }

/// What a colour is painted with: one of the page's hues, or a hex someone chose in Obsidian, kept as it is.
class CardPaint {
  const CardPaint.hue(CanvasHue this.hue) : hex = null;
  const CardPaint.hex(String this.hex) : hue = null;
  final CanvasHue? hue;
  final String? hex;

  @override
  bool operator ==(Object other) => other is CardPaint && other.hue == hue && other.hex == hex;

  @override
  int get hashCode => Object.hash(hue, hex);

  @override
  String toString() => hue != null ? 'CardPaint.hue(${hue!.name})' : 'CardPaint.hex($hex)';
}

/// The spec's six presets - red, orange, yellow, green, cyan, purple, their exact values "intentionally not
/// defined" so each app paints them its own way - as the page's own hues (Matt: workspace hues, not a palette of
/// the canvas's own). Null for no colour, or one the spec does not allow.
CardPaint? paintOf(CanvasColor? color) => switch (color) {
  '1' => const CardPaint.hue(CanvasHue.rose),
  '2' => const CardPaint.hue(CanvasHue.ember),
  '3' => const CardPaint.hue(CanvasHue.amber),
  '4' => const CardPaint.hue(CanvasHue.moss),
  '5' => const CardPaint.hue(CanvasHue.sea),
  '6' => const CardPaint.hue(CanvasHue.violet),
  _ => color != null && color.startsWith('#') ? CardPaint.hex(color) : null,
};

final RegExp _md = RegExp(r'\.md$', caseSensitive: false);
final RegExp _image = RegExp(r'\.(png|jpe?g|gif|webp|avif|svg|bmp)$', caseSensitive: false);
final RegExp _row = RegExp(r'^\s*\|.*\|\s*$');

/// A file node's name as a note's title: the last part of the path, without `.md`. `Plans/Cabin trip.md` is
/// "Cabin trip".
String fileTitle(String file) => file.split('/').last.replaceFirst(_md, '');

/// Whether a file node points at a picture rather than a note.
bool isImageFile(String file) => _image.hasMatch(file);

/// A file node that is one of Ghost.md's own pictures: its name in the picture store (core/images.dart), or null.
/// A picture from another vault has a folder in its name and no such picture here, and is drawn as being elsewhere.
String? ownPicture(CanvasNode node) => node.type == NodeType.file && isImageFile(node.file) && !node.file.contains('/') ? node.file : null;

/// Whether a card of words is nothing but a table, which is then drawn edge to edge.
bool isOnlyTable(String text) {
  final lines = text.trim().split('\n');
  return lines.length >= 2 && lines.every(_row.hasMatch);
}
