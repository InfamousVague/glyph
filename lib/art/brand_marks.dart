/// The marks of the companies whose products the plugins reach, drawn as icons (Matt, 2026-10-29: "Iconize real
/// company logos for openAI todoist, GitHub, Google meets, zoom etc and use those for the plugin icons").
///
/// Each is the brand's own drawing, one path on the 24 grid: Simple Icons' (CC0, simple-icons@16.35.0) where that
/// project carries the brand, else the company's own from its own site (Lovart's). They are copied, never drawn or
/// traced here: `assets/brands/<slug>.svg` is the file as it came, lib/art/brand_marks.g.dart its path as the app draws
/// it (`dart run tool/brands/generate.dart`), and assets/brands/SOURCES.md says where each came from. The marks are
/// their owners' trademarks, drawn to say which service a plugin reaches.
///
/// **Iconized.** [BrandMarkIcon] sits in the box an [AppIcon] of the same size takes, the mark a little inside it
/// ([BrandMarkData.optical]), as a Lucide glyph's drawing sits inside its 24 with room round it: a filled mark weighs
/// more than a line, so a row of plugin icons, marks and glyphs together, reads level. In one colour, the icon's
/// (`currentColor`) unless told: the brand's own hex only where the plugin is shown as itself, its tile in the Market
/// and its page's head ([brandInkOn] keeps it readable, and gives the ink where it would not be). The icon styles
/// (Outline, Solid, Filled; lib/art/icon_pack.dart) draw a mark as it is in all three: a logo has no outline of its
/// own to be drawn in, and a mark drawn in a line it never had would not be the brand's.
///
/// **Never in a store's pictures.** A build made for the App Store's or Play's screenshots
/// (`--dart-define=GHOST_STORE_NEUTRAL=true`, the define the store pack's shoot scripts build with) draws no brand's
/// mark: [brandMarksShown] is false, and every plugin wears its generic glyph (Apple refused iOS 2.2.1 under 4.1(a)
/// for a third party's name in its metadata, 2026-10-19).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'app_icon.dart' show inkAt;
import 'brand_marks.g.dart';
import 'svg_path.dart';

export 'brand_marks.g.dart' show brandMarkData;

/// A build for a store's screenshots: one made with `--dart-define=GHOST_STORE_NEUTRAL=true`.
const bool storeShotBuild = bool.fromEnvironment('GHOST_STORE_NEUTRAL');

/// A test's say over [storeShotBuild]: true draws as the store's pictures are drawn, false as the app is; null is
/// the build's own.
@visibleForTesting
bool? debugStoreShots;

/// Whether brands' marks are drawn at all: everywhere in the app, but never in a build for a store's pictures.
bool get brandMarksShown => !(debugStoreShots ?? storeShotBuild);

/// One brand's mark: its name, its colour (Simple Icons' hex; null where the source gave none), and its path on the
/// 24 grid.
@immutable
class BrandMarkData {
  const BrandMarkData({required this.slug, required this.title, required this.hex, required this.d});

  final String slug;
  final String title;
  final int? hex;
  final String d;

  /// The brand's colour, opaque; null where it has none.
  Color? get colour => hex == null ? null : Color(hex!);

  /// How much of the box the mark takes: the share a Lucide glyph's drawing takes of its 24 (some 20 of it) for a
  /// light mark, a little less for one that is a solid round or square, which would weigh more beside a line.
  double get optical => _optical[slug] ?? 0.8;
}

/// The marks drawn smaller or larger than the rest, by eye against the Lucide glyphs beside them in Settings' list
/// (build/feature-shots/brand-icons/).
const Map<String, double> _optical = {
  // Solid rounds and squares, the box filled to its corners.
  'github': 0.8,
  'lovart': 0.74,
  'todoist': 0.74,
  'things': 0.76,
  // Light marks, a spark or bars with the ground between them.
  'claude': 0.84,
  'googlegemini': 0.84,
  'elevenlabs': 0.7,
  // Discord's face is wide and short: a little larger, to weigh what the rest do.
  'discord': 0.86,
  // Zoom's mark is its word, four letters wide and a quarter as tall (Simple Icons carries no other): the box's whole
  // width, or it cannot be read.
  'zoom': 1,
};

/// The mark of [slug], or null where the app carries none.
BrandMarkData? brandMark(String? slug) => slug == null ? null : brandMarkData[slug];

/// The contrast of two colours, as WCAG counts it: 1 for the same, 21 for black on white.
double contrastOf(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// The least contrast a mark keeps with its ground in its brand's colour: WCAG's for a graphic (1.4.11).
const double brandContrast = 3;

/// The colour [mark] is drawn in on [ground]: its brand's where that stands out from the ground, else [ink] (GitHub's
/// near-black, or Notion's black, on the dark paper).
Color brandInkOn(BrandMarkData mark, {required Color ground, required Color ink}) {
  final colour = mark.colour;
  if (colour == null) return ink;
  return contrastOf(colour, ground) >= brandContrast ? colour : ink;
}

/// A brand's mark as an icon, [size] square: the mark centred in it at its [BrandMarkData.optical] share (or
/// [scale]), filled in [color], else the icon's colour round it, else the text's.
class BrandMarkIcon extends StatelessWidget {
  const BrandMarkIcon(this.mark, {super.key, this.size = 24, this.color, this.scale});

  final BrandMarkData mark;
  final double size;
  final Color? color;
  final double? scale;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? inkAt(context);
    return ExcludeSemantics(child: CustomPaint(size: Size.square(size), painter: _BrandPainter(mark.d, ink, scale ?? mark.optical)));
  }
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter(this.d, this.color, this.scale);

  final String d;
  final Color color;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * scale;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 24);
    canvas.drawPath(svgPath(d), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter old) => old.d != d || old.color != color || old.scale != scale;
}
