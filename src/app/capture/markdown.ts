/**
 * Speech, turned into a note.
 *
 * Local rules, run on every committed Whisper segment with no network and no
 * delay: they catch the spoken cues the guide teaches ("new paragraph",
 * "bullet point", "heading", "check box", "bold … end bold"), the obvious
 * to-dos ("I need to..."), a spoken enumeration after a word that introduces
 * one ("I need eggs, milk and bread"), and an ordinal run ("first... second...
 * finally..."). Nothing else decides the shape of a note: it is what was said,
 * laid out by what was said.
 *
 * Deliberately heuristic and deliberately high-precision. A rule that turns a
 * sentence into a list it was not is worse than one that misses a list, because
 * a missed list is still readable prose and a false one mangles it; so the
 * enumeration rule demands a list-introducing word before the items, and short
 * items after it, rather than trusting commas.
 */

export interface Segment {
  text: string;
  startMs: number;
  endMs: number;
}

export interface RenderedNote {
  markdown: string;
  /** Where the in-progress, uncommitted phrase begins, or null when there is none. */
  pendingFrom: number | null;
  /** The committed transcript, paragraphs joined by blank lines. */
  plain: string;
}

/**
 * A pause long enough to be a new thought.
 *
 * The engine commits a segment on a much shorter pause (about 600 ms), which is
 * a breath rather than a paragraph; treating every commit as a paragraph break
 * would turn a note into a column of one-line fragments. Two seconds is where
 * spoken notes measurably change subject - long enough that a speaker thinking
 * mid-sentence does not trigger it.
 */
export const PARAGRAPH_GAP_MS = 2000;

const PARAGRAPH_CUE = /\b(?:new|next) paragraph\b[.,!?]?/gi;

// ---- paragraphs and sentences ----------------------------------------------

const capitalise = (text: string): string => text.charAt(0).toUpperCase() + text.slice(1);

const stripEnd = (text: string): string => text.replace(/[\s.,;:!?]+$/, '');

/** Committed segments, grouped into paragraphs by pause length and spoken cue. */
export function toParagraphs(segments: readonly Segment[]): string[] {
  const paragraphs: string[] = [];
  let current = '';
  let lastEnd: number | null = null;

  const flush = () => {
    const text = current.trim();
    if (text) paragraphs.push(capitalise(text));
    current = '';
  };

  for (const segment of segments) {
    const text = segment.text.trim();
    if (!text) continue;
    if (lastEnd !== null && segment.startMs - lastEnd > PARAGRAPH_GAP_MS) flush();
    lastEnd = segment.endMs;

    text.split(PARAGRAPH_CUE).forEach((piece, index) => {
      if (index > 0) flush();
      const part = piece.replace(/^[\s.,;:!?]+/, '').trim();
      if (part) current = current ? `${current} ${part}` : part;
    });
  }
  flush();
  return paragraphs;
}

interface Sentence {
  text: string;
}

/**
 * The sentences of a paragraph.
 *
 * Whisper punctuates and capitalises, so a terminal mark followed by a capital
 * is a reliable boundary for speech in a way it is not for typed prose (which
 * has "e.g. Smith" and version numbers).
 */
