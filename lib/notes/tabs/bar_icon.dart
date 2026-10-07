import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The glyphs the top bar draws (notes/NoteTabs.tsx: `House` of art/Icons.tsx, and `PanelLeft`, `ArrowLeft`,
/// `ArrowRight`, `UserGroup`, `Bell`, `Settings`, `Plus` and `X` of @glacier/icons).
enum BarGlyph { house, panelLeft, arrowLeft, arrowRight, people, bell, settings, plus, close }

/// One glyph of the bar, at the size the web draws it, in the colour of the control it is in.
///
/// The one place the bar reaches for an icon, so the icons can be swapped for the app's own widget when that is
/// built: until then each is the Lucide font's glyph of the same name.
///
/// Differs from the web: the web's icons are SVG at a stroke the bar chooses (2.1 to 2.4) with a wash inside the
/// closed ones (iconWash.css), and the house is the app's own drawing; the font's are one weight, hollow, and its
/// house is Lucide's. `UserGroup` is drawn as Lucide's `users-round`.
class BarIcon extends StatelessWidget {
  const BarIcon(this.glyph, {super.key, required this.size, required this.color, this.mirrored = false});

  final BarGlyph glyph;
  final double size;
  final Color color;

  /// `.mirrored svg { transform: scaleX(-1) }`: the aside's toggle is the sidebar's icon reversed.
  final bool mirrored;

  static IconData _data(BarGlyph glyph) => switch (glyph) {
        BarGlyph.house => LucideIcons.house,
        BarGlyph.panelLeft => LucideIcons.panelLeft,
        BarGlyph.arrowLeft => LucideIcons.arrowLeft,
        BarGlyph.arrowRight => LucideIcons.arrowRight,
        BarGlyph.people => LucideIcons.usersRound,
        BarGlyph.bell => LucideIcons.bell,
        BarGlyph.settings => LucideIcons.settings,
        BarGlyph.plus => LucideIcons.plus,
        BarGlyph.close => LucideIcons.x,
      };

  @override
  Widget build(BuildContext context) {
    // `aria-hidden="true"`: the control around it carries the name.
    Widget icon = ExcludeSemantics(child: Icon(_data(glyph), size: size, color: color));
    if (mirrored) icon = Transform.flip(flipX: true, child: icon);
    return icon;
  }
}
