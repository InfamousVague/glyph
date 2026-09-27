import { capitalise } from '../core/text.ts';
import { findKeyword, onlyFiller } from './command.ts';
import { commandWords, nameable, withoutFinalStop } from './liveCommand.ts';
import { splitSentences } from './markdown.ts';

/**
 * Taking back the last thing said, as one committed phrase says it: the grammar of "scratch that", "actually, …",
 * "no wait, four" and "scratch that, add it to Groceries instead" (docs/DESIGN.md §130). A sibling of liveCommand.ts:
 * which readings a phrase has is decided here, with no notes and no clock; what is taken back, and where it goes, is
 * the live reader's (liveRoute.ts).
 *
 * Matt: "Id like sentences to be able to redact." Asked what that means: redacting is what happens "when the user says
 * something like 'actually …' or 'scratch that, add it to the <note> instead'".
 *
 * Two kinds of opener. A safe one is an order, and needs a pause after it or a send: "scratch that", "strike that",
 * "take that back", "forget that", "delete that", "never mind", "cancel that", "ignore that", and "no wait" alone;
 * "Take that back to the shop" and "Strike that pose" are words. A risky one is how people talk, and counts only before
 * a correction: "actually", "I mean", "sorry,", "or rather", "no," and "no wait" with words after it. Whether the words
 * after a risky opener correct what came before is `corrects` (the sentence said again with a change) or `swapWord`
 * (one word of a kind changed: a number, a day, a month, a name); the live reader asks, since only it knows what came
 * before. An opener stands at the start of a phrase, after a stop in any case, or after a comma inside a sentence when
 * only a drop, a send or a change follows, since Whisper writes "the meeting is at three, scratch that" for a beat
 * under 300 ms. Pure, so every phrasing is a test.
 */

export interface TakeBack {
  /**
   * What came before the opener in the same phrase, as said, the keyword kept where it was: '' when nothing did. The
   * take's own words first, a phrase of their own.
   */
  head: string;
  /** The head came before the keyword ("The heating is fixed, hey Ghost, scratch that"): the phrase is marked `keyword`, as read() marks one. */
  headBeforeKeyword: boolean;
  /** The opener as said, for the log: "scratch that". */
  opener: string;
  /** The opener and its rest as said, keyword and head off: what Undo writes as words. */
  said: string;
  /** "actually", "I mean", "no,", "sorry,", "or rather", and "no wait" with a rest: ordinary words, so only a correction, a change of one word, or a send counts. */
  risky: boolean;
  /** What followed the opener, its separator gone, as said (lead-ins kept: these may be written): '' when nothing did. */
  rest: string;
  /** The rest read as "send it to <name>": the name as heard, "instead" gone; null when the rest is not a send. */
  send: string | null;
  /** "Hey Ghost" was said before the opener. */
  keyed: boolean;
  /** The opener stood after a comma inside a sentence ("…at three, scratch that"): only a bare drop, a send or a change may follow it. */
  afterComma: boolean;
}

interface Opener {
  rule: RegExp;
  safe: boolean;
  /** "no wait": safe only with nothing after it, risky with a rest. */
  bareOnly?: boolean;
}

/** No letter or digit follows: "actually" is not "actualize", "no" is not "nobody". */
const END = String.raw`(?![\p{L}\p{N}])`;

/** The openers, each matched at one position (`y`), in the order they are tried. */
const OPENERS: readonly Opener[] = [
  { rule: new RegExp(String.raw`scratch\s+that${END}`, 'iuy'), safe: true },
  { rule: new RegExp(String.raw`strike\s+that${END}`, 'iuy'), safe: true },
  { rule: new RegExp(String.raw`take\s+that\s+back${END}`, 'iuy'), safe: true },
  { rule: new RegExp(String.raw`forget\s+that${END}`, 'iuy'), safe: true },
  { rule: new RegExp(String.raw`delete\s+that${END}`, 'iuy'), safe: true },
  { rule: new RegExp(String.raw`never\s+mind${END}`, 'iuy'), safe: true },
  { rule: new RegExp(String.raw`cancel\s+that${END}`, 'iuy'), safe: true },
  { rule: new RegExp(String.raw`ignore\s+that${END}`, 'iuy'), safe: true },
  { rule: new RegExp(String.raw`(?:no,?\s+wait|wait,?\s+no)${END}`, 'iuy'), safe: true, bareOnly: true },
  { rule: new RegExp(String.raw`actually${END}`, 'iuy'), safe: false },
  { rule: new RegExp(String.raw`i\s+mean${END}`, 'iuy'), safe: false },
  { rule: new RegExp(String.raw`or\s+rather${END}`, 'iuy'), safe: false },
  { rule: new RegExp(String.raw`sorry(?=\s*,)`, 'iuy'), safe: false },
  { rule: new RegExp(String.raw`(?:no,?\s+)*no(?=\s*,)`, 'iuy'), safe: false },
];

