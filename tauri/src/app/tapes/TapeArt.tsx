import { useEffect, useId, useRef, type CSSProperties, type Ref } from 'react';
import { HUB_R, LEFT_X, REEL_Y, RIGHT_X, TAPE_HUES, TAPE_MS, packRadii, reelTurn } from '../capture/tape.ts';
import { prefersStill } from '../core/motion.ts';
import styles from './TapeArt.module.css';

/**
 * A cassette, drawn flat in two inks: an ink shell with everything on it
 * printed in paper, and a paper label with everything on it printed in ink.
 * The tokens reverse with the theme, so the tape does too.
 *
 * `positionMs` sets how much tape is on the right reel - a note's length, or
 * where playback has got to - out of `lengthMs`, the whole tape. While
 * `playing`, the reels turn at tape speed over their own radii, straight
 * through refs so nothing re-renders per frame. (Shells coloured from the
 * note's id were tried and taken out the same day; Matt: "the color doesn't
 * work well".)
 *
 * Drawn `bare` on the home page's shelf (home/TapeShelf.tsx): the label paper
 * with its A mark and no words on it. At the shelf's 11rem the label's 13px
 * title would be 7px and its small print 4px, so the words go under the
 * cassette in real type instead (docs/DESIGN.md §127).
 *
 * Given a `hue`, one of the kit's ramps, it is drawn as the Flutter app draws
 * a meeting's cassette (lib/tapes/tape_art.dart `_paintHued`, Matt,
 * 2026-10-24: "give the cassettes different colors from the color token
 * palette as well with different opacities on different parts of the cassete
 * to build depth"): that hue at several strengths, flat, the screws and the
 * guides cut through. The shared meeting page (src/read/MeetingRead.tsx)
 * wears the hue the app gives the meeting, so the tape reads as the same one.
 */

interface TapeArtProps {
  /** Milliseconds of tape on the take-up reel: the note's length, or the playhead. */
  positionMs: number;
  /** How much tape the cassette holds: five minutes unless the note, or the shelf, is longer (capture/tape.ts). */
  lengthMs?: number;
  playing?: boolean;
  /** The label's first line. Not drawn on a `bare` cassette. */
  title?: string;
  /** Small print, top right of the label. */
  side?: string;
  /** Small print, bottom right of the label. */
  counter?: string;
  /** The label paper and its A mark, and no words: the words are set under the cassette in real type. */
  bare?: boolean;
  /** One of `TAPE_HUES`: the cassette in that hue, as the app draws a meeting's. Anything else is the two inks. */
  hue?: string;
  /** Whether the page is dark: where the hued cassette takes its light and its shade from. */
  dark?: boolean;
  className?: string;
  style?: CSSProperties;
}