function sentencesOf(paragraph: string): Sentence[] {
  const out: Sentence[] = [];
  // A sentence can now start with inline markup ("**Friday** is the
  // deadline"), so the lookahead allows asterisks and underscores before the
  // capital; without them the two sentences merged.
  const boundary = /(?<=[.!?*_])\s+(?=["'([*_]*[A-Z0-9])/g;
  let start = 0;
  for (const match of paragraph.matchAll(boundary)) {
    const end = match.index ?? 0;
    const text = paragraph.slice(start, end).trim();
    if (text) out.push({ text });
    start = end + match[0].length;
  }
  const tail = paragraph.slice(start).trim();
  if (tail) out.push({ text: tail });
  return out;
}

// ---- the local rules --------------------------------------------------------

const HEADING_CUE = /^(?:new\s+section|section|heading)[:,.]?\s+(.+)$/i;
const BULLET_CUE = /^(?:bullet(?:\s+point)?|(?:next|new)\s+(?:point|item|bullet))[:,.]?\s+(.+)$/i;
const TITLE_CUE = /^(?:title|note\s+title|call\s+(?:this|it)(?:\s+note)?)[:,.]?\s+(.+)$/i;
const IMPORTANT_CUE = /^(important|key\s+point|note)[:,]\s*(.+)$/i;
const TASK = /^(?:(?:i|we)\s+(?:really\s+)?(?:need|have|got)\s+to|remember\s+to|don'?t\s+forget\s+to|do\s+not\s+forget\s+to|remind\s+me\s+to|to[\s-]?do[:,]?|task[:,])\s+(.+)$/i;
const ORDINAL = /^(first(?:ly)?|second(?:ly)?|third(?:ly)?|fourth(?:ly)?|fifth(?:ly)?|next|then|after\s+that|finally|lastly)[,:]?\s+(.+)$/i;
const ORDINAL_START = /^first(?:ly)?\b/i;

/*
 * Cues added for the "how to talk to Glyph" guide. Each one that could be
 * ordinary speech demands the comma or colon Whisper writes after a spoken
 * pause, because that pause is the only thing separating a command from a
 * sentence: "Number one, book flights" is a list item, "number one priority is
 * sleep" is prose, and only the comma tells them apart.
 */
const QUOTE_CUE = /^quote[:,]\s*(.+)$/i;
const NUMBER_CUE = /^number\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2})[:,]\s*(.+)$/i;
const CHECKBOX_CUE = /^(?:check\s?box[:,.]?|checklist(?:\s+item)?[:,]|check\s+item[:,])\s*(.+)$/i;
const DIVIDER_CUE = /^(?:divider|horizontal\s+(?:line|rule)|separator)[.!]?$/i;

/**
 * A cue said on its own, as its own sentence.
 *
 * The way people actually dictate a command is word, pause, content - and
 * Whisper writes the pause as a full stop, so "Heading. Groceries." arrives as
 * two sentences and the cue regexes above, which expect the content in the same
 * sentence, never saw it: the note got the literal word "Heading." Now a
 * sentence that is nothing but a cue is held and applied to the next sentence,
 * across a paragraph break if the pause was long.
 *
 * It doubles as the guard against prompt leakage. Whisper is prompted with the
 * cue vocabulary so it spells cue words consistently, and a model prompted with
 * words can echo them on a quiet window. An echoed "Bullet point." with nothing
 * after it is held forever and never rendered, instead of appearing in the note.
 */
const STANDALONE_CUE =
  /^(title|note\s+title|heading|section|new\s+section|bullet(?:\s+point)?|(?:next|new)\s+(?:point|item|bullet)|quote|check\s?box|checklist(?:\s+item)?|check\s+item|to[\s-]?do|task|important|key\s+point|number\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2}))[.,:!]?$/i;

/** A plugin's formatting said the way bold is: its cue word, and the delimiter the words it wraps are put between. */
export interface SpokenFormat {
  word: string;
  delimiter: string;
}

/**
 * The plugin formattings that can be said, set by the recorder from the switched-on plugins (plugins/types.ts
 * `InlineFormat.cue`; the Spoiler plugin's "spoiler … end spoiler" wraps the words in `||`). Held here rather than
 * read from the registry so this file stays pure and testable.
 */
let spokenFormats: readonly SpokenFormat[] = [];

export function setSpokenFormats(formats: readonly SpokenFormat[]): void {
  spokenFormats = formats.filter((format) => /^[a-z][a-z ]*[a-z]$/i.test(format.word.trim()) && format.delimiter);
}

const escapeWord = (word: string) => word.trim().replace(/\s+/g, '\\s+');

