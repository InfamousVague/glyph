import { findKeyword, type Plan } from '../capture/command.ts';
import { classifyFinalTranscript } from '../capture/finalInstruction.ts';
import type { InferenceRun } from '../capture/instructionIntent.ts';
import { appendToList, placeWords } from '../capture/listAppend.ts';
import { listTitle } from '../capture/instructionMutation.ts';
import type { Candidate } from '../capture/route.ts';
import type { Offer } from '../capture/take.ts';
import type { Note } from '../core/store.ts';
import type { RunKind } from './kinds.ts';

/**
 * One reader for an instruction, typed into the bar or spoken after "hey
 * Ghost": what the person wants done, and to which note.
 *
 * Matt chose one pipeline: a spoken instruction after Done goes through the
 * same reader, the same confirm card and the same strip as a typed one. So
 * the rules are here, once, in the order they bite:
 *
 * 1. The things the chips do, said in words - "fix the spelling", "make this
 *    a list", "summarise it", "carry on" - are those runs on the note on
 *    screen. Specific phrasings, read before anything else, so a model is
 *    never asked what a chip already knows.
 * 2. A command that names another note - "add eggs to Groceries", "make a
 *    new list called Comic books" - is read by the voice commands' reader
 *    (capture/finalInstruction.ts): its rules first and, for speech, the
 *    on-device model once when the rules heard a name they could not match
 *    (a misheard title is what the model is for; typed words are read by
 *    the rules alone, so an ask that starts "add a heading" never waits on
 *    the command model or is mistaken for a note by that name). What comes
 *    back is offered on the confirm card before anything is written, as it
 *    always was for a recording. A command that named a note there is no
 *    note for is refused, with its reason, rather than written into the
 *    note as words.
 * 3. Anything else typed is an ask about the note on screen. Spoken, it is an
 *    ask only after the keyword; without it, speech is the note's words.
 */

export type Read<N extends Candidate> =
  /** One of the chips' runs, on the note on screen. */
  | { kind: 'run'; run: RunKind; instruction?: string }
  /** A command on a note by name, to be confirmed first. */
  | { kind: 'command'; plan: Extract<Plan<N>, { kind: 'place' | 'create-list' }> }
  /** A command that could not be carried out, and why. */
  | { kind: 'reject'; reason: string }
  /** Free words about the note on screen. */
  | { kind: 'ask'; instruction: string }
  /** Not an instruction at all: spoken words with no keyword. `notice` says when the model could not be asked. */
  | { kind: 'words'; notice?: string };

/** The lead-ins a person says or types before the thing itself. */
const LEAD = /^\s*(?:(?:hey|hi|ok(?:ay)?|alright|all right|please|can you|could you|would you|will you|just|now|um+|uh+)[,.\s]+)+/i;