export function TapeArt({ positionMs, lengthMs = TAPE_MS, playing = false, title, side, counter, bare = false, hue, dark = false, className, style }: TapeArtProps) {
  const supplyReel = useRef<SVGGElement>(null);
  const takeupReel = useRef<SVGGElement>(null);
  const angles = useRef({ supply: 0, takeup: 0 });
  const at = useRef({ positionMs, lengthMs });
  at.current = { positionMs, lengthMs };
  const packs = packRadii(positionMs, lengthMs);
  // The label's mask, one per cassette: eight on one page sharing `tape-label-mask` would all wear the first one's.
  // Letters and digits only, as art/WispText.tsx does, since the id goes into `url(#…)` and React has punctuated it.
  const maskId = `${useId().replace(/[^a-zA-Z0-9]/g, '')}-label`;

  useEffect(() => {
    if (!playing || prefersStill()) return undefined;
    let frame = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const dt = Math.min(100, now - last);
      last = now;
      // Counter-clockwise while the tape runs left to right along the bottom.
      const turn = reelTurn(at.current.positionMs, dt, at.current.lengthMs);
      angles.current.supply = (angles.current.supply - turn.supply) % 360;
      angles.current.takeup = (angles.current.takeup - turn.takeup) % 360;
      supplyReel.current?.setAttribute('transform', `rotate(${angles.current.supply.toFixed(2)} ${LEFT_X} ${REEL_Y})`);
      takeupReel.current?.setAttribute('transform', `rotate(${angles.current.takeup.toFixed(2)} ${RIGHT_X} ${REEL_Y})`);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [playing]);

  if (hue && (TAPE_HUES as readonly string[]).includes(hue)) {
    return (
      <HuedTape
        hue={hue}
        dark={dark}
        packs={packs}
        maskId={maskId}
        supplyReel={supplyReel}
        takeupReel={takeupReel}
        title={bare ? undefined : title}
        side={bare ? undefined : side}
        counter={bare ? undefined : counter}
        className={className}
        style={style}
      />
    );
  }

  return (
    <svg viewBox="0 0 320 204" className={`${styles.tape} ${className ?? ''}`} style={style} aria-hidden="true">
      <defs>
        <mask id={maskId}>
          <rect x="20" y="14" width="280" height="132" rx="8" fill="#fff" />
          <rect x="62" y="61" width="196" height="56" rx="28" fill="#000" />
        </mask>
      </defs>

      <rect x="2" y="2" width="316" height="200" rx="14" className={styles.shell} />

      <circle cx={LEFT_X} cy={REEL_Y} r={packs.supply} className={styles.pack} />
      <circle cx={RIGHT_X} cy={REEL_Y} r={packs.takeup} className={styles.pack} />
      <Reel ref={supplyReel} cx={LEFT_X} />
      <Reel ref={takeupReel} cx={RIGHT_X} />

      <path d={tapePath(packs.supply, packs.takeup)} className={styles.tapeLine} />
      <circle cx="50" cy="154" r="3.5" className={styles.onShell} />
      <circle cx="270" cy="154" r="3.5" className={styles.onShell} />

      <g mask={`url(#${maskId})`}>
        <rect x="20" y="14" width="280" height="132" rx="8" className={styles.paper} />
        <rect x="30" y="22" width="15" height="15" rx="2" className={styles.ink} />
        <text x="37.5" y="33.5" textAnchor="middle" className={styles.sideMark}>
          A
        </text>
        {!bare && title ? (
          <text x="53" y="34" className={styles.title}>
            {title}
          </text>
        ) : null}
        {!bare && side ? (
          <text x="290" y="33" textAnchor="end" className={styles.small}>
            {side}
          </text>
        ) : null}
        <line x1="30" y1="44" x2="290" y2="44" className={styles.rule} />
        <line x1="20" y1="129" x2="300" y2="129" className={styles.rule} />
        {!bare && counter ? (
          <text x="290" y="142" textAnchor="end" className={styles.small}>
            {counter}
          </text>
        ) : null}
      </g>

      <path d="M66 202 L84 166 L236 166 L254 202" className={styles.outline} />
      <rect x="146" y="177" width="28" height="10" rx="2" className={styles.outline} />
      <circle cx="104" cy="186" r="5" className={styles.outline} />
      <circle cx="216" cy="186" r="5" className={styles.outline} />
      {[
        [14, 14],
        [306, 14],
        [14, 190],
        [306, 190],
        [160, 194],
      ].map(([x, y]) => (
        <circle key={`${x}-${y}`} cx={x} cy={y} r="2.8" className={styles.onShell} />
      ))}
    </svg>
  );
}

/** From the left pack down round its guide, along the bottom, and up onto the right pack. */
function tapePath(supply: number, takeup: number): string {
  const leave = { x: LEFT_X - supply * 0.62, y: REEL_Y + supply * 0.78 };
  const arrive = { x: RIGHT_X + takeup * 0.62, y: REEL_Y + takeup * 0.78 };
  return `M${leave.x.toFixed(1)} ${leave.y.toFixed(1)} L46 156 L70 170 L250 170 L274 156 L${arrive.x.toFixed(1)} ${arrive.y.toFixed(1)}`;
}

/** A hub: a paper ring, the spindle hole, and the six teeth that show it turning. `ring` and `hole` are the hued tape's paints. */
function Reel({ cx, ref, ring, hole }: { cx: number; ref: Ref<SVGGElement>; ring?: CSSProperties; hole?: CSSProperties }) {
  return (
    <g ref={ref}>
      <circle cx={cx} cy={REEL_Y} r={HUB_R} className={ring ? undefined : styles.hub} style={ring} />
      <circle cx={cx} cy={REEL_Y} r={HUB_R - 5.5} className={hole ? undefined : styles.hubHole} style={hole} />
      {[0, 60, 120, 180, 240, 300].map((deg) => (
        <rect
          key={deg}
          x={cx - 1.4}
          y={REEL_Y - (HUB_R - 5.5)}
          width="2.8"
          height="3.4"
          className={ring ? undefined : styles.hub}
          style={ring}
          transform={`rotate(${deg} ${cx} ${REEL_Y})`}
        />
      ))}
      <circle cx={cx} cy={REEL_Y - HUB_R + 2.6} r="1.3" className={hole ? undefined : styles.hubHole} style={hole} />
    </g>
  );
}

/** `a` of `over` laid on `under`: Flutter's `Color.alphaBlend`, as CSS. */
const blend = (over: string, a: number, under: string) => `color-mix(in srgb, ${over} ${(a * 100).toFixed(1)}%, ${under})`;

/**
 * The cassette in one hue at several strengths (lib/tapes/tape_art.dart `_paintHued`, part for part): the shell a
 * wash of the hue, the guard at its foot a step into the shade, the window pale glass with the wound tape dark on it,
 * the label nearly paper with a band of the hue under the window, and the screws and the tape's guides cut through to
 * what is behind. The light is the lighter of paper and ink and the shade the darker, so it falls from above in either
 * theme.
 */
function HuedTape({
  hue,
  dark,
  packs,
  maskId,
  supplyReel,
  takeupReel,
  title,
  side,
  counter,
  className,
  style,
}: {
  hue: string;
  dark: boolean;
  packs: { supply: number; takeup: number };
  maskId: string;
  supplyReel: Ref<SVGGElement>;
  takeupReel: Ref<SVGGElement>;
  title?: string;
  side?: string;
  counter?: string;
  className?: string;
  style?: CSSProperties;
}) {
  const colour = `var(--glacier-${hue}-9)`;
  const paper = 'var(--app-paper)';
  const ink = 'var(--app-ink)';
  const light = dark ? ink : paper;
  const shade = dark ? paper : ink;
  const wound = blend(shade, dark ? 0.86 : 0.78, colour);
  const cutId = `${maskId}-cut`;
  const shellId = `${maskId}-shell`;
  const holes: [number, number, number][] = [[14, 14, 2.8], [306, 14, 2.8], [14, 190, 2.8], [306, 190, 2.8], [160, 194, 2.8], [50, 154, 3.5], [270, 154, 3.5]];
  const outline: CSSProperties = { fill: 'none', stroke: shade, strokeOpacity: 0.3, strokeWidth: 1.2, strokeLinejoin: 'round' };
  const recess: CSSProperties = { fill: shade, fillOpacity: 0.3 };
  return (
    <svg viewBox="0 0 320 204" className={`${styles.tape} ${className ?? ''}`} style={style} aria-hidden="true" data-hue={hue}>
      <defs>
        <mask id={maskId}>
          <rect x="20" y="14" width="280" height="132" rx="8" fill="#fff" />
          <rect x="62" y="61" width="196" height="56" rx="28" fill="#000" />
        </mask>
        <mask id={cutId}>
          <rect x="0" y="0" width="320" height="204" fill="#fff" />
          {holes.map(([x, y, r]) => (
            <circle key={`${x}-${y}`} cx={x} cy={y} r={r} fill="#000" />
          ))}
        </mask>
        <clipPath id={shellId}>
          <rect x="2" y="2" width="316" height="200" rx="14" />
        </clipPath>
      </defs>
      <g mask={`url(#${cutId})`}>
        <rect x="2" y="2" width="316" height="200" rx="14" style={{ fill: blend(colour, 0.55, paper) }} />
        <path d="M66 204 L84 166 L236 166 L254 204 Z" clipPath={`url(#${shellId})`} style={{ fill: shade, fillOpacity: 0.14 }} />
        <rect x="62" y="61" width="196" height="56" rx="28" style={{ fill: blend(light, dark ? 0.26 : 0.45, blend(colour, dark ? 0.6 : 0.4, paper)) }} />
        <circle cx={LEFT_X} cy={REEL_Y} r={packs.supply} style={{ fill: wound }} />
        <circle cx={RIGHT_X} cy={REEL_Y} r={packs.takeup} style={{ fill: wound }} />
        <Reel ref={supplyReel} cx={LEFT_X} ring={{ fill: light, fillOpacity: 0.92 }} hole={{ fill: blend(shade, 0.4, colour) }} />
        <Reel ref={takeupReel} cx={RIGHT_X} ring={{ fill: light, fillOpacity: 0.92 }} hole={{ fill: blend(shade, 0.4, colour) }} />
        <path d={tapePath(packs.supply, packs.takeup)} style={{ fill: 'none', stroke: wound, strokeWidth: 1.4, strokeLinejoin: 'round' }} />

        <g mask={`url(#${maskId})`}>
          <rect x="20" y="14" width="280" height="132" rx="8" style={{ fill: blend(colour, dark ? 0.1 : 0.07, paper) }} />
          <rect x="20" y="119" width="280" height="8" style={{ fill: colour, fillOpacity: 0.4 }} />
          <rect x="30" y="22" width="15" height="15" rx="2" style={{ fill: colour, fillOpacity: 0.75 }} />
          <text x="37.5" y="33.5" textAnchor="middle" className={styles.sideMark} style={{ fill: light }}>
            A
          </text>
          {title ? (
            <text x="53" y="34" className={styles.title}>
              {title}
            </text>
          ) : null}
          {side ? (
            <text x="290" y="33" textAnchor="end" className={styles.small}>
              {side}
            </text>
          ) : null}
          <line x1="30" y1="44" x2="290" y2="44" style={{ stroke: ink, strokeOpacity: 0.55, strokeWidth: 0.8 }} />
          <line x1="20" y1="129" x2="300" y2="129" style={{ stroke: ink, strokeOpacity: 0.55, strokeWidth: 0.8 }} />
          {counter ? (
            <text x="290" y="142" textAnchor="end" className={styles.small}>
              {counter}
            </text>
          ) : null}
        </g>
        <rect x="20" y="14" width="280" height="132" rx="8" style={{ fill: 'none', stroke: colour, strokeOpacity: 0.35, strokeWidth: 0.8 }} />

        <path d="M66 202 L84 166 L236 166 L254 202" style={outline} />
        <rect x="146" y="177" width="28" height="10" rx="2" style={recess} />
        <rect x="146" y="177" width="28" height="10" rx="2" style={outline} />
        {[104, 216].map((x) => (
          <g key={x}>
            <circle cx={x} cy="186" r="5" style={recess} />
            <circle cx={x} cy="186" r="5" style={outline} />
          </g>
        ))}
        {holes.map(([x, y, r]) => (
          <circle key={`rim-${x}-${y}`} cx={x} cy={y} r={r + 0.9} style={recess} />
        ))}
      </g>
    </svg>
  );
}
