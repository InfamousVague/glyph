import { matchNote, parseRoute, type Candidate } from './route.ts';
import { cellsOf } from './table.ts';

/**
 * "Glyph, add buy milk to HelloTrade": commands while recording, which only
 * count after the keyword, and which ask before they act.
 *
 * Matt, after "add a note to hello trade" became a new note called "To the
 * hello trade": "have it listen for keywords and not do anything until it
 * hears the keyword and confirms the action". Commands used to be read out of
 * every phrase, in a handful of exact phrasings, and a pause in the middle of
 * one split it into two phrases that were each just words. So:
 *
 * - Nothing is a command until "Glyph" is heard (`findKeyword`). What comes
 *   before it in the phrase stays in the note; what comes after, across as many
 *   phrases as it takes, is the command and never lands in the note.
 * - The command is read more loosely than before (`planCommand`), since the
 *   keyword already says it is one: "add buy milk to hello trade", "add a list
 *   item to HelloTrade", "put call Sam on the work list", plus every phrasing
 *   route.ts knew. A command that names its note but not yet what to add waits
 *   for the next phrase.
 * - Then it asks: the recorder shows what it is about to do, and "yes" or "no"
 *   (`reply`), or a tap, decides. Nothing changes until then.
 *
 * Pure, so every phrasing is a test.
 */

// ---- the keyword ------------------------------------------------------------------------------

/**
 * "Glyph", and what speech recognition writes for it: a rare word, so the
 * small model sometimes spells it the way it sounds. "Hey" or "OK" before it
 * are part of the keyword.
 */
