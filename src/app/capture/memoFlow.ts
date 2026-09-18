import { matchNote, similarity, type Candidate } from './route.ts';

/**
 * Memo mode as a conversation: a note first, then things asked for by their trigger words.
 *
 * Matt: "I want memo mode to have the first step selecting a note - ask for the title of the note and show a few
 * recent options and get a partial match - take a keyword as 'select note <note>' or 'use note <note>' or other
 * variations. Then after a note is selected we can use words like 'add task' as a trigger word, then the screen
 * should say 'adding task… what task should we add?', and we speak the task."
 *
 * So a memo opens on a question rather than a blank page: which note? A few recent ones are shown, and the name is
 * said with a word in front of it ("use note groceries", "select the work note", "open weekend trip") or on its own,
 * or as its place in the list ("the first one"), or "new note" for a fresh one. Once a note is chosen, the recorder
 * is on that note: plain talk goes onto its end as it always has, and a trigger word at the start of a phrase asks
 * for one thing - "add task" asks what the task is, and the next phrase is it, straight into the note's list. No
 * "shall I?" after that: the trigger and the question were the asking.
 *
 * This is the pure half, what a phrase asks for; the take (take.ts) runs the steps and the recorder (CaptureScreen)
 * draws them. It replaces the scratch page and the sort at the end (docs/DESIGN.md, "Memo mode sorts"): a memo
 * that knows its note from the first word has nothing left to sort.
 */

// ---- which note ---------------------------------------------------------------------------------

export type Choice =
  /** A note by name. `explicit` when a word like "use note" came first, so a looser match will do. */
  | { kind: 'name'; name: string; explicit: boolean }
  /** "The first one", "number two": a place in the options shown, from 0. */
  | { kind: 'ordinal'; index: number }
  /** "New note", "new note called camping". */
  | { kind: 'new'; title: string }
  | null;

const LEAD = String.raw`(?:(?:ok(?:ay)?|so|um+|uh+|please|and|then|hey)[,\s]+)*`;
const FILLER = String.raw`(?:(?:the|my|our|a|that)\s+)?`;
/** "note", "notes", and what base.en writes for it said quickly. */
const NOUN = String.raw`(?:notes?|node|page|list)`;

/** "Use note groceries", "select the note called work", "open weekend trip", "go to my groceries list". */
const EXPLICIT = new RegExp(
  String.raw`^\s*${LEAD}(?:select|selects|use|choose|pick|open|take|load|go\s+to|switch\s+to|jump\s+to|change\s+to)\s+${FILLER}(?:${NOUN}\s+(?:called|named|titled|for|about)?\s*)?(.+?)(?:\s+${NOUN})?[.!?]*\s*$`,
  'i',
);
/** "New note", "new note called camping", "start a new note for the trip". */
const NEW = new RegExp(String.raw`^\s*${LEAD}(?:start\s+|make\s+|create\s+)?(?:a\s+)?(?:new|fresh|another)\s+${NOUN}(?:\s+(?:called|named|titled|for|about|on)\s+(.+?))?[.!?]*\s*$`, 'i');
/** "The first one", "number two", "the top one", "option three". */
const ORDINAL = new RegExp(
  String.raw`^\s*${LEAD}(?:the\s+)?(?:(first|second|third|fourth|fifth|top|1st|2nd|3rd|4th|5th)(?:\s+(?:one|note))?|(?:number|option|note)\s+(one|two|three|four|five|1|2|3|4|5)|(one|two|three|four|five|1|2|3|4|5))[.!?]*\s*$`,
  'i',
);
const PLACES: Record<string, number> = { first: 0, top: 0, '1st': 0, one: 0, '1': 0, second: 1, '2nd': 1, two: 1, '2': 1, third: 2, '3rd': 2, three: 2, '3': 2, fourth: 3, '4th': 3, four: 3, '4': 3, fifth: 4, '5th': 4, five: 4, '5': 4 };

