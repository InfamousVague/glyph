import { useEffect, useRef, useState, type RefObject } from 'react';
import { prefersStill } from '../core/motion.ts';
import styles from './VoiceWaves.module.css';
import { onVoiceLevel, paceRings, type RingPacer } from './voiceLevel.ts';

const SVG = 'http://www.w3.org/2000/svg';
/** More than this many rings on screen at once is a smear, not a picture of a voice. */
const MOST_RINGS = 9;

/**
 * Rings rising from behind the microphone in the recorder's top line while a
 * recording runs: a picture of sound, and a mark that the mic is live.
 *
 * They rose from the screen's edge beside the side key before, and only for a
 * recording the key had started: the app guessed where the key was from the
 * phone's model and a Settings card let the guess be moved. Matt: "move the
 * ripple waves effect to show behind the mic icon in app when recording", so
 * they are every recording's now, and their source is the mic drawn in the top
 * line (`anchor`), measured where it is - nothing to guess and nothing to set.
 * In the page's faintest ink, over the words and under the top line, so the
 * line and its mic sit in front of them.
 *
 * The voice sends them out (Matt: "make the ripple … react to the levels of my
 * voice as I record the note"). In a pause, one faint ring every 2.7 seconds,
 * so the screen shows it is listening; talking, rings go out as often as five
 * a second, each wider, brighter, thicker and quicker the louder the voice
 * (voiceLevel.ts `paceRings`). Rings are added and animated straight in the
 * DOM (Web Animations), never through a React render. Decoration only. With
 * reduced motion three rings stand still.
 */
export function VoiceWaves({ anchor }: { anchor: RefObject<HTMLElement | null> }) {
  const box = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [at, setAt] = useState({ x: 0, y: 0 });

  // The layer's size, and the mic's centre in it: the layer is fixed to the viewport, so the mic's viewport box is its place.
  useEffect(() => {
    const el = box.current;
    if (!el) return undefined;
    const measure = () => {
      setSize({ width: el.clientWidth, height: el.clientHeight });
      const mic = anchor.current?.getBoundingClientRect();
      if (mic) setAt({ x: mic.left + mic.width / 2, y: mic.top + mic.height / 2 });
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    if (anchor.current) observer.observe(anchor.current);
    window.addEventListener('resize', measure);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, [anchor]);

  const { width, height } = size;
  // Far enough to cross most of the screen's width, never the whole screen.
  const reach = Math.min(Math.max(width, height) * 0.5, width * 1.1);
  const rings = useRef<SVGGElement>(null);
  const still = prefersStill();

  useEffect(() => {
    const group = rings.current;
    if (!group || width === 0 || still || typeof group.animate !== 'function') return undefined;
    let level = 0;
    const off = onVoiceLevel((next) => (level = next));
    const pacer: RingPacer = { smooth: 0, lastRingAt: -Infinity };
    let frame = 0;
    const tick = (now: number) => {
      const shape = paceRings(pacer, level, now);
      if (shape && group.childElementCount < MOST_RINGS) {
        const ring = document.createElementNS(SVG, 'circle');
        ring.setAttribute('class', styles.ring ?? '');
        ring.setAttribute('cx', String(at.x));
        ring.setAttribute('cy', String(at.y));
        ring.setAttribute('r', String(reach));
        ring.style.transformOrigin = `${at.x}px ${at.y}px`;
        ring.style.strokeWidth = `${shape.stroke}px`;
        group.appendChild(ring);
        const animation = ring.animate(
          [
            { transform: 'scale(0.04)', opacity: 0 },
            { opacity: shape.opacity, offset: 0.1 },
            { opacity: shape.opacity * 0.32, offset: 0.6 },
            { transform: `scale(${shape.reach})`, opacity: 0 },
          ],
          { duration: shape.durationMs, easing: 'cubic-bezier(0.2, 0.6, 0.35, 1)', fill: 'forwards' },
        );
        animation.onfinish = () => ring.remove();
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => {
      off();
      cancelAnimationFrame(frame);
      group.replaceChildren();
    };
  }, [width, height, at.x, at.y, reach, still]);

  return (
    <div ref={box} className={styles.waves} aria-hidden="true" data-testid="voice-waves">
      {width > 0 ? (
        <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
          <g ref={rings}>
            {still
              ? [0, 1, 2].map((i) => (
                  <circle key={i} className={`${styles.ring} ${styles.still}`} cx={at.x} cy={at.y} r={reach} style={{ transformOrigin: `${at.x}px ${at.y}px` }} />
                ))
              : null}
          </g>
        </svg>
      ) : null}
    </div>
  );
}
