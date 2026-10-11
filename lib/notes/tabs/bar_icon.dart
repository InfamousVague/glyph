import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart';
import '../../art/icons.dart';
import '../../art/lucide.g.dart';

/// The glyphs the top bar draws (notes/NoteTabs.tsx: `House` of art/Icons.tsx, and `PanelLeft`, `ArrowLeft`,
/// `ArrowRight`, `UserGroup`, `Bell`, `Settings`, `Plus` and `X` of @glacier/icons).
enum BarGlyph { house, panelLeft, arrowLeft, arrowRight, people, bell, settings, plus, close }

/// One glyph of the bar, at the size the web draws it, in the colour of the control it is in.
///
/// The one place the bar reaches for an icon. Each is the web's own drawing: the kit's lucide paths ([AppIcon]) with
/// the wash inside the closed ones (iconWash.css), and the app's own house ([HouseIcon]). The stroke is the one the
/// bar's JSX gives that glyph wherever it draws it, so it is chosen here rather than by the caller: 2.1 for the
/// house, the sidebar's toggle, the people, the bell and the cog; 2.2 for the arrows (in a ring at 19 and beside a
/// word at 16 alike) and the strip's plus; 2.4 for a tab's cross.
class BarIcon extends StatelessWidget {
  const BarIcon(this.glyph, {super.key, required this.size, required this.color, this.mirrored = false});

  final BarGlyph glyph;
  final double size;
  final Color color;

  /// `.mirrored svg { transform: scaleX(-1) }`: the aside's toggle is the sidebar's icon reversed.
  final bool mirrored;

  /// The kit's icon for [glyph]; the house is the app's own and has none.
  static LucideIcon? drawing(BarGlyph glyph) => switch (glyph) {
        BarGlyph.house => null,
        BarGlyph.panelLeft => Lucide.panelLeft,
        BarGlyph.arrowLeft => Lucide.arrowLeft,
        BarGlyph.arrowRight => Lucide.arrowRight,
        BarGlyph.people => Lucide.userGroup,
        BarGlyph.bell => Lucide.bell,
        BarGlyph.settings => Lucide.settings,
        BarGlyph.plus => Lucide.plus,
        BarGlyph.close => Lucide.x,
      };

  /// `strokeWidth={…}` as NoteTabs.tsx writes it for [glyph].
  static double strokeOf(BarGlyph glyph) => switch (glyph) {
        BarGlyph.arrowLeft || BarGlyph.arrowRight || BarGlyph.plus => 2.2,
        BarGlyph.close => 2.4,
        _ => 2.1,
      };

  @override
  Widget build(BuildContext context) {
    // `aria-hidden="true"`: the control around it carries the name; both widgets keep themselves from the tree.
    final drawn = drawing(glyph);
    Widget icon = drawn == null ? HouseIcon(size: size, strokeWidth: strokeOf(glyph), color: color) : AppIcon(drawn, size: size, strokeWidth: strokeOf(glyph), color: color);
    if (mirrored) icon = Transform.flip(flipX: true, child: icon);
    return icon;
  }
}
