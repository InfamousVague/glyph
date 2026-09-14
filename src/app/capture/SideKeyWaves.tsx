import { useEffect, useRef, useState } from 'react';
import { origin, type Spot } from './sideKey.ts';
import styles from './SideKeyWaves.module.css';

/**
 * Rings rising from where the side key is, while a recording from the side
 * key runs: a picture of sound, and a pointer at the key that stops it.
 *
 * The rings start just outside the screen's edge beside the key, so what
 * shows is arcs opening into the screen, the way sound leaves a speaker.
 * Three of them, a beat apart, in the page's faintest ink, behind the words.
 * The recorder's `--level` (0 to 1, the microphone) swells them a little
 * while someone talks, without a React render.
 * Decoration only. With reduced motion the rings stand still.
 *
 * `contained` draws inside its parent instead of over the whole screen, for
 * the preview in Settings.
 */
export function SideKeyWaves({ spot, contained = false }: { spot: Spot; contained?: boolean }) {
  const box = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });

  useEffect(() => {
    const el = box.current;
    if (!el) return undefined;
    const measure = () => setSize({ width: el.clientWidth, height: el.clientHeight });
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const { width, height } = size;
  const at = origin(spot, width, height, contained ? 4 : 12);
  // Far enough to cross most of the screen's width, never the whole screen.
  const reach = contained ? Math.max(width, height) * 0.9 : Math.min(Math.max(width, height) * 0.5, width * 1.1);

  return (
    <div
      ref={box}
      className={styles.waves}
      data-contained={contained ? '' : undefined}
      aria-hidden="true"
    >
      {width > 0 ? (
        <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
          <g className={styles.swell} style={{ transformOrigin: `${at.x}px ${at.y}px` }}>
            {[0, 1, 2].map((i) => (
              <circle
                key={i}
                className={styles.ring}
                cx={at.x}
                cy={at.y}
                r={reach}
                style={{ transformOrigin: `${at.x}px ${at.y}px`, animationDelay: `${i * 900}ms` }}
              />
            ))}
          </g>
          <circle className={styles.key} cx={at.x} cy={at.y} r={contained ? 10 : 22} style={{ transformOrigin: `${at.x}px ${at.y}px` }} />
        </svg>
      ) : null}
    </div>
  );
}
