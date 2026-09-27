import type { FinalPlan, Placement } from './command.ts';
import { placeWords } from './listAppend.ts';
import type { TakeCandidate, TakeNote } from './takeTypes.ts';

/**
 * "Shall I?": what a command read at Done will do, before it does anything.
 *
 * The reader at Done (ai/instruction.ts) carries out two commands, and each asks first: words for a note by name, and
 * a new list by name. A plan becomes an offer here - the note it names and the lines as they would land, or the list
 * and its items - which is what the confirm card draws (ai/ConfirmCard.tsx) and what the take carries out on a tap.
 *
 * Pure, so every plan's offer is a test.
 */

/** A command understood and waiting for a tap: what it will do, shown on the card. */
export type Offer<N extends TakeNote> =
  | { kind: 'place'; note: N; title: string; text: string; placement: Placement; added: string[]; into: 'list' | 'paragraph' }
  | { kind: 'new'; title: string; lines?: readonly string[] };

/** The offer `plan` makes, or null when there is nothing to offer: words that would add nothing to the note they name. */
export function offerFor<N extends TakeNote>(plan: FinalPlan<TakeCandidate<N>>): Offer<N> | null {
  if (plan.kind === 'create-list') return { kind: 'new', title: plan.title, ...(plan.items?.length ? { lines: plan.items } : {}) };
  const note = plan.note.note;
  const preview = placeWords(note.body, plan.text, plan);
  if (!preview.added.length) return null;
  return { kind: 'place', note, title: plan.note.title, text: plan.text, placement: plan, added: preview.added, into: preview.into };
}
