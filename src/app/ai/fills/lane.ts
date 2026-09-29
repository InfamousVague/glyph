import { askingWords, type Blank } from '../../core/blanks.ts';
import { type CannotWork, type FactClock, workOut, type WorkedAnswer } from '../../core/fillFacts.ts';
import { screen, type Live } from '../../core/fillLive.ts';
import { shapeOf, type ShapeInfo } from './shape.ts';
import { lookupPlan, type LookupPlan } from './web.ts';

/**
 * Which lane a blank is in, decided by code before any model is asked (docs/DESIGN.md §145, 2.1): worked out by the
 * app, recognised and not finished by it, live (looked up on the web once pressed, or paused, or refused), or waiting
 * for the model. The editor draws by it and the queue runs by it, so the two never disagree. Pure.
 */

/** Whether this device may look a live blank up: on, held by Local only, or switched off in Settings. */
export type Lookups = 'on' | 'local-only' | 'off';

export type Lane =
  | { lane: 'worked'; worked: WorkedAnswer }
  | { lane: 'cannot'; cannot: CannotWork }
  | {
      lane: 'live';
      live: Live;
      plan: LookupPlan;
      /**
       * `look`, a press looks it up; `local-only`, Local only keeps it paused; `off`, Look up blanks online is off;
       * `none`, no public source answers it.
       */
      can: 'look' | 'local-only' | 'off' | 'none';
      info: ShapeInfo;
    }
  | { lane: 'model'; info: ShapeInfo };

export interface LaneOptions {
  clock: FactClock;
  /** The chosen model's horizon (core/ai.ts `learntUntil`). */
  learntUntil: number;
  lookups: Lookups;
}

/** A blank's lane. */
export function laneOf(blank: Blank, text: string, options: LaneOptions): Lane {
  // A translation is read first: `- Is the museum open on Sundays? {?in German}` asks for German words, not the hours,
  // and `- How many days until Christmas? {?in French}` for French ones, not the count.
  const shaped = shapeOf(blank, text);
  if (shaped.shape === 'language') return { lane: 'model', info: shaped };
  const worked = workOut(blank, text, options.clock);
  if (worked?.kind === 'answer') return { lane: 'worked', worked };
  if (worked?.kind === 'cannot') return { lane: 'cannot', cannot: worked };
  const asking = askingWords(blank, text);
  const live = screen(asking, options.learntUntil);
  const info = shaped;
  if (live) {
    const plan = lookupPlan(live.kind, asking, options.clock.now);
    const can = plan.kind === 'none' ? 'none' : options.lookups === 'on' ? 'look' : options.lookups;
    return { lane: 'live', live, plan, can, info };
  }
  return { lane: 'model', info };
}

/** Whether a press of Fill takes the blank: the model's, and a live one this device may look up. */
export function fillable(lane: Lane): boolean {
  return lane.lane === 'model' || (lane.lane === 'live' && lane.can === 'look');
}