function inlineMarkup(formats: readonly SpokenFormat[]): RegExp {
  const words = ['bold', 'italics?', 'emphasis', ...formats.map((format) => escapeWord(format.word))];
  return new RegExp(`\\b(${words.join('|')})\\b([.,:;!]?)\\s+([\\s\\S]+?)[.,;:!]?\\s+(end|and)\\s+\\1\\b([.,;:!?]?)`, 'gi');
}

/**
 * Spoken inline markup: "bold ... end bold", "italic ... end italic", and a
 * plugin's own ("spoiler ... end spoiler", `setSpokenFormats`).
 *
 * Matched across a whole paragraph rather than inside one sentence, because a
 * speaker pauses around the words being marked and Whisper turns each pause
 * into a full stop - "the deadline is bold. Friday. End bold." - so a
 * sentence-level rule would never see both halves. Both halves are required:
 * "a bold move" has no "end bold" and is left alone. The punctuation Whisper
 * put after "end bold" is kept, so the sentence after it still starts a new
 * sentence.
 *
 * "and bold" also closes, but only when Whisper put a mark straight after the
 * opening word ("Italics, maybe, and italics."). The two words sound almost
 * the same, and on synthesised speech base.en wrote "and" for "end" in most
 * voices even with the cue vocabulary as its prompt. The mark shows the
 * speaker paused after saying the cue; "bold and bold" in running prose has no
 * pause there and is left alone.
 */
export function spokenInlineMarkup(paragraph: string, formats: readonly SpokenFormat[] = spokenFormats): string {
  return paragraph.replace(inlineMarkup(formats), (match, kind: string, paused: string, inner: string, closer: string, after: string) => {
    if (closer.toLowerCase() === 'and' && !paused) return match;
    const words = inner.trim().replace(/[.,;:!]+$/, '');
    const said = kind.toLowerCase().replace(/\s+/g, ' ');
    const format = formats.find((f) => f.word.trim().toLowerCase().replace(/\s+/g, ' ') === said);
    const marker = format ? format.delimiter : said === 'bold' ? '**' : '_';
    return `${marker}${words}${marker}${after}`;
  });
}

/**
 * Words after which a comma-separated run is a list rather than a clause.
 *
 * The whole precision of the enumeration rule rests here. "I need eggs, milk
 * and bread" is a list because of "need"; "we went to the store, bought food,
 * and came home" has the same commas and is not, and the difference is that
 * nothing before its first comma introduces a list.
 */
const LIST_INTRO = /\b(?:need|needs|want|wants|buy|get|grab|bring|pack|include|includes|including|like|such\s+as|are|were|is|was|with|pick\s+up)$/i;

/*
 * Lists said the way people actually say them, not in cue words. Matt's first
 * real list on the Fold was "list item is weed", "the next list item is …"
 * and "and lastly, the final item that we need on our list is a gallon of
 * black coffee": all prose under the cue rules, because nobody says "bullet
 * point" to a phone.
 *
 * An item phrase names an item and then gives it: "list item is X", "the next
 * item is X", "another one is X", "item number three is X", "the last thing
 * we need on the list is X". Still high precision: a bare "item" or "thing"
 * needs an ordinal or the word "list" with it, so "the thing is, I'm tired"
 * and "the item is broken" stay sentences.
 */
