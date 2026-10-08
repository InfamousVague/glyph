/// Whether a note is a canvas, and how many cards it holds: what a list asks of `src/app/canvas/jsonCanvas.ts`
/// (`isCanvasBody`, and `canvasOf(body).nodes.length` for a row's "6 cards"). A canvas note is front matter that
/// names it, then JSON Canvas 1.0 and nothing else.
///
/// The canvas's own model is lib/canvas/json_canvas.dart, which this hands on; the count is the canvas read as the
/// canvas's screen reads it.
library;

import '../canvas/json_canvas.dart';

export '../canvas/json_canvas.dart' show isCanvasBody;

/// How many cards the canvas in [body] holds, or null for a note that is words (`canvasOf(body)?.nodes.length`).
int? canvasCardCount(String body) => canvasOf(body)?.nodes.length;
