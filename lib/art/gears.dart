import 'dart:math' as math;

/// Gears that mesh, as geometry (art/gears.ts): where a gear's teeth point, the angle that meshes one gear with
/// another, and the outline of a spur gear to draw. For the cogs that turn on the update card (working_gears.dart).
///
/// Every gear in one train shares a module `m` (the size of a tooth), so any two can mesh: a gear of `n` teeth has a
/// pitch circle of radius `n·m/2`, and two meshing gears sit exactly the sum of their pitch radii apart. An outside
/// mesh turns the other way at `n₁/n₂` the speed. A gear's "tooth phase" in a direction is how many teeth, counted
/// from its tooth 0, lie between its own zero and that direction; where two gears meet, a tooth of one has to face
/// a gap of the other, so their phases at the contact point must add up to a half, and that sum is constant while
/// they turn at their rolling speeds.
///
/// Angles are radians on the screen: y points down, so a positive angle turns clockwise.

enum Hub { plain, spokes, holes }

const double _tau = math.pi * 2;

/// How steep a tooth's sides are: the classic 20° pressure angle.
final double _flank = math.tan(20 * math.pi / 180);

double pitchRadius(int teeth, double module) => teeth * module / 2;

/// The tooth phase of a gear of [teeth] at [angle], in the direction [direction]: whole where a tooth points that
/// way.
double toothPhase(int teeth, double angle, double direction) => teeth * (direction - angle) / _tau;

/// The start angle for a gear of [teeth] meshing on the outside of a gear ([teethA], at [angleA]), placed in
/// [direction] from it.
double outsidePhase(int teethA, double angleA, double direction, int teeth) {
  final phaseA = toothPhase(teethA, angleA, direction);
  return direction + math.pi - (_tau * (0.5 - phaseA)) / teeth;
}

// ---- shapes ------------------------------------------------------------------------------------

String _f(double n) => n.abs() < 1e-9 ? '0' : n.toStringAsFixed(2);
String _polar(double radius, double angle) => '${_f(radius * math.cos(angle))} ${_f(radius * math.sin(angle))}';

/// One closed ring of teeth around the centre. Each tooth is straight sided at the pressure angle, a tip arc and a
/// root arc, and a hair thinner than half the pitch, so meshing teeth never quite touch.
String _toothOutline(int teeth, double module) {
  final pitchR = pitchRadius(teeth, module);
  final tip = pitchR + module;
  final root = pitchR - 1.25 * module;
  final step = _tau / teeth;
  final halfAtPitch = (math.pi * pitchR) / teeth / 2 - 0.05 * module;
  // Thinner toward the tip.
  double halfAt(double radius) => halfAtPitch - (radius - pitchR) * _flank;
  final rootHalf = math.min(halfAt(root) / root, step * 0.47);
  final tipHalf = math.max(halfAt(tip) / tip, step * 0.1);
  // A tip arc turns the short way along the tooth; a root arc along the gap between teeth.
  final d = StringBuffer('M ${_polar(root, -rootHalf)}');
  for (var k = 0; k < teeth; k++) {
    final c = k * step;
    d.write(' L ${_polar(tip, c - tipHalf)} A ${_f(tip)} ${_f(tip)} 0 0 1 ${_polar(tip, c + tipHalf)} L ${_polar(root, c + rootHalf)}');
    d.write(' A ${_f(root)} ${_f(root)} 0 0 1 ${_polar(root, c + step - rootHalf)}');
  }
  d.write(' Z');
  return d.toString();
}

String _circle(double radius, [double cx = 0, double cy = 0]) =>
    'M ${_f(cx + radius)} ${_f(cy)} A ${_f(radius)} ${_f(radius)} 0 1 1 ${_f(cx - radius)} ${_f(cy)} A ${_f(radius)} ${_f(radius)} 0 1 1 ${_f(cx + radius)} ${_f(cy)} Z';

/// The cut-outs inside a gear's body: the axle hole, and spokes or a ring of holes when there is room for them.
String _hubCuts(Hub hub, double rim, double module, int count) {
  final axle = math.max(1.6 * module, rim * 0.14);
  final d = StringBuffer(_circle(axle));
  final inner = axle * 2.3;
  final outer = rim - 1.6 * module;
  if (outer - inner < 4 * module) return d.toString();
  if (hub == Hub.spokes) {
    final half = 1.1 * module;
    for (var k = 0; k < count; k++) {
      final a0 = (k * _tau) / count;
      final a1 = ((k + 1) * _tau) / count;
      d.write(' M ${_polar(inner, a0 + half / inner)} L ${_polar(outer, a0 + half / outer)} A ${_f(outer)} ${_f(outer)} 0 0 1 ${_polar(outer, a1 - half / outer)}');
      d.write(' L ${_polar(inner, a1 - half / inner)} A ${_f(inner)} ${_f(inner)} 0 0 0 ${_polar(inner, a0 + half / inner)} Z');
    }
  } else if (hub == Hub.holes) {
    final at = (inner + outer) / 2;
    final size = math.min((outer - inner) * 0.34, ((math.pi * at) / count) * 0.55);
    for (var k = 0; k < count; k++) {
      d.write(' ${_circle(size, at * math.cos((k * _tau) / count), at * math.sin((k * _tau) / count))}');
    }
  }
  return d.toString();
}

/// A spur gear, centred on 0,0, its tooth 0 pointing along +x: the outline and its cut-outs, for an even-odd fill.
String spurPath(int teeth, double module, Hub hub) {
  final rim = pitchRadius(teeth, module) - 1.25 * module;
  return '${_toothOutline(teeth, module)} ${_hubCuts(hub, rim, module, teeth >= 30 ? 6 : teeth >= 20 ? 5 : 4)}';
}