const LEADERS = String.raw`(?:(?:and|so|ok(?:ay)?|also|plus|then|lastly|finally|next|oh)[,\s]+)*`;
const ARTICLE = String.raw`(?:(?:the|a|an|my|our)\s+)?`;
const ORDINAL_WORD = String.raw`(?:first|second|third|fourth|fifth|sixth|next|last|final|another|other|new|1st|2nd|3rd|4th|5th)`;
const COUNT_WORD = String.raw`(?:one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2})`;
const NAMED_ITEM = [
  // "list item", "the next list item", "list item number two"
  String.raw`(?:${ORDINAL_WORD}\s+)?list\s+(?:item|entry)(?:\s+(?:number\s+)?${COUNT_WORD})?`,
  // "the next item", "another thing", "the final one", "item number two"
  String.raw`${ORDINAL_WORD}\s+(?:item|thing|entry|one)(?:\s+(?:number\s+)?${COUNT_WORD})?`,
  String.raw`item\s+number\s+${COUNT_WORD}`,
  // "the item on the list", "the thing we need on our list"
  String.raw`(?:item|thing)(?=.*\b(?:on|in|for|to)\s+(?:the|our|my|this)\s+(?:\w+\s+)?list\b)`,
].join('|');
const WHICH = String.raw`(?:\s+(?:that\s+|which\s+)?(?:we|i|you)(?:'ll|\s+will)?\s+(?:really\s+)?(?:need|want|have|should\s+get|need\s+to\s+(?:get|buy|add|grab))(?:\s+to\s+(?:get|buy|add|grab))?)?`;
const ON_LIST = String.raw`(?:\s+(?:on|in|for|to)\s+(?:the|our|my|this)\s+(?:\w+\s+)?list)?`;
const ITEM_PHRASE = new RegExp(String.raw`^${LEADERS}${ARTICLE}(?:${NAMED_ITEM})${WHICH}${ON_LIST}\s*(?:is|are|will\s+be|would\s+be|should\s+be|[:,-])\s+(.+)$`, 'i');

/**
 * An item phrase that stops before its item: "The next item is." Whisper
 * commits a phrase at a breath, so "the next item is … Paris" arrives as two:
 * the phrase, then the item. Held, and the next sentence is taken as the item.
 */
const ITEM_OPENER = new RegExp(String.raw`^${LEADERS}${ARTICLE}(?:${NAMED_ITEM})${WHICH}${ON_LIST}\s*(?:is|are|will\s+be|would\s+be|should\s+be)?\s*[.:,-]?\s*$`, 'i');

/**
 * Whisper's own numbering, written inline when it hears a list being
 * dictated: "1. The Grand Canyon 2. Spain 3. The next item is". Two or more
 * markers counting up one at a time are that; each piece becomes a spoken
 * "number N," cue so the numbered rule lays it out, and a piece that is only
 * an item phrase is left for the next phrase to finish. A year ("1990.") or
 * a lone "2." in a sentence is not a run.
 */
export function inlineNumbering(paragraph: string): string {
  const markers = [...paragraph.matchAll(/(^|\s)(\d{1,2})\.\s+(?=\S)/g)];
  if (markers.length < 2) return paragraph;
  const numbers = markers.map((m) => Number(m[2]));
  if (numbers.some((n, i) => i > 0 && n !== (numbers[i - 1] ?? 0) + 1)) return paragraph;
  const starts = markers.map((m) => (m.index ?? 0) + (m[1] ?? '').length);
  const prefix = paragraph.slice(0, starts[0]).trim();
  const pieces = markers.map((m, i) => {
    const bodyStart = (m.index ?? 0) + m[0].length;
    const end = i + 1 < starts.length ? starts[i + 1] : paragraph.length;
    const text = stripEnd(paragraph.slice(bodyStart, end).trim());
    if (!text) return '';
    return ITEM_OPENER.test(text) ? `${capitalise(text)}.` : `Number ${numbers[i]}, ${text}.`;
  });
  return [prefix, ...pieces].filter(Boolean).join(' ');
}

/** The item an item phrase gives, or null: "The next list item is oat milk." is "Oat milk". */
export function itemOf(text: string): string | null {
  const match = ITEM_PHRASE.exec(text.trim());
  const item = match?.[1] ? stripEnd(match[1].trim()) : '';
  return item ? capitalise(item) : null;
}

/**
 * A sentence that announces a list: "add a list below", "here's my shopping
 * list", "make a numbered list". Its own words stay; the short sentences after
 * it are taken as the list's items until a longer one ends it.
 */
