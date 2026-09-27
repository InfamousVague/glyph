import { memo, useId, type CSSProperties } from 'react';
import { STEP_ICONS } from './icons.ts';
import type { StepId, Warmth } from './steps.ts';
import styles from './HotPhone.module.css';

/**
 * The phone at work: one SVG in the app's two inks, drawn over the pane of
 * scrolling words (scene/AtWork.tsx). Matt: "high contrast SVG iconography
 * with cool effects like a piping hot phone CPU".
 *
 * The case is the dotwork's faint line (the third ink), so the words read
 * through it and the contrast sits on the CPU: a die in full ink at the
 * phone's heart, its core a hatch that warms as a model works (state), rings
 * of dots blooming out of it and its pins lighting from the phone's real busy
 * figure and temperature (measured, scene/steps.ts `glowOf`), and above the
 * phone a column of stipple thinning upward, the heat off it in the rings'
 * own language. On the phone's screen, above the die, the working step's
 * icon drawn large: the same lucide family as the strip's (ai/icons.ts), so
 * the mark on the phone and the mark in the step list are one thing.
 *
 * Nothing here loops. The rings, the hatch and the column change by CSS
 * transition when their inputs change, and the mark fades in when the step
 * does; under reduced motion they step. The one looped motion on the scene is
 * the haze on the words, which the overlay owns. Memoised on its quantised
 * inputs, so the engine's eight reports a second redraw nothing here unless
 * a ring, a pin, the warmth or the step has changed.
 */

export interface HotPhoneProps {
  warmth: Warmth;
  /** Which ring the glow reaches, 0 to 5 (steps.ts `glowStepOf`). */
  glowStep: number;
  /** How many of the die's pins are lit. */
  litPins: number;
  /** How many pins the die has: the phone's cores. */
  pins: number;
  /** The working step, whose icon is drawn large on the screen; null once nothing is. */
  step: StepId | null;
  /** Reduced motion: no fade on the mark, no transitions. */
  still: boolean;
}

/** The die's centre. */
const CX = 120;
const CY = 250;
/** The rings: their radii, how many dots each has, and how big a dot is, innermost first. */
const RINGS = [
  { r: 48, dots: 16, dot: 1.8 },
  { r: 62, dots: 20, dot: 1.6 },
  { r: 78, dots: 26, dot: 1.4 },
  { r: 96, dots: 32, dot: 1.2 },
  { r: 116, dots: 40, dot: 1.0 },
];
/** The column above the phone: each row's height, its dots and their size, densest at the phone's edge. */
const COLUMN = [
  { y: -8, dots: 7, dot: 1.6 },
  { y: -17, dots: 5, dot: 1.45 },
  { y: -27, dots: 4, dot: 1.3 },
  { y: -37, dots: 3, dot: 1.15 },
  { y: -47, dots: 2, dot: 1.0 },
  { y: -56, dots: 1, dot: 0.9 },
];
const COLUMN_FROM = 96;
const COLUMN_TO = 144;

function ring(n: number, r: number, dots: number, dot: number) {
  return Array.from({ length: dots }, (_, i) => {
    // Each ring turned by half a step against the one inside it, so the dots never line up into spokes.
    const angle = ((i + (n % 2) * 0.5) / dots) * Math.PI * 2;
    return <circle key={i} cx={(CX + r * Math.cos(angle)).toFixed(2)} cy={(CY + r * Math.sin(angle)).toFixed(2)} r={dot} />;
  });
}

function HotPhoneDrawing({ warmth, glowStep, litPins, pins, step, still }: HotPhoneProps) {
  // Two scenes on one page (the bench beside a note, two note tabs) must not share a pattern or a clip. Letters and
  // digits only, as art/WispText.tsx does, since the id goes into `url(#…)` and React has punctuated it.
  const id = useId().replace(/[^a-zA-Z0-9]/g, '');
  const hatch = `${id}hatch`;
  const clip = `${id}clip`;
  const Mark = step ? STEP_ICONS[step] : null;
  const top = Math.ceil(pins / 2);
  const bottom = pins - top;

  return (
    <svg
      className={styles.phone}
      viewBox="0 -64 240 544"
      aria-hidden="true"
      focusable="false"
      data-warmth={warmth}
      data-still={still || undefined}
      style={{ '--glow-step': String(glowStep) } as CSSProperties}
    >
      <defs>
        <pattern id={hatch} patternUnits="userSpaceOnUse" width="4" height="4" patternTransform="rotate(45)">
          <line x1="0" y1="0" x2="0" y2="4" stroke="currentColor" strokeWidth="1.5" />
        </pattern>
        <clipPath id={clip}>
          <rect x="18" y="18" width="204" height="444" rx="26" />
        </clipPath>
      </defs>

      {/* The rings, measured: each is there once the glow reaches it. Kept inside the case. */}
      <g clipPath={`url(#${clip})`} fill="currentColor" data-part="rings">
        {RINGS.map((band, n) => (
          <g key={n} className={styles.ring} style={{ '--ring': String(n + 1) } as CSSProperties} data-ring={n + 1}>
            {ring(n + 1, band.r, band.dots, band.dot)}
          </g>
        ))}
      </g>

      {/* The heat off the phone's top, state: stipple thinning upward. */}
      <g className={styles.column} fill="currentColor" data-part="column">
        {COLUMN.map((row, n) => {
          const pitch = (COLUMN_TO - COLUMN_FROM) / row.dots;
          return Array.from({ length: row.dots }, (_, i) => <circle key={`${n}-${i}`} cx={(COLUMN_FROM + pitch * (i + 0.5) + (n % 2) * 2).toFixed(2)} cy={row.y} r={row.dot} />);
        })}
      </g>

      {/* The case: the dotwork's faint line, so the words read through it. */}
      <rect x="6" y="6" width="228" height="468" rx="34" fill="none" stroke="var(--app-ink-3)" strokeWidth="4" data-part="case" />
      <rect x="100" y="22" width="40" height="4" rx="2" fill="var(--app-ink-3)" />

      {/* The working step, drawn large on the screen. */}
      {Mark ? (
        <g key={step} className={styles.mark} data-mark={step}>
          <rect x="84" y="104" width="72" height="72" rx="12" fill="var(--app-paper)" stroke="currentColor" strokeWidth="3" />
          <Mark x={96} y={116} size={48} strokeWidth={1.75} />
        </g>
      ) : null}

      {/* The die: paper and full ink, solid, so a line passing behind it is hidden by it; its core the hatch that warms. */}
      <rect x="88" y="218" width="64" height="64" rx="4" fill="var(--app-paper)" stroke="currentColor" strokeWidth="4" data-part="die" />
      <rect x="102" y="232" width="36" height="36" fill="var(--app-paper)" />
      <rect x="102" y="232" width="36" height="36" fill={`url(#${hatch})`} className={styles.core} data-part="core" />

      {/* The pins, measured: one a core, lit one a busy core, top and bottom in turn. */}
      <g data-part="pins">
        {Array.from({ length: pins }, (_, k) => {
          const onTop = k % 2 === 0;
          const slot = Math.floor(k / 2);
          const across = 64 / (onTop ? top : bottom);
          const x = 88 + across * (slot + 0.5) - 1.5;
          const lit = k < litPins;
          return <rect key={k} x={x.toFixed(2)} y={onTop ? 206 : 282} width="3" height="12" fill={lit ? 'currentColor' : 'var(--app-paper)'} stroke="currentColor" strokeWidth="1.5" data-pin data-lit={lit || undefined} />;
        })}
      </g>
    </svg>
  );
}

export const HotPhone = memo(HotPhoneDrawing);
