import { finalCommandWords, planCommand, type Placement, type Plan } from './command.ts';
import { inferInstruction, type InferenceRun } from './instructionIntent.ts';
import { resolveTarget, type Candidate } from './route.ts';
import { literalMarkdown } from './instructionMutation.ts';
import { spokenListItems } from './spokenList.ts';

export type FinalInstruction<N extends Candidate> =
  | { kind: 'ordinary'; notice: string | null }
  | { kind: 'offer'; plan: Plan<N> }
  | { kind: 'rejected'; reason: string };

/** A spoken command that says it is about a list. */
const LIST_WORDS = /\b(?:list|lists|items?|bullets?|bullet\s+points?|tasks?|to-?\s?dos?|check\s?list)\b/i;
/** A Markdown list line: the note already keeps a list. */
const LIST_LINE = /^\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)\S/m;
/** The most words an item has when nobody said "list": longer pieces are a sentence with commas in it. */
const SHORT_ITEM_WORDS = 4;
/** "We should…", "it was…": a piece that starts like a sentence is not an item. */
const SENTENCE_START = /^(?:i|i'm|we|we're|you|he|she|it|it's|they|this|that|there|so|if|when|because|after|before|with)\b/i;

/**
 * Items, when what is added is a list: the command asked for one, or the note
 * already is one and the words are several short things. The app decides this
 * from the person's words and the note, not from the model's answer, so a
 * small model that leaves its placement empty cannot turn a list into a block
 * of text.
 */
function listItems(words: string, content: string, body: string | undefined, asked: boolean): string[] | null {
  const wanted = asked || LIST_WORDS.test(words);
  if (!wanted && !LIST_LINE.test(body ?? '')) return null;
  const items = spokenListItems(content);
  if (items.length < 2) return null;
  if (!wanted && items.some((item) => item.split(/\s+/).length > SHORT_ITEM_WORDS || SENTENCE_START.test(item))) return null;
  return items;
}

/** What a finished recording may do once confirmed: add to a note, or make a new list (with its items). */
const permitted = <N extends Candidate>(plan: Plan<N>): boolean => plan.kind === 'place' || plan.kind === 'create-list';

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
    if (deterministic.kind === 'place' && deterministic.how === 'leave') {
      // "Add to Movies Jaws, Alien and Heat": a list note takes several things as several items.
      const items = listItems(words, deterministic.text, deterministic.note.note?.body, false);
      if (items) return { kind: 'offer', plan: { ...deterministic, how: 'item', many: true, items } };
    }
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
  // A list is told apart by the app, not the model: its items are literal
  // text, one bullet each, whether or not the model said "list".
  const said = area !== 'notes' ? listItems(words, result.intent.content, target.note.note?.body, area === 'list' || area === 'tasks' || area === 'bugs') : null;
  const listed = area === 'list' || area === 'tasks' || area === 'bugs' || said !== null;
  const items = (said ?? []).map(literalMarkdown);
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
