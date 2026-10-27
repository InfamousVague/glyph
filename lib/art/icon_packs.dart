/// The app's icon packs and how each draws in each style (Matt, 2026-10-27: "I would like you to add three icon styles
/// (outline, solid and filled) and add a few different icon packs for the app to choose from"): Lucide, the app's own
/// until then and still the default, and four more with permissive licences that between them have nearly every
/// glyph the app draws (tool/icons/map.json says which of theirs is which of the app's).
///
/// Every icon is drawn through [AppIcon] (lib/art/app_icon.dart), or the app's own drawings through [DrawnIconView]
/// and [HouseIcon] (lib/art/icons.dart), and each reads the [IconLook] the app is drawn under ([IconLookScope],
/// put round the whole app by lib/app/ghost_app.dart from the preferences `iconPack` and `iconStyle`), so a pack or a
/// style chosen in the Market or in Settings › Appearance is every icon at once, with nothing restarted.
///
/// How a pack draws a style it has not got, and a glyph it has not got ([drawingFor], [lucideDrawing]):
///
/// - A glyph the pack has no match for is Lucide's, in the chosen style. The generator says how many per pack (the
///   head of each lib/art/packs/*.g.dart).
/// - **Solid** where a pack has no bolder set: a pack of lines (Lucide, Tabler) strokes the same lines heavier, which is
///   its own stroke width turned up; a pack of shapes (Remix) is its outline thickened, the shapes stroked round as
///   well as filled.
/// - **Filled** where a pack has no filled glyph: a pack of lines fills the glyph's body, the same body the wash is
///   on (lib/art/icon_wash.dart), and cuts the lines inside it out of the fill; a glyph with no body (an arrow, a tick)
///   is its Solid. A pack of shapes with no filled glyph (Remix's letters) is its Solid too.
///
/// The wash, a third of the ink inside an icon's body (app.css "Icons are outlines, with a wash inside"), stays in
/// Outline and Solid whatever the pack: a pack of lines by the body rule, Phosphor by its duotone layer, Material
/// Symbols and Remix by their own filled glyph laid under the outline.
///
/// What does not follow: the launcher's icon, the Android widgets, the launcher's shortcuts and the notifications'
/// small icons, which are Android's own drawables (android/app/src/main/res/drawable) drawn by the launcher, not by
/// Flutter; the brands' marks (Claude's, Notion's, GitHub's, Lovart's), which are theirs; the ghost; and the few
/// drawings that are pictures rather than icons (the map's pin, the board's status rings, the scenes' phones).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'icon_pack.dart';
import 'icon_wash.dart';
import 'packs/licences.g.dart';
import 'packs/material.g.dart';
import 'packs/phosphor.g.dart';
import 'packs/remix.g.dart';
import 'packs/tabler.g.dart';
import 'svg_path.dart';

export 'icon_pack.dart';

/// What a style is drawn from in a pack: the pack's own set, or another made into it.
enum StyleSource { native, heavier, thickened, cut, solid }

/// One icon pack: what it is, whose it is and under what licence, how it draws each style, and its glyphs by the
/// app's names ([glyphs]; null for Lucide, whose glyphs are lib/art/lucide.g.dart's).
@immutable
class IconPack {
  const IconPack({
    required this.id,
    required this.name,
    required this.line,
    required this.about,
    required this.author,
    required this.licence,
    required this.version,
    required this.home,
    required this.styles,
    required this.glyphs,
    this.hue = 'indigo',
  });

  /// As the preferences keep it and a link names it (`ghostmd://market/icons/<id>`).
  final String id;
  final String name;

  /// Its card's line.
  final String line;

  /// Its page's words.
  final String about;
  final String author;

  /// SPDX's name for its licence: MIT, ISC, Apache-2.0.
  final String licence;

  /// The release its paths were made from (tool/icons/map.json).
  final String version;

  /// Its own site, named on its page (not linked: the Market reaches nowhere a plugin's page does not say).
  final String home;

  /// How each style is drawn, and in a few words.
  final Map<IconStyle, ({StyleSource source, String words})> styles;

  /// The app's glyphs as it draws them, by their Lucide names; null for Lucide itself.
  final Map<String, PackGlyphs>? glyphs;

  /// Its card's colour in the Market, one of `marketHues` (lib/market/market_items.dart).
  final String hue;
}

