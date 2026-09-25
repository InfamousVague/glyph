import { isBookBody } from '../book/book.ts';
import { addToLane, lanesOf, matchLane, moveToLane, type Lane } from '../core/boards.ts';
import { capitalise } from '../core/text.ts';
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
 * The word a command follows, and what speech recognition writes for it. "Glyph" is a rare word, so the small model
 * sometimes spells it the way it sounds, and "hey" or "OK" before it are part of the keyword but not needed. "Ghost"
 * - the app's name since it became Ghost.md - is a common word, so a note that begins "Ghost stories…" would have
 * been a command with no command in it; Matt chose "hey Ghost": the new word only counts after "hey", "hi", "OK" or
 * "so", and the old word keeps working as it always did.
 */
const KEYWORD =
  /(^|[\s,.;:!?"“])(?:(?:hey|hi|ok(?:ay)?|so)[,\s]+(?:ghost|ghosts|goast|gost|ghos|ghoast|ghossed|ghosed)|(?:(?:hey|hi|ok(?:ay)?|so)[,\s]+)?(?:glyph|glyphs|glyphe|glyf|glif|gliff|glyff|gliph|glyth|glith|glithe|clith|clyph|gleef|gliv|glive|glit|bliff))(?=$|[\s,.;:!?"”'])[,.;:!?"”]*\s*/i;

/**
 * What base.en writes for "Glyph" that is a word of its own: "Life. Add eggs to my list", "Live, new note", "Head
 * life, put call Sam on the work list". Twelve synthesised voices were run through the phone's model saying
 * "Glyph, …"; half came back as one of these. They are
 * ordinary words, so one only counts at the very start of a phrase, followed by a stop or a comma, and only when what
 * follows reads as a command (`findSoundAlike`); "We climbed the cliff at dawn" and "Life is short" stay words.
 */
const SOUND_ALIKE = /^\s*(?:(?:hey|hi|ok(?:ay)?|so|a|add|head|hade|hate|take|tag)[,\s]+)?(?:life|live|lift|lip|cliff|clip|glide|slip)[,.;:!?]+\s*/i;

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

/**
 * A sound-alike of the keyword at the start of `text` ("Life. Add eggs to work."), when `reads` says the rest is a
 * command: the same shape as `findKeyword`, nothing before it.
 */
export function findSoundAlike(text: string, reads: (words: string) => boolean): { before: string; after: string } | null {
  const found = SOUND_ALIKE.exec(text);
  if (!found) return null;
  const after = text.slice(found[0].length).trim();
  return after && reads(after) ? { before: '', after } : null;
}

/** Whether a plan is something to do: a note to add to or move to, a new note, a table, or a note named and waiting. */
export function actionable(plan: Plan | null): boolean {
  return plan !== null && plan.kind !== 'no-note';
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
  /** "leave": into the list it fits, or a paragraph (listAppend.ts `leaveNote`). "item": always a list item. "paragraph": always its own paragraph. */
  how: 'leave' | 'item' | 'paragraph';
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
  /** A card for a board's lane: "Glyph, add fix the login bug to Doing" (core/boards.ts). */
  | { kind: 'lane'; note: N; lane: string; words: string; change: (body: string) => string | null }
  /** A card moved to a lane: "Glyph, move the pricing page to Done". */
  | { kind: 'card'; note: N; lane: string; words: string; change: (body: string) => string | null }
  /** "Glyph, make this a board": the note being recorded is written as a board. */
  | { kind: 'board' }
  /** "Make a book called Field guide with Trees, Birds and Rivers": a book note, its pages the notes named or chapters still to write (docs/BOOKS.md). */
  | { kind: 'book'; title: string; pages: string[] }
  /** A chapter for a book: "add a chapter called Trees to the field guide". `title` null is this note: "put this in the field guide". */
  | { kind: 'chapter'; note: N; title: string | null }
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
    .replace(/\s+(?:note|notes|node|list|page)$/i, '')
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
export interface PlanOptions<N extends Candidate & { note?: { body: string } }> {
  notes: readonly N[];
  targets?: readonly string[];
  /** The note being recorded into, when it has a board: its lanes can be named (core/boards.ts). */
  board?: N | null;
}

export function planCommand<N extends Candidate & { note?: { body: string } }>(words: string, options: PlanOptions<N>): Plan<N> | null {
  const plan = readCommand(words, options);
  // What is added is words, not the end of a spoken sentence.
  return plan?.kind === 'place' ? { ...plan, text: plan.text.replace(/[\s.,;:!?]+$/, '') } : plan;
}

/** "Make this a board", "turn the list into a kanban board". */
const MAKE_BOARD = /^(?:make|turn|change)\s+(?:this|it|this\s+note|the\s+note|this\s+list|the\s+list)\s+(?:into\s+)?(?:a\s+)?(?:kanban\s+)?(?:board|kanban)[.!]?$/i;
/** "Move the pricing page to Done", "drag call Sam into doing". */
const MOVE_CARD = /^(?:move|drag|shift|put)\s+(.+?)\s+(?:to|into|in|onto|over\s+to)\s+(.+?)[.!?]*$/i;

/** "Make a book called Field guide", "new book, Trip". Not "add a book to…": that is a book for a list. */
const MAKE_BOOK = /^(?:make|create|start|begin|new)\s+(?:(?:a|an|another|one|the)\s+)?(?:new\s+)?book\b(.*)$/i;
/** "…with Trees, Birds and Rivers" after the name: its pages. */
const BOOK_PAGES = /\s*,?\s*(?:with|holding|containing|out of)\s+(?:the\s+)?(?:notes?|pages?|chapters?)?\s*(?:of|:|,)?\s*(.+)$/i;
/** "a chapter called", "the page named": the kind of thing a book gets, not the thing. */
const CHAPTER_NOUN = /^(?:(?:a|an|another|one more|new|the)\s+)?(?:new\s+)?(?:chapters?|pages?|sections?|parts?)(?:\s+(?:called|named|titled|that says|saying|for|:|,))?\s*/i;
/** The note being recorded, named as the thing: "add this to the field guide". */
const SELF = /^(?:this|that|it|this note|that note|the note|this one|this page|these|those|them|everything)$/i;

/** A note that is a book (book/book.ts): what is added "to" it is a chapter, not words. */
function isBook<N extends Candidate & { note?: { body: string } }>(named: N): boolean {
  return named.note !== undefined && isBookBody(named.note.body);
}

/**
 * What "add … to <book>" adds: a chapter with that title ("a chapter called Trees", "Trees"), this note when that is
 * what was said ("add this to the field guide"), or nothing yet, and then the next phrase names it.
 */
function chapterFor<N extends Candidate & { note?: { body: string } }>(note: N, words: string): Plan<N> {
  const said = words.replace(/[\s.,;:!?]+$/, '').trim();
  if (SELF.test(said)) return { kind: 'chapter', note, title: null };
  const title = said.replace(CHAPTER_NOUN, '').replace(/^["“]|["”]$/g, '').trim();
  return title ? { kind: 'chapter', note, title: capitalise(title) } : { kind: 'await', note, how: 'leave', task: false, many: false, target: null };
}

/**
 * A plan read for a book (docs/BOOKS.md): words placed in it are a chapter, and moving this recording there makes
 * this note one. Every plan the rules make goes through it, and the model's too (take.ts), so "add Trees to the field
 * guide" lands the same whoever read it.
 */
export function forBook<N extends Candidate & { note?: { body: string } }>(plan: Plan<N>): Plan<N> {
  if (plan.kind === 'place' && isBook(plan.note)) return chapterFor(plan.note, plan.text);
  if (plan.kind === 'move' && isBook(plan.note)) return { kind: 'chapter', note: plan.note, title: null };
  return plan;
}

/** The words a named note waited for, as the plan to carry out: a chapter when the note is a book. */
export function placedOn<N extends Candidate & { note?: { body: string } }>(plan: Extract<Plan<N>, { kind: 'await' }>, text: string): Plan<N> {
  return forBook({ ...plan, kind: 'place', text });
}

/** A lane of `board`'s note by spoken name, with the score it won by. */
function laneNamed<N extends Candidate & { note?: { body: string } }>(name: string, board: N | null | undefined): { lane: Lane; score: number } | null {
  const body = board?.note?.body;
  if (!body) return null;
  return matchLane(name.replace(/[.,;:!?"“”]+/g, ' ').trim(), lanesOf(body));
}

/** A change to a lane, found again by name in the body it is given, which is the fresh one when it runs. */
function laneChange(lane: Lane, act: (body: string, lane: Lane) => string | null): (body: string) => string | null {
  return (body) => {
    const fresh = lanesOf(body).find((l) => l.name === lane.name && l.board === lane.board) ?? lanesOf(body).find((l) => l.name === lane.name);
    return fresh ? act(body, fresh) : null;
  };
}

function readCommand<N extends Candidate & { note?: { body: string } }>(words: string, options: PlanOptions<N>): Plan<N> | null {
  const plan = readWords(words, options);
  return plan ? forBook(plan) : null;
}

function readWords<N extends Candidate & { note?: { body: string } }>(words: string, { notes, targets = [], board = null }: PlanOptions<N>): Plan<N> | null {
  const text = words.replace(LEAD, '').trim();
  if (!text) return null;
  if (MAKE_BOARD.test(text)) return { kind: 'board' };

  // "Make a book called Field guide with Trees, Birds and Rivers" (docs/BOOKS.md). Said with no name, it waits for one.
  const making = MAKE_BOOK.exec(text);
  if (making) {
    let tail = (making[1] ?? '').replace(/^[\s.,;:!?]+/, '');
    let pages: string[] = [];
    const listed = BOOK_PAGES.exec(tail);
    if (listed) {
      pages = cellsOf((listed[1] ?? '').replace(/[\s.!?]+$/, '')).map((page) => noteNamed(page, notes)?.note.title ?? page);
      tail = tail.slice(0, listed.index);
    }
    const name = tail
      .replace(/^(?:called|named|titled|for|about|on)\s+/i, '')
      .replace(/[\s.,;:!?]+$/, '')
      .replace(/^["“]|["”]$/g, '')
      .trim();
    return name ? { kind: 'book', title: capitalise(name), pages } : null;
  }

  // "Move the pricing page to Done": a card, when the note being recorded has a board with that lane and no note by
  // that name is the better match.
  const moving = board ? MOVE_CARD.exec(text) : null;
  if (moving && board) {
    const lane = laneNamed(moving[2] ?? '', board);
    const note = noteNamed(moving[2] ?? '', notes);
    const item = (moving[1] ?? '').replace(/^(?:the|my|our)\s+/i, '').trim();
    if (lane && item && !/^(?:this|that|it|everything|these|those|them)$/i.test(item) && (!note || lane.score > note.score)) {
      return {
        kind: 'card',
        note: board,
        lane: lane.lane.name,
        words: item,
        change: laneChange(lane.lane, (body, fresh) => moveToLane(body, item, fresh)?.body ?? null),
      };
    }
  }
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
    let bestLane: { lane: Lane; score: number; thing: string } | null = null;
    for (const split of after.matchAll(INTO)) {
      const thing = after.slice(0, split.index).trim();
      const tail = after.slice((split.index ?? 0) + split[0].length);
      // The name runs to a stop or colon, and anything after that is the thing too ("…to work: call Sam").
      const [, name = tail, rest = ''] = /^([^.,;:!?]+)(?:[.,;:!?]\s*(.*))?$/.exec(tail) ?? [];
      const target = targets.find((word) => new RegExp(String.raw`\s+(?:in|on|to|into)\s+${word}\s*$`, 'i').test(name)) ?? null;
      const found = noteNamed(target ? name.replace(new RegExp(String.raw`\s+(?:in|on|to|into)\s+${target}\s*$`, 'i'), '') : name, notes);
      if (found && (!best || found.score > best.score)) best = { ...found, thing, rest: rest.trim() };
      const lane = board && !rest.trim() ? laneNamed(name, board) : null;
      if (lane && thing && (!bestLane || lane.score > bestLane.score)) bestLane = { ...lane, thing };
    }
    // A lane of the board being recorded into, named better than any note: a card for it.
    if (board && bestLane && (!best || bestLane.score > best.score) && !MOVERS.test(text)) {
      const noun = OBJECT_NOUN.exec(bestLane.thing);
      const said = (noun ? bestLane.thing.slice(noun[0].length) : bestLane.thing).trim();
      const item = capitalise(said);
      if (item && !/^(?:this|that|it|everything|these|those|them)$/i.test(item)) {
        return {
          kind: 'lane',
          note: board,
          lane: bestLane.lane.name,
          words: item,
          change: laneChange(bestLane.lane, (body, fresh) => addToLane(body, fresh, item)?.body ?? null),
        };
      }
    }
    if (best) {
      // A book named: the thing is a chapter, or this note ("put this in the field guide").
      if (isBook(best.note)) {
        const said = [best.thing, best.rest].filter(Boolean).join(' ');
        return chapterFor(best.note, said || (MOVERS.test(text) ? 'this' : ''));
      }
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
