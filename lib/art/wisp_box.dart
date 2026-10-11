import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'wisp_kit.dart';
import 'wisp_settings.dart';
import 'wisp_strips.dart';

/// What the two boxed wisps share: a board lane's foot (wisp_foot.dart) and the tab row's ends (wisp_sides.dart),
/// as art/wispBox.ts is what art/wispFoot.ts and art/wispSides.ts share.
///
/// On the page each is an SVG filter said in its element's own box (`objectBoundingBox`), so every length there is a
/// fraction of the box, made once per size and kept on a shelf (`filterShelf`). A shader has no units to pick and
/// nothing to keep: the numbers stay in pixels and are handed over each frame, so the fractions (`boxOf`'s `box`),
/// the shelf and the element builders have no counterpart here. One piece of that arithmetic does: [boxBend].

/// The box's diagonal over root two (`boxOf`'s `corner`): what the specification measures a displacement's throw
/// against in a box's own units, and what the web app divides its bend by.
double boxCorner(double wide, double tall) => math.sqrt((wide * wide + tall * tall) / 2);

/// The throw a boxed wisp really has in Chromium, in pixels, for a [bend] the web app means.
///
/// The web app writes `scale = bend / corner`, meaning [bend] px by the specification's rule. Chromium does not
/// follow that rule: it multiplies a displacement's `scale` in box units by the box's WIDTH and nothing else
/// (Blink's FEDisplacementMap carries a FIXME saying so), so what the phone draws is `bend × wide / corner`: 31px
/// where 28 was meant on a lane 390 by 300, and 20px where 14 was meant on a tab row 390 by 48. Measured against
/// Chromium's own pictures (test/art/wisp_parity_test.dart: the lane and the row each score closer with this than
/// with [bend] itself). The port draws what the phone draws.
double boxBend(double bend, double wide, double tall) => bend * wide / boxCorner(wide, tall);

/// Draws [child] through [smoke] over [strip] of it when there is a smoke, and under a plain [fade] of [fadeRect]
/// when there is not: what a boxed wisp's caller does on the page with a `filter` and a `mask-image` of its own.
class WispBoxed extends StatefulWidget {
  const WispBoxed({super.key, required this.build, required this.child});

  /// The strips for a box of this size; [still] is the phone asking for reduced motion.
  final List<WispStrip> Function(Size size, double ratio, bool still) build;
  final Widget child;

  @override
  State<WispBoxed> createState() => _WispBoxedState();
}

class _WispBoxedState extends State<WispBoxed> {
  final ValueNotifier<int> _ready = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WispSettings.instance.addListener(_changed);
    WispKit.load(seeds: const [3, 5]).then((_) {
      if (mounted) _ready.value += 1;
    });
  }

  @override
  void dispose() {
    WispSettings.instance.removeListener(_changed);
    _ready.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) return widget.child;
        final strips = WispStrips(strips: widget.build(constraints.biggest, media.devicePixelRatio, media.disableAnimations), repaint: _ready, child: widget.child);
        // Drawn the quick way, a box keeps its own picture: a row of tabs is painted again when a tab changes,
        // not on every frame the page under it scrolls, and a strip that was not painted again makes no pictures.
        // (The page and everything in the window were one picture, so a scroll drew the tabs' smoke anew sixty
        // times a second for tabs that had not moved.) Its strips know where they were laid: wisp_strips.dart.
        return wispQuick ? RepaintBoundary(child: strips) : strips;
      },
    );
  }
}