/// The packs, Lucide first, in the order the Market lays them out.
const List<IconPack> iconPacks = [
  IconPack(
    id: 'lucide',
    name: 'Lucide',
    line: 'Clean, even lines. Ghost.md’s own.',
    about: 'The icons Ghost.md was drawn with from the start: rounded lines of one weight on a 24 grid, with the app’s wash inside them. Lucide grew out of Feather and is kept by its community.',
    author: 'Lucide Contributors',
    licence: 'ISC',
    version: 'lucide-react 1.45.0',
    home: 'lucide.dev',
    styles: {
      IconStyle.outline: (source: StyleSource.native, words: 'Its own line, at its regular weight'),
      IconStyle.solid: (source: StyleSource.heavier, words: 'The same lines at a heavier stroke, as Lucide lets them be set'),
      IconStyle.filled: (source: StyleSource.cut, words: 'Lucide has no filled set: each icon’s body is filled and the lines inside it cut out, and an icon of lines alone is its Solid'),
    },
    glyphs: null,
    hue: 'indigo',
  ),
  IconPack(
    id: 'phosphor',
    name: 'Phosphor',
    line: 'Friendly and round, in six weights.',
    about: 'A family of 1,500 icons drawn in six weights by Helena Zhang and Tobias Fried. Ghost.md uses three: regular, bold and fill, with the duotone layer as the wash.',
    author: 'Phosphor Icons',
    licence: 'MIT',
    version: '@phosphor-icons/core 2.1.1',
    home: 'phosphoricons.com',
    styles: {
      IconStyle.outline: (source: StyleSource.native, words: 'Regular'),
      IconStyle.solid: (source: StyleSource.native, words: 'Bold'),
      IconStyle.filled: (source: StyleSource.native, words: 'Fill'),
    },
    glyphs: phosphorGlyphs,
    hue: 'purple',
  ),
  IconPack(
    id: 'tabler',
    name: 'Tabler',
    line: 'Over 5,000 crisp lines.',
    about: 'More than five thousand icons on a 24 grid with a 2 point line, built as Lucide’s are, by Paweł Kuna and the Tabler community. About a fifth of them have a filled twin.',
    author: 'Paweł Kuna',
    licence: 'MIT',
    version: '@tabler/icons 3.49.0',
    home: 'tabler.io/icons',
    styles: {
      IconStyle.outline: (source: StyleSource.native, words: 'Outline'),
      IconStyle.solid: (source: StyleSource.heavier, words: 'Outline at a heavier stroke, as Tabler lets it be set'),
      IconStyle.filled: (source: StyleSource.native, words: 'Filled where Tabler draws one; elsewhere its body filled with the lines cut out, or its Solid'),
    },
    glyphs: tablerGlyphs,
    hue: 'blue',
  ),
  IconPack(
    id: 'material',
    name: 'Material Symbols',
    line: 'Google’s symbols, rounded.',
    about: 'Google’s Material Symbols, nearly 4,000 of them, in their Rounded shape: one set drawn to every weight, filled or not. Ghost.md uses weight 400 for Outline, 700 for Solid, and 400 filled.',
    author: 'Google',
    licence: 'Apache-2.0',
    version: '@material-symbols/svg-400 and svg-700 0.48.0',
    home: 'fonts.google.com/icons',
    styles: {
      IconStyle.outline: (source: StyleSource.native, words: 'Rounded, weight 400'),
      IconStyle.solid: (source: StyleSource.native, words: 'Rounded, weight 700'),
      IconStyle.filled: (source: StyleSource.native, words: 'Rounded, weight 400, filled'),
    },
    glyphs: materialGlyphs,
    hue: 'green',
  ),
  IconPack(
    id: 'remix',
    name: 'Remix Icon',
    line: 'Neutral, in line and fill.',
    about: 'Some 1,700 neutral icons by the Remix Design team, nearly every one drawn twice, as a line and filled.',
    author: 'Remix Design',
    licence: 'Apache-2.0',
    version: 'remixicon 4.9.1',
    home: 'remixicon.com',
    styles: {
      IconStyle.outline: (source: StyleSource.native, words: 'Line'),
      IconStyle.solid: (source: StyleSource.thickened, words: 'Remix draws one weight: the line set, thickened'),
      IconStyle.filled: (source: StyleSource.native, words: 'Fill, where Remix draws one; its letters are their Solid'),
    },
    glyphs: remixGlyphs,
    hue: 'coral',
  ),
];

/// The pack [id] names; Lucide for any other, a newer build's pack among them.
IconPack iconPackOf(Object? id) => iconPacks.firstWhere((pack) => pack.id == id, orElse: () => iconPacks.first);

/// Whether [id] is one of [iconPacks].
bool isIconPack(Object? id) => iconPacks.any((pack) => pack.id == id);

