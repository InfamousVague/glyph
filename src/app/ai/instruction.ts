import { findKeyword, type Plan } from '../capture/command.ts';
import { classifyFinalTranscript } from '../capture/finalInstruction.ts';
import type { Candidate } from '../capture/route.ts';
import type { RunKind } from './kinds.ts';

/**
 * One reader for an instruction spoken after "hey Ghost": what the person
 * wants done, and to which note. (The note's AI bar took typed ones too
 * until it was removed, docs/DESIGN.md §122.)
 *
 * The rules are here, once, in the order they bite:
 *
 * 1. The runs, said in words - "fix the spelling", "make this a list",
 *    "summarise it", "carry on" - are those runs on the note on screen.
 *    Specific phrasings, read before anything else, so a model is never
 *    asked what a run's own words already say.
 * 2. A command that names another note - "add eggs to Groceries", "make a
 *    new list called Comic books" - is read by the voice commands' reader
 *    (capture/finalInstruction.ts): its rules first and the on-device model
 *    once when the rules heard a name they could not match (a misheard
 *    title is what the model is for). What comes back is offered on the
 *    confirm card before anything is written, as it always was for a
 *    recording. A command that named a note there is no note for is
 *    refused, with its reason, rather than written into the note as words.
 * 3. Anything else is an ask about the note on screen, but only after the
 *    keyword; without it, speech is the note's words.
 */

export type Read<N extends Candidate> =
  /** One of the runs, on the note on screen. */
  | { kind: 'run'; run: RunKind; instruction?: string }
  /** A command on a note by name, to be confirmed first. */
  | { kind: 'command'; plan: Extract<Plan<N>, { kind: 'place' | 'create-list' }> }
  /** A command that could not be carried out, and why. */
  | { kind: 'reject'; reason: string }
  /** Free words about the note on screen. */
  | { kind: 'ask'; instruction: string }
  /** Not an instruction at all: spoken words with no keyword. `notice` says when the model could not be asked. */
  | { kind: 'words'; notice?: string };

/** The lead-ins a person says before the thing itself. */
const LEAD = /^\s*(?:(?:hey|hi|ok(?:ay)?|alright|all right|please|can you|could you|would you|will you|just|now|um+|uh+)[,.\s]+)+/i;

/** The words themselves: a keyword at the start and the lead-ins gone. Null when the keyword is inside, not first. */
export function bareWords(text: string): { words: string; keyed: boolean } | null {
  let words = text.trim().replace(/^[\s.,;:!?…"“]+/, '');
  let keyed = false;
  for (let pass = 0; pass < 3; pass += 1) {
    const before = words;
    const keyword = findKeyword(words);
    if (keyword) {
      if (keyword.before.trim()) return null;
      words = keyword.after;
      keyed = true;
    }
    words = words.replace(LEAD, '').trim();
    if (words === before) break;
  }
  return { words: words.replace(/[.!?]+$/, '').trim(), keyed };
}

/** The runs, said in words: each rule is the phrasings that mean one kind and nothing else. */
const RUN_RULES: readonly [RunKind, RegExp][] = [
  ['fix', /^(?:(?:fix|correct|check|clean up)(?:\s+(?:the|my|its|any))?\s+(?:spelling|grammar|typos?|punctuation|mistakes)|spell\s?check|proof\s?read)/i],
  ['summarize', /^(?:summari[sz]e|sum (?:it |this )?up|give me (?:a |the )?summary|tl;?dr)\b/i],
  ['format', /^(?:format|reformat|tidy(?: (?:it|this|up))?(?: up)?|clean (?:it |this )?up|organi[sz]e(?: it| this)?)\b(?!.*\b(?:spelling|grammar)\b)/i],
  ['enhance', /^(?:enhance|expand(?: on)?(?: it| this)?|flesh (?:it |this )?out|elaborate|make (?:it|this) (?:fuller|longer|richer|better))\b/i],
  ['continue', /^(?:continue|carry on|keep (?:going|writing)|write more|go on|what(?:'s| is) next)\b/i],
  // "Make this a list", never "make a list called…", which is a new list by name (capture/command.ts CREATE_LIST).
  ['shape', /^(?:make|turn)\s+(?:this|it|the note|these|this note|everything)\s+(?:into\s+)?(?:a\s+|an\s+)?(?:list|to-?\s?do(?: list)?|task list|tasks|check\s?list|table|numbered list|bullet(?:ed)? list|bullets)\b/i],
];

/** The run a phrasing means, or null. */
export function runOf(words: string): RunKind | null {
  return RUN_RULES.find(([, rule]) => rule.test(words))?.[0] ?? null;
}

/** Reads a spoken instruction. `notes` are the person's notes, for a command that names one. */
export async function readInstruction<N extends Candidate & { note?: { body: string } }>(text: string, notes: readonly N[]): Promise<Read<N>> {
  const bare = bareWords(text);
  if (!bare || !bare.words) return { kind: 'words' };
  const run = runOf(bare.words);
  if (run) return { kind: 'run', run };
  const decision = await classifyFinalTranscript(bare.words, notes);
  if (decision.kind === 'offer') {
    if (decision.plan.kind === 'place' || decision.plan.kind === 'create-list') return { kind: 'command', plan: decision.plan };
    return { kind: 'reject', reason: 'That command is not one the note can take. Nothing changed.' };
  }
  // A command that named a note fails closed, with its reason; one the reader could make nothing of is an ask.
  const named = decision.kind === 'rejected' && /\bnote\b/i.test(decision.reason) && /called|matches|No unambiguous/i.test(decision.reason);
  if (named) return { kind: 'reject', reason: decision.reason };
  if (!bare.keyed) return { kind: 'words', ...(decision.kind === 'ordinary' && decision.notice ? { notice: decision.notice } : {}) };
  return { kind: 'ask', instruction: bare.words };
}
