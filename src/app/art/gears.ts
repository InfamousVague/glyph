/**
 * Gears that mesh, as geometry: where a gear's teeth point, the angle that
 * meshes one gear with another, and the outline of a spur gear to draw. For
 * the cogs that turn on the update card (art/WorkingGears.tsx).
 *
 * Every gear in one train shares a module `m` (the size of a tooth), so any
 * two can mesh: a gear of `n` teeth has a pitch circle of radius `n·m/2`, and
 * two meshing gears sit exactly the sum of their pitch radii apart. Speeds
 * follow from the pitch circles rolling on each other without slipping: an
 * outside mesh turns the other way at `n₁/n₂` the speed.
 *
 * The part that makes teeth interleave instead of crossing is the phase. A
 * gear's "tooth phase" in a direction is how many teeth, counted from its
 * tooth 0, lie between its own zero and that direction: `n·(ψ − θ)/2π`. A
 * whole number means a tooth points exactly that way. Where two gears meet,
 * a tooth of one has to face a gap of the other, so their phases at the
 * contact point must add up to a half. That sum is constant while the gears
 * turn at their rolling speeds, so a train set right at the start stays right
 * forever; the tests check it over time.
 *
 * Angles are radians on the screen: y points down, so a positive angle turns
 * clockwise, as CSS `rotate()` does.
 *
 * This held a whole-screen machine once - a planetary set, a rack, stacked
 * gears - for a thinking animation that has since gone (commit 18491db); what
 * the update card's three cogs need is all that is left.
 */

export type Hub = 'plain' | 'spokes' | 'holes';

const TAU = Math.PI * 2;
/** How steep a tooth's sides are: the classic 20° pressure angle. */
const FLANK = Math.tan((20 * Math.PI) / 180);

export const pitchRadius = (teeth: number, module: number): number => (teeth * module) / 2;

/** The tooth phase of a gear of `teeth` at `angle`, in the direction `direction`: whole where a tooth points that way. */
export function toothPhase(teeth: number, angle: number, direction: number): number {
  return (teeth * (direction - angle)) / TAU;
}

/** The start angle for a gear of `teeth` meshing on the outside of a gear (`teethA`, at `angleA`), placed in `direction` from it. */
export function outsidePhase(teethA: number, angleA: number, direction: number, teeth: number): number {
  const phaseA = toothPhase(teethA, angleA, direction);
  return direction + Math.PI - (TAU * (0.5 - phaseA)) / teeth;
}

// ---- shapes ------------------------------------------------------------------------------------

const f = (n: number): string => (Math.abs(n) < 1e-9 ? '0' : n.toFixed(2));
const polar = (radius: number, angle: number): string => `${f(radius * Math.cos(angle))} ${f(radius * Math.sin(angle))}`;

/**
 * One closed ring of teeth around the centre. Each tooth is straight sided at the pressure angle, a tip arc and a
 * root arc, and a hair thinner than half the pitch, so meshing teeth never quite touch.
 */
function toothOutline(teeth: number, module: number): string {
  const pitchR = pitchRadius(teeth, module);
  const tip = pitchR + module;
  const root = pitchR - 1.25 * module;
  const step = TAU / teeth;
  const halfAtPitch = (Math.PI * pitchR) / teeth / 2 - 0.05 * module;
  // Thinner toward the tip.
  const halfAt = (radius: number) => halfAtPitch - (radius - pitchR) * FLANK;
  const rootHalf = Math.min(halfAt(root) / root, step * 0.47);
  const tipHalf = Math.max(halfAt(tip) / tip, step * 0.1);
  // A tip arc turns the short way along the tooth; a root arc along the gap between teeth.
  let d = `M ${polar(root, -rootHalf)}`;
  for (let k = 0; k < teeth; k += 1) {
    const c = k * step;
    d += ` L ${polar(tip, c - tipHalf)} A ${f(tip)} ${f(tip)} 0 0 1 ${polar(tip, c + tipHalf)} L ${polar(root, c + rootHalf)}`;
    d += ` A ${f(root)} ${f(root)} 0 0 1 ${polar(root, c + step - rootHalf)}`;
  }
  return `${d} Z`;
}

const circle = (radius: number, cx = 0, cy = 0): string =>
  `M ${f(cx + radius)} ${f(cy)} A ${f(radius)} ${f(radius)} 0 1 1 ${f(cx - radius)} ${f(cy)} A ${f(radius)} ${f(radius)} 0 1 1 ${f(cx + radius)} ${f(cy)} Z`;

/** The cut-outs inside a gear's body: the axle hole, and spokes or a ring of holes when there is room for them. */
function hubCuts(hub: Hub, rim: number, module: number, count: number): string {
  const axle = Math.max(1.6 * module, rim * 0.14);
  let d = circle(axle);
  const inner = axle * 2.3;
  const outer = rim - 1.6 * module;
  if (outer - inner < 4 * module) return d;
  if (hub === 'spokes') {
    const half = 1.1 * module;
    for (let k = 0; k < count; k += 1) {
      const a0 = (k * TAU) / count;
      const a1 = ((k + 1) * TAU) / count;
      d += ` M ${polar(inner, a0 + half / inner)} L ${polar(outer, a0 + half / outer)} A ${f(outer)} ${f(outer)} 0 0 1 ${polar(outer, a1 - half / outer)}`;
      d += ` L ${polar(inner, a1 - half / inner)} A ${f(inner)} ${f(inner)} 0 0 0 ${polar(inner, a0 + half / inner)} Z`;
    }
  } else if (hub === 'holes') {
    const at = (inner + outer) / 2;
    const size = Math.min((outer - inner) * 0.34, ((Math.PI * at) / count) * 0.55);
    for (let k = 0; k < count; k += 1) d += ` ${circle(size, at * Math.cos((k * TAU) / count), at * Math.sin((k * TAU) / count))}`;
  }
  return d;
}

/** A spur gear, centred on 0,0, its tooth 0 pointing along +x: the outline and its cut-outs, for `fill-rule: evenodd`. */
export function spurPath(teeth: number, module: number, hub: Hub): string {
  const rim = pitchRadius(teeth, module) - 1.25 * module;
  return `${toothOutline(teeth, module)} ${hubCuts(hub, rim, module, teeth >= 30 ? 6 : teeth >= 20 ? 5 : 4)}`;
}
