import { useEffect, useRef, useState } from 'react';
import { TAPE_MS, counter } from '../app/capture/tape.ts';
import { TapeArt } from '../app/tapes/TapeArt.tsx';
import { tapeDate } from '../app/tapes/tapeDate.ts';

/**
 * A meeting's tape, as a spoken note carries it (tapes/NoteTape.tsx): the cassette with its label, dated today, and
 * its length. A tap plays it and pauses it, as on the note, and the reels wind the tape across while it plays.
 *
 * It makes no sound: the site has no recording behind its meeting, of anybody (Matt: "make sure the recorded meeting
 * on the website doesn't use real audio"). Only the reels and the counter move. src/landing/silent.test.ts keeps it so.
 */
export function Tape({ title, lengthMs }: { title: string; lengthMs: number }) {
  const [playing, setPlaying] = useState(false);
  const [at, setAt] = useState(lengthMs);
  const from = useRef(0);
  useEffect(() => {
    if (!playing) return undefined;
    from.current = performance.now() - (at >= lengthMs ? 0 : at);
    let frame = 0;
    const tick = (now: number) => {
      const next = now - from.current;
      if (next >= lengthMs) {
        setAt(lengthMs);
        setPlaying(false);
        return;
      }
      setAt(next);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
    // Started from where it stood when Play was pressed, not restarted on every frame's position.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, lengthMs]);
  return (
    <button type="button" className="part-tape" aria-pressed={playing} aria-label={playing ? `Pause ${title}` : `Play ${title}, ${counter(lengthMs)}`} onClick={() => setPlaying((was) => !was)}>
      <TapeArt positionMs={playing ? at : lengthMs} lengthMs={Math.max(TAPE_MS, lengthMs)} playing={playing} title={title} side={tapeDate.format(Date.now()).toUpperCase()} counter={counter(playing ? at : lengthMs)} />
    </button>
  );
}
