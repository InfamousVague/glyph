import { capitalise } from '../../core/text.ts';
import { SMALL_NUMBER } from './numbers.ts';
import { stripEnd, words } from './words.ts';

/**
 * Lists said the way people say them, not in cue words: "I need eggs, milk and bread", "the next item is oat milk",
 * "here's my shopping list" and the short sentences after it, and Whisper's own "1. 2. 3." when it hears a list.
 *
 * Deliberately high-precision, as every rule here is (capture/markdown.ts): a missed list is still readable prose,
 * and a false one mangles it. So an enumeration needs a word that introduces a list before its items, an item phrase
 * needs an ordinal or the word "list", and an announced list takes only short, noun-shaped sentences. Pure.
 */

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
const NAMED_ITEM = [
  // "list item", "the next list item", "list item number two"
  String.raw`(?:${ORDINAL_WORD}\s+)?list\s+(?:item|entry)(?:\s+(?:number\s+)?${SMALL_NUMBER})?`,
  // "the next item", "another thing", "the final one", "item number two"
  String.raw`${ORDINAL_WORD}\s+(?:item|thing|entry|one)(?:\s+(?:number\s+)?${SMALL_NUMBER})?`,
  String.raw`item\s+number\s+${SMALL_NUMBER}`,
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

/** Whether `text` is an item phrase that stopped before its item ("The next item is."), waiting for the next sentence. */
export function opensItem(text: string): boolean {
  return ITEM_OPENER.test(text);
}

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

/** "Pack these.", "we need the following.": a list said with its colon heard as a full stop. */
const LIST_LEAD = /^(?:[a-z]+\s+){0,4}(?:these|the\s+following|as\s+follows)[.:]?$/i;

/** Whether `text` is a line a list hangs from, its colon heard as a full stop: "Pack these." */
export function leadsList(text: string): boolean {
  return LIST_LEAD.test(text.trim());
}

/** Whether `text` announces a list, and whether it asked for numbers. */
export function announcesList(text: string): 'number' | 'bullet' | null {
  if (LIST_LEAD.test(text.trim()) && LIST_INTRO.test(text.trim().replace(/\s+(?:these|the\s+following|as\s+follows)[.:]?$/i, ''))) return 'bullet';
  const match = LIST_ANNOUNCE.exec(text);
  if (!match) return null;
  const kind = (match[1] ?? match[2] ?? '').toLowerCase();
  return /^(?:numbered|numbering|ordered)$/.test(kind) ? 'number' : 'bullet';
}

/** Short enough, and noun-shaped enough, to be an item in a list someone announced. */
const MAX_OPEN_ITEM_WORDS = 5;
export function itemShaped(text: string): boolean {
  const body = stripEnd(text);
  if (!body || words(body) > MAX_OPEN_ITEM_WORDS || /\?\s*$/.test(text)) return false;
  // "I'm tired", "It works", "That's it": a sentence, not an item.
  return !/^(?:i|i'm|im|we|we're|you|he|she|it|it's|they|this|that|that's|there|there's|so|and\s+then)\b/i.test(body);
}

const MAX_ITEM_WORDS = 4;

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
    // "Pack these, the tent, …": "these" points at the list, so it belongs to the intro, not the first item.
    const pointsAtList = cut >= 0 && /^(?:these|those|the\s+following)$/i.test(tokens.slice(cut + 1).join(' '));
    if (cut < 0 || (cut === tokens.length - 1 && !pointsAtList)) return null;
    if (pointsAtList) {
      introPart = first;
      listPart = chunks.slice(1).join(', ');
    } else {
      introPart = tokens.slice(0, cut + 1).join(' ');
      listPart = [tokens.slice(cut + 1).join(' '), ...chunks.slice(1)].join(', ');
    }
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
