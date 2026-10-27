import 'package:flutter/foundation.dart';

/// The three ways the app's icons can be drawn (Matt, 2026-10-27: "I would like you to add three icon styles
/// (outline, solid and filled)"), whichever pack draws them (lib/art/icon_packs.dart):
///
/// - [outline]: the pack's own line at its regular weight, the app's look until then.
/// - [solid]: the same glyphs drawn bolder, a heavier line (Phosphor's bold, Material Symbols at weight 700, Lucide
///   and Tabler at a heavier stroke).
/// - [filled]: filled glyphs (Phosphor's fill, Tabler's filled, Material Symbols with FILL 1, Remix's fill).
///
/// A pack that calls its filled set "solid" (Heroicons does) is mapped onto these three by what is drawn, not by the
/// word.
enum IconStyle {
  outline('Outline'),
  solid('Solid'),
  filled('Filled');

  const IconStyle(this.label);

  /// Its word in Settings and the Market.
  final String label;

  /// The style a stored word names; Outline for anything else, a newer build's style among them.
  static IconStyle of(Object? word) => values.firstWhere((style) => style.name == word, orElse: () => outline);
}

/// One drawing of a glyph in one style, on the 24 grid: lines that are stroked ([PackGlyph.lines], Lucide's and
/// Tabler's outlines), or shapes that are filled ([PackGlyph.shapes], every pack drawn as outlines of its own and
/// every filled set). Made by tool/icons/generate.dart (lib/art/packs/*.g.dart), never written by hand.
@immutable
class PackGlyph {
  /// Lines, stroked at the weight the caller asks for. [wash] is the places of the paths that wear the wash, by the
  /// rule Lucide's do (lib/art/icon_wash.dart), and [solids] those filled as well as stroked (Tabler's dots).
  const PackGlyph.lines(this.paths, {this.wash = const [], this.solids = const []}) : shapes = false;

  /// Shapes, filled whole, nonzero, as the packs' SVGs fill them.
  const PackGlyph.shapes(this.paths)
      : shapes = true,
        wash = const [],
        solids = const [];

  final List<String> paths;
  final bool shapes;
  final List<int> wash;
  final List<int> solids;
}

/// One glyph of a pack in each style: its [outline] always, and its [solid] and [filled] where the pack draws them.
/// A style left null is drawn from another (lib/art/icon_packs.dart `drawingFor`).
@immutable
class PackGlyphs {
  const PackGlyphs(this.outline, {this.solid, this.filled, this.back});

  final PackGlyph outline;
  final PackGlyph? solid;
  final PackGlyph? filled;

  /// The wash under an outline or a solid where the pack draws one of its own: Phosphor's duotone layer, a fifth of
  /// the ink on the glyph's body. Where it is null, a shapes pack's wash is its own filled glyph.
  final PackGlyph? back;
}
