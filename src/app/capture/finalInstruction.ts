import { isStandaloneCommandLike, planCommand, type Placement, type Plan } from './command.ts';
import { inferInstruction, type InferenceRun } from './instructionIntent.ts';
import { resolveTarget, type Candidate } from './route.ts';
import { literalMarkdown } from './instructionMutation.ts';

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
  const words = transcript.trim();
  if (!isStandaloneCommandLike(words)) return { kind: 'ordinary', notice: null };

  const deterministic = planCommand(words, { notes });
  if (deterministic) {
    if (deterministic.kind === 'no-note') return { kind: 'rejected', reason: `No unambiguous note matches “${deterministic.name}”. Nothing changed.` };
    return permitted(deterministic) ? { kind: 'offer', plan: deterministic } : { kind: 'rejected', reason: 'That command is not supported from a voice capture. Nothing changed.' };
  }

  // One constrained on-device pass, with this capture's complete transcript
  // and no phrase history or prior session context.
  const result = await startInference(words).done;
  if (result.status === 'unavailable') return { kind: 'ordinary', notice: 'Command understanding was unavailable; saved this recording as a note.' };
  if (result.intent.action === 'none') return { kind: 'rejected', reason: `That ${result.intent.reason} request was not changed.` };
  if (result.intent.action === 'create') return { kind: 'rejected', reason: 'Creating a named note is not supported from a voice capture. Nothing changed.' };
  const target = resolveTarget(result.intent.target, notes);
  if (target.status !== 'resolved') {
    return { kind: 'rejected', reason: target.status === 'ambiguous' ? `“${result.intent.target}” matches more than one note. Nothing changed.` : `No note called “${result.intent.target}”. Nothing changed.` };
  }
  const placement: Placement = {
    how: result.intent.placement === 'notes' ? 'paragraph' : result.intent.placement === 'bugs' || result.intent.placement === 'tasks' || result.intent.placement === 'list' ? 'item' : 'leave',
    task: result.intent.placement === 'tasks',
    many: false,
    target: null,
    ...(result.intent.placement === 'bugs' ? { near: 'bugs' as const } : {}),
  };
  return { kind: 'offer', plan: { kind: 'place', note: target.note, text: literalMarkdown(result.intent.content), ...placement } };
}