/// The glyphs the Market draws a pack with: twelve of the app's own, a row of the things it does.
const List<String> iconPreviewNames = [
  'search',
  'bell',
  'settings',
  'folder',
  'file-text',
  'mic',
  'calendar-days',
  'trash',
  'image',
  'lock',
  'bookmark',
  'circle-check',
];

// --- the look the app is drawn in ----------------------------------------------------------------------------------

/// A pack and a style: what every icon below an [IconLookScope] is drawn in.
@immutable
class IconLook {
  const IconLook([this.pack = 'lucide', this.style = IconStyle.outline]);

  /// The app's look before there was a choice: Lucide's outlines.
  static const IconLook standard = IconLook();

  final String pack;
  final IconStyle style;

  /// Lucide's outline, drawn exactly as it was before there were packs.
  bool get isStandard => iconPackOf(pack).id == 'lucide' && style == IconStyle.outline;

  /// The look round [context]; [standard] where nothing set one.
  static IconLook of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IconLookScope>()?.look ?? standard;

  @override
  bool operator ==(Object other) => other is IconLook && other.pack == pack && other.style == style;

  @override
  int get hashCode => Object.hash(pack, style);

  @override
  String toString() => 'IconLook($pack, ${style.name})';
}

/// Puts [look] on every icon below it. The app has one round everything (lib/app/ghost_app.dart); the Market and
/// Appearance draw their previews in other looks with [AppIcon]'s own `look`.
class IconLookScope extends InheritedWidget {
  const IconLookScope({super.key, required this.look, required super.child});

  final IconLook look;

  @override
  bool updateShouldNotify(IconLookScope old) => old.look != look;
}

// --- what is drawn ------------------------------------------------------------------------------------------------

/// How a drawing's paths are inked: stroked, stroked heavier, filled with their inside lines cut out, filled, or
/// filled and thickened.
enum IconInk { lines, heavyLines, cutLines, shapes, thickShapes }

/// One icon as it is drawn: its glyph, how it is inked, and the wash under it where it is a pack of shapes'.
@immutable
class IconDrawing {
  const IconDrawing(this.glyph, this.ink, {this.under, this.fallback = false});

  final PackGlyph glyph;
  final IconInk ink;

  /// The wash's drawing under a glyph of shapes: Phosphor's duotone layer, or the pack's filled glyph.
  final PackGlyph? under;

  /// Whether it is Lucide's, drawn because the pack has not got the glyph.
  final bool fallback;

  @override
  bool operator ==(Object other) =>
      other is IconDrawing && identical(other.glyph.paths, glyph.paths) && identical(other.glyph.wash, glyph.wash) && other.ink == ink && identical(other.under?.paths, under?.paths) && other.fallback == fallback;

  @override
  int get hashCode => Object.hash(identityHashCode(glyph.paths), ink, identityHashCode(under?.paths));
}

/// How much heavier Solid's line is than Outline's, on the 24 grid: Lucide's 2 is 2.8, the weight Phosphor's bold
/// is to its regular by eye at the sizes the app draws, and a line the caller already asked to be heavy (a tick at
/// 3) grows by as much, not by a share.
const double solidStroke = 0.8;

/// How much a pack of shapes with no bolder set is thickened for Solid, on the 24 grid: the shapes stroked this wide
/// round their edges as well as filled, so Remix's 2-unit line is about 2.7.
const double thickenedStroke = 0.7;

/// A pack's [entry] in [style], drawn from another style where the pack has not got it (see the library's comment).
/// [body] is whether the app's own glyph for it has a body (Lucide's wash, or a drawing's body): only then is there a
/// wash under a glyph of shapes, as there is none in a tick or an arrow in Lucide.
IconDrawing drawingFor(PackGlyphs entry, IconStyle style, {bool body = true}) {
  final outline = entry.outline;
  final under = outline.shapes && body ? (entry.back ?? entry.filled) : null;
  switch (style) {
    case IconStyle.outline:
      return IconDrawing(outline, outline.shapes ? IconInk.shapes : IconInk.lines, under: under);
    case IconStyle.solid:
      if (entry.solid case final solid?) return IconDrawing(solid, solid.shapes ? IconInk.shapes : IconInk.heavyLines, under: body ? entry.back ?? entry.filled : null);
      return IconDrawing(outline, outline.shapes ? IconInk.thickShapes : IconInk.heavyLines, under: under);
    case IconStyle.filled:
      if (entry.filled case final filled?) return IconDrawing(filled, filled.shapes ? IconInk.shapes : IconInk.cutLines);
      if (!outline.shapes) return IconDrawing(outline, IconInk.cutLines);
      return drawingFor(entry, IconStyle.solid, body: body);
  }
}

