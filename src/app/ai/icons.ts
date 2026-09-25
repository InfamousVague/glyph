import { BookOpenText, Bot, Brain, CircleCheck, CircleStop, Hourglass, ListChecks, LoaderCircle, PenLine, ScanText, Sparkles, SpellCheck, TriangleAlert, WandSparkles, type LucideIcon } from '@glacier/icons';
import type { RunKind } from './kinds.ts';
import type { RunPhase } from './runs.ts';

/**
 * The AI's icons, from the kit's set (@glacier/icons, lucide underneath):
 * one per phase of a run, one per kind. Matt chose the kit's set over the
 * app's own drawn strokes for these, so every AI state and action reads as
 * one family with the rest of the kit. The same icon means the same thing
 * wherever it shows - the strip, the log, a home card, a chip.
 */

export const PHASE_ICONS: Record<RunPhase, LucideIcon> = {
  queued: Hourglass,
  loading: LoaderCircle,
  prefill: BookOpenText,
  generating: PenLine,
  done: CircleCheck,
  stopped: CircleStop,
  failed: TriangleAlert,
};

export const KIND_ICONS: Record<RunKind, LucideIcon> = {
  format: WandSparkles,
  summarize: ScanText,
  enhance: Sparkles,
  fix: SpellCheck,
  shape: ListChecks,
  continue: PenLine,
  ask: Bot,
  review: Brain,
};

/** The phases whose icon turns: the model is at work and nothing else on the page is moving. */
export function spins(phase: RunPhase): boolean {
  return phase === 'loading';
}