const KEYWORD = /(^|[\s,.;:!?"“])(?:(?:hey|hi|ok(?:ay)?|so)[,\s]+)?(?:glyph|glyphs|glyf|glif|gliff|glyff|glith|clyph|gleef)(?=$|[\s,.;:!?"”'])[,.;:!?"”]*\s*/i;

/**
 * "…to the Glyph note": the word as a note's name, not the keyword. Matt has a
 * note called Glyph, and "add a note to the Glyph note saying testing if this
 * works", said without the keyword first, took the name for the keyword: the
 * words before it became a note titled "Add a note to" and the rest was lost.
 * A preposition before and "note" or "page" after say it is a name.
 */
const NAMED_BEFORE = /(?:^|\s)(?:to|in|into|on|onto|for|under|about|called|named|titled)\s+(?:(?:the|my|our|a)\s+)?$/i;
const NAMED_AFTER = /^\s*(?:notes?|pages?|list)\b/i;

/** The keyword in `text`: the words before it (kept as words) and after it (the command). */
export function findKeyword(text: string): { before: string; after: string } | null {
  const all = new RegExp(KEYWORD.source, 'gi');
  for (const found of text.matchAll(all)) {
    const at = found.index + (found[1]?.length ?? 0);
    const end = found.index + found[0].length;
    if (NAMED_BEFORE.test(text.slice(0, at)) && NAMED_AFTER.test(text.slice(end))) continue;
    return {
      before: text.slice(0, at).replace(/[\s,;:]+$/, '').trim(),
      after: text.slice(end).trim(),
    };
  }
  return null;
}

// ---- yes or no --------------------------------------------------------------------------------

const YES = /^(?:yes|yeah|yep|yup|sure|ok(?:ay)?|confirm(?:ed)?|correct|right|do it|go ahead|go for it|add it|send it|move it|please(?: do)?|that's right|that is right|sounds good|perfect)\b/i;
const NO = /^(?:no|nope|nah|cancel|never ?mind|stop|don't|do not|wrong|scratch that|forget it|not that)\b/i;

/** A reply to "shall I?": yes, no, or neither. Short phrases only, so a sentence starting "No problem with the invoice" is a sentence. */
export function reply(text: string): 'yes' | 'no' | null {
  const said = text.trim().replace(/^(?:um+|uh+|er+|oh)[,\s]+/i, '').replace(/[.!?,]+$/, '').trim();
  if (!said || said.split(/\s+/).length > 5) return null;
  if (NO.test(said)) return 'no';
  if (YES.test(said)) return 'yes';
  return null;
}

// ---- the plan ---------------------------------------------------------------------------------

export interface Placement {
  /** "leave": into the list it fits, or a paragraph (listAppend.ts `leaveNote`). "item": always a list item. */
  how: 'leave' | 'item';
  task: boolean;
  /** "Items", "tasks": every phrase until a pause is one. */
  many: boolean;
  /** A plugin's word after the note's name ("…in Notion"). */
  target: string | null;
}

export type Plan<N extends Candidate = Candidate> =
  /** Words into a note. */
  | ({ kind: 'place'; note: N; text: string } & Placement)
  /** A note named, but not yet what goes in it: the next phrase is that. */
  | ({ kind: 'await'; note: N } & Placement)
  /** This take's words move to a note and carry on there. */
  | { kind: 'move'; note: N }
  /** This take becomes a new note. */
  | { kind: 'new' }
  /** A table, asked for a piece at a time (capture/table.ts): in a named note, or this one when none is named. */
  | { kind: 'table'; note: N | null; columns: string[] }
  /** A note was named that there is no note for. */
  | { kind: 'no-note'; name: string };

const LEAD = /^\s*(?:(?:please|can you|could you|would you|and|so|ok(?:ay)?|um+|uh+)[,\s]+)+/i;
const MOVERS = /^\s*(?:switch|go|jump|change|move|carry on|continue)\b/i;

/** "a list item", "a task", "a note that says" at the front of what is being added: the kind of thing, not the thing. */
const OBJECT_NOUN = /^(?:(?:a|an|another|one more|some|new)\s+)?(?:quick\s+)?(?:(list\s+)?(items?|entry|entries|bullets?|points?)|(tasks?|to-?\s?dos?|check\s?box(?:es)?)|(notes?|lines?|reminders?|comments?|memos?))(?:\s+(?:that\s+says|saying|which\s+says|called|:|,))?\s*/i;

const TABLE = /^(?:add|make|create|start|put|insert|draw|build|new)\s+(?:(?:a|an|another|one)\s+)?(?:new\s+)?table\b(.*)$/i;
/** "…with columns bug, owner and status": the labels said up front, so the first question is skipped. */
const TABLE_COLUMNS = /\s*,?\s*(?:with|using|that has|having)\s+(?:the\s+)?(?:columns?|column labels?|headings?|headers?|labels?)\s*(?:of|:|,)?\s*(.+)$/i;

/** A preposition that can end what is added and start the note's name. */
const INTO = /(?:^|\s+)(?:to|in|into|onto|on|under|for)\s+/gi;

/** The note a spoken name means, leniently: "the", "my" and a trailing "note" or "list" gone. */
function noteNamed<N extends Candidate>(raw: string, notes: readonly N[]): { note: N; score: number } | null {
  const name = raw
    .replace(/[.,;:!?"“”]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^(?:(?:the|my|our|a)\s+)+/i, '')
    .replace(/\s+(?:note|notes|list|page)$/i, '')
    .trim();
  if (name.length < 2) return null;
  return matchNote(name, notes);
}

function placementOf(noun: RegExpExecArray | null): Placement {
  if (noun?.[3]) return { how: 'item', task: true, many: /s$|es$/i.test(noun[3]), target: null };
  if (noun?.[2]) return { how: 'item', task: false, many: /s$|ies$/i.test(noun[2]), target: null };
  return { how: 'leave', task: false, many: false, target: null };
}

/**
 * What the words after the keyword ask for, or null when they don't say yet.
 * `notes` are the notes that can be named; `targets` the words plugins offer
 * after a note's name.
 */
export function planCommand<N extends Candidate>(words: string, options: { notes: readonly N[]; targets?: readonly string[] }): Plan<N> | null {
  const plan = readCommand(words, options);
  // What is added is words, not the end of a spoken sentence.
  return plan?.kind === 'place' ? { ...plan, text: plan.text.replace(/[\s.,;:!?]+$/, '') } : plan;
}

function readCommand<N extends Candidate>(words: string, { notes, targets = [] }: { notes: readonly N[]; targets?: readonly string[] }): Plan<N> | null {
  const text = words.replace(LEAD, '').trim();
  if (!text) return null;
  // The phrase is committed: a command that stops after a name has ended.
  const ended = /[.!?]\s*$/.test(text) ? text : `${text}.`;
  const find = (name: string) => noteNamed(name, notes)?.note ?? null;

  // "Add a table to the AttackFM bugbash note (with columns bug, owner and status)".
  const table = TABLE.exec(text);
  if (table) {
    let tail = table[1] ?? '';
    let columns: string[] = [];
    const labelled = TABLE_COLUMNS.exec(tail);
    if (labelled) {
      columns = cellsOf(labelled[1] ?? '');
      tail = tail.slice(0, labelled.index);
    }
    const into = /^\s*(?:to|in|into|on|onto|for|under)\s+(.+?)[.!?]*\s*$/i.exec(tail);
    if (into?.[1]) {
      const found = noteNamed(into[1], notes);
      return found ? { kind: 'table', note: found.note, columns } : { kind: 'no-note', name: into[1].replace(/^(?:(?:the|my|our)\s+)+/i, '').replace(/\s+(?:note|page)$/i, '') };
    }
    return tail.replace(/[\s.!?]/g, '') ? null : { kind: 'table', note: null, columns };
  }

  const route = parseRoute(ended, { targets });
  if (route?.kind === 'new') return { kind: 'new' };
  if (route?.kind === 'item') {
    const note = find(route.name);
    if (!note) return { kind: 'no-note', name: route.name };
    const placement: Placement = { how: 'item', task: route.task, many: route.many, target: route.target };
    return route.rest ? { kind: 'place', note, text: route.rest, ...placement } : { kind: 'await', note, ...placement };
  }
  if (route?.kind === 'leave') {
    const note = find(route.name);
    if (!note) return { kind: 'no-note', name: route.name };
    const placement: Placement = { how: 'leave', task: false, many: false, target: null };
    return route.rest ? { kind: 'place', note, text: route.rest, ...placement } : { kind: 'await', note, ...placement };
  }

  // "Add buy milk to hello trade", "put a list item on the work list: call Sam":
  // every place the thing could end and the note's name begin, and the one
  // whose name is the best match for a note.
  const verb = /^\s*(?:add|put|stick|write|jot(?:\s+down)?|append|save|file|pop|drop|note|leave|send|move|switch|go|jump|change)\s+/i.exec(text);
  if (verb) {
    const after = text.slice(verb[0].length);
    let best: { note: N; score: number; thing: string; rest: string } | null = null;
    for (const split of after.matchAll(INTO)) {
      const thing = after.slice(0, split.index).trim();
      const tail = after.slice((split.index ?? 0) + split[0].length);
      // The name runs to a stop or colon, and anything after that is the thing too ("…to work: call Sam").
      const [, name = tail, rest = ''] = /^([^.,;:!?]+)(?:[.,;:!?]\s*(.*))?$/.exec(tail) ?? [];
      const target = targets.find((word) => new RegExp(String.raw`\s+(?:in|on|to|into)\s+${word}\s*$`, 'i').test(name)) ?? null;
      const found = noteNamed(target ? name.replace(new RegExp(String.raw`\s+(?:in|on|to|into)\s+${target}\s*$`, 'i'), '') : name, notes);
      if (found && (!best || found.score > best.score)) best = { ...found, thing, rest: rest.trim() };
    }
    if (best) {
      if (MOVERS.test(text) && /^(?:this|that|it|everything|these|those|them)?$/i.test(best.thing) && !best.rest) return { kind: 'move', note: best.note };
      const noun = OBJECT_NOUN.exec(best.thing);
      const placement = placementOf(noun);
      const thing = [noun ? best.thing.slice(noun[0].length) : best.thing, best.rest].filter(Boolean).join(' ').trim();
      const bare = /^(?:this|that|it|everything|these|those|them)$/i.test(thing);
      return thing && !bare ? { kind: 'place', note: best.note, text: thing, ...placement } : { kind: 'await', note: best.note, ...placement };
    }
  }

  if (route?.kind === 'note') {
    const note = find(route.name);
    if (!note) return { kind: 'no-note', name: route.name };
    if (route.rest) return { kind: 'place', note, text: route.rest, how: 'leave', task: false, many: false, target: null };
    return MOVERS.test(text) ? { kind: 'move', note } : { kind: 'await', note, how: 'leave', task: false, many: false, target: null };
  }
  return null;
}
