import { spokenMaths, spokenScript } from './numbers.ts';
import { GLUE } from './standIns.ts';

/**
 * Marks said around words inside a sentence: "bold … end bold", "italic … end italic", "code … end code", "maths …
 * end maths", "superscript … end superscript", and a switched-on plugin's own ("spoiler … end spoiler").
 *
 * Matched across a whole paragraph, because a speaker pauses around the words being marked and Whisper turns each
 * pause into a full stop. Both halves are required, so "a bold move" is left alone; see `spokenInlineMarkup` for when
 * "and" closes one. Pure but for the plugins' cues, which the recorder sets as it opens (`setSpokenFormats`).
 */

/** A plugin's formatting said the way bold is: its cue word, and the delimiter the words it wraps are put between. */
export interface SpokenFormat {
  word: string;
  delimiter: string;
}

/**
 * The plugin formattings that can be said, set by the recorder from the switched-on plugins (plugins/types.ts
 * `InlineFormat.cue`; the Spoiler plugin's "spoiler … end spoiler" wraps the words in `||`). Held here rather than
 * read from the registry so this file stays pure and testable. A module's own state, so whatever set it last is what
 * every later render reads: the recorder sets it once as it opens, and a test that sets it puts it back.
 */
let spokenFormats: readonly SpokenFormat[] = [];

export function setSpokenFormats(formats: readonly SpokenFormat[]): void {
  spokenFormats = formats.filter((format) => /^[a-z][a-z ]*[a-z]$/i.test(format.word.trim()) && format.delimiter);
}

const escapeWord = (word: string) => word.trim().replace(/\s+/g, '\\s+');

/** How a cue word is heard as well as how it is spelled: "aside" comes back as "a side". */
const SAID_AS: Record<string, string> = { aside: 'a\\s?side', unsure: '(?:un|en|in)sure|onshore' };

function inlineMarkup(formats: readonly SpokenFormat[]): RegExp {
  const words = ['bold\\s+italics?', 'bold', 'italics?', 'emphasis', 'strike(?:through)?', 'crossed\\s+out', 'code', 'super\\s?script', 'sub\\s?script', 'maths?', ...formats.map((format) => SAID_AS[format.word.trim().toLowerCase()] ?? escapeWord(format.word))];
  const any = words.join('|');
  return new RegExp(`\\b(${any})\\b([.,:;!]?)\\s+([\\s\\S]+?)[.,;:!]?\\s+(end|and)\\s+(${any})\\b([.,;:!?]?)`, 'gi');
}

/** Which cue a spoken word is, however it was heard: "A side" is aside, "ensure" is unsure, "italics" is italic. */
function cueOf(word: string, formats: readonly SpokenFormat[]): string {
  const heard = word.toLowerCase().replace(/\s+/g, ' ').trim();
  for (const format of formats) {
    const name = format.word.trim().toLowerCase().replace(/\s+/g, ' ');
    const alias = SAID_AS[name];
    if (heard === name || (alias && new RegExp(`^(?:${alias})$`, 'i').test(heard))) return name;
  }
  if (/^strike(?:through)?$|^crossed out$/.test(heard)) return 'strike';
  if (/^italics?$/.test(heard)) return 'italic';
  if (/^bold italics?$/.test(heard)) return 'bold italic';
  if (/^super ?script$/.test(heard)) return 'superscript';
  if (/^sub ?script$/.test(heard)) return 'subscript';
  if (/^maths?$/.test(heard)) return 'maths';
  return heard;
}

/** A cue word run into what follows it: "spoiler4417". */
function inlineGlued(formats: readonly SpokenFormat[]): RegExp {
  const words = ['bold', 'italic', 'strike', 'code', ...formats.map((format) => escapeWord(format.word))];
  return new RegExp(`\\b(${words.join('|')})(\\d)`, 'gi');
}

const BUILT_IN_MARKERS: Record<string, string> = {
  'bold italic': '***',
  bold: '**',
  strike: '~~',
  code: '`',
  superscript: '^',
  subscript: '~',
  maths: '$',
};

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
 * "and bold" also closes, when Whisper put a mark straight after the opening
 * word ("Italics, maybe, and italics.") or when it ends the sentence ("The
 * deadline is bold Friday at noon and bold."). The two words sound almost the
 * same, and on synthesised speech base.en wrote "and" for "end" in most voices
 * even with the cue vocabulary as its prompt. "It was bold thinking and bold action"
 * has neither a pause after the first "bold" nor the sentence ending at the
 * second, and is left alone.
 */
export function spokenInlineMarkup(paragraph: string, formats: readonly SpokenFormat[] = spokenFormats): string {
  // Whisper's own spellings of the cues: "italics" for "italic", "spoiler4417" run together.
  const heard = paragraph.replace(/\bitalics\b/gi, (word) => word.slice(0, -1)).replace(inlineGlued(formats), '$1 $2');
  return heard.replace(inlineMarkup(formats), (match, kind: string, paused: string, inner: string, closer: string, closing: string, after: string, offset: number, whole: string) => {
    const said = cueOf(kind, formats);
    // "A side … end aside" is one mark; "the gate code is spoiler … end spoiler" is not a code mark, but may hold one.
    if (cueOf(closing, formats) !== said) return `${kind}${spokenInlineMarkup(match.slice(kind.length), formats)}`;
    // "and bold" closes after a pause at the opening cue, or when it ends the sentence: "… at noon and bold." Mid-sentence, "bold thinking and bold action" is prose.
    // The other cue words are rare enough in speech that "and" closes them anywhere.
    const endsSentence = Boolean(after) || !whole.slice(offset + match.length).trim();
    const common = /^(?:bold|italic|emphasis)$/.test(said);
    // Three words or more between them is a stretch someone chose to mark: "bold thinking and bold action" is one.
    const marked = inner.trim().split(/\s+/).length >= 3;
    if (closer.toLowerCase() === 'and' && common && !paused && !endsSentence && !marked) return match;
    const words = inner.trim().replace(/[.,;:!]+$/, '');
    const format = formats.find((f) => f.word.trim().toLowerCase().replace(/\s+/g, ' ') === said);
    if (format) return `${format.delimiter}${words}${format.delimiter}${after}`;
    const marker = BUILT_IN_MARKERS[said] ?? '_';
    // Code is as it was said, lower case and without the commas Whisper puts at its pauses, as a command is typed.
    const inside =
      said === 'code' ? words.toLowerCase().replace(/,/g, '') : said === 'maths' ? spokenMaths(words) : said === 'superscript' || said === 'subscript' ? spokenScript(words) : words;
    // Raised and lowered words hang on the word before them: the 2^nd^, H~2~O.
    const glued = said === 'superscript' || said === 'subscript';
    return `${glued ? GLUE : ''}${marker}${inside}${marker}${glued && !after ? GLUE : ''}${after}`;
  })
    .replace(new RegExp(`\\s*${GLUE}(?=[\\^~])`, 'g'), '')
    // After the mark, only a short capital run is part of the same word (H~2~O); "the 2^nd^ of June" keeps its space.
    .replace(new RegExp(`${GLUE}\\s+(?=[A-Z0-9]{1,2}\\b)`, 'g'), '')
    .replaceAll(GLUE, '');
}