/// A Lucide icon's lines ([shapes], with the places of those that wear the [wash]) in [style]: Lucide's own drawing,
/// and every pack's for a glyph it has not got ([fallback]).
IconDrawing lucideDrawing(List<String> shapes, List<int> wash, IconStyle style, {bool fallback = false}) => IconDrawing(
      PackGlyph.lines(shapes, wash: wash),
      switch (style) {
        IconStyle.outline => IconInk.lines,
        IconStyle.solid => IconInk.heavyLines,
        IconStyle.filled => IconInk.cutLines,
      },
      fallback: fallback,
    );

/// The glyph [name] (a Lucide name, tool/icons/map.json) in [look]'s pack; null where the pack is Lucide or has not
/// got it, and Lucide's is drawn.
PackGlyphs? packGlyphsFor(IconLook look, String name) => iconPackOf(look.pack).glyphs?[name];

/// Paints an [IconDrawing] on the 24 grid scaled to the size it is given, in [color]: lines at [strokeWidth] (the
/// caller's, as Lucide's is; a pack of lines is stroked as Lucide is), shapes filled whatever the stroke.
class PackIconPainter extends CustomPainter {
  const PackIconPainter({required this.drawing, required this.color, required this.strokeWidth, this.wash = true});

  final IconDrawing drawing;
  final Color color;
  final double strokeWidth;

  /// False leaves the wash out, as `AppIcon(wash: false)` asks.
  final bool wash;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final glyph = drawing.glyph;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final washInk = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: color.a * iconWash);
    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (drawing.ink) {
      case IconInk.lines || IconInk.heavyLines:
        final line = stroke(drawing.ink == IconInk.heavyLines ? strokeWidth + solidStroke : strokeWidth);
        if (wash) {
          for (final index in glyph.wash) {
            canvas.drawPath(svgPath(glyph.paths[index]), washInk);
          }
        }
        for (var i = 0; i < glyph.paths.length; i++) {
          final path = svgPath(glyph.paths[i]);
          if (glyph.solids.contains(i)) canvas.drawPath(path, fill);
          canvas.drawPath(path, line);
        }
      case IconInk.cutLines:
        final line = stroke(strokeWidth + solidStroke);
        final box = const Rect.fromLTWH(-4, -4, 32, 32);
        // The body filled and its own edge drawn, then the rest drawn over it exclusive-or: a line inside the body is
        // cut out of it, a line outside it is drawn. The rest are a layer of their own first, so where two of them
        // cross they do not cut each other back in.
        canvas.saveLayer(box, Paint());
        for (final index in glyph.wash) {
          final path = svgPath(glyph.paths[index]);
          canvas.drawPath(path, fill);
          canvas.drawPath(path, line);
        }
        canvas.saveLayer(box, Paint()..blendMode = glyph.wash.isEmpty ? BlendMode.srcOver : BlendMode.xor);
        for (var i = 0; i < glyph.paths.length; i++) {
          if (glyph.wash.contains(i)) continue;
          final path = svgPath(glyph.paths[i]);
          if (glyph.solids.contains(i)) canvas.drawPath(path, fill);
          canvas.drawPath(path, line);
        }
        canvas.restore();
        canvas.restore();
      case IconInk.shapes || IconInk.thickShapes:
        if (wash && drawing.under != null) {
          for (final d in drawing.under!.paths) {
            canvas.drawPath(svgPath(d), washInk);
          }
        }
        final thick = drawing.ink == IconInk.thickShapes ? stroke(thickenedStroke) : null;
        for (final d in glyph.paths) {
          final path = svgPath(d);
          canvas.drawPath(path, fill);
          if (thick != null) canvas.drawPath(path, thick);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PackIconPainter old) => old.drawing != drawing || old.color != color || old.strokeWidth != strokeWidth || old.wash != wash;
}

// --- licences -----------------------------------------------------------------------------------------------------

var _licensed = false;

/// Puts every pack's licence among the app's (Flutter's [LicenseRegistry], where the packages' own are), each as the
/// pack ships it (tool/icons/licences/). Once, however often it is asked; lib/main.dart asks as the app starts.
void registerIconPackLicences() {
  if (_licensed) return;
  _licensed = true;
  LicenseRegistry.addLicense(() => Stream.fromIterable([
        for (final pack in iconPacks)
          if (iconPackLicenceTexts[pack.id] case final text?) LicenseEntryWithLineBreaks(['${pack.name} icons'], text),
      ]));
}