/** What may follow a safe opener: a pause (a comma, a stop, a colon), "and", or the end of the phrase. */
const SEPARATOR = /^(?:[,.:;!?…]+\s*|\s+and\s+|\s*$)/i;
/** A stop, or nothing: "No wait." is bare. */
const BARE = /^[.!?…]*\s*$/;

/** "Check box:" and "Bullet point:", which a command's payload and the block cues write, taken off what a person would quote. */
const CUE_PREFIX = /^(?:check(?:ed)?\s?box|bullet\s?point|checklist(?:\s+item)?|check\s+item)[:,.]?\s*/i;

const SEND_VERB = /^(?:add|put|send|move|stick|file|save|drop)\s+(?:that|it|this|those|them|these)\s+(?:to|in|into|on|onto|under|for)\s+(?:(?:the|my|our)\s+)?(.+)$/i;
const SEND_GOES = /^(?:that|it|this)(?:['’]s|\s+(?:goes|belongs|should\s+go|should\s+be|is|was))\s+(?:in|into|on|to|for|under)\s+(?:(?:the|my|our)\s+)?(.+)$/i;

/** Words that carry nothing of a sentence, for telling one said again from a new one. */
const STOP = new Set(
  'the a an and or but so to of in on at for is are was were be it its this that i we you he she they my our your with from by as not do did does have has had will would should can could'.split(' '),
);

const NUMBER_WORDS = new Set('one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty seventy eighty ninety hundred thousand half quarter'.split(' '));
const WEEKDAYS = new Set('monday tuesday wednesday thursday friday saturday sunday'.split(' '));
const MONTHS = new Set('january february march april may june july august september october november december'.split(' '));
const NUMBER = /^\d+(?:[:.]\d+)?(?:\s?[ap]m)?$/i;

type Kind = 'number' | 'weekday' | 'month' | 'name';

/** The kind of word `word` is, for a change of one word, or null for none: a number, a day, a month, or a capitalised word. */
function kindOf(word: string): Kind | null {
  const lower = word.toLowerCase();
  if (NUMBER.test(word) || NUMBER_WORDS.has(lower)) return 'number';
  if (WEEKDAYS.has(lower)) return 'weekday';
  if (MONTHS.has(lower)) return 'month';
  if (/^\p{Lu}/u.test(word)) return 'name';
  return null;
}

/** A phrase's words as a send, or null: the keyword and the lead-ins off, a final "instead" and stop off, the name checked. */
function sendOf(text: string): string | null {
  const heard = findKeyword(text);
  if (heard && !onlyFiller(heard.before)) return null;
  const words = withoutFinalStop(commandWords(heard ? heard.after : text))
    .replace(/\s+instead$/i, '')
    .trim();
  if (!words) return null;
  const found = SEND_VERB.exec(words) ?? SEND_GOES.exec(words);
  const name = found?.[1]?.trim();
  if (!name) return null;
  // A name runs to the end: with more after it, this is more than a send.
  if (/[,;:]|\.\s/.test(name)) return null;
  return nameable(name) === 'name' ? name : null;
}

/** An opener at `at` in `text`, and what follows it, or null when none stands there. */
function openerAt(text: string, at: number): { opener: string; end: number; safe: boolean; rest: string } | null {
  for (const { rule, safe, bareOnly } of OPENERS) {
    rule.lastIndex = at;
    const found = rule.exec(text);
    if (!found) continue;
    const opener = found[0];
    const end = at + opener.length;
    const after = text.slice(end);
    if (bareOnly) {
      if (BARE.test(after)) return { opener, end, safe: true, rest: '' };
      // "No wait, four": how people correct one word. Words after it, with or without the comma.
      const rest = after.replace(/^[,:;]?\s*/, '').trim();
      return /^[\s,:;]/.test(after) && rest ? { opener, end, safe: false, rest } : null;
    }
    if (safe) {
      const sep = SEPARATOR.exec(after);
      if (sep) return { opener, end, safe, rest: after.slice(sep[0].length).trim() };
      // "scratch that add it to groceries": a send needs no pause, and never occurs in prose.
      return sendOf(after.trim()) ? { opener, end, safe, rest: after.trim() } : null;
    }
    // A risky opener counts only with words after it: "Actually." alone is words.
    const rest = after.replace(/^[,:;]?\s*/, '').trim();
    if (!rest || !/^[\s,:;]/.test(after)) return null;
    return { opener, end, safe, rest: withoutFinalStop(rest) === '' ? '' : rest };
  }
  return null;
}

/**
 * A phrase read as a take-back: where its opener stands, what came before it, what follows it, and whether it was
 * said after the keyword. Null when the phrase is words.
 */
export function readTakeBack(raw: string): TakeBack | null {
  const text = raw.trim();
  if (!text) return null;
  const heard = findKeyword(text);
  const keyAt = heard ? heard.before.length : -1;
  /** Where the phrase's own words start, its lead-ins gone; and where the command's do, after the keyword and its lead-ins. */
  const leadStart = text.length - commandWords(text).length;
  const keyStart = heard ? text.length - commandWords(heard.after).length : -1;
  /** The words before the keyword, when they are words: the take's own. */
  const beforeKeyword = heard && !onlyFiller(heard.before) ? heard.before : '';

  const make = (at: number, found: NonNullable<ReturnType<typeof openerAt>>, head: string, afterComma: boolean): TakeBack => {
    const keyed = heard !== null && keyAt < at;
    return {
      head,
      headBeforeKeyword: keyed && beforeKeyword !== '',
      opener: found.opener,
      said: text.slice(at).trim(),
      risky: !found.safe,
      rest: found.rest,
      send: found.rest ? sendOf(found.rest) : null,
      keyed,
      afterComma,
    };
  };
  const counts = (found: ReturnType<typeof openerAt>): found is NonNullable<ReturnType<typeof openerAt>> => found !== null && (found.safe || found.rest !== '');

  // At the start, after the keyword and the lead-ins: "Okay, scratch that", "Hey Ghost, actually, …".
  if (heard && keyStart < text.length) {
    const first = openerAt(text, keyStart);
    if (counts(first)) return make(keyStart, first, beforeKeyword, false);
  }
  // Or at the phrase's own start, the keyword inside the rest: "Scratch that, hey Ghost, add it to Groceries".
  if ((!heard || beforeKeyword) && leadStart < text.length) {
    const first = openerAt(text, leadStart);
    if (counts(first)) return make(leadStart, first, '', false);
  }

  // After a stop, in any case ("We need eggs. scratch that."), or after a comma inside a sentence.
  const boundaries = [...text.matchAll(/([.!?…]["”]?|,)\s+/g)];
  for (const boundary of boundaries) {
    const at = boundary.index + boundary[0].length;
    // Not before the phrase's own words, and not between the keyword and its command: those starts were tried above.
    if (at <= leadStart || (keyAt >= 0 && keyAt < at && at <= keyStart)) continue;
    const found = openerAt(text, at);
    if (!found) continue;
    const comma = boundary[1] === ',';
    // A head keeps its stop, and loses its comma.
    const head = text.slice(0, boundary.index + (comma ? 0 : boundary[1]!.length)).replace(/[\s,;:]+$/, '');
    if (!head) continue;
    if (!comma) {
      if (counts(found)) return make(at, found, head, false);
      continue;
    }
    // After a comma only a drop, a send, or a change of what came before: "…at three, no wait for me" is words.
    const last = splitSentences(head).at(-1) ?? head;
    const change = found.rest !== '' && (sendOf(found.rest) !== null || swapWord(quoted(last), found.rest) !== null || corrects(quoted(last), found.rest));
    if ((found.safe && found.rest === '') || change) return make(at, found, head, true);
  }
  return null;
}

/**
 * The rest of a phrase read on its own as "add it to <name>" (keyword and lead-ins off, a final "instead" off): the
 * name, or null. For the send said in a breath of its own after "scratch that".
 */
export function readSend(text: string): string | null {
  return sendOf(text.trim());
}

/** The words of `text` that carry its sense: the cue prefix off, contractions to their base word, lower-cased, the stop words gone. */
export function contentWords(text: string): string[] {
  return text
    .replace(CUE_PREFIX, '')
    .toLowerCase()
    .replace(/[’`]/g, "'")
    .replace(/n't\b/g, '')
    .replace(/'(?:s|re|ve|ll|d|m)\b/g, '')
    .split(/[^\p{L}\p{N}]+/u)
    .filter((word) => word && !STOP.has(word));
}

/**
 * Whether `replacement` is `previous` said again with a change, by the content words they share: at least half of
 * the longer one, so the frame is shared from both sides and a one-word item is not "corrected" by a long new sentence.
 * Or the same words but for one of a kind ("it's on Tuesday" | "it's on Thursday"), where the frame is only stop words.
 */
export function corrects(previous: string, replacement: string): boolean {
  const before = contentWords(previous);
  const after = contentWords(replacement);
  if (!after.length) return false;
  const had = new Set(before);
  const shared = [...new Set(after)].filter((word) => had.has(word)).length;
  if (shared * 2 >= Math.max(had.size, new Set(after).size)) return true;
  if (before.length !== after.length) return false;
  const changed = before.map((word, i) => i).filter((i) => before[i] !== after[i]);
  return changed.length === 1 && kindOf(before[changed[0]!]!) !== null && kindOf(before[changed[0]!]!) === kindOf(after[changed[0]!]!);
}

/**
 * `previous` with its one word of `fragment`'s kind (a number, a weekday, a month, a name) replaced by `fragment`, case
 * and punctuation kept: "The meeting is at three." and "four" give "The meeting is at four.". Null when the fragment
 * is more than one word or of no kind, or when `previous` has two words of that kind, or none.
 */
export function swapWord(previous: string, fragment: string): { text: string; from: string; to: string } | null {
  const word = withoutFinalStop(commandWords(fragment)).trim();
  if (!word || /\s/.test(word)) return null;
  const kind = kindOf(word);
  if (!kind) return null;
  const prefix = CUE_PREFIX.exec(previous)?.[0] ?? '';
  const body = previous.slice(prefix.length);
  const tokens = [...body.matchAll(/[\p{L}\p{N}](?:[\p{L}\p{N}:.'’]*[\p{L}\p{N}])?/gu)];
  // A name is a capitalised word that is not the sentence's first, which Whisper capitalises whatever it is.
  const found = tokens.filter((token, i) => kindOf(token[0]) === kind && (kind !== 'name' || i > 0));
  if (found.length !== 1) return null;
  const [token] = found;
  const from = token![0];
  const to = kind === 'name' ? capitalise(word) : /^\p{Lu}/u.test(from) ? capitalise(word.toLowerCase()) : NUMBER.test(word) ? word : word.toLowerCase();
  if (from === to) return null;
  const at = prefix.length + token!.index;
  return { text: `${previous.slice(0, at)}${to}${previous.slice(at + from.length)}`, from, to };
}

/** A segment's words as a person would quote them: "Check box:" and "Bullet point:" off, a final stop off. */
export function quoted(text: string): string {
  return withoutFinalStop(text.replace(CUE_PREFIX, '')).trim();
}

/** The safe openers a partial can be starting, and how much of each is ordinary words that start prose too. */
const STARTS: readonly { opener: string; ordinary: string }[] = [
  { opener: 'scratch that', ordinary: '' },
  { opener: 'strike that', ordinary: '' },
  { opener: 'take that back', ordinary: 'take that' },
  { opener: 'forget that', ordinary: 'forget' },
  { opener: 'delete that', ordinary: 'delete' },
  { opener: 'never mind', ordinary: 'never' },
  { opener: 'cancel that', ordinary: 'cancel' },
  { opener: 'ignore that', ordinary: 'ignore' },
  { opener: 'no wait', ordinary: 'no' },
  { opener: 'wait no', ordinary: 'wait' },
];

/**
 * A partial that is starting a safe opener, past any ordinary first words: for the chip, never the page. "scratch",
 * "no w" and "take that b" count; "no", "take that" and every risky opener do not, since "No parking on Sunday" and
 * "Take that to the shop" start the same way, and a partial is transient.
 */
export function opensTakeBack(partial: string): boolean {
  const said = commandWords(partial)
    .toLowerCase()
    .replace(/[,.:;!?…]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!said) return false;
  return STARTS.some(({ opener, ordinary }) => {
    if (said.startsWith(opener)) return true;
    if (!opener.startsWith(said)) return false;
    const first = opener.split(' ')[0]!;
    return ordinary ? said.length > ordinary.length + 1 : said.length >= first.length;
  });
}
