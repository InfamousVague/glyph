import { BookOpenText, Brain, CircleCheck, Ear, LoaderCircle, PenLine, type LucideIcon } from '@glacier/icons';
import type { StepId } from './steps.ts';

/**
 * One icon a step, from the kit's set (@glacier/icons, lucide underneath), the same family as the strip's
 * (ai/icons.ts): drawn small in the step list and large on the phone's screen (scene/HotPhone.tsx), so the mark on
 * the phone and the mark in the list are one thing.
 */
export const STEP_ICONS: Record<StepId, LucideIcon> = {
  listen: Ear,
  load: LoaderCircle,
  read: BookOpenText,
  think: Brain,
  write: PenLine,
  done: CircleCheck,
};
