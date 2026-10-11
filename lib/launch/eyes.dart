import 'dart:math' as math;
import 'dart:ui' show Offset;

/// The launch screen's ghost watching the bar go round it (`launch/eyes.ts`; Matt: "I want the ghost's eyes to follow
/// around the loading bar that moves around the icon mask ... fake eyes that look around and follow the loader"). The
/// picture's own eyes are painted out (assets/launch/ghost-icon-eyeless.webp) and two are drawn in their place, each
/// turned toward the bar.
///
/// Positions are in the launch drawing's units: a 128 box, the icon 96 of it at (16, 16), drawn from a 192 picture, so
/// a point of the picture is at 16 + p / 2.

/// Where the picture's eyes were: the centres of its two dark ovals (192 picture: (85.6, 101.1) and (139.2, 101.4)).
const List<Offset> eyes = [Offset(58.8, 66.6), Offset(85.6, 66.7)];

/// An eye's half-width and half-height: the ovals were 13 by 25 of the picture.
const double eyeRx = 3.3;
const double eyeRy = 6.3;

/// How far an eye moves toward what it looks at: a little more up and down than across, as the ovals are tall.
const double lookX = 2.6;
const double lookY = 3.4;

/// One lap of the bar, in ms: the pace the CSS chase had.
const double lapMs = 1150;

/// The bar's length, in hundredths of the ring (its dash, `stroke-dasharray: 14 86` on a pathLength of 100).
const double dash = 14;

/// Where an eye sits to look at [target]: moved toward it, as far as it goes, whatever the distance.
Offset lookAt(Offset eye, Offset target) {
  final dx = target.dx - eye.dx;
  final dy = target.dy - eye.dy;
  final distance = math.sqrt(dx * dx + dy * dy);
  if (distance < 0.001) return Offset.zero;
  return Offset((dx / distance) * lookX, (dy / distance) * lookY);
}

/// How far round the ring the bar's middle is at [ms], from 0 to 1, and the dash offset that puts the bar there.
({double middle, double offset}) barAt(double ms) {
  final lap = (((ms % lapMs) + lapMs) % lapMs) / lapMs;
  return (middle: (lap + dash / 200) % 1, offset: -lap * 100);
}

/// Once the app is open: how long the ghost takes to turn and look out of the screen, then how long its wink lasts.
const int lookOutMs = 240;
const int winkMs = 380;

/// The eye that winks: the one on the viewer's right.
const int winkingEye = 1;

/// How much of the way to its new place an eye goes in [ms]: it catches up in about a tenth of a second, as eyes do.
double easeFor(double ms) => 1 - math.exp(-math.max(0, ms) / 90);
