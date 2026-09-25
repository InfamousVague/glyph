/**
 * What the AI can do to a note: the kinds of run.
 *
 * The robot had three (format/modes.ts: Format, Summarize, Enhance), which
 * the More sheet still runs. A spoken instruction adds three more a person
 * reaches for daily - fix the spelling, make a shape of it, carry on
 * writing - and a free-text Ask for everything else (ai/instruction.ts).
 * The review after a recording is a kind too, so the strip and the log
 * speak of it in the same words as the rest. Each kind is a set of words the
 * screen says (its name, its hint, the verb while it runs, the word once it
 * has); its prompt and budget live with the prompts (format/prompt.ts, and
 * ai/prompts.ts for the newer kinds), and the run itself is the same
 * machine for all of them (ai/runs.ts).
 */

export type RunKind = 'format' | 'summarize' | 'enhance' | 'fix' | 'shape' | 'continue' | 'ask' | 'review';

export interface KindWords {
  id: RunKind;
  /** Its name, in the menu and the log. */
  label: string;
  /** What it does, under the word. */
  hint: string;
  /** "Formatting with Qwen 4B": the verb while it runs. */
  doing: string;
  /** "Formatted by Qwen 4B": once it has. */
  done: string;
}

export const KINDS: readonly KindWords[] = [
  { id: 'format', label: 'Format', hint: 'Tidy and organise, keeping every word that matters.', doing: 'Formatting', done: 'Formatted' },
  { id: 'summarize', label: 'Summarize', hint: 'The point of the note and its tasks, in far fewer words.', doing: 'Summarizing', done: 'Summarized' },
  { id: 'enhance', label: 'Enhance', hint: 'Every thought finished and the note made fuller, without inventing.', doing: 'Enhancing', done: 'Enhanced' },
  { id: 'fix', label: 'Fix spelling', hint: 'Spelling, grammar and punctuation, and not a word more.', doing: 'Fixing', done: 'Fixed' },
  { id: 'shape', label: 'Make a list', hint: 'Tasks, a list or a table out of what is there.', doing: 'Shaping', done: 'Shaped' },
  { id: 'continue', label: 'Continue', hint: 'Carries on from the last line in the note’s own voice.', doing: 'Writing', done: 'Written' },
  { id: 'ask', label: 'Ask', hint: 'Whatever you tell it to do with the note.', doing: 'Working', done: 'Done' },
  { id: 'review', label: 'Review', hint: 'Listens again with the careful model and checks what was heard.', doing: 'Reviewing', done: 'Reviewed' },
];

export function kindWords(kind: RunKind): KindWords {
  return KINDS.find((k) => k.id === kind) ?? KINDS[0]!;
}