const LIST_ANNOUNCE =
  /\b(?:add|make|start|create|write|begin|do)\s+(?:up\s+)?(?:a|an|the|my|our|this|another)?\s*(?:new\s+|quick\s+)?(?:(numbered|numbering|ordered|bullet(?:ed)?|bullet\s+point|shopping|grocery|to-?\s?do|packing|reading|check)\s+)?list\b|\b(?:here(?:'s|\s+is)|this\s+is|that'?s)\s+(?:a|the|my|our)\s+(?:(numbered|\w+)\s+)?list\b/i;

/** Whether `text` announces a list, and whether it asked for numbers. */
function announcesList(text: string): 'number' | 'bullet' | null {
  const match = LIST_ANNOUNCE.exec(text);
  if (!match) return null;
  const kind = (match[1] ?? match[2] ?? '').toLowerCase();
  return /^(?:numbered|numbering|ordered)$/.test(kind) ? 'number' : 'bullet';
}

/** Short enough, and noun-shaped enough, to be an item in a list someone announced. */
const MAX_OPEN_ITEM_WORDS = 5;
function itemShaped(text: string): boolean {
  const body = stripEnd(text);
  if (!body || words(body) > MAX_OPEN_ITEM_WORDS || /\?\s*$/.test(text)) return false;
  // "I'm tired", "It works", "That's it": a sentence, not an item.
  return !/^(?:i|i'm|im|we|we're|you|he|she|it|it's|they|this|that|that's|there|there's|so|and\s+then)\b/i.test(body);
}

const MAX_ITEM_WORDS = 4;
const words = (text: string): number => text.trim().split(/\s+/).filter(Boolean).length;

/** "I need eggs, milk, bread and coffee" as an intro and its items, or null. */
export function enumeration(sentence: string): { intro: string; items: string[] } | null {
  const body = stripEnd(sentence);
  if (words(body) > 40) return null;

  let introPart: string;
  let listPart: string;

  const colon = body.indexOf(':');
  if (colon > 0) {
    introPart = body.slice(0, colon);
    listPart = body.slice(colon + 1);
  } else {
    const chunks = body.split(/,\s*/);
    if (chunks.length < 2) return null;
    const first = chunks[0] ?? '';
    // The intro is everything up to and including the LAST list-introducing
    // word in the first chunk; what follows it is the first item.
    const tokens = first.split(/\s+/);
    let cut = -1;
    for (let i = tokens.length - 1; i >= 0; i -= 1) {
      if (LIST_INTRO.test(tokens.slice(0, i + 1).join(' '))) {
        cut = i;
        break;
      }
    }
    if (cut < 0 || cut === tokens.length - 1) return null;
    introPart = tokens.slice(0, cut + 1).join(' ');
    listPart = [tokens.slice(cut + 1).join(' '), ...chunks.slice(1)].join(', ');
  }

  const items = listPart
    .split(/,\s*|\s+(?:and|or)\s+/i)
    .map((item) => item.replace(/^(?:and|or)\s+/i, '').trim())
    .filter(Boolean);

  if (items.length < 3) return null;
  if (items.some((item) => words(item) > MAX_ITEM_WORDS)) return null;
  // A final conjunction is what makes it spoken-list shaped at all.
  if (colon < 0 && !/\s(?:and|or)\s/i.test(listPart)) return null;

  return { intro: capitalise(introPart.trim()), items };
}

// ---- blocks ------------------------------------------------------------------

type Block =
  | { kind: 'para'; text: string }
  | { kind: 'heading'; text: string }
  | { kind: 'bullet'; text: string }
  /** One entry of a spoken enumeration: a bullet that belongs to its intro, not to its neighbours. */
  | { kind: 'item'; text: string }
  | { kind: 'number'; text: string }
  | { kind: 'task'; text: string }
  | { kind: 'intro'; text: string }
  | { kind: 'quote'; text: string }
  | { kind: 'rule'; text: string };

/**
 * Which run a block belongs to, for deciding where blank lines go.
 *
 * An enumeration is its own family, separate from spoken bullets and to-dos,
 * because it is a CLOSED list: "for the drive we want snacks, water and a
 * charger" is complete when the sentence ends. Sharing a family let the next
 * sentence's to-do ("ask Sam about the dog") render as a fifth item of the
 * snacks list, which is a claim about the note Matt never made. Spoken bullets
 * and to-dos, by contrast, are open lists that grow a sentence at a time, so
 * consecutive ones do merge.
 */
const family = (block: Block): string => {
  switch (block.kind) {
    case 'item':
    case 'intro':
      return 'items';
    case 'bullet':
    case 'task':
      return 'bullets';
    case 'number':
      return 'numbers';
    case 'quote':
      return 'quotes';
    default:
      return block.kind;
  }
};

/**
 * Blocks for one sentence under the local rules.
 *
 * `ordinalRun` is decided per paragraph by the caller, because "then" and
 * "next" only start list items once a "first" has made the run a list; on
 * their own they are just how people join clauses.
 */
function localBlocks(text: string, ordinalRun: boolean): Block[] {
  const heading = HEADING_CUE.exec(text);
  if (heading?.[1]) return [{ kind: 'heading', text: capitalise(stripEnd(heading[1])) }];

  const bullet = BULLET_CUE.exec(text);
  if (bullet?.[1]) return [{ kind: 'bullet', text: itemOf(bullet[1]) ?? capitalise(stripEnd(bullet[1])) }];

  const important = IMPORTANT_CUE.exec(text);
  if (important?.[1] && important[2]) {
    return [{ kind: 'para', text: `**${capitalise(important[1])}:** ${important[2]}` }];
  }

  if (DIVIDER_CUE.test(text)) return [{ kind: 'rule', text: '---' }];

  const quote = QUOTE_CUE.exec(text);
  if (quote?.[1]) return [{ kind: 'quote', text: capitalise(quote[1].trim()) }];

  const numbered = NUMBER_CUE.exec(text);
  if (numbered?.[2]) return [{ kind: 'number', text: itemOf(numbered[2]) ?? capitalise(stripEnd(numbered[2])) }];

  const checkbox = CHECKBOX_CUE.exec(text);
  if (checkbox?.[1]) return [{ kind: 'task', text: itemOf(checkbox[1]) ?? capitalise(stripEnd(checkbox[1])) }];

  const task = TASK.exec(text);
  if (task?.[1]) return [{ kind: 'task', text: capitalise(stripEnd(task[1])) }];

  if (ordinalRun) {
    const ordinal = ORDINAL.exec(text);
    if (ordinal?.[2]) return [{ kind: 'number', text: capitalise(stripEnd(ordinal[2])) }];
  }

  const list = enumeration(text);
  if (list) {
    return [
      { kind: 'intro', text: `${list.intro}:` },
      ...list.items.map((item): Block => ({ kind: 'item', text: item })),
    ];
  }

  return [{ kind: 'para', text }];
}

/**
 * `paragraphStarts` holds the index of the first block each spoken paragraph
 * produced. Sentences of one paragraph arrive as separate prose blocks and are
 * joined back into one line; two prose blocks either side of a paragraph break
 * (a spoken "new paragraph", or a long pause) must not be.
 */
function renderBlocks(blocks: readonly Block[], paragraphStarts: ReadonlySet<number> = new Set()): string {
  const out: string[] = [];
  let previous: Block | null = null;
  let number = 0;

  for (const [index, block] of blocks.entries()) {
    if (block.kind !== 'number') number = 0;
    const joined = previous?.kind === 'para' && block.kind === 'para' && !paragraphStarts.has(index);
    // An intro always opens a new run. Written straight under a list line,
    // markdown reads "For food we want:" as a lazy continuation of the item
    // above it rather than as the start of a new list - it rendered inside a
    // to-do before this rule existed.
    const sameRun =
      previous !== null && family(previous) === family(block) && block.kind !== 'para' && block.kind !== 'intro';

    if (joined) {
      out[out.length - 1] = `${out[out.length - 1]} ${block.text}`;
    } else {
      if (previous !== null && !sameRun) out.push('');
      switch (block.kind) {
        case 'heading':
          out.push(`## ${block.text}`);
          break;
        case 'bullet':
        case 'item':
          out.push(`- ${block.text}`);
          break;
        case 'task':
          out.push(`- [ ] ${block.text}`);
          break;
        case 'number':
          number += 1;
          out.push(`${number}. ${block.text}`);
          break;
        case 'quote':
          out.push(`> ${block.text}`);
          break;
        case 'rule':
          // Always behind a blank line (a different family from anything
          // before it): `---` straight under a line of text is a setext
          // underline, which would turn that text into a heading.
          out.push('---');
          break;
        default:
          out.push(block.text);
      }
    }
    previous = block;
  }
  return out.join('\n');
}

// ---- the whole note -------------------------------------------------------------

/**
 * Committed segments and an optional in-progress phrase, rendered to markdown.
 *
 * Pure, and cheap enough to run on every event: a note is a few hundred words
 * and the engine emits about one event a second.
 */
export interface RenderOptions {
  /**
   * Whether the note may take a `# title`. False for a recording added to the
   * end of an existing note (capture/continuation.ts): its opening sentence
   * stays a sentence, and a spoken "Title: …"
   * becomes a `## heading` there rather than a second title mid-note.
   */
  titled?: boolean;
}

export function renderNote(
  segments: readonly Segment[],
  partial = '',
  { titled = true }: RenderOptions = {},
): RenderedNote {
  const paragraphs = toParagraphs(segments);
  const plain = paragraphs.join('\n\n');

  const blocks: Block[] = [];
  let title: string | null = null;
  /** A cue said as its own sentence, waiting for the sentence it introduces. */
  let pendingCue: string | null = null;
  /** The title is decided by the first sentence with content, not by a cue before it. */
  let seenContent = false;
  /** A list is open: announced, or begun by an item. Its kind, for the items that follow. */
  let openList: 'number' | 'bullet' | null = null;
  /**
   * Whether short plain sentences join the open list: only when it was
   * announced ("here's my shopping list") or talked into being ("the next item
   * is …"). After a cue ("bullet point, eggs") a short "Thanks." is a reply,
   * not an item.
   */
  let takesShortItems = false;
  /** An item phrase that stopped short ("The next item is."), waiting for its item. */
  let pendingItem: string | null = null;
  /** The phrase waiting was a numbered cue ("number three, the next item is"): the item is numbered. */
  let pendingNumbered = false;
  const paragraphStarts = new Set<number>();

  paragraphs.forEach((paragraph) => {
    paragraphStarts.add(blocks.length);
    const sentences = sentencesOf(spokenInlineMarkup(inlineNumbering(paragraph)));

    const firstOrdinal = sentences.findIndex((s) => ORDINAL_START.test(s.text));

    sentences.forEach((spoken, sentenceIndex) => {
      const cueOnly = STANDALONE_CUE.exec(spoken.text);
      if (cueOnly?.[1]) {
        pendingCue = cueOnly[1];
        return;
      }
      const sentence: Sentence = pendingCue ? { ...spoken, text: `${pendingCue}: ${spoken.text}` } : spoken;
      pendingCue = null;

      // The item after "the next item is", said as its own phrase. A second
      // item phrase instead means the first was just words.
      if (pendingItem !== null) {
        const held = pendingItem;
        const numbered = pendingNumbered;
        pendingItem = null;
        pendingNumbered = false;
        if (!ITEM_OPENER.test(sentence.text) && !itemOf(sentence.text)) {
          const last = blocks[blocks.length - 1];
          const kind = numbered || last?.kind === 'number' ? 'number' : last?.kind === 'bullet' || last?.kind === 'item' ? 'bullet' : (openList ?? 'bullet');
          blocks.push({ kind, text: capitalise(stripEnd(sentence.text)) });
          openList = kind;
          takesShortItems = true;
          return;
        }
        blocks.push({ kind: 'para', text: held });
      }
      if (ITEM_OPENER.test(sentence.text)) {
        pendingItem = sentence.text;
        seenContent = true;
        return;
      }
      // "Number three, the next item is", with the item after a breath: the
      // number waits for it too, so the list's count carries on.
      const numberedOpener = NUMBER_CUE.exec(sentence.text);
      if (numberedOpener?.[2] && ITEM_OPENER.test(numberedOpener[2])) {
        pendingItem = sentence.text;
        pendingNumbered = true;
        seenContent = true;
        return;
      }

      // The very first sentence can be a spoken title, or a short opening that
      // reads as one.
      if (!seenContent) {
        seenContent = true;
        const cue = TITLE_CUE.exec(sentence.text);
        if (cue?.[1]) {
          const words = capitalise(stripEnd(cue[1]));
          if (titled) title = words;
          else blocks.push({ kind: 'heading', text: words });
          return;
        }
        if (titled && isTitleShaped(sentence.text) && !itemOf(sentence.text)) {
          title = stripEnd(sentence.text);
          openList = announcesList(sentence.text);
          takesShortItems = openList !== null;
          return;
        }
      }

      // A list item said as a phrase ("the next item is …"), or a short item
      // under a list someone announced. It takes the list's kind: numbered if
      // the list is, bullets otherwise.
      const listKind = (): 'number' | 'bullet' => {
        const last = blocks[blocks.length - 1];
        if (last?.kind === 'number') return 'number';
        if (last?.kind === 'bullet' || last?.kind === 'item') return 'bullet';
        return openList ?? 'bullet';
      };
      const item = itemOf(sentence.text);
      if (item) {
        const kind = listKind();
        blocks.push({ kind, text: item });
        openList = kind;
        takesShortItems = true;
        return;
      }

      const ordinalRun = firstOrdinal >= 0 && sentenceIndex >= firstOrdinal;
      const made = localBlocks(sentence.text, ordinalRun);
      // A short plain sentence under an open list is its next item. Only
      // plain: a cue ("number two, …", "then …" in an ordinal run) has
      // already said what the sentence is.
      if (openList && takesShortItems && made.length === 1 && made[0]?.kind === 'para' && itemShaped(sentence.text)) {
        const kind = listKind();
        blocks.push({ kind, text: capitalise(stripEnd(sentence.text)) });
        openList = kind;
        return;
      }
      blocks.push(...made);
      const last = made[made.length - 1];
      const announced = announcesList(sentence.text);
      if (announced) {
        openList = announced;
        takesShortItems = true;
      } else if (last?.kind === 'number' || last?.kind === 'bullet') {
        openList = last.kind;
      } else {
        openList = null;
        takesShortItems = false;
      }
    });
  });

  // A "the next item is" that nothing followed: it was words.
  if (pendingItem !== null) blocks.push({ kind: 'para', text: pendingItem });

  const body = renderBlocks(blocks, paragraphStarts);
  let markdown = title ? `# ${title}${body ? `\n\n${body}` : ''}` : body;

  let pendingFrom: number | null = null;
  const tail = partial.trim();
  if (tail) {
    const last = blocks[blocks.length - 1];
    const separator = !markdown ? '' : last?.kind === 'para' ? ' ' : '\n\n';
    pendingFrom = markdown.length + separator.length;
    markdown = `${markdown}${separator}${tail}`;
  }

  return { markdown, pendingFrom, plain };
}

/**
 * Whether an opening sentence reads as a title: short, not a question, and not
 * something the local rules would rather make a list item or a to-do. "Grocery
 * run." is a title; "I need to call the bank." is a task that happens to be
 * first.
 */
function isTitleShaped(text: string): boolean {
  if (/\?$/.test(text.trim())) return false;
  if (words(text) > 6) return false;
  if (
    TASK.test(text) ||
    BULLET_CUE.test(text) ||
    HEADING_CUE.test(text) ||
    QUOTE_CUE.test(text) ||
    NUMBER_CUE.test(text) ||
    CHECKBOX_CUE.test(text) ||
    DIVIDER_CUE.test(text) ||
    IMPORTANT_CUE.test(text) ||
    enumeration(text)
  ) {
    return false;
  }
  return true;
}
