import { isBookBody } from '../book/book.ts';
import { capitalise, escapeRegExp } from '../core/text.ts';
import { findNote, nameWords, spokenName } from './noteFind.ts';
import { parseRoute, type Candidate } from './route.ts';
import { ONE_TO_TEN } from './spoken/numbers.ts';
import { spokenListItems } from './spokenList.ts';

/**
 * "Glyph, add buy milk to HelloTrade": the keyword, and the plan a command's
 * words make, for the reader at Done (finalInstruction.ts).
 *
 * Matt, after "add a note to hello trade" became a new note called "To the
 * hello trade": "have it listen for keywords and not do anything until it
 * hears the keyword and confirms the action". So:
 *
 * - Nothing is a command until "Glyph" or "hey Ghost" is heard (`findKeyword`),
 *   or a mishearing of it followed by a command (`findMisheard`). What comes
 *   before it in the phrase stays in the note.
 * - The command is read loosely (`planCommand`), since the keyword already says
 *   it is one: "add buy milk to hello trade", "add a list item to HelloTrade",
 *   "put call Sam on the work list", plus every phrasing route.ts knew, the
 *   note found by its words (noteFind.ts).
 * - A plan read at Done is shown on a card and waits for a tap. Only two are
 *   carried out, words for a note and a new list by name; the rest - a table,
 *   a book or a chapter, a board, a move, a new note - are read so that the
 *   reader can turn them down rather than take them for words to add. What the
 *   live reader (liveRoute.ts) carries out as it is said, it reads with its own
 *   grammar (liveCommand.ts), which shares the keyword, its mishearings and the
 *   lead-ins with this.
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
 *
 * Only the phrase-at-a-time reader that has gone (docs/DESIGN.md §127) used these: neither the live reader nor the
 * reader at Done does, so they are kept here, tested, until it is decided whether the live reader's mishearings take
 * them.
 */
const SOUND_ALIKE = /^\s*(?:(?:hey|hi|ok(?:ay)?|so|a|add|head|hade|hate|take|tag)[,\s]+)?(?:life|live|lift|lip|cliff|clip|glide|slip)[,.;:!?]+\s*/i;

/**
 * What Whisper writes for "hey Ghost" and "hey Glyph" as words of their own: "Hey, like, add a note to…" (Glyph heard
 * as "like", "life" or "live"), "Hey goes add…", "Hi coast, add…" (Ghost). Matt said "hey, like add a note to house to
 * do's" and it became a note of its words. These are ordinary words, so one counts only at the very start of a phrase,
 * and only when what follows reads as a command (`findMisheard`, and each reader's own guard). Not "okay, like", nor
 * "hey, go", "hey, most" or "hey, post", which are how people talk: "Okay, like, I have to say it was a great run."
 */
const MISHEARD = /^\s*(?:hey|hi)[,.\s]+(?:like|life|live|goes|coast|host|toast|gost)(?=$|[\s,.;:!?])[,.;:!?]*\s*/i;

/** A mishearing of the keyword at the start of `text`, when `reads` says the rest is a command: the same shape as `findKeyword`. */
export function findMisheard(text: string, reads: (words: string) => boolean): { before: string; after: string } | null {
  const found = MISHEARD.exec(text);
  if (!found) return null;
  const after = text.slice(found[0].length).trim();
  return after && reads(after) ? { before: '', after } : null;
}

/**
 * What a person says before the command itself, taken off for reading and never from the words kept: "um", "okay",
 * "like", "please", "can you", and "I want to" or "let's" when "add" or "put" follows.
 */
export const LEAD_INS =
  /^\s*(?:(?:um+|uh+|er+|hmm+|ok(?:ay)?|alright|all right|so|and|like|well|right|please|just|now|hey|hi)(?:[,.\s]+|$)|(?:can|could|would|will)\s+you(?:[,.\s]+|$)|(?:i\s+want\s+to|i['’]?d\s+like\s+to|i\s+need\s+to|let['’]?s|go\s+ahead\s+and)\s+(?=(?:add|put|append)\b))+/i;

