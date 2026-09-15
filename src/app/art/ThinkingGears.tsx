import { useEffect, useRef, useState } from 'react';
import { useThinking } from '../core/thinking.ts';
import { carrierPath, layoutGears, outerRadius, pitchRadius, rackPath, ringPath, spurPath, type Gear, type GearLayout } from './gears.ts';
import styles from './ThinkingGears.module.css';

/**
 * Gears turning over the whole screen while the model thinks (core/thinking.ts). Matt: "a thinking animation that
 * plays on the whole screen while the AI is thinking, gears on the page that all cleanly mesh together, different
 * kinds of gears going that shows that the AI is thinking".
 *
 * The machine is laid out for the screen (art/gears.ts), a new arrangement each time the thinking starts: a big
 * driving gear, a planetary set turned by its ring, spur gears of every size with plain, spoked and drilled hubs,
 * stacked gears on a couple of axles, and a rack sliding along the bottom under a pinion and an idler. Every pair
 * that touches meshes, tooth into gap, and stays meshed.
 *
 * Each gear is its own box turned by a Web Animation on `transform`, all started on one clock, so the phone's
 * compositor turns them without the page's main thread: the model is running on the same phone, and the gears
 * must cost it nothing. In the page's ink, faint, and over everything without catching a touch, so a Stop button
 * under them still works and a streaming thought can still be read. Fades in when the thinking starts and out when
 * it ends. With reduced motion the machine stands still.
 */

const FADE_MS = 420;
const TAU = Math.PI * 2;

export function ThinkingGears() {
  const thinking = useThinking();
  // Up while thinking, and for the fade after it.
  const [shown, setShown] = useState(false);
  const [leaving, setLeaving] = useState(false);
  useEffect(() => {
    if (thinking) {
      setShown(true);
      setLeaving(false);
      return undefined;
    }
    if (!shown) return undefined;
    setLeaving(true);
    const timer = window.setTimeout(() => {
      setShown(false);
      setLeaving(false);
    }, FADE_MS);
    return () => window.clearTimeout(timer);
  }, [thinking, shown]);
  return shown ? <Machine leaving={leaving} /> : null;
}

function Machine({ leaving }: { leaving: boolean }) {
  const [size, setSize] = useState(() => ({ width: window.innerWidth, height: window.innerHeight }));
  const [seed] = useState(() => Math.floor(Math.random() * 1e9));
  useEffect(() => {
    const resize = () => setSize({ width: window.innerWidth, height: window.innerHeight });
    window.addEventListener('resize', resize);
    return () => window.removeEventListener('resize', resize);
  }, []);
  const [layout, setLayout] = useState<GearLayout>(() => layoutGears(size.width, size.height, seed));
  useEffect(() => setLayout(layoutGears(size.width, size.height, seed)), [size.width, size.height, seed]);

  const stage = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const root = stage.current;
    if (!root || typeof root.animate !== 'function') return undefined;
    if (typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches) return undefined;
    const animations: Animation[] = [];
    const swingOptions: KeyframeAnimationOptions = { duration: layout.swingMs, iterations: Infinity, direction: 'alternate', easing: 'cubic-bezier(0.45, 0, 0.55, 1)' };
    for (const element of root.querySelectorAll<HTMLElement>('[data-gear]')) {
      const gear = layout.gears.find((g) => g.id === Number(element.dataset.gear));
      if (!gear) continue;
      const degrees = (gear.phase * 180) / Math.PI;
      if (gear.swing !== undefined) {
        // Swings from one end to the other with the rack: angle = phase + swing·s, s from −1 to 1.
        const reach = (gear.swing * 180) / Math.PI;
        animations.push(element.animate([{ transform: `rotate(${degrees - reach}deg)` }, { transform: `rotate(${degrees + reach}deg)` }], swingOptions));
      } else if (gear.omega !== 0) {
        const period = (TAU / Math.abs(gear.omega)) * 1000;
        const turn = Math.sign(gear.omega) * 360;
        animations.push(element.animate([{ transform: `rotate(${degrees}deg)` }, { transform: `rotate(${degrees + turn}deg)` }], { duration: period, iterations: Infinity, easing: 'linear' }));
      }
    }
    const rack = root.querySelector<HTMLElement>('[data-rack]');
    if (rack && layout.rack) {
      animations.push(rack.animate([{ transform: `translateX(${-layout.rack.amplitude}px)` }, { transform: `translateX(${layout.rack.amplitude}px)` }], swingOptions));
    }
    // One clock for the whole machine: every gear set going at the same instant, so what meshed at the start meshes still.
    const start = document.timeline.currentTime;
    if (typeof start === 'number') for (const animation of animations) animation.startTime = start;
    return () => animations.forEach((animation) => animation.cancel());
  }, [layout]);

  const { module, rack } = layout;
  const carriers = layout.gears.filter((g) => g.kind === 'ring');
  return (
    <div ref={stage} className={styles.stage} data-leaving={leaving || undefined} aria-hidden="true">
      {carriers.map((ring) => {
        const arm = pitchRadius(ring.teeth, module) - pitchRadius(12, module);
        const reach = arm + 2 * module;
        return (
          <svg key={`carrier-${ring.id}`} className={styles.part} style={{ left: ring.x - reach, top: ring.y - reach, width: reach * 2, height: reach * 2 }} viewBox={`${-reach} ${-reach} ${reach * 2} ${reach * 2}`}>
            <path className={styles.carrier} d={carrierPath(arm, module, 3)} />
          </svg>
        );
      })}
      {layout.gears.filter((g) => !g.top).map((gear) => (
        <GearPart key={gear.id} gear={gear} module={module} />
      ))}
      {layout.gears.filter((g) => g.top).map((gear) => (
        <GearPart key={gear.id} gear={gear} module={module} />
      ))}
      {rack ? (
        <svg
          data-rack=""
          className={styles.part}
          style={{ left: -rack.amplitude, top: rack.pitchY - 2 * module, width: layout.width + rack.amplitude * 2, height: layout.height - rack.pitchY + 4 * module }}
          viewBox={`${-rack.amplitude} ${-2 * module} ${layout.width + rack.amplitude * 2} ${layout.height - rack.pitchY + 4 * module}`}
        >
          <path className={styles.gear} d={rackPath(-rack.amplitude * 2, layout.width + rack.amplitude * 2, rack.pitch, rack.origin, module, layout.height - rack.pitchY + 3 * module)} />
        </svg>
      ) : null}
    </div>
  );
}

function GearPart({ gear, module }: { gear: Gear; module: number }) {
  const reach = outerRadius(gear, module) + 1;
  const d = gear.kind === 'ring' ? ringPath(gear.teeth, gear.outerTeeth ?? gear.teeth, module) : spurPath(gear.teeth, module, gear.hub);
  return (
    <svg
      data-gear={gear.id}
      className={styles.part}
      style={{ left: gear.x - reach, top: gear.y - reach, width: reach * 2, height: reach * 2, transform: `rotate(${(gear.phase * 180) / Math.PI}deg)` }}
      viewBox={`${-reach} ${-reach} ${reach * 2} ${reach * 2}`}
    >
      <path className={gear.top ? `${styles.gear} ${styles.top}` : styles.gear} d={d} />
    </svg>
  );
}
