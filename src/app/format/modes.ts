import { KINDS, type KindWords, type RunKind } from '../ai/kinds.ts';

/**
 * What the model can do to a note: the three asks behind the robot button.
 *
 * Matt: "add more features around the AI in addition to format, I want a
 * summarize and an enhance; make all of these buttons instead of the
 * segmented toggle, make a robot drop-down button for these options". Each
 * mode is one prompt (prompt.ts) and one output budget, and the same run
 * machine as every other kind (ai/runs.ts); the note's cog lists them
 * (editor/NoteSettings.tsx).
 *
 * They are the first three kinds of run, and their words are the kinds' own
 * (ai/kinds.ts). This module names the three as a set: the set the older
 * prompts and budgets serve.
 */

export type Mode = Extract<RunKind, 'format' | 'summarize' | 'enhance'>;

const IDS = new Set<RunKind>(['format', 'summarize', 'enhance']);

/** The three, in the order the cog shows them: Format, Summarize, Enhance. */
export const MODES: readonly (KindWords & { id: Mode })[] = KINDS.filter((kind): kind is KindWords & { id: Mode } => IDS.has(kind.id));
