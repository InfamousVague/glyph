import { findKeyword, findMisheard, LEAD_INS, onlyFiller, withoutPayloadLead } from './command.ts';
import { FIND, headingsOf, nameScore, nameWords, titleKind } from './noteFind.ts';

/**
 * Hearing a command in one committed phrase, as it is said: the keyword, and the shapes of "words for a note you name".
 * Pure grammar, with no notes: which readings a phrase has is decided here, and which note a name means is noteFind.ts's
 * and the live reader's (liveRoute.ts).
 *
 * Whisper commits a phrase after a short quiet, so a phrase is not a sentence: nearly every one ends with Whisper's own
 * full stop, whether or not the speaker stopped there. A phrase-final stop is therefore never a separator. A stop, a
 * comma, a colon or "that says" inside the phrase is.
 *
 * A command needs no keyword (docs/DESIGN.md §136; Matt: "Remove the function which expects hey ghost before
 * commands"). Without one, or after a mishearing of it, a phrase is a command only through one gate, `bareCommand`:
 * the plainest shapes, a note named clearly, the evidence that a note was meant, and its words in the same breath.
 * Both readers ask it, so a mishearing means the same to each.
 */

// ---- the keyword --------------------------------------------------------------------------------

export interface HeardKeyword {
  /** Words before the keyword in the phrase: the take's own, unless they are only filler ("Um,"). */
  before: string;
  /** What followed it: the command. */
  after: string;
  /** A mishearing of the keyword ("Hey, like", "Hey goes"), which counts only when a command follows. */
  misheard: boolean;
}

/** The keyword in a phrase, said anywhere in it, or misheard at its very start when `reads` says a command follows. */
export function hearKeyword(text: string, reads: (words: string) => boolean): HeardKeyword | null {
  const said = findKeyword(text);
  if (said) return { before: said.before, after: said.after, misheard: false };
  const misheard = findMisheard(text, (after) => reads(commandWords(after)));
  return misheard ? { before: '', after: misheard.after, misheard: true } : null;
}

/** A phrase that is only a keyword's lead, which Whisper cut from its keyword: "Hey." | "Ghost, add…". */
export function onlyLead(text: string): boolean {
  return /^\s*(?:hey|hi|ok(?:ay)?|so)[\s.,!?]*$/i.test(text);
}

/** A phrase that is only filler, said before anything ("Okay.", "Um."). */
export function onlyFillerPhrase(text: string): boolean {
  return onlyFiller(text) && /\p{L}/u.test(text);
}

/** What Whisper writes for a silence: never the start of a note. */
export function silenceLine(text: string): boolean {
  return /^\s*(?:thank you|thanks for watching|bye|you)[\s.!]*$/i.test(text);
}

