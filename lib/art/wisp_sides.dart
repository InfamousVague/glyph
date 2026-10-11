import 'package:flutter/widgets.dart';

import 'wisp_box.dart';
import 'wisp_edge.dart';
import 'wisp_kit.dart';
import 'wisp_settings.dart';
import 'wisp_strips.dart';

/// The wisp for a row that scrolls sideways: the tabs (art/wispSides.ts). What runs off either end is bent by
/// fractal noise and softened, the smoke a page makes under its header turned on its side, with the noise in tall
/// streaks as the header's runs in long ones. The noise stays where it is and the tabs scroll through it, so the
/// edge churns while they move and rests when they stop.

/// The full-strength lip at each end, and the soft ramp in from it.
const double _band = 6;
const double _soft = 12;

/// How far outside the row the bend may throw a pixel, and so how far the web filter's region reaches round it.
const double _side = 24;

/// How far in from each end the lip sits: where the tabs are still drawn.
const double _in = 14;

/// Smaller than a page's: a tab's words are small.
const double _bend = 14;
const double _blur = 1.6;
const double _near = 1.5;

/// The fade a row's open end wears under the smoke, and the longer one it wears alone on a desktop
/// (notes/NoteTabs.module.css `--tab-fade-start`, `--tab-fade-end`).
const double wispSidesFade = 12;
const double wispSidesFadePlain = 32;

/// The smoke a row [width] by [height] wears with its [start] and [end] open (`wispSides`), or null where it is
/// not wanted: switched off, with reduced motion ([still]), with neither end open, on a desktop (a filter on a row
/// that scrolls stalled the Mac's engine; its ends keep the plain fade, a little longer), on a row too small to
/// carry a band, and where the web filter's region would not fit its budget.
WispSmoke? wispSides(double width, double height, bool start, bool end, {required double ratio, bool still = false, bool? wanted, double fadeStart = wispSidesFade, double fadeEnd = wispSidesFade}) {
  if (!(wanted ?? WispSettings.instance.wanted) || (!start && !end)) return null;
  if (still) return null;
  if (wispDraw() == WispDraw.mask || wispHead() == WispHead.blur) return null;
  final wide = width.roundToDouble(), tall = height.roundToDouble();
  if (wide <= (_band + _soft) * 2 || tall <= 0) return null;
  if (!withinWispBudget(wide + _side * 2, tall + _side * 2, ratio)) return null;
  return WispSmoke(
    seed: 5,
    frequency: const Offset(0.07, 0.035),
    noiseRect: wispSidesWithin(wide, tall),
    lipA: start ? _in + _band : null,
    lipB: end ? wide - _in - _band : null,
    soft: _soft,
    axis: Axis.horizontal,
    bend: boxBend(_bend, wide, tall),
    blur: _blur,
    near: const Offset(_near, _near),
    fade: wispSidesMask(wide, start, end, fadeStart, fadeEnd),
  );
}

/// The web filter's region: the row's own box grown by its margin on all four sides.
Rect wispSidesWithin(double width, double height) => Rect.fromLTWH(-_side, -_side, width + _side * 2, height + _side * 2);

/// The row's own `mask-image`: each open end clear at the edge and whole a fade's length in.
WispFade wispSidesMask(double width, bool start, bool end, double fadeStart, double fadeEnd) =>
    WispFade(clearUntil: start ? 0 : -1e9, wholeFrom: start ? fadeStart : -1e9, wholeUntil: end ? width - fadeEnd : 1e9, clearFrom: end ? width : 1e9);

/// A row's open ends in smoke: wrap the row that scrolls, and say which ends have tabs past them
/// (notes/useTabOutline.ts, which marks the ends and sets the filter; notes/NoteTabs.module.css, which fades them).
///
/// An open end smokes and fades over [fade]; where the smoke is not to be had ([wispSides] answers null: a desktop,
/// reduced motion, the wisp switched off) it fades over [plainFade] on a desktop and [fade] elsewhere, as the
/// stylesheet has it.
class WispSides extends StatelessWidget {
  const WispSides({super.key, required this.start, required this.end, this.fade = wispSidesFade, this.plainFade = wispSidesFadePlain, required this.child});

  final bool start, end;
  final double fade, plainFade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WispBoxed(
      build: (size, ratio, still) {
        if (!start && !end) return const [];
        final whole = Offset.zero & size;
        final smoke = wispSides(size.width, size.height, start, end, ratio: ratio, still: still, fadeStart: fade, fadeEnd: fade);
        if (smoke != null) return wispSmokeStrips(rect: whole, smoke: smoke, within: wispSidesWithin(size.width.roundToDouble(), size.height.roundToDouble()));
        final length = wispHead() == WispHead.blur ? plainFade : fade;
        final mask = wispSidesMask(size.width, start, end, length, length);
        return [
          if (start) WispFadeStrip(rect: Rect.fromLTWH(0, 0, length, size.height), fade: mask, axis: Axis.horizontal),
          if (end) WispFadeStrip(rect: Rect.fromLTWH(size.width - length, 0, length, size.height), fade: mask, axis: Axis.horizontal),
        ];
      },
      child: child,
    );
  }
}
