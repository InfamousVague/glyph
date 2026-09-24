import { finalCommandWords, planCommand, type Placement, type Plan } from './command.ts';
import { inferInstruction, type InferenceRun } from './instructionIntent.ts';
import { resolveTarget, type Candidate } from './route.ts';
import { literalMarkdown } from './instructionMutation.ts';
import { spokenListItems } from './spokenList.ts';

export type FinalInstruction<N extends Candidate> =
  | { kind: 'ordinary'; notice: string | null }
  | { kind: 'offer'; plan: Plan<N> }
  | { kind: 'rejected'; reason: string };

const permitted = <N extends Candidate>(plan: Plan<N>): boolean => plan.kind === 'place';

/**
 * Read one stopped recording. Live phrase commits never call this: an action
 * is possible only after Whisper has supplied the complete transcript.
 */
export async function classifyFinalTranscript<N extends Candidate & { note?: { body: string } }>(
  transcript: string,
  notes: readonly N[],
  startInference: (words: string) => InferenceRun = inferInstruction,
): Promise<FinalInstruction<N>> {
  // "Hey Ghost, add…", "Okay, um, add…": the lead-in is not the command, but
  // it must not turn the command back into a note of its own words.
  const words = finalCommandWords(transcript);
  if (words === null) return { kind: 'ordinary', notice: null };

  const deterministic = planCommand(words, { notes });
  // The rules heard a note name they could not match. The on-device model
  // reads the same words once more before that is the answer: it knows "my
  // note labeled Go" means Go when the rules' phrasing list does not.
  const unmatched = deterministic?.kind === 'no-note' ? `No unambiguous note matches “${deterministic.name}”. Nothing changed.` : null;
  if (deterministic && !unmatched) {
    return permitted(deterministic) ? { kind: 'offer', plan: deterministic } : { kind: 'rejected', reason: 'That command is not supported from a voice capture. Nothing changed.' };
  }

  // One constrained on-device pass, with this capture's complete transcript
  // and no phrase history or prior session context.
  const result = await startInference(words).done;
  if (result.status === 'unavailable') {
    return unmatched ? { kind: 'rejected', reason: unmatched } : { kind: 'ordinary', notice: 'Command understanding was unavailable; saved this recording as a note.' };
  }
  if (result.intent.action === 'none') return { kind: 'rejected', reason: unmatched ?? `That ${result.intent.reason} request was not changed.` };
  if (result.intent.action === 'create') return { kind: 'rejected', reason: unmatched ?? 'Creating a named note is not supported from a voice capture. Nothing changed.' };
  const target = resolveTarget(result.intent.target, notes);
  if (target.status !== 'resolved') {
    return { kind: 'rejected', reason: unmatched ?? (target.status === 'ambiguous' ? `“${result.intent.target}” matches more than one note. Nothing changed.` : `No note called “${result.intent.target}”. Nothing changed.`) };
  }
  const area = result.intent.placement;
  const listed = area === 'list' || area === 'tasks' || area === 'bugs';
  // A list the model heard is told apart by the app, not the model: its
  // items are literal text, one bullet each.
  const items = listed ? spokenListItems(result.intent.content).map(literalMarkdown) : [];
  const placement: Placement = {
    how: area === 'notes' ? 'paragraph' : listed ? 'item' : 'leave',
    task: area === 'tasks',
    many: items.length > 1,
    target: null,
    ...(area === 'bugs' ? { near: 'bugs' as const } : {}),
    ...(items.length > 1 ? { items } : {}),
  };
  return { kind: 'offer', plan: { kind: 'place', note: target.note, text: literalMarkdown(result.intent.content), ...placement } };
}