/** The command's words, the lead-ins gone ("like, add…", "can you add…", "I want to add…"). */
export function commandWords(text: string): string {
  let words = text.replace(/^[\s.,;:!?…"“]+/, '');
  for (let pass = 0; pass < 3; pass += 1) {
    const before = words;
    words = words.replace(LEAD_INS, '').trim();
    if (words === before) break;
  }
  return words;
}

/** A phrase-final stop taken off: never a separator, never "stopped". */
export function withoutFinalStop(text: string): string {
  return text.replace(/[\s.!?…]+$/, '').trim();
}

/** What introduced a payload ("The note is …"), taken off it. */
export function payloadOf(text: string): string {
  return withoutPayloadLead(text).trim();
}

// ---- the readings ------------------------------------------------------------------------------

export interface Reading {
  /** Which shape of command (docs/DESIGN.md §126). */
  shape: 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 'S';
  /** The note's name as heard. */
  name: string;
  /** What goes in it, when it was said in the same phrase; '' when it is still to come. */
  payload: string;
  /** Words after the command that are the take's own again: what follows a full stop after a shape-4 name. */
  trailing: string;
  /**
   * Everything said after the verb (and a noun and preposition before the name), as said: what a name that finds no
   * note gives back when the grammar cannot tell where it ends (liveRoute.ts `keptWords`).
   */
  tail: string;
  /** What the noun said: a to-do, an item, a paragraph, or a note left where it fits. */
  placing: 'task' | 'item' | 'paragraph' | 'leave';
  /** "…under Kitchen in Home jobs": the heading whose list the words go in. */
  heading: string | null;
  /** "Move this to …": the take goes there. */
  move: boolean;
  /**
   * "Move this to …" or "switch this to …" as said: the move said plainly, which a phrase with no keyword must be. "Go
   * to work", "carry on in the garage" and "move it to …" are `move` but not this: bare, they are words ("it" is a
   * send's word, takeBack.ts).
   */
  plainMove: boolean;
  /** "For Groceries, …", "House TODOs: …": the name came first. */
  nameFirst: boolean;
  /** "New note". */
  newNote: boolean;
  /** "Remind me to …": for the note being written to. */
  self: boolean;
  /** The name ended at a separator inside the phrase, so it can grow no more. */
  stopped: boolean;
  /** A note or item noun was said ("a note", "a to-do"): it was plainly about a note. */
  noun: boolean;
  /** The name ends at a split point the grammar chose, not at a separator or the phrase's end. */
  split: boolean;
  /**
   * The name starts with a verb a note is never named by ("call the electrician"): a name only when it finds a title
   * that starts with the same word, clearly (liveRoute.ts), and otherwise what to do.
   */
  verb: boolean;
}

const VERB = String.raw`(?:add|put|stick|write|jot(?:\s+down)?|append|save|file|pop|drop|leave|make|note|send)`;
const TASK_NOUN = String.raw`(?:tasks?|to-?\s?dos?|todos?|reminders?)`;
const ITEM_NOUN = String.raw`(?:items?|entry|entries|bullets?|points?|things?|bugs?|issues?)`;
const NOTE_NOUN = String.raw`(?:note|line|comment|memo)`;
const NOUN = String.raw`(?:(?:list\s+)?${ITEM_NOUN}|${TASK_NOUN}|${NOTE_NOUN})`;
const NOUN_OPEN = String.raw`(?:(?:a|an|another|one\s+more|some|new)\s+)?(?:(?:quick|little|short|new)\s+)?`;
const PREP = String.raw`(?:to|in|into|onto|on|for|under)`;
const OWNER = String.raw`(?:(?:the|my|our)\s+)?`;
const LABEL = String.raw`(?:(?:page|note|list)\s+(?:for|called|named|titled|label(?:l)?ed)\s+)?`;
/** What ends a name inside a phrase: a comma, colon, semicolon or full stop, or "that says". */
const SEP = /\s*[,:;]\s*|\.\s+|\s+(?:that\s+says|which\s+says|that\s+reads|saying|to\s+say)\s+/i;

const SHAPE_1 = new RegExp(String.raw`^${VERB}\s+${NOUN_OPEN}(${NOUN})\s+${PREP}\s+${OWNER}${LABEL}(.+)$`, 'i');
const SHAPE_2 = new RegExp(String.raw`^(?:(?:a|an)\s+)?(?:new|another)\s+(${NOUN})\s+(?:for|to|on|in|into)\s+${OWNER}(.+)$`, 'i');
const SHAPE_3 = new RegExp(String.raw`^${VERB}\s+(?:(?:this|these|the\s+following)\s+)?${PREP}\s+${OWNER}${LABEL}(.+)$`, 'i');
const SHAPE_4_VERB = new RegExp(String.raw`^${VERB}\s+`, 'i');
const PREP_SPLIT = new RegExp(String.raw`\s+${PREP}\s+`, 'gi');
const SHAPE_5 = new RegExp(String.raw`^(move|switch|carry\s+on|continue|go|jump)\s+(?:(this|it|everything|these)\s+)?(?:over\s+)?(?:back\s+)?(?:to|into|onto|on|in)\s+${OWNER}${LABEL}([^,:;.]+)$`, 'i');
const SHAPE_6 = [
  new RegExp(String.raw`^for\s+${OWNER}([^,:;.]+?)\s*,\s*(.+)$`, 'i'),
  new RegExp(String.raw`^on\s+${OWNER}([^,:;.]+?)\s*,?\s+(?:add|put)\s+(.+)$`, 'i'),
  /^([^,:;.]{2,40}):\s*(.+)$/i,
];
const SHAPE_7 = /^(?:(?:a|an)\s+)?(?:new|start\s+a\s+new|another)\s+(?:notes?|node)$/i;
const SHAPE_8 = new RegExp(String.raw`^${VERB}\s+(?:(.+?)\s+)?(?:under|in)\s+${OWNER}(.+?)\s+(?:in|on)\s+${OWNER}(.+)$`, 'i');
const SELF = [
  { rule: /^(?:remind\s+me\s+to|i\s+need\s+to|i\s+have\s+to|don['’]?t\s+forget\s+to)\s+(.+)$/i, task: true },
  { rule: /^add\s+(?:(?:a|an)\s+)?(?:to-?\s?do|todo|task)\s*[:,]\s*(.+)$/i, task: true },
  { rule: /^add\s+(?:(?:a|an)\s+)?item\s*[:,]\s*(.+)$/i, task: false },
  { rule: /^(?:add|put)\s+(.+?)\s+here$/i, task: false },
];

/**
 * Verbs a note is never named by, so a "name" that starts with one is what to do: "make a note to call the
 * electrician" is the to-do "Call the electrician", not a note called "call the electrician".
 */
const NOT_NAMES =
  /^(?:call|fix|book|buy|get|ask|email|send|pick|make|check|clean|take|see|find|try|set|sort|look|do|go|pay|ring|text|order|tell|remember|finish|write|read)\b/i;

/** A command for something other than words: a table, a board, a book or a chapter, which the live reader leaves alone. */
const NOT_WORDS =
  /^(?:(?:add|make|create|start|put|insert|draw|build|begin|new)\s+(?:(?:a|an|another|one|the)\s+)?(?:new\s+)?(?:table|board|kanban|book|chapter)s?\b|(?:make|turn|change)\s+(?:this|it|the\s+note|this\s+note|the\s+list|this\s+list)\s+(?:into\s+)?(?:a\s+)?(?:kanban\s+)?(?:board|kanban|table|book)\b)/i;

/** Whether a name can be one: not "a table", not "the top", and not a thing to do (`NOT_NAMES`). */
export function nameable(name: string): 'name' | 'verb' | 'not' {
  const said = name.trim();
  if (/^(?:a|an)\s/i.test(said)) return 'not';
  if (/^(?:the\s+)?(?:top|bottom|end|start|beginning|middle)\b/i.test(said)) return 'not';
  if (NOT_NAMES.test(said)) return 'verb';
  return 'name';
}

/** A reading, with the fields a shape leaves alone. */
function reading(shape: Reading['shape'], name: string, over: Partial<Reading> = {}): Reading {
  return { shape, name: name.trim(), payload: '', trailing: '', tail: '', placing: 'leave', heading: null, move: false, plainMove: false, nameFirst: false, newNote: false, self: false, stopped: false, noun: false, split: false, verb: false, ...over };
}

/** A reading for a name alone, with nothing said for it: "Not this note" offering the others for that name. */
export function namedAs(name: string): Reading {
  return reading(3, name);
}

function placingOf(noun: string): Reading['placing'] {
  if (new RegExp(`^${TASK_NOUN}$`, 'i').test(noun.trim())) return 'task';
  if (new RegExp(`^(?:list\\s+)?${ITEM_NOUN}$`, 'i').test(noun.trim())) return 'item';
  return 'leave';
}

/**
 * A name and what follows it: up to a separator when there is one (`stopped`), and otherwise the whole of it, and
 * every split of its first one to six words with the rest as the payload.
 */
function namesIn(tail: string): { name: string; payload: string; stopped: boolean; split: boolean }[] {
  const sep = SEP.exec(tail);
  if (sep && sep.index > 0) return [{ name: tail.slice(0, sep.index), payload: tail.slice(sep.index + sep[0].length).trim(), stopped: true, split: false }];
  const words = tail.trim().split(/\s+/);
  const out = [{ name: tail.trim(), payload: '', stopped: false, split: false }];
  for (let k = 1; k <= Math.min(6, words.length - 1); k += 1) out.push({ name: words.slice(0, k).join(' '), payload: words.slice(k).join(' '), stopped: false, split: true });
  return out;
}

/** "a list item", "a task", "a note that says" at the front of what is added: the kind of thing, not the thing. */
const THING_NOUN = new RegExp(String.raw`^${NOUN_OPEN}(${NOUN})(?:\s+(?:about|that\s+says|saying|which\s+says|called|:|,))?\s+`, 'i');
const BARE_THING = /^(?:this|that|it|everything|these|those|them)$/i;
/** "Add a paragraph to Groceries that says…": the kind of words, which go on the note's end, not the words. */
const PARAGRAPH = /^(?:(?:a|an|another|one\s+more|new)\s+)?(?:(?:new|short|quick|little)\s+)?paragraph$/i;

/**
 * Every reading of a command's words (the keyword and the lead-ins already gone, `commandWords`). Empty when the words
 * are not a command for a note: "fix the spelling", "put the dates in a table", "add a summary to the top".
 */
export function readRoute(text: string): Reading[] {
  // "Add it to Groceries instead": the word after the name is not the name's (a take-back's send, takeBack.ts).
  const words = withoutFinalStop(text).replace(/\s+instead$/i, '');
  if (!words) return [];
  // A table, a board, a book or a chapter is asked for, not words for a note: "add a table to this note" is no bullet.
  if (NOT_WORDS.test(words)) return [];
  if (SHAPE_7.test(words)) return [reading(7, '', { newNote: true })];
  for (const { rule, task } of SELF) {
    const self = rule.exec(words);
    if (self?.[1]) return [reading('S', '', { self: true, payload: self[1].trim(), placing: task ? 'task' : 'item' })];
  }
  const out: Reading[] = [];
  const named = (shape: Reading['shape'], tail: string, over: Partial<Reading>) => {
    for (const found of namesIn(tail)) {
      const kind = nameable(found.name);
      if (kind === 'not') continue;
      // "Make a note to call the electrician": a thing to do, for the note being written to, unless a note is plainly called that.
      if (kind === 'verb' && shape === 1 && !found.split) out.push(reading('S', '', { self: true, payload: [found.name, found.payload].filter(Boolean).join(', '), placing: 'task', noun: true }));
      out.push(reading(shape, found.name, { ...over, payload: found.payload, tail: tail.trim(), stopped: found.stopped, split: found.split, verb: kind === 'verb' }));
    }
  };

  const one = SHAPE_1.exec(words);
  if (one?.[1] && one[2]) named(1, one[2], { placing: placingOf(one[1]), noun: true });
  const two = SHAPE_2.exec(words);
  if (two?.[1] && two[2]) named(2, two[2], { placing: placingOf(two[1]), noun: true });
  const three = SHAPE_3.exec(words);
  if (three?.[1]) named(3, three[1], {});
  const eight = SHAPE_8.exec(words);
  if (eight?.[2] && eight[3] && nameable(eight[2]) === 'name') {
    const thing = eight[1] ?? '';
    for (const found of namesIn(eight[3])) {
      if (found.split || nameable(found.name) !== 'name') continue;
      out.push(reading(8, found.name, { heading: eight[2].trim(), payload: BARE_THING.test(thing) ? found.payload : [thing, found.payload].filter(Boolean).join(', '), tail: words.replace(SHAPE_4_VERB, ''), stopped: found.stopped }));
    }
  }
  const five = SHAPE_5.exec(words);
  if (five?.[1] && five[3] && nameable(five[3]) === 'name') {
    const plainMove = /^(?:move|switch)$/i.test(five[1]) && five[2] !== undefined && five[2].toLowerCase() !== 'it';
    out.push(reading(5, five[3], { move: true, plainMove }));
  }

  // "Add call Sam to House TODOs": at every preposition, the thing before it and the name after.
  if (SHAPE_4_VERB.test(words) && !one && !three) {
    const after = words.replace(SHAPE_4_VERB, '');
    for (const split of after.matchAll(PREP_SPLIT)) {
      const thing = after.slice(0, split.index).trim();
      const tail = after.slice((split.index ?? 0) + split[0].length).replace(/^(?:(?:the|my|our)\s+)/i, '');
      if (!thing || !tail) continue;
      const noun = THING_NOUN.exec(`${thing} `);
      const paragraph = PARAGRAPH.test(thing);
      const said = paragraph ? '' : noun ? `${thing} `.slice(noun[0].length).trim() : thing;
      const placing = paragraph ? 'paragraph' : noun?.[1] ? placingOf(noun[1]) : 'leave';
      // The name runs to a stop, where the take's words begin again, or to a comma, a colon or "that says", where more
      // of the thing is.
      const stop = /^([^.,;:]+?)\s*(?:\.\s+(.+)|(?:[,;:]|\s(?:that\s+says|which\s+says|that\s+reads|saying|to\s+say)\s)\s*(.+))$/.exec(tail);
      const name = stop ? stop[1]! : tail;
      const kind = nameable(name);
      if (kind === 'not') continue;
      const payload = BARE_THING.test(said) ? '' : said;
      out.push(
        reading(4, name, {
          payload: stop?.[3] ? [payload, stop[3]].filter(Boolean).join(', ') : payload,
          trailing: stop?.[2]?.trim() ?? '',
          tail: after,
          placing,
          noun: Boolean(noun),
          stopped: Boolean(stop),
          verb: kind === 'verb',
        }),
      );
      // "Add milk to groceries and eggs": a title, and more of the thing after it.
      const joined = stop ? [] : name.split(/\s+/);
      for (let k = 1; k < joined.length; k += 1) {
        const rest = joined.slice(k).join(' ');
        if (!/^and\s+\S/i.test(rest)) continue;
        out.push(reading(4, joined.slice(0, k).join(' '), { payload: [payload, rest.replace(/^and\s+/i, '')].filter(Boolean).join(', '), placing, noun: Boolean(noun), split: true }));
      }
    }
  }
  return out;
}

// ---- the gate a phrase passes with no keyword ---------------------------------------------------

/**
 * The shapes a command has to have with no keyword said, or a mishearing of it, by its words alone (docs/DESIGN.md
 * §136): a note or an item said for it, the name run to a separator or the phrase's end and never to a split the
 * grammar chose ("add a note to house to-dos, call Sam"; "another item on the agenda is the budget" is meeting talk);
 * "put this in X, …" stopped at a separator; "add X to Y" and "add X under H in Y"; and "move this to X" said plainly.
 * Never a to-do for here ("remind me to …" is prose in a voice note), "new note", a name said first, a name that
 * starts with a verb, or "go to X": "Go to work" moved a whole recording once.
 */
export function bareShape(r: Reading): boolean {
  if (r.self || r.newNote || r.verb || r.nameFirst) return false;
  if (r.shape === 1 || r.shape === 2) return r.noun && !r.split;
  if (r.shape === 3) return r.stopped;
  if (r.shape === 5) return r.plainMove;
  return r.shape === 4 || r.shape === 8;
}

/**
 * What the note named has to be for a bare phrase: for "put this in X", "add X to Y" and a heading, the name or the
 * title says what kind of list it is (a kind word in the name, or a title that ends in one: House TODOs, Groceries,
 * Packing list), and the heading is one the note has. "A note" and "an item" said are their own evidence, and so is
 * "move this". Nearly every note has one bullet, so a list in the body is no evidence: "send this to Sam, the deposit
 * is due" beside a note called Sam is a sentence.
 */
export function bareEvidence(r: Reading, note: { title: string; body: string }): boolean {
  if (r.shape === 3 || r.shape === 4 || r.shape === 8) {
    const kind = nameWords(r.name);
    if (kind.specific.length + kind.generic.length === 0 && titleKind(note.title) === null) return false;
  }
  if (r.shape === 8) return r.heading !== null && headingsOf(note.body).some((h) => nameScore(nameWords(r.heading!), nameWords(h)) >= FIND.resolved);
  return true;
}

/**
 * The gate a phrase passes with no trustworthy keyword: the shape (`bareShape`), a note named clearly (`FIND.clear`),
 * the evidence (`bareEvidence`), and its words in the same phrase unless the take is at its start, where a route may
 * wait for them in the open, or it moves the take. A bare command with nothing said for it opened a one-shot that took
 * the next three phrases of dictation, which is why the words must come in the same breath mid-take. Both readers ask
 * this (liveRoute.ts `clear`, ai/instruction.ts), and the live reader's mishearing path, so a mishearing means the
 * same to each.
 */
export function bareCommand(r: Reading, note: { title: string; body: string }, score: number, { atStart }: { atStart: boolean }): boolean {
  return bareShape(r) && score >= FIND.clear && bareEvidence(r, note) && (atStart || r.payload !== '' || r.plainMove);
}

/**
 * Whether a command's words after a mishearing of the keyword ("Hey, like, …", "Hey goes …") are a command for a note:
 * the gate every bare phrase passes (`bareShape`), and the caller's `clear`, which is `bareCommand` with its own find.
 * "Hey, like, I need to call my mum" and "Hey, like, put the parcel in the post" are words.
 */
export function misheardShape(words: string, clear: (reading: Reading) => boolean): boolean {
  return readRoute(words).some((r) => bareShape(r) && clear(r));
}

/** "For Groceries, eggs", "on the work list, add call Sam", "House TODOs: call Sam": the name said first. After the keyword only. */
export function readNameFirst(text: string): Reading[] {
  const words = withoutFinalStop(text);
  const out: Reading[] = [];
  for (const rule of SHAPE_6) {
    const found = rule.exec(words);
    if (found?.[1] && found[2] && nameable(found[1]) === 'name') out.push(reading(6, found[1], { payload: found[2].trim(), nameFirst: true, stopped: true }));
  }
  return out;
}

/**
 * An opener with no name yet: "add a note to", "put this in", "new item for", "move this to", "for". The live reader
 * holds it for the next phrase, where the name is.
 */
export function isOpener(text: string): boolean {
  const words = withoutFinalStop(text);
  if (!words) return true;
  if (SHAPE_7.test(words)) return false;
  return (
    new RegExp(String.raw`^(?:${VERB}(?:\s+${NOUN_OPEN}${NOUN})?(?:\s+(?:this|these|the\s+following))?|(?:new|another)\s+${NOUN}|move(?:\s+this)?|switch|carry\s+on|go|for|on)$`, 'i').test(words) ||
    new RegExp(String.raw`^(?:${VERB}|move|switch|(?:new|another)\s+${NOUN}).*\s${PREP}(?:\s+(?:the|my|our))?$`, 'i').test(words)
  );
}
