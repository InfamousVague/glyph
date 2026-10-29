/// Lovart's mark: the circle with "Lo" cut out of it, from the header of www.lovart.ai as read on 2026-10-26
/// (assets/plugins/lovart/lovart-mark.svg; docs/LOVART.md). Drawn by `flutter_svg`, the app's one reader of SVG, in
/// one colour: the text's around it unless told.
///
/// A third party's mark: it is drawn in the plugin's own places only (its page, its actions, the chip by a cue, the
/// badge on a picture it made), never in a store listing or a screenshot for one: a build for a store's pictures
/// draws Lucide's palette in its place (lib/art/brand_marks.dart `brandMarksShown`). The same drawing is the plugin's
/// icon (assets/brands/lovart.svg, lib/plugins/brands.dart).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../art/app_icon.dart' show AppIcon;
import '../../art/brand_marks.dart' show brandMarksShown;
import '../../art/lucide.g.dart' show Lucide;

/// Where the mark is.
const String lovartMarkAsset = 'assets/plugins/lovart/lovart-mark.svg';

class LovartMark extends StatelessWidget {
  const LovartMark({super.key, this.size = 16, this.color});

  final double size;

  /// Its colour; the icon's or the text's around it when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    if (!brandMarksShown) return AppIcon(Lucide.palette, size: size, color: ink);
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(lovartMarkAsset, width: size, height: size, colorFilter: ColorFilter.mode(ink, BlendMode.srcIn), excludeFromSemantics: true),
    );
  }
}

/// The mark as a plugin's icon (lib/plugins/types.dart [PluginIcon]).
Widget lovartIcon(BuildContext context, double size) => LovartMark(size: size);
