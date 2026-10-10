import 'package:flutter/widgets.dart';

import 'icon_wash.dart';
import 'svg_path.dart';

/// One of the kit's lucide icons as the web app draws it: its shapes as paths on the 24 grid, and the places of the
/// shapes that wear the wash. Made by tool/lucide.dart (lib/art/lucide.g.dart), never written by hand.
@immutable
class LucideIcon {
  const LucideIcon(this.name, this.shapes, this.wash);

  /// Lucide's own name for it: the class its svg wears on the page, less `lucide-`.
  final String name;
  final List<String> shapes;
  final List<int> wash;
}

/// A lucide icon drawn the way the web app draws them: an outline in the text's own colour with round ends and
/// joins, at a stroke the caller chooses (often 2.1 or 2.2 on the page; lucide's own is 2), and inside it the wash,
/// a third of that colour on the icon's body alone (app.css "Icons are outlines, with a wash inside", iconWash.css).
///
/// `<Search size={18} strokeWidth={2.1} />` is `AppIcon(Lucide.search, size: 18, strokeWidth: 2.1)`. The size is
/// the svg's width and height; the stroke is in the icon's own 24 units and grows with the size, as lucide's does.
/// The colour is the `IconTheme`'s, else the text's (`currentColor`), unless [color] is given.
///
/// What differs from the page: nothing drawn; an icon font (`lucide_icons_flutter`, which the app carried until
/// nothing drew from it) has one fixed stroke and no wash, which is why these are drawn from the paths.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size = 24, this.strokeWidth = 2, this.color, this.wash = true, this.semanticLabel});

  final LucideIcon icon;
  final double size;
  final double strokeWidth;
  final Color? color;

  /// False draws the outline alone: an icon whose own stylesheet on the page says `fill: none`.
  final bool wash;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? inkAt(context);
    final picture = CustomPaint(size: Size.square(size), painter: DrawnIconPainter(strokes: icon.shapes, washed: wash ? [for (final index in icon.wash) icon.shapes[index]] : const [], color: ink, strokeWidth: strokeWidth));
    if (semanticLabel == null) return ExcludeSemantics(child: picture);
    return Semantics(label: semanticLabel, image: true, child: picture);
  }
}

/// `currentColor` at [context]: the colour an icon theme set round it gives its icons, else the text's own. Only a
/// theme someone set counts: with none, Flutter's fallback is black, which is not the page's ink.
Color inkAt(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<IconTheme>()?.data.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);

/// Paints a drawn icon: [washed] paths filled with a third of [color], then [strokes] in [color], on a box
/// [viewBox] wide scaled to the size it is given. Shared by the kit's icons ([AppIcon]) and the app's own
/// (icons.dart).
class DrawnIconPainter extends CustomPainter {
  const DrawnIconPainter({required this.strokes, required this.washed, required this.color, required this.strokeWidth, this.viewBox = 24, this.evenOdd = false});

  final List<String> strokes;
  final List<String> washed;
  final Color color;
  final double strokeWidth;
  final double viewBox;

  /// A body with a hole in it - a cog's middle, a cassette's reels - is filled even-odd, and the hole stays clear.
  final bool evenOdd;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / viewBox, size.height / viewBox);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: color.a * iconWash);
    // Each path from the store of them (svg_path.dart): parsed once for its string, and its even-odd self made once.
    for (final d in washed) {
      canvas.drawPath(svgPath(d, evenOdd: evenOdd), fill);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final d in strokes) {
      canvas.drawPath(svgPath(d), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DrawnIconPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.viewBox != viewBox || old.evenOdd != evenOdd || !_same(old.strokes, strokes) || !_same(old.washed, washed);

  static bool _same(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
