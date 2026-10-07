import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'wisp_box.dart';
import 'wisp_edge.dart';
import 'wisp_kit.dart';
import 'wisp_settings.dart';
import 'wisp_strips.dart';

/// The wisp edge's foot for a small box that scrolls inside a page: a board's lane with more cards than it shows
/// (art/wispFoot.ts). What slides off the lane's foot is bent by fractal noise and softened, the same smoke a page
/// makes under its header, where a plain fade used to be. Nothing about it moves: the cards scroll through the
/// noise, so a lane at rest costs nothing but its band.

/// The full-strength lip, how far above the lane's foot it sits, the soft ramp above it, and room above the ramp.
const double _band = 8;
const double _lift = 18;
const double _soft = 16;
const double _slack = 16;

/// The band at full size: the lip, the room above it, and the ramp's four sigma.
const double _full = _band + _lift + _soft * 4;

/// A short lane gets the same band, made smaller, down to this much of it; under that, the plain fade.
const double _least = 0.5;
const double _shortest = _full * _least + _slack;

/// The strip reaches this far below the lane, and the bend may throw a pixel this far outside it.
const double _below = 120;
const double _side = 40;

/// Smaller than the page's: a card's words are smaller than a page's.
const double _bend = 28;
const double _blur = 2.4;
const double _near = 2;

/// How much of the whole band a lane [height] tall carries (`fit`): 1 with room for all of it.
double wispFootFit(double height) => math.min(1, math.max(_least, (height - _slack) / _full));

/// The band's parts at a lane's own height, all scaled together (`band`).
({double band, double lift, double soft, double reach}) wispFootShape(double height) {
  final of = wispFootFit(height);
  return (band: _band * of, lift: _lift * of, soft: _soft * of, reach: _full * of + _slack);
}

/// The lane's own fade, in px, for a lane of [height] (`wispFootFade`): derived from the lip, since the fade must
/// start below where the band reaches full strength or it rubs out the bend it sits under.
double wispFootFade(double height) {
  final shape = wispFootShape(height);
  return shape.band + shape.lift - 4 * wispFootFit(height);
}

/// The smoke a lane [height] by [width] wears at its foot (`wispFoot`), or null where it is not wanted: switched off
/// ([WispSettings.wanted]), with reduced motion ([still]), on a lane too short to carry a band, and where the web
/// filter's region would not fit its budget. There the lane keeps its plain fade.
///
/// The frequency is per pixel, as every wisp's is; the web app's note on why it must not be made a fraction of the
/// box has no counterpart here, where nothing is a fraction of the box.
WispSmoke? wispFoot(double height, double width, {required double ratio, bool still = false, bool? wanted}) {
  if (!(wanted ?? WispSettings.instance.wanted) || still) return null;
  final tall = height.roundToDouble();
  final wide = width.roundToDouble() + _side * 2;
  if (tall < _shortest || wide <= _side * 2) return null;
  if (!withinWispBudget(wide, tall + _side * 2 + _below, ratio)) return null;
  final shape = wispFootShape(tall);
  return WispSmoke(
    seed: 3,
    frequency: const Offset(0.02, 0.07),
    noiseRect: wispFootLaneWithin(tall, width.roundToDouble()),
    lipB: tall - shape.band - shape.lift,
    soft: shape.soft,
    bend: boxBend(_bend, wide - _side * 2, tall),
    blur: _blur,
    near: const Offset(_near, _near),
    fade: WispFade(wholeUntil: tall - wispFootFade(tall), clearFrom: tall),
  );
}

/// The subregion a lane's bend and blur are worked out over (`reach`): the band's reach above the foot, and 40 below.
Rect wispFootLaneWithin(double height, double width) {
  final shape = wispFootShape(height);
  return Rect.fromLTWH(-_side, height - shape.reach, width + _side * 2, shape.reach + 40);
}

/// A lane's foot in smoke: wrap the lane's scroller, and say whether there is [more] below than it shows
/// (editor/boards/height.ts `laneFoot`, which sets the filter and the fade on a lane with `data-more`).
///
/// With more below, the foot smokes and fades over [wispFootFade]; where the smoke is not to be had ([wispFoot]
/// answers null) it fades over [plainFade], the stylesheet's `1.2em`, which the caller gives in px. With no more
/// below, the lane is drawn as it is.
class WispFoot extends StatelessWidget {
  const WispFoot({super.key, required this.more, required this.plainFade, required this.child});

  final bool more;
  final double plainFade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WispBoxed(
      build: (size, ratio, still) {
        if (!more) return const [];
        final smoke = wispFoot(size.height, size.width, ratio: ratio, still: still);
        if (smoke == null) {
          final fade = WispFade(wholeUntil: size.height - plainFade, clearFrom: size.height);
          return [WispFadeStrip(rect: Rect.fromLTRB(0, math.max(0, size.height - plainFade), size.width, size.height), fade: fade)];
        }
        final within = wispFootLaneWithin(size.height.roundToDouble(), size.width.roundToDouble());
        return [WispSmokeStrip(rect: Rect.fromLTRB(0, math.max(0, within.top), size.width, size.height), smoke: smoke, within: within)];
      },
      child: child,
    );
  }
}
