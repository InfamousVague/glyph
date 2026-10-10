/// Who draws a diagram: the seam between the editor and Mermaid.
///
/// There is no Mermaid in Dart, and the same diagrams means Mermaid itself: the release ../glyph pins, run in the
/// platform's own web view, kept off the screen and never shown (assets/diagrams/, DiagramRenderer.kt on Android,
/// apple/DiagramRenderer.swift on a Mac and an iPhone). The page there is the web app's as far as a diagram can
/// tell, and what comes back is a photograph of the part of it the diagram is on. A web view shown inside the
/// scrolling note would cost every scroll frame; a picture costs one image.
///
/// [DiagramBridge] is what the store asks (store.dart); [ChannelDiagramBridge] is the phone's, over
/// `ghost_md/diagrams`; a test hands the store one of its own.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// What decides a diagram's picture: its words, and everything of the page round it that Mermaid or the browser
/// reads while drawing it.
class DiagramAsk {
  const DiagramAsk({
    required this.code,
    required this.dark,
    required this.viewport,
    required this.room,
    required this.gutter,
    required this.em,
    required this.ui,
    required this.note,
    required this.coding,
    required this.ink,
    required this.ratio,
  });

  /// What is between the fences.
  final String code;

  /// Which way the app is painted: Mermaid's `dark` theme, or its `neutral` (mermaid.ts `render`).
  final bool dark;

  /// The app's window, across, in logical pixels: the page's width, which a gantt is sized by.
  final double viewport;

  /// The note's column, across: the block's own width.
  final double room;

  /// `--app-gutter` where the diagram is: the block's padding either side.
  final double gutter;

  /// The note's size there (`--app-body`): the block's padding above and below is 0.6 of it.
  final double em;

  /// The interface's face as CSS says it (`--glacier-font-sans`): a diagram's words are measured in it.
  final String ui;

  /// The note's face (`--app-note-font`): they are drawn in it.
  final String note;

  /// A note in a coding face: the font's own features, no optical size, no tracking (typefaces.css).
  final bool coding;

  /// The note's ink, for anything in a diagram that takes the colour round it.
  final Color ink;

  /// Device pixels to the logical one.
  final double ratio;

  /// What the page is asked, less the picture's number.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'dark': dark,
    'viewport': viewport,
    'room': room,
    'gutter': gutter,
    'em': em,
    'ui': ui,
    'note': note,
    'coding': coding,
    'ink': cssColor(ink),
  };

  /// What tells one picture from another, and names it where it is kept: every answer above, the device's ratio,
  /// and [diagramPage], so a picture made by another Mermaid or another page is not taken for this one.
  String get key => '$diagramPage\n${dark ? 'dark' : 'light'}\n${_n(viewport)}|${_n(room)}|${_n(gutter)}|${_n(em)}|${_n(ratio)}|${coding ? 'c' : 's'}|${cssColor(ink)}\n$ui\n$note\n$code';

  static String _n(double value) => value.toStringAsFixed(3);

  /// Whether `other` asks for the same diagram painted the same way, in another room at most: a window being
  /// dragged wider, a phone unfolding.
  bool sameButRoom(DiagramAsk other) =>
      other.code == code && other.dark == dark && other.gutter == gutter && other.em == em && other.ui == ui && other.note == note && other.coding == coding && other.ink == ink && other.ratio == ratio;
}

/// The Mermaid the page runs and the page's own version: said in every picture's key. To be changed whenever
/// assets/diagrams/ changes in a way that changes a picture.
const String diagramPage = 'mermaid-12.0.0/page-1';

/// A colour as a stylesheet writes it.
String cssColor(Color color) {
  int part(double value) => (value * 255).round().clamp(0, 255);
  return 'rgba(${part(color.r)},${part(color.g)},${part(color.b)},${color.a.toStringAsFixed(3)})';
}

/// What the web view answered.
sealed class DiagramAnswer {
  const DiagramAnswer();
}

/// A diagram drawn: its picture as a PNG, and where the picture sits in its block.
class DiagramDrawn extends DiagramAnswer {
  const DiagramDrawn({required this.png, required this.block, required this.at, required this.scale});

  final Uint8List png;

  /// The block's size on the page (`.cm-mermaid`, its padding included), in logical pixels.
  final Size block;

  /// Where in the block the picture is, in logical pixels: its size is the picture's pixels over [scale].
  final Rect at;

  /// Pixels of the picture to the logical one.
  final double scale;
}

/// A diagram not drawn. [said] is Mermaid's own words for a diagram written wrong, and empty when the fault is not
/// the person's: no web view here, a page that did not load, a picture that never came.
class DiagramFailed extends DiagramAnswer {
  const DiagramFailed(this.said);

  final String said;
}

/// What draws a diagram. One at a time: whoever asks waits for the answer before asking again (store.dart).
abstract interface class DiagramBridge {
  Future<DiagramAnswer> draw(DiagramAsk ask);
}

/// The phone's web view, and the Mac's (`ghost_md/diagrams`).
///
/// `draw` is given `{n, viewport, ask}`: the picture's number, the window's width for the web view to be laid out
/// at, and the page's question as JSON, handed to the page as it is. It answers
/// `{png, blockWidth, blockHeight, x, y, width, height, scale}` for a picture, or `{failed}`.
class ChannelDiagramBridge implements DiagramBridge {
  ChannelDiagramBridge({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('ghost_md/diagrams');

  final MethodChannel _channel;

  /// The pictures' numbers: never 0, and under 2^24, since the page says one as a colour.
  int _n = 0;

  @override
  Future<DiagramAnswer> draw(DiagramAsk ask) async {
    _n = _n % 0xfffffe + 1;
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('draw', <String, Object?>{
        'n': _n,
        'viewport': ask.viewport,
        'ask': jsonEncode(<String, Object?>{'n': _n, ...ask.toJson()}),
      });
      return answerOf(answer);
    } on PlatformException {
      return const DiagramFailed('');
    } on MissingPluginException {
      // No web view on this platform: a diagram stays its text, with "could not be drawn here".
      return const DiagramFailed('');
    }
  }

  /// The channel's answer, read.
  static DiagramAnswer answerOf(Map<String, Object?>? answer) {
    if (answer == null) return const DiagramFailed('');
    final failed = answer['failed'];
    if (failed is String) return DiagramFailed(failed);
    final png = answer['png'];
    double number(String name) => (answer[name] as num?)?.toDouble() ?? 0;
    final scale = number('scale');
    if (png is! Uint8List || png.isEmpty || !(scale > 0) || !(number('blockHeight') > 0)) return const DiagramFailed('');
    return DiagramDrawn(
      png: png,
      block: Size(number('blockWidth'), number('blockHeight')),
      at: Rect.fromLTWH(number('x'), number('y'), number('width'), number('height')),
      scale: scale,
    );
  }
}