/** Whether `text` is only filler, which may come before the keyword and leave it the first thing said ("Um, hey Ghost"). */
export function onlyFiller(text: string): boolean {
  return text.replace(/[\s,.;:!?…"“]+/g, ' ').trim().replace(LEAD_INS, '').trim() === '';
}

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

// ---- the plan ---------------------------------------------------------------------------------

export interface Placement {
  /** "leave": into the list it fits, or a paragraph (listAppend.ts `leaveNote`). "item": always a list item. "paragraph": always its own paragraph. */
  how: 'leave' | 'item' | 'paragraph';
  task: boolean;
  /** "Items", "tasks": every phrase until a pause is one. */
  many: boolean;
  /** Semantic list area named explicitly by the command. */
  near?: 'bugs';
  /** The items already told apart ("a list with…"), so a comma inside one ("Parkersburg, West Virginia") stays in it. */
  items?: readonly string[];
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
  /** A standalone Speak request creates a separately titled list note, with the items said for it. */
  | { kind: 'create-list'; title: string; items?: readonly string[] }
  /** A table asked for, in a named note or this one: read so the reader at Done can turn it down, since a recording makes none. */
  | { kind: 'table'; note: N | null; columns: string[] }
  /** "Glyph, make this a board": read so the reader at Done can turn it down (a board is made with More > Make a board). */
  | { kind: 'board' }
  /** "Make a book called Field guide with Trees, Birds and Rivers": a book note, its pages the notes named or chapters still to write (docs/BOOKS.md). */
  | { kind: 'book'; title: string; pages: string[] }
  /** A chapter for a book: "add a chapter called Trees to the field guide". `title` null is this note: "put this in the field guide". */
  | { kind: 'chapter'; note: N; title: string | null }
  /** A note was named that there is no note for. */
  | { kind: 'no-note'; name: string };

/** The plans the reader at Done carries out, once their card is tapped: words for a note, and a new list by name. */
export type FinalPlan<N extends Candidate = Candidate> = Extract<Plan<N>, { kind: 'place' | 'create-list' }>;

const LEAD = /^\s*(?:(?:please|can you|could you|would you|and|so|ok(?:ay)?|um+|uh+)[,\s]+)+/i;
const MOVERS = /^\s*(?:switch|go|jump|change|move|carry on|continue)\b/i;

/** "a list item", "a task", "a note that says" at the front of what is being added: the kind of thing, not the thing. */
const OBJECT_NOUN = /^(?:(?:a|an|another|one more|some|new)\s+)?(?:quick\s+)?(?:(list\s+)?(items?|entry|entries|bullets?|points?)|(tasks?|to-?\s?dos?|check\s?box(?:es)?)|(notes?|lines?|reminders?|comments?|memos?)|(bugs?|issues?|defects?))(?:\s+(?:about|that\s+says|saying|which\s+says|called|:|,))?\s*/i;

const TABLE = /^(?:add|make|create|start|put|insert|draw|build|new)\s+(?:(?:a|an|another|one)\s+)?(?:new\s+)?table\b(.*)$/i;
const CREATE_LIST = /^(?:(?:please\s+)?(?:make|create|start)\s+(?:(?:me\s+)?(?:a|another)\s+)?(?:new\s+)?list|(?:i\s+(?:need|want|would\s+like))\s+(?:a\s+)?new\s+list)\s+(?:called|named|titled)\s+(.+)$/i;
const ADD_TO_LIST = /^(?:please\s+)?(?:add|put|append)\s+(?:these\s+)?(?:items?\s+)?(?:to|in|into|on)\s+(?:the\s+)?(.+?)\s+list(?:\s+(?:that\s+)?(?:i\s+(?:need|want)|with|containing|:))?\s+(.+)$/i;
const DIRECT_APPEND = /^(?:please\s+)?(?:add|put|append)\s+(?:(?:this|these|the\s+following)\s+)?to\s+(?:(?:the|my|our)\s+)?(?:(?:note|list|page)\s+(?:that(?:'s|\s+is)\s+)?(?:label(?:ed|led)|called|named|titled)\s+|note\s+)?(.+)$/i;

/**
 * What is added, when it says it is a list: "a list with…", "a to-do list of…", "the following items:", "these
 * tasks…". The words after it are the items, told apart by `spokenListItems`.
 */
const LIST_INTRO = /^(?:(?:a|an|the|this|my)\s+)?(?:(?:new|short|quick)\s+)?(?:(?:bullet(?:ed)?|bulleted|numbered|check(?:ed)?|(to-?\s?do|task|check)|shopping|grocery)\s+)?(?:list|items?|(tasks?|to-?\s?dos?|check\s?list))\s*(?:(?:of|with|containing|including|that\s+(?:has|says|includes)|saying|for)\b|:|,|-)\s*|^(?:the\s+following(?:\s+(?:items?|things|places|(tasks?|to-?\s?dos?)))?|(?:these|those)\s+(?:items?|things|places|(tasks?|to-?\s?dos?)))\s*(?::|,|-)?\s*/i;

/** "…and add to the list", "…then put", ", add these": where a new list's title ends and its items begin. */
const THEN_ADD = /(?:\s*[,.;:]\s*|\s+)(?:(?:and|then|and\s+then)\s+)?(?:add|put)\s+/i;
/** "…with", "…containing", "…:": the same, when what follows is plainly several items. */
const WITH_ITEMS = /\s+(?:with|containing|including|that\s+has|of)\s+|\s*:\s*/i;
const THE_LIST = String.raw`(?:(?:the|that|this|my)\s+)?(?:new\s+)?(?:list|note|it)`;
const INTO_LIST_FIRST = new RegExp(String.raw`^(?:to|in|on|into|onto)\s+${THE_LIST}\b\s*[,:]?\s*`, 'i');
const INTO_LIST_LAST = new RegExp(String.raw`\s+(?:to|in|on|into|onto)\s+${THE_LIST}\s*$`, 'i');
const THESE = /^(?:(?:these|the\s+following)(?:\s+(?:items?|things))?|items?)\s*[,:]?\s+/i;

/**
 * "Comic books and add to the list Spider-Man, Batman and Superman": the new list's title, and its items when some
 * were said. A title that merely contains "with" ("Books with pictures") stays a title: only several items split it.
 */
function titleAndItems(said: string): { title: string; items: string[] } {
  const added = THEN_ADD.exec(said);
  if (added && added.index > 0) {
    const rest = said
      .slice(added.index + added[0].length)
      .replace(INTO_LIST_FIRST, '')
      .replace(INTO_LIST_LAST, '')
      .replace(THESE, '')
      .trim();
    const items = spokenListItems(rest);
    if (items.length) return { title: said.slice(0, added.index).trim(), items };
  }
  const listed = WITH_ITEMS.exec(said);
  if (listed && listed.index > 0) {
    const items = spokenListItems(said.slice(listed.index + listed[0].length).replace(THESE, ''));
    if (items.length > 1) return { title: said.slice(0, listed.index).trim(), items };
  }
  return { title: said, items: [] };
}

/** A named note's words, as a list when they say they are one. */
function directPayload(text: string): Pick<Placement, 'how' | 'task' | 'many' | 'items'> & { text: string } {
  const intro = LIST_INTRO.exec(text);
  const rest = intro ? text.slice(intro[0].length).trim() : '';
  if (!intro || !rest) return { text, how: 'leave', task: false, many: false };
  const items = spokenListItems(rest);
  const task = Boolean(intro[1] || intro[2] || intro[3] || intro[4]);
  return { text: items.join(', '), how: 'item', task, many: items.length > 1, items };
}

/** `text` without an "end" or "stop" said last: a stop cue is the recording's control, never the command's words. */
function stripStopCue(text: string): string {
  return text.replace(/(?:[.!?]\s*)?\b(?:end|stop)\s*[.!?]*\s*$/i, '').trim();
}

/**
 * The command in a finished recording, or null when it is not one: what is left once a leading "hey Ghost", "okay",
 * "um" or "can you" is gone, if that starts like a command. Only the very start counts, so a command said inside a
 * sentence ("I told Sam, add to…") stays words.
 */
export function finalCommandWords(text: string): string | null {
  let words = stripStopCue(text.trim()).replace(/^[\s.,;:!?…"“]+/, '');
  let keyed = false;
  for (let pass = 0; pass < 3; pass += 1) {
    const before = words;
    const keyword = findKeyword(words) ?? findMisheard(words, (after) => isStandaloneCommandLike(after.replace(LEAD_INS, '')));
    if (keyword && onlyFiller(keyword.before)) {
      words = keyword.after;
      keyed = true;
    }
    // After the keyword, what a person says before a command goes too ("like, add…", "I want to add…"); without it,
    // only the words that never start a sentence of their own, so "Just put the parcel in the post" stays one.
    words = words.replace(keyed ? LEAD_INS : PLAIN_LEAD, '').trim();
    if (words === before) break;
  }
  return isStandaloneCommandLike(words) ? words : null;
}

/** What comes before a command said without the keyword that is not the command: "okay", "um", "can you". */
const PLAIN_LEAD = /^\s*(?:(?:hey|hi|please|can you|could you|would you|will you|and|so|ok(?:ay)?|alright|all right|um+|uh+|er+|hmm+)[,.\s]+)+/i;

/** Narrow gate for no-wake commands in a fresh main Speak capture. */
export function isStandaloneCommandLike(text: string): boolean {
  return /^(?:please\s+)?(?:make|create|new|add|put|append|i\s+(?:need|want|would\s+like)\s+(?:a\s+)?new)\b/i.test(stripStopCue(text));
}

/** Split only unmistakable short enumerations; preserve ordinary phrases. */
function splitSpokenItems(text: string, allowBareWords = false): string[] {
  const cleaned = text.trim().replace(/^(?:that\s+)?i\s+(?:need|want)\s+/i, '').replace(/[.!?]+$/, '').trim();
  const punctuated = cleaned.split(/\s*(?:,|;|\band\b)\s*/i).filter(Boolean);
  if (punctuated.length > 1) return punctuated;
  const words = cleaned.split(/\s+/).filter(Boolean);
  return allowBareWords && words.length >= 2 && words.length <= 8 && words.every((word) => /^[\p{L}\p{N}'-]+$/u.test(word)) ? words : [cleaned];
}

/** "…with columns bug, owner and status": the labels said with a table, read as its shape is (`TABLE`). */
const TABLE_COLUMNS = /\s*,?\s*(?:with|using|that has|having)\s+(?:the\s+)?(?:columns?|column labels?|headings?|headers?|labels?)\s*(?:of|:|,)?\s*(.+)$/i;

/** Words that name a column or row position, said before a cell: "column one, bug". */
const POSITION = new RegExp(String.raw`^(?:(?:column|row|cell)\s+(?:\d+|${ONE_TO_TEN})|first|second|third|fourth|fifth|next|then|last)[,:\s]+`, 'i');
/** A position said with nothing after it ("column two"): no cell at all. */
const POSITION_ALONE = new RegExp(String.raw`^(?:column|row)\s+(?:\d+|${ONE_TO_TEN})$`, 'i');

/**
 * What was said, as cells: a table's column labels, or a book's pages. People say them the way they say a list, so
 * commas (or semicolons) split it, with "and" before the last one; with no commas, "and" alone does. "Column one,
 * bug, column two, owner" keeps only the cells.
 */
export function cellsOf(text: string): string[] {
  // Whisper often writes the pauses between cells as full stops: "Item. Where. Packed."
  const said = text
    .trim()
    .replace(/^[\s.,;:!?]+/, '')
    .replace(/[.!?]+$/, '')
    .replace(/\.\s+/g, ', ')
    .trim();
  if (!said) return [];
  // "Bug, owner and status": the last of a comma list carries the "and".
  const parts = /[,;]/.test(said)
    ? said.split(/\s*[,;]\s*/).flatMap((part, i, all) => (i === all.length - 1 ? part.split(/\s+and\s+/i) : [part]))
    : said.split(/\s+and\s+/i);
  return parts
    .map((part) => part.replace(/^(?:and|then)\s+/i, '').replace(POSITION, '').trim())
    .filter((part) => part && !POSITION_ALONE.test(part))
    .map((part) => capitalise(part));
}

/** A preposition that can end what is added and start the note's name. */
const INTO = /(?:^|\s+)(?:to|in|into|onto|on|under|for)\s+/gi;

/**
 * The note a spoken name means, when one clearly does (noteFind.ts): "the house list" and "house chores" are House
 * TODOs. Only a resolved note counts here; a name that is unsure, or means the note being written to, is no note.
 */
function noteNamed<N extends Candidate & { note?: { body: string } }>(raw: string, notes: readonly N[]): { note: N; score: number } | null {
  // "Node" is how base.en writes "note" said quickly.
  const name = spokenName(raw).replace(/\s+node$/i, '').trim();
  if (name.length < 2) return null;
  const found = findNote(name, notes);
  return found.status === 'resolved' ? { note: found.note, score: found.score } : null;
}

/** Match an actual title at the start of a spoken tail, case/punctuation-insensitively. */
function titledPrefix<N extends Candidate>(tail: string, notes: readonly N[]): { note: N; text: string } | null {
  const found = notes
    .map((note) => {
      const words = note.title.trim().replace(/[^\p{L}\p{N}]+/gu, ' ').trim().split(/\s+/).filter(Boolean);
      if (!words.length) return null;
      const pattern = words.map((word) => escapeRegExp(word)).join(String.raw`[\s\p{P}_]+`);
      const match = new RegExp(String.raw`^\s*${pattern}(?:[\s\p{P}_]+)(.+)$`, 'iu').exec(tail);
      return match?.[1]?.trim() ? { note, text: match[1].trim() } : null;
    })
    .filter((value): value is { note: N; text: string } => value !== null);
  return found.length === 1 ? (found[0] ?? null) : null;
}

/**
 * A spoken name at the start of a tail, found as any name is (noteFind.ts), and what follows it: up to a comma, colon
 * or semicolon when there is one ("add to house to-dos, call an electrician"), otherwise the first few words that
 * name a note clearly, the best of them ("add to house to-dos call an electrician").
 */
function namedPrefix<N extends Candidate & { note?: { body: string } }>(tail: string, notes: readonly N[]): { note: N; text: string } | null {
  const stop = /^([^,:;]+?)\s*[,:;]\s*(.+)$/.exec(tail);
  if (stop?.[1] && stop[2]?.trim()) {
    const found = noteNamed(stop[1], notes);
    return found ? { note: found.note, text: stop[2].trim() } : null;
  }
  const words = tail.trim().split(/\s+/);
  // The whole tail a name as good as any part of it: it is the name ("add this to the field guide"), with nothing after.
  const whole = noteNamed(tail, notes);
  let best: { note: N; score: number; text: string } | null = null;
  for (let k = 1; k <= Math.min(6, words.length - 1); k += 1) {
    const found = noteNamed(words.slice(0, k).join(' '), notes);
    // A kind word that scores the same belongs to the name: "house chores", not "house" and then "chores call…".
    const kind = nameWords(words[k - 1] ?? '').distinctive.length === 0;
    if (found && (!best || found.score > best.score || (found.score === best.score && kind))) best = { note: found.note, score: found.score, text: words.slice(k).join(' ') };
  }
  return best && (!whole || best.score > whole.score) ? { note: best.note, text: best.text } : null;
}

function placementOf(noun: RegExpExecArray | null): Placement {
  if (noun?.[3]) return { how: 'item', task: true, many: /s$|es$/i.test(noun[3]) };
  // Group 2 is "items"/"bullets", group 5 is "bugs"/"issues": both are list
  // items. A bug request also carries its semantic area to list placement.
  if (noun?.[5]) return { how: 'item', task: false, many: /s$|ies$/i.test(noun[5]), near: 'bugs' };
  if (noun?.[2]) return { how: 'item', task: false, many: /s$|ies$/i.test(noun[2]) };
  return { how: 'leave', task: false, many: false };
}

/** What the words after the keyword ask for, or null when they don't say yet. `notes` are the notes that can be named. */
export interface PlanOptions<N extends Candidate & { note?: { body: string } }> {
  notes: readonly N[];
}

export function planCommand<N extends Candidate & { note?: { body: string } }>(words: string, options: PlanOptions<N>): Plan<N> | null {
  const plan = readCommand(words, options);
  // What is added is words, not the end of a spoken sentence, and not how it was introduced ("The note is …").
  // Spoken quote cues are user punctuation, not literal command prose.
  return plan?.kind === 'place'
    ? {
        ...plan,
        text: withoutPayloadLead(plan.text)
          .replace(/\bquote\s+(.+?)\s+quote\b/gi, '"$1"')
          .replace(/[\s.,;:!?]+$/, ''),
      }
    : plan;
}

/**
 * How a person introduces what a note should say, which is not what it says: "The note is call an electrician", "it
 * says…", "the item is…". Matt's "add a note to house to do's, the note is call an electrician to fix the light
 * sockets" put "The note is" in the list.
 */
export const PAYLOAD_LEAD =
  /^\s*(?:(?:and\s+)?(?:the|my|this)\s+(?:note|item|task|to-?\s?do|reminder|line|entry)\s+(?:is|says|reads|should\s+say|will\s+say)|it\s+says|that\s+says|which\s+says|saying|to\s+say)(?:\s*[:,-]\s*|\s+)(?=\S)/i;

/** `text` without the words that introduced it (`PAYLOAD_LEAD`). */
export function withoutPayloadLead(text: string): string {
  return text.replace(PAYLOAD_LEAD, '');
}

/** "Make this a board", "turn the list into a kanban board". */
const MAKE_BOARD = /^(?:make|turn|change)\s+(?:this|it|this\s+note|the\s+note|this\s+list|the\s+list)\s+(?:into\s+)?(?:a\s+)?(?:kanban\s+)?(?:board|kanban)[.!]?$/i;

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
  return title ? { kind: 'chapter', note, title: capitalise(title) } : { kind: 'await', note, how: 'leave', task: false, many: false };
}

/**
 * A plan read for a book (docs/BOOKS.md): words placed in it are a chapter, and moving this recording there makes
 * this note one. Every plan the rules make goes through it, so "add Trees to the field guide" is a chapter, which the
 * reader at Done turns down, and never words for the book's index.
 */
export function forBook<N extends Candidate & { note?: { body: string } }>(plan: Plan<N>): Plan<N> {
  if (plan.kind === 'place' && isBook(plan.note)) return chapterFor(plan.note, plan.text);
  if (plan.kind === 'move' && isBook(plan.note)) return { kind: 'chapter', note: plan.note, title: null };
  return plan;
}

function readCommand<N extends Candidate & { note?: { body: string } }>(words: string, options: PlanOptions<N>): Plan<N> | null {
  const plan = readWords(words, options);
  return plan ? forBook(plan) : null;
}

function readWords<N extends Candidate & { note?: { body: string } }>(words: string, { notes }: PlanOptions<N>): Plan<N> | null {
  const text = stripStopCue(words.replace(LEAD, '').trim());
  if (!text) return null;
  if (MAKE_BOARD.test(text)) return { kind: 'board' };
  const createList = CREATE_LIST.exec(text);
  if (createList?.[1]) {
    const { title, items } = titleAndItems(createList[1].replace(/[.!?]+$/, '').trim());
    return title ? { kind: 'create-list', title, ...(items.length ? { items } : {}) } : null;
  }
  const addList = ADD_TO_LIST.exec(text);
  if (addList?.[1] && addList[2]) {
    const found = noteNamed(addList[1], notes);
    if (found) {
      const items = splitSpokenItems(addList[2], true);
      return { kind: 'place', note: found.note, text: items.join(', '), how: 'item', task: false, many: items.length > 1 };
    }
  }
  // "Add to my note labeled Go a list with…" also reads as "add to <my note labeled Go a> list with…": when that name
  // is no note, the labeled note is the reading, and the no-note answer waits until it has failed too.
  const missing: Plan<N> | null = addList?.[1] && addList[2] ? { kind: 'no-note', name: addList[1].replace(/[\s.,;:!?]+$/, '').trim() } : null;
  const directAppend = DIRECT_APPEND.exec(text);
  if (directAppend?.[1]) {
    // 'labeled "Go" a list…': the quotes are the title's, not the words'.
    const named = /^["“]([^"”]+)["”]\s*(.*)$/.exec(directAppend[1]);
    const tail = named ? `${named[1]} ${named[2]}` : directAppend[1];
    const found = titledPrefix(tail, notes) ?? namedPrefix(tail, notes);
    if (found) return { kind: 'place', note: found.note, ...directPayload(found.text.replace(/^[\s,:;-]+/, '')) };
    // "Add this to the field guide": a whole title with nothing after it is this recording going there, which the
    // rules below read (a chapter, when the note is a book). Only a shape with words after the title fails closed
    // here, when no unique title is found.
    if (!noteNamed(directAppend[1], notes)) return missing ?? { kind: 'no-note', name: directAppend[1].replace(/[\s.,;:!?]+$/, '').trim() };
  }
  if (missing) return missing;

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

  const route = parseRoute(ended);
  if (route?.kind === 'new') return { kind: 'new' };
  if (route?.kind === 'item') {
    const note = find(route.name);
    if (!note) return { kind: 'no-note', name: route.name };
    const placement: Placement = { how: 'item', task: route.task, many: route.many };
    return route.rest ? { kind: 'place', note, text: route.rest, ...placement } : { kind: 'await', note, ...placement };
  }
  if (route?.kind === 'leave') {
    const note = find(route.name);
    if (!note) return { kind: 'no-note', name: route.name };
    const placement: Placement = { how: 'leave', task: false, many: false };
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
      const found = noteNamed(name, notes);
      if (found && (!best || found.score > best.score)) best = { ...found, thing, rest: rest.trim() };
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
    if (route.rest) return { kind: 'place', note, text: route.rest, how: 'leave', task: false, many: false };
    return MOVERS.test(text) ? { kind: 'move', note } : { kind: 'await', note, how: 'leave', task: false, many: false };
  }
  return null;
}
