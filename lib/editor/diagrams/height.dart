/// How tall a diagram is on the page before it is drawn: the height it was last drawn at, by what it says, and a
/// guess from how much it says for one never drawn. Ports `heights` and `guessHeight` of
/// `src/app/editor/mermaid.ts`.
///
/// A diagram is drawn after the note is laid out, and without this the editor would count an undrawn one as a
/// single line and shift the note under a reading finger when it arrives: the same lesson as boards
/// (boards/height.dart).
///
/// What differs: the memory can be switched off ([rememberDiagramHeights]), for tests that end before its write
/// would.
library;

import 'dart:math' as math;

import '../../note/height_memory.dart';

const String _heightsKey = 'glyph-mermaid-heights';

/// How tall each diagram was drawn, by what it says: 200 of them, to the whole pixel, as the page keeps them.
final HeightMemory diagramHeights = HeightMemory(HeightStore.kept(_heightsKey), 200, (px) => px.roundToDouble());

/// Whether diagrams remember their heights and read them back.
bool rememberDiagramHeights = true;

/// The height `code` was last drawn at, or null for one never drawn here.
double? knownDiagramHeight(String code) => rememberDiagramHeights ? diagramHeights.known(code) : null;

/// A diagram of `code` drawn `height` tall.
void rememberDiagramHeight(String code, double height) {
  if (rememberDiagramHeights && height > 0) diagramHeights.keep(code, height);
}

/// How tall a diagram is before it has been drawn: what it was last time, else a guess from how much it says
/// (`guessHeight`).
double guessDiagramHeight(String code) {
  final known = knownDiagramHeight(code);
  if (known != null) return known;
  // Lines of a diagram are steps, and a step is about a row of boxes; near enough to keep the note still.
  final lines = code.split('\n').where((line) => line.trim().isNotEmpty).length;
  return math.min(420, 80 + lines * 34).toDouble();
}
