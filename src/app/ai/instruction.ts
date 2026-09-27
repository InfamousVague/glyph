import { isBookBody } from '../book/book.ts';
import { findKeyword, findMisheard, isStandaloneCommandLike, LEAD_INS, onlyFiller, type FinalPlan } from '../capture/command.ts';
import { classifyFinalTranscript } from '../capture/finalInstruction.ts';
import { bareCommand, misheardShape } from '../capture/liveCommand.ts';
import { findNote } from '../capture/noteFind.ts';
import type { Candidate } from '../capture/route.ts';
import type { RunKind } from './kinds.ts';

/**
 * One reader for a spoken instruction, with "hey Ghost" before it or without
 * (docs/DESIGN.md §136): what the person wants done, and to which note. (The
 * note's AI bar took typed ones too until it was removed, docs/DESIGN.md §122.)
 *
 * The rules are here, once, in the order they bite:
 *
 * 1. The runs, said in words - "fix the spelling", "make this a list",
 *    "summarise it", "carry on" - are those runs on the note on screen.
 *    Specific phrasings, read before anything else, so a model is never
 *    asked what a run's own words already say. Without the keyword a run is
 *    the whole phrase and nothing more but its object: "fix the spelling of
 *    Kowalski on the sign" is a sentence, which the keyword makes the run.
 * 2. A command that names another note - "add eggs to Groceries", "make a
 *    new list called Comic books" - is read by the voice commands' reader
 *    (capture/finalInstruction.ts): its rules first and the on-device model
 *    once when the rules heard a name they could not match (a misheard
 *    title is what the model is for). What comes back is offered on the
 *    confirm card before anything is written, as it always was for a
 *    recording. A command that named a note there is no note for is
 *    refused, with its reason, after the keyword, since the person said it
 *    was a command; without it, the words are the note's, and the reason is
 *    the chip's.
 * 3. Anything else is an ask about the note on screen, but only after the
 *    keyword; without it, speech is the note's words.
 */

export type Read<N extends Candidate> =
  /** One of the runs, on the note on screen. */
  | { kind: 'run'; run: RunKind; instruction?: string }
  /** A command on a note by name, to be confirmed first. */
  | { kind: 'command'; plan: FinalPlan<N> }
  /** A command that could not be carried out, and why. */
  | { kind: 'reject'; reason: string }
  /** Free words about the note on screen. */
  | { kind: 'ask'; instruction: string }
  /**
   * Not an instruction at all: spoken words with no keyword. `notice` says when the model could not be asked, or why a
   * command said without the keyword was not carried out.
   */
  | { kind: 'words'; notice?: string };

/** The lead-ins a person says before the thing itself. */
const LEAD = /^\s*(?:(?:hey|hi|ok(?:ay)?|alright|all right|please|can you|could you|would you|will you|just|now|um+|uh+)[,.\s]+)+/i;

/**
 * The words themselves: a keyword at the start and the lead-ins gone. Null when the keyword is inside, not first;
 * filler before it ("Um, hey Ghost") leaves it first. A mishearing of it ("Hey, like, add…", "Hey goes, add…") is taken
 * off when a command follows (capture/command.ts `findMisheard`), but it is `misheard`, not `keyed`: it may start a
 * command for a note, which a card asks about, and never makes the words an ask or a run.
 */
export function bareWords(text: string): { words: string; keyed: boolean; misheard: boolean } | null {
  let words = text.trim().replace(/^[\s.,;:!?…"“]+/, '');
  let keyed = false;
  let misheard = false;
  for (let pass = 0; pass < 3; pass += 1) {
    const before = words;
    const keyword = findKeyword(words);
    const heard = keyword ?? (keyed || misheard ? null : findMisheard(words, (after) => isStandaloneCommandLike(after.replace(LEAD_INS, ''))));
    if (heard) {
      if (!onlyFiller(heard.before)) return null;
      words = heard.after;
      if (keyword) keyed = true;
      else misheard = true;
    }
    words = words.replace(LEAD, '').trim();
    // After the keyword, what a person says before the command goes too ("like, add…", "I want to add…"); without it,
    // those are the words ("And carry on tomorrow" is no run).
    if (keyed || misheard) words = words.replace(LEAD_INS, '').trim();
    if (words === before) break;
  }
  return { words: words.replace(/[.!?]+$/, '').trim(), keyed, misheard };
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

/** What may follow a run's words and leave it the run alone: its object ("summarise it for me", "tidy this up"). */
const RUN_REST = /^(?:\s+(?:it|this|that|the note|this note|everything|up|please|for me|now))*\s*$/i;

/**
 * The run a phrasing means, or null. With `whole`, the run and nothing more: without the keyword, "fix the spelling of
 * Kowalski on the sign" is a sentence, not a run on the note, since the rules are anchored at the front and would take
 * any sentence that opens with one of them.
 */
export function runOf(words: string, { whole = false }: { whole?: boolean } = {}): RunKind | null {
  for (const [kind, rule] of RUN_RULES) {
    const found = rule.exec(words);
    if (!found) continue;
    if (!whole || RUN_REST.test(words.slice(found[0].length))) return kind;
  }
  return null;
}

/** Reads a spoken instruction. `notes` are the person's notes, for a command that names one. */
export async function readInstruction<N extends Candidate & { note?: { body: string } }>(text: string, notes: readonly N[]): Promise<Read<N>> {
  const bare = bareWords(text);
  if (!bare || !bare.words) return { kind: 'words' };
  if (bare.misheard && !bare.keyed) {
    // "Hey, like, make sure the door is locked" is how people talk: after a mishearing of the keyword only a command
    // that passes the gate every bare phrase passes counts (capture/liveCommand.ts `bareCommand`), as it does for the
    // live reader, which its card asks about; anything else is the note's words, never a run, an ask or a refusal.
    const clear = misheardShape(bare.words, (reading) => {
      const found = findNote(reading.name, notes);
      if (found.status !== 'resolved') return false;
      const body = found.note.note?.body ?? '';
      return !isBookBody(body) && bareCommand(reading, { title: found.note.title, body }, found.score, { atStart: true });
    });
    if (!clear) return { kind: 'words' };
    const decision = await classifyFinalTranscript(bare.words, notes);
    return decision.kind === 'offer' ? { kind: 'command', plan: decision.plan } : { kind: 'words' };
  }
  const run = runOf(bare.words, { whole: !bare.keyed });
  if (run) return { kind: 'run', run };
  const decision = await classifyFinalTranscript(bare.words, notes);
  if (decision.kind === 'offer') return { kind: 'command', plan: decision.plan };
  // A command that named a note fails closed after the keyword, with its reason; without it the words are the note's,
  // and the reason is the chip's. One the reader could make nothing of is an ask.
  const named = decision.kind === 'rejected' && /\bnote\b/i.test(decision.reason) && /called|matches|No unambiguous/i.test(decision.reason);
  if (named) return bare.keyed ? { kind: 'reject', reason: decision.reason } : { kind: 'words', notice: decision.reason.replace(/\.\s*Nothing changed\.$/, ', so the words are saved as a note.') };
  if (!bare.keyed) return { kind: 'words', ...(decision.kind === 'ordinary' && decision.notice ? { notice: decision.notice } : {}) };
  return { kind: 'ask', instruction: bare.words };
}