function cleanName(raw: string): string {
  return raw
    .replace(/[.,;:!?"“”]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^(?:(?:the|my|our|a)\s+)+/i, '')
    .replace(new RegExp(String.raw`\s+${NOUN}$`, 'i'), '')
    .trim();
}

/** What a phrase says while the recorder is asking which note. A phrase that says nothing is a name, said bare. */
export function parseChoice(text: string): Choice {
  const fresh = NEW.exec(text);
  if (fresh) return { kind: 'new', title: cleanName(fresh[1] ?? '') };
  const place = ORDINAL.exec(text);
  if (place) {
    const word = (place[1] ?? place[2] ?? place[3] ?? '').toLowerCase();
    if (word in PLACES) return { kind: 'ordinal', index: PLACES[word]! };
  }
  const explicit = EXPLICIT.exec(text);
  if (explicit?.[1]) {
    const name = cleanName(explicit[1]);
    // "Use note" with no name after it: still asking.
    if (name && !new RegExp(String.raw`^${NOUN}$`, 'i').test(name)) return { kind: 'name', name, explicit: true };
    return null;
  }
  const bare = cleanName(text);
  return bare ? { kind: 'name', name: bare, explicit: false } : null;
}

export type Chosen<N extends Candidate> =
  | { kind: 'note'; note: N }
  | { kind: 'new'; title: string }
  /** A name that fits nothing well enough. */
  | { kind: 'none'; said: string }
  /** A name two notes fit about as well: they are offered, to pick between. */
  | { kind: 'unsure'; said: string; between: N[] };

/** The notes `name` could mean, best first, with how well each fits. */
function ranked<N extends Candidate>(name: string, notes: readonly N[]): { note: N; score: number }[] {
  return notes
    .filter((note) => note.title.trim())
    .map((note) => ({ note, score: similarity(name, note.title) }))
    .sort((a, b) => b.score - a.score);
}

/**
 * The note a choice means. `options` are the ones on screen, for a place in the list; `all` is every note a name can
 * mean. A name said after "use note" is taken on a looser match than one said bare, since the word said it was a
 * name: a bare phrase that only half fits a title is more likely talk than a choice.
 */
export function chooseNote<N extends Candidate>(choice: Exclude<Choice, null>, options: readonly N[], all: readonly N[]): Chosen<N> {
  if (choice.kind === 'new') return { kind: 'new', title: choice.title };
  if (choice.kind === 'ordinal') {
    const note = options[choice.index];
    return note ? { kind: 'note', note } : { kind: 'none', said: `number ${choice.index + 1}` };
  }
  const threshold = choice.explicit ? 0.6 : 0.72;
  const found = matchNote(choice.name, all, { threshold, margin: 0.08 });
  if (found) return { kind: 'note', note: found.note };
  const [best, second] = ranked(choice.name, all);
  // Two that fit, neither clearly: offered side by side, so "the first one" settles it.
  if (best && second && best.score >= threshold && second.score >= threshold) return { kind: 'unsure', said: choice.name, between: [best.note, second.note] };
  return { kind: 'none', said: choice.name };
}

/**
 * The note a phrase still being said seems to mean, for marking it in the list before the phrase ends; null when none
 * stands out. `options` are the ones on screen, for a place in the list; `all` is every note a name can mean.
 */
export function guessNote<N extends Candidate>(text: string, options: readonly N[], all: readonly N[]): N | null {
  const choice = parseChoice(text);
  if (!choice) return null;
  if (choice.kind === 'ordinal') return options[choice.index] ?? null;
  if (choice.kind === 'new') return null;
  const [best, second] = ranked(choice.name, all);
  if (!best || best.score < 0.45) return null;
  return second && second.score > best.score - 0.05 && best.score < 0.99 ? null : best.note;
}

// ---- what to add ---------------------------------------------------------------------------------

/** What a trigger asks for: a to-do, a list item, or a line of words; one or several. */
export interface Ask {
  what: 'task' | 'item' | 'line';
  many: boolean;
}

export type Trigger =
  /** "Add task": the next phrase is the thing, unless it came in the same breath (`said`). */
  | { kind: 'ask'; ask: Ask; said: string }
  /** "Switch note", "use another note": back to choosing; "switch to work": straight to it. */
  | { kind: 'switch'; name: string | null }
  | { kind: 'new'; title: string }
  /** "Undo", "scratch that": the last thing added comes out. */
  | { kind: 'undo' }
  | null;

const TASK = String.raw`tasks?|to-?\s?dos?|todos?|check\s?box(?:es)?|action\s+items?`;
const ITEM = String.raw`(?:list\s+)?items?|bullet\s+points?|bullets?|points?|entr(?:y|ies)`;
const LINE = String.raw`notes?|lines?|paragraphs?|sentences?|comments?|thoughts?|remarks?`;
/** "Add a task", "new to-do", "add tasks", "add a task: buy milk", "add item saying call Sam". */
const ASK = new RegExp(
  String.raw`^\s*${LEAD}(?:add|new|create|make|insert|put|write|start|another)\s+(?:(?:a|an|another|one\s+more|some|the|this)\s+)?(?:(?:quick|new|little)\s+)?(?:(${TASK})|(${ITEM})|(${LINE}))\b(?:\s*[:,]\s*|\s+(?:that\s+says|which\s+says|saying|reading|of|for)\s+|\s+|\s*(?=[.!?]*\s*$))(.*)$`,
  'i',
);
/** "Switch note", "use a different note", "change notes", "switch to work". */
const SWITCH = new RegExp(
  String.raw`^\s*${LEAD}(?:switch|select|choose|pick|change|use|open|go\s+to|move\s+to|jump\s+to)\s+(?:(?:to|over\s+to)\s+)?(?:(?:a|the|another|a\s+different|the\s+other|some\s+other|my)\s+)?(?:different\s+|other\s+)?${NOUN}(?:\s+(?:called|named|titled)?\s*(.+?))?[.!?]*\s*$`,
  'i',
);
const UNDO = new RegExp(String.raw`^\s*${LEAD}(?:undo(?:\s+(?:that|it|the\s+last\s+one))?|scratch\s+that|take\s+that\s+(?:back|out)|remove\s+that|delete\s+that)[.!?]*\s*$`, 'i');

/** Whether a phrase opens like a trigger or a command, so the rules should read it before it is taken as words. */
const OPENS = new RegExp(String.raw`^\s*${LEAD}(?:add|new|create|make|insert|put|write|start|another|switch|select|choose|pick|change|use|open|go\s+to|move|jump\s+to|undo|scratch|take\s+that|remove\s+that|delete\s+that)\b`, 'i');

export function opensLikeCommand(text: string): boolean {
  return OPENS.test(text);
}

/** What a phrase asks for once a note is chosen, or null when it is words for the note. */
export function parseTrigger(text: string): Trigger {
  if (UNDO.test(text)) return { kind: 'undo' };
  const fresh = NEW.exec(text);
  if (fresh) return { kind: 'new', title: cleanName(fresh[1] ?? '') };
  const change = SWITCH.exec(text);
  if (change) {
    const name = change[1] ? cleanName(change[1]) : '';
    return { kind: 'switch', name: name || null };
  }
  // "Switch to work" without the word "note": a named note, when the flow already knows it is a switch.
  const to = /^\s*(?:switch|go|jump|change|move)\s+(?:over\s+)?to\s+(.+?)[.!?]*\s*$/i.exec(text);
  if (to?.[1]) return { kind: 'switch', name: cleanName(to[1]) || null };
  const ask = ASK.exec(text);
  if (ask) {
    const noun = (ask[1] ?? ask[2] ?? ask[3] ?? '').toLowerCase();
    const what: Ask['what'] = ask[1] ? 'task' : ask[2] ? 'item' : 'line';
    // Several tasks or items are each a line of the list; several lines would run into one paragraph, so a line is one.
    const many = what !== 'line' && /(?:s|es|ies)$/.test(noun.replace(/\s+/g, '')) && !/(?:ss|us)$/.test(noun);
    return { kind: 'ask', ask: { what, many }, said: (ask[4] ?? '').replace(/^[\s,:;]+|[\s.,;:!?]+$/g, '').trim() };
  }
  return null;
}

/** "Done", "that's all", "that's it", "finished": the end of several things said one after another. */
export function saysFinished(text: string): boolean {
  return /^\s*(?:(?:ok(?:ay)?|and|so)[,\s]+)*(?:done|that'?s\s+(?:all|it|everything)|that\s+is\s+(?:all|it)|finished|no\s+more|nothing\s+else|end|stop)[.!]*\s*$/i.test(text);
}

/** "Never mind", "cancel", "forget it": the thing asked for is not wanted after all. */
export function saysNeverMind(text: string): boolean {
  return /^\s*(?:(?:ok(?:ay)?|no|and|so)[,\s]+)*(?:never\s*mind|cancel(?:\s+that)?|forget\s+(?:it|that)|scratch\s+that|nothing|no(?:thing)?\s+thanks|skip(?:\s+(?:it|that))?)[.!]*\s*$/i.test(text);
}

/** What the recorder says while it waits: the heading and the question, in the recorder's own words. */
export function askWords(ask: Ask): { heading: string; question: string; hint: string } {
  const thing = ask.what === 'task' ? 'task' : ask.what === 'item' ? 'item' : 'line';
  if (ask.many) {
    return {
      heading: `Adding ${thing}s`,
      question: `What ${thing}s should we add?`,
      hint: `Say each one, then “done”. Or “never mind”.`,
    };
  }
  return {
    heading: `Adding ${ask.what === 'item' ? 'an' : 'a'} ${thing}`,
    question: ask.what === 'line' ? 'What should it say?' : `What ${thing} should we add?`,
    hint: 'Say it, or “never mind”.',
  };
}