/** The words themselves: a keyword at the start and the lead-ins gone. Null when the keyword is inside, not first. */
export function bareWords(text: string, spoken: boolean): { words: string; keyed: boolean } | null {
  let words = text.trim().replace(/^[\s.,;:!?…"“]+/, '');
  let keyed = false;
  for (let pass = 0; pass < 3; pass += 1) {
    const before = words;
    const keyword = findKeyword(words);
    if (keyword) {
      if (keyword.before.trim()) return spoken ? null : { words: words.replace(LEAD, '').trim(), keyed: false };
      words = keyword.after;
      keyed = true;
    }
    words = words.replace(LEAD, '').trim();
    if (words === before) break;
  }
  return { words: words.replace(/[.!?]+$/, '').trim(), keyed };
}

/** The chips' runs, said in words: each rule is the phrasings that mean one kind and nothing else. */
const RUN_RULES: readonly [RunKind, RegExp][] = [
  ['fix', /^(?:(?:fix|correct|check|clean up)(?:\s+(?:the|my|its|any))?\s+(?:spelling|grammar|typos?|punctuation|mistakes)|spell\s?check|proof\s?read)/i],
  ['summarize', /^(?:summari[sz]e|sum (?:it |this )?up|give me (?:a |the )?summary|tl;?dr)\b/i],
  ['format', /^(?:format|reformat|tidy(?: (?:it|this|up))?(?: up)?|clean (?:it |this )?up|organi[sz]e(?: it| this)?)\b(?!.*\b(?:spelling|grammar)\b)/i],
  ['enhance', /^(?:enhance|expand(?: on)?(?: it| this)?|flesh (?:it |this )?out|elaborate|make (?:it|this) (?:fuller|longer|richer|better))\b/i],
  ['continue', /^(?:continue|carry on|keep (?:going|writing)|write more|go on|what(?:'s| is) next)\b/i],
  // "Make this a list", never "make a list called…", which is a new list by name (capture/command.ts CREATE_LIST).
  ['shape', /^(?:make|turn)\s+(?:this|it|the note|these|this note|everything)\s+(?:into\s+)?(?:a\s+|an\s+)?(?:list|to-?\s?do(?: list)?|task list|tasks|check\s?list|table|numbered list|bullet(?:ed)? list|bullets)\b/i],
];

/** The chip a phrasing means, or null. */
export function runOf(words: string): RunKind | null {
  return RUN_RULES.find(([, rule]) => rule.test(words))?.[0] ?? null;
}

/**
 * Reads an instruction. `notes` are the person's notes, for a command that
 * names one; `spoken` says the words were heard rather than typed, which
 * changes what counts as an ask.
 */
export async function readInstruction<N extends Candidate & { note?: { body: string } }>(text: string, notes: readonly N[], spoken = false): Promise<Read<N>> {
  const bare = bareWords(text, spoken);
  if (!bare || !bare.words) return spoken ? { kind: 'words' } : { kind: 'ask', instruction: text.trim() };
  const run = runOf(bare.words);
  if (run) return { kind: 'run', run };
  const decision = await classifyFinalTranscript(bare.words, notes, spoken ? undefined : noInference);
  if (decision.kind === 'offer') {
    if (decision.plan.kind === 'place' || decision.plan.kind === 'create-list') return { kind: 'command', plan: decision.plan };
    return { kind: 'reject', reason: 'That command is not one the note can take. Nothing changed.' };
  }
  // A command that named a note fails closed, with its reason; one the reader could make nothing of is an ask.
  const named = decision.kind === 'rejected' && /\bnote\b/i.test(decision.reason) && /called|matches|No unambiguous/i.test(decision.reason);
  if (named) return { kind: 'reject', reason: decision.reason };
  if (spoken && !bare.keyed) return { kind: 'words', ...(decision.kind === 'ordinary' && decision.notice ? { notice: decision.notice } : {}) };
  return { kind: 'ask', instruction: bare.words };
}

/** No model for typed words: the rules alone read them. */
const noInference = (): InferenceRun => ({ done: Promise.resolve({ status: 'unavailable', reason: 'Typed instructions are read by the rules alone.' }), cancel: () => undefined });

/** A confirmed plan as the card shows it: the words that would land, where. */
export function offerOf(plan: Extract<Plan<Candidate & { note?: Note }>, { kind: 'place' | 'create-list' }>): Offer<Note> | null {
  const span = { startMs: 0, endMs: 0 };
  if (plan.kind === 'create-list') return { kind: 'new', title: plan.title, lines: plan.items ?? [], span };
  const body = plan.note.note?.body;
  if (body === undefined) return null;
  const { kind: _kind, note: _note, text, ...placement } = plan;
  const placed = placeWords(body, text, placement);
  if (!placed.added.length) return null;
  return { kind: 'place', note: plan.note.note as Note, title: plan.note.title, text, placement, added: placed.added, into: placed.into, span };
}

/** A new list's body, as the voice commands make it: the title, then its items. */
export function listBody(title: string, items: readonly string[]): string {
  const named = listTitle(title);
  return items.length ? appendToList(named, items).body : named;
}
