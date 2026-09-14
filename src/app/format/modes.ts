/**
 * What the model can do to a note: the three asks behind the robot button.
 *
 * Matt: "add more features around the AI in addition to format, I want a
 * summarize and an enhance; make all of these buttons instead of the
 * segmented toggle, make a robot drop-down button for these options". Each
 * mode is one prompt (prompt.ts), one output budget, and one kept text per
 * note (results.ts); the pipeline, the view and the queue are shared.
 */

export type Mode = 'format' | 'summarize' | 'enhance';

export interface ModeWords {
  id: Mode;
  /** The word in the menu. */
  label: string;
  /** What it does, under the word. */
  hint: string;
  /** "Formatted by Qwen 4B": the result, done. */
  done: string;
  /** "Formatting with Qwen 4B": the result, arriving. */
  doing: string;
}

export const MODES: readonly ModeWords[] = [
  { id: 'format', label: 'Format', hint: 'Tidy and organise, keeping every word that matters.', done: 'Formatted', doing: 'Formatting' },
  { id: 'summarize', label: 'Summarize', hint: 'The point of the note and its tasks, in far fewer words.', done: 'Summary', doing: 'Summarizing' },
  { id: 'enhance', label: 'Enhance', hint: 'Every thought finished and the note made fuller, without inventing.', done: 'Enhanced', doing: 'Enhancing' },
];

export function modeWords(mode: Mode): ModeWords {
  return MODES.find((m) => m.id === mode) ?? MODES[0]!;
}
