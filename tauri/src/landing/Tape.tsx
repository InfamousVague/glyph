import { useEffect, useRef, useState } from 'react';
import { TAPE_MS, counter } from '../app/capture/tape.ts';
import { TapeArt } from '../app/tapes/TapeArt.tsx';
import { tapeDate } from '../app/tapes/tapeDate.ts';

/**
 * A meeting's tape, as a spoken note carries it (tapes/NoteTape.tsx): the cassette with its label, dated today, and
 * its length. It plays from the moment the page shows it (Matt: "Make the cassette animate by default"), the reels
 * winding the tape across and the counter running, round again from the start when it reaches the end; a tap pauses it
 * where it is, and another plays it on from there. It rests while it is scrolled out of sight, and stands still for a
 * visitor whose device asks for less motion, until they tap it.
 *
 * It makes no sound: the site has no recording behind its meeting, of anybody (Matt: "make sure the recorded meeting
 * on the website doesn't use real audio"). Only the reels and the counter move. src/landing/silent.test.ts keeps it so.
 */
const stillPlease = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

export function Tape({ title, lengthMs }: { title: string; lengthMs: number }) {
  // Playing unless the visitor paused it, or their device asks for less motion.
  const [playing, setPlaying] = useState(() => !stillPlease());
  // On screen: a tape scrolled away does not keep the page drawing.
  const [seen, setSeen] = useState(true);
  const [at, setAt] = useState(0);
  const here = useRef<HTMLButtonElement>(null);
  const from = useRef(0);
  useEffect(() => {
    const button = here.current;
    if (!button || typeof IntersectionObserver !== 'function') return undefined;
    const watch = new IntersectionObserver(([entry]) => setSeen(entry?.isIntersecting ?? true));
    watch.observe(button);
    return () => watch.disconnect();
  }, []);
  const moving = playing && seen;
  useEffect(() => {
    if (!moving) return undefined;
    from.current = performance.now() - at;
    let frame = 0;
    const tick = (now: number) => {
      // Round again from the start at the end, as a tape on a loop.
      setAt((now - from.current) % lengthMs);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
    // Carried on from where it stood when it last stopped, not restarted on every frame's position.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [moving, lengthMs]);
  return (
    <button ref={here} type="button" className="part-tape" aria-pressed={playing} aria-label={playing ? `Pause ${title}` : `Play ${title}, ${counter(lengthMs)}`} onClick={() => setPlaying((was) => !was)}>
      <TapeArt positionMs={at} lengthMs={Math.max(TAPE_MS, lengthMs)} playing={moving} title={title} side={tapeDate.format(Date.now()).toUpperCase()} counter={counter(at)} />
    </button>
  );
}
