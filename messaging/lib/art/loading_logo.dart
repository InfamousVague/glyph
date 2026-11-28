import 'dart:async';

import 'package:flutter/widgets.dart';

/// The logo of the splash the app opens with: a computer's while it looks for an update
/// (lib/desktop/ui/launch_splash.dart), a phone's while it loads (lib/ui/launch_gate.dart). Large, and still: for one
/// release (0.12.54) it was Matt's film of the logo turning, and of that he said the same day: "actually just do the
/// static image, the video doesn't look good".
///
/// The picture (assets/art/logo-large.png, cut from the app icon's art by tool/app_icon.py) is the white logo on
/// black, solid. It is drawn in [color]: how bright each dot of the picture is, is how much of the colour it gets,
/// and the black gets none. So it is the page's ink on whatever page is behind it, light or dark. The small mark
/// elsewhere in the app is see-through and tinted instead; at this size on a phone that left a faint line along the
/// edges of its place, and this way leaves none.
///
/// The picture is read for as long as the logo is shown and let go of after: at its size it is a few megabytes in
/// the pictures' cache, and nothing shows it again once the app is open.
class LoadingLogo extends StatefulWidget {
  const LoadingLogo({super.key, required this.width, required this.color, this.onShown});

  /// How wide its picture is drawn (the logo itself is [filled] of that); its height follows from [shape].
  final double width;

  /// What it is drawn in: the page's ink.
  final Color color;

  /// Told once, after the frame in which the logo is first on the page (true), or in which it turned out that this
  /// build of the app can't read it (false): what a splash counts its time from.
  final ValueChanged<bool>? onShown;

  static const asset = 'assets/art/logo-large.png';

  /// The picture's width over its height: 1240 by 958, the logo cut to its own edges with a little room round them.
  static const shape = 1240 / 958;

  /// How much of the picture's width the logo itself is: 1200 of the 1240.
  static const filled = 1200 / 1240;

  /// What draws a black and white picture in [color]: red, green and blue are the colour's own whatever the picture
  /// has there, and how solid a dot is, is how bright the picture is there (its red, the three being alike). The
  /// colour is taken as solid: how see-through it is, is drawn over this, not by it.
  static List<double> inked(Color color) => [
        0, 0, 0, 0, color.r * 255, //
        0, 0, 0, 0, color.g * 255, //
        0, 0, 0, 0, color.b * 255, //
        1, 0, 0, 0, 0, //
      ];

  @override
  State<LoadingLogo> createState() => _LoadingLogoState();
}

class _LoadingLogoState extends State<LoadingLogo> {
  bool _told = false;

  /// Says the logo is on the page, or can't be, once: after the frame being built now, which is the one it is in.
  void _tell(bool there) {
    if (_told) return;
    _told = true;
    final tell = widget.onShown;
    if (tell != null) WidgetsBinding.instance.addPostFrameCallback((_) => tell(there));
  }

  @override
  void dispose() {
    // Asked of the cache and not waited on: the picture under this is let go of first, so nothing is listening.
    unawaited(const AssetImage(LoadingLogo.asset).evict().catchError((_) => false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width, color = widget.color;
    final height = width / LoadingLogo.shape;
    Widget logo = ColorFiltered(
      colorFilter: ColorFilter.matrix(LoadingLogo.inked(color)),
      child: Image.asset(
        LoadingLogo.asset,
        width: width,
        height: height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        // Nothing until the picture is read (a moment): it simply appears.
        frameBuilder: (context, child, frame, sync) {
          if (frame == null && !sync) return const SizedBox.expand();
          _tell(true);
          return child;
        },
        // A build that can't read it leaves its place empty, where an error's picture would be drawn.
        errorBuilder: (context, _, _) {
          _tell(false);
          return const SizedBox.expand();
        },
      ),
    );
    // A see-through ink is the solid one, drawn that see-through.
    if (color.a < 1) logo = Opacity(opacity: color.a, child: logo);
    return SizedBox(width: width, height: height, child: logo);
  }
}
