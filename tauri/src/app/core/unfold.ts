import { useEffect, type RefObject } from 'react';
import { answerHost } from './host.ts';
import { prefersStill } from './motion.ts';

/**
 * The unfold: the note opening with the phone.
 *
 * On a folding phone MainActivity streams the hinge angle (`window.__glyph.hinge`,
 * degrees, 0 closed to 180 flat) while Glyph is up. One UI hands the app from
 * the cover screen to the inner display at about 30 degrees, and from there
 * to flat is the moment this draws: the note is paper folded down its middle,
 * foreshortened with the crease's shadow in the valley, and it flattens as
 * the hinge does. The hand drives it, not a clock, so it runs exactly as fast
 * as the phone opens.
 *
 * Two rules keep it out of the way. It only ever moves forward: a hinge that
 * stops (flex mode, the phone propped at a hundred degrees) settles the note
 * flat on its own after a short pause rather than leaving it creased, and a
 * hinge closing never folds it back up. And it starts only on the way open:
 * a page that boots partway (the first reading it ever sees is mid-hinge)
 * joins in, and anything else sees the note flat.
 *
 * The hook writes `--unfold` and `data-unfolding` straight onto the screen's
 * element rather than through state: fifty readings a second re-rendering
 * the note screen is fifty re-renders for nothing, and the CSS does the rest.
 */

/** Where One UI hands the app over to the inner display. */
export const HANDOVER = 30;
/** Where the note is fully open. Flat is 180, but the eye is done well before. */
export const FLAT = 115;
/** No reading for this long mid-unfold and the hinge has stopped: settle. */
export const STALL_MS = 220;
/** How long a settle takes to reach flat. */
export const SETTLE_MS = 320;
/** No unfold runs longer than this, whatever the hinge is doing. */
export const LONGEST_MS = 1600;

/** How open the note is for a hinge angle: 0 at hand-over, 1 at flat, eased. */
export function progressAt(angle: number): number {
  const t = Math.min(1, Math.max(0, (angle - HANDOVER) / (FLAT - HANDOVER)));
  return t * t * (3 - 2 * t);
}

/**
 * The unfold as a state machine, time passed in so it runs the same under
 * test as on the phone. `reading` is a hinge angle; `tick` is time passing
 * without one. Both answer the progress to draw, 1 meaning flat and idle.
 */
export class Unfold {
  private last: number | null = null;
  private progress = 1;
  private startedAt: number | null = null;
  private readAt = 0;
  private settle: { at: number; from: number } | null = null;

  /** Whether an unfold is being drawn. */
  get active(): boolean {
    return this.startedAt !== null;
  }

  reading(angle: number, now: number): number {
    const before = this.last;
    this.last = angle;
    this.readAt = now;
    if (this.startedAt === null) {
      // Opening through the hand-over, or a page that woke up mid-hinge.
      const opening = angle > HANDOVER && (before === null ? angle < FLAT : before <= HANDOVER);
      if (!opening) return 1;
      this.startedAt = now;
      this.settle = null;
      this.progress = progressAt(angle);
      if (this.progress >= 1) this.end();
      return this.progress;
    }
    if (angle <= HANDOVER) {
      // Closed again before it finished: the cover screen is about to take
      // over, and a note folding back up is not a thing anyone asked to see.
      this.end();
      return 1;
    }
    // Once settling, the hinge no longer drives; the settle finishes. An
    // unfold that has dragged past its longest starts settling here too, so a
    // hinge inching open cannot hold the note creased for ever.
    if (this.settle || now - this.startedAt >= LONGEST_MS) return this.tick(now);
    this.progress = Math.max(this.progress, progressAt(angle));
    if (this.progress >= 1) this.end();
    return this.progress;
  }

  tick(now: number): number {
    if (this.startedAt === null) return 1;
    if (!this.settle && (now - this.readAt >= STALL_MS || now - this.startedAt >= LONGEST_MS)) {
      this.settle = { at: now, from: this.progress };
    }
    if (this.settle) {
      const t = Math.min(1, (now - this.settle.at) / SETTLE_MS);
      const eased = 1 - (1 - t) * (1 - t) * (1 - t);
      this.progress = this.settle.from + (1 - this.settle.from) * eased;
      if (t >= 1) this.end();
    }
    return this.progress;
  }

  /** Ends the unfold where it stands, flat. For a page that can no longer draw it. */
  abandon(): void {
    this.end();
  }

  private end(): void {
    this.startedAt = null;
    this.settle = null;
    this.progress = 1;
  }
}

/**
 * Draws the unfold onto `ref`'s element: `--unfold` runs 0 to 1 and
 * `data-unfolding` is present while it runs. Nothing happens where there is
 * no hinge, or where motion is turned down.
 */
export function useUnfold(ref: RefObject<HTMLElement | null>): void {
  useEffect(() => {
    if (prefersStill()) return undefined;
    const machine = new Unfold();
    let frame: number | null = null;
    let guard: number | null = null;

    const draw = (value: number) => {
      const el = ref.current;
      if (!el) return;
      if (machine.active && value < 1) {
        el.style.setProperty('--unfold', value.toFixed(3));
        el.dataset.unfolding = '';
      } else {
        el.style.removeProperty('--unfold');
        delete el.dataset.unfolding;
        if (guard !== null) {
          window.clearTimeout(guard);
          guard = null;
        }
      }
    };
    // Frames are how it settles, and a page that is not being shown gets no
    // frames. So a creased note is never left to wait for one: the phone
    // going dark mid-unfold flattens it at once, and a timer past the longest
    // an unfold can run flattens it whatever happened to the frames.
    const flatten = () => {
      machine.abandon();
      draw(1);
    };
    const loop = () => {
      frame = null;
      draw(machine.tick(performance.now()));
      if (machine.active) frame = requestAnimationFrame(loop);
    };
    const unanswer = answerHost('hinge', (angle) => {
      const wasActive = machine.active;
      draw(machine.reading(angle, performance.now()));
      if (!machine.active) return;
      if (frame === null) frame = requestAnimationFrame(loop);
      if (!wasActive) guard = window.setTimeout(flatten, LONGEST_MS + SETTLE_MS + 100);
    });
    const onHide = () => {
      if (document.visibilityState === 'hidden') flatten();
    };
    document.addEventListener('visibilitychange', onHide);
    return () => {
      unanswer();
      document.removeEventListener('visibilitychange', onHide);
      if (frame !== null) cancelAnimationFrame(frame);
      flatten();
    };
  }, [ref]);
}
