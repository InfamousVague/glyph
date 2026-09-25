/**
 * Numbers and sums as they are said: "four hundred fifty", "twenty-one", "four four one seven" read a digit at a
 * time, and "four hundred fifty plus one hundred twenty times two", worked out on the page as `= 450 + 120 * 2`.
 *
 * What the cues that take a number need (a counter, a numbered item, a sum, a formula, a raised or lowered word) and
 * what the voice suite compares recorded audio by (capture/voiceSuite.ts `heardForm`), so a number said is a number
 * however Whisper spelled it. Pure.
 */

const NUMBER_WORDS: Record<string, number> = {
  zero: 0, none: 0, nil: 0, oh: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
  twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90,
};

/**
 * The words a number is said in, as regex alternations, written once for every pattern that finds one: a count, a
 * table's column, a number inside a sentence, and the voice suite's runs of them.
 */
export const ONE_TO_TEN = 'one|two|three|four|five|six|seven|eight|nine|ten';
const ELEVEN_TO_NINETY = 'eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety';
/** Every word a number from zero to the thousands is said in. */
export const NUMBER_WORD = `zero|${ONE_TO_TEN}|${ELEVEN_TO_NINETY}|hundred|thousand`;

/** A small count said or written, as a cue that numbers something takes one: "number three", "item number 12". */
export const SMALL_NUMBER = String.raw`(?:${ONE_TO_TEN}|\d{1,2})`;

/**
 * A number said in words or written in digits: "four hundred fifty", "1,200", "twenty-one", "two thousand and five".
 * Null when it isn't one.
 */
export function spokenNumber(text: string): number | null {
  const said = text.trim().toLowerCase().replace(/,(?=\d{3})/g, '');
  if (/^\d+(?:\.\d+)?$/.test(said)) return Number(said);
  const words = said.split(/[\s-]+/).filter((word) => word && word !== 'and');
  if (!words.length) return null;
  // "Four four one seven" is a code read out a digit at a time: 4417, not 16.
  if (words.length > 1 && words.every((word) => (NUMBER_WORDS[word] ?? 99) < 10 || /^\d$/.test(word))) {
    return Number(words.map((word) => (/^\d$/.test(word) ? word : String(NUMBER_WORDS[word]))).join(''));
  }
  let total = 0;
  let group = 0;
  for (const word of words) {
    if (word in NUMBER_WORDS) group += NUMBER_WORDS[word]!;
    else if (word === 'hundred') group = (group || 1) * 100;
    else if (word === 'thousand') {
      total += (group || 1) * 1000;
      group = 0;
    } else if (word === 'million') {
      total += (group || 1) * 1_000_000;
      group = 0;
    } else if (/^\d+(?:\.\d+)?$/.test(word)) group += Number(word);
    else return null;
  }
  return total + group;
}

/** A number as it may be said inside a sentence, in digits or in words, for a pattern to find before `spokenNumber` reads it. */
export const NUMBER_PHRASE = String.raw`(?:\d[\d,]*(?:\.\d+)?|(?:(?:zero|none|${ONE_TO_TEN}|${ELEVEN_TO_NINETY}|hundred|thousand|million|and)[\s-]*)+)`;

/** The operators as they are said, and the signs they are written as. "x" is times only with a space either side. */
const OPERATORS: [RegExp, string][] = [
  [/\bto\s+the\s+power\s+of\b/gi, ' ^ '],
  [/\b(?:multiplied\s+by|times)\b/gi, ' * '],
  [/\b(?:divided\s+by|over)\b/gi, ' / '],
  [/\bplus\b/gi, ' + '],
  [/\bminus\b/gi, ' - '],
  [/\s[x×]\s/g, ' * '],
  [/÷/g, ' / '],
];

/** "Four hundred fifty plus one hundred twenty times two" as `450 + 120 * 2`, or null when it isn't a sum. */
export function spokenSum(text: string): string | null {
  let said = ` ${text.trim().replace(/[.?!]+$/, '')} `;
  for (const [word, symbol] of OPERATORS) said = said.replace(word, symbol);
  const parts = said.split(/\s*([-+*/^()])\s*/).map((part) => part.trim()).filter(Boolean);
  if (!parts.some((part) => /^[-+*/^]$/.test(part))) return null;
  const out: string[] = [];
  for (const part of parts) {
    if (/^[-+*/^()]$/.test(part)) {
      out.push(part);
      continue;
    }
    const sign = /^[$€£]/.exec(part)?.[0] ?? '';
    const percent = /%$|\s+percent$/i.test(part) ? '%' : '';
    const value = spokenNumber(part.replace(/^[$€£]/, '').replace(/%$|\s+percent$/i, ''));
    if (value === null) return null;
    out.push(`${sign}${value}${percent}`);
  }
  return out.join(' ').replace(/\( /g, '(').replace(/ \)/g, ')');
}

/** "x squared plus two y" as `x^2 + 2 y`: the operators as signs and the numbers as digits, the letters as said. */
export function spokenMaths(text: string): string {
  let said = ` ${text.trim().toLowerCase()} `
    .replace(/\bsquared\b/g, '^2')
    .replace(/\bcubed\b/g, '^3')
    .replace(/\b(?:is\s+)?equals?(?:\s+to)?\b/g, ' = ')
    .replace(/\bsquare\s+root\s+of\b/g, ' \\sqrt ')
    .replace(/\bopen\s+brackets?\b/g, ' ( ')
    .replace(/\bclose\s+brackets?\b/g, ' ) ');
  // "x" is a letter here, not "times".
  for (const [word, symbol] of OPERATORS) if (!word.source.includes('x×')) said = said.replace(word, symbol);
  said = said.replace(new RegExp(`\\b${NUMBER_PHRASE}\\b`, 'gi'), (phrase) => {
    const value = spokenNumber(phrase.replace(/\s+and\s*$/, ''));
    return value === null ? phrase : ` ${value} `;
  });
  return said
    .replace(/\s*\^\s*/g, '^')
    .replace(/\(\s+/g, '(')
    .replace(/\s+\)/g, ')')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Raised or lowered words: numbers as digits, and no bare space, which ends the mark (`^2nd^`, `~2~`, `^to\\ be^`). */
export function spokenScript(text: string): string {
  // Said alone, "to" and "for" are the numbers: "metres superscript two" is heard "superscript to".
  const alone = { to: '2', too: '2', for: '4', won: '1' }[text.trim().toLowerCase()];
  if (alone) return alone;
  const said = text.trim().replace(new RegExp(`\\b${NUMBER_PHRASE}\\b`, 'gi'), (phrase) => {
    const value = spokenNumber(phrase);
    return value === null ? phrase : `${phrase.match(/^\s*/)?.[0] ?? ''}${value}${phrase.match(/\s*$/)?.[0] ?? ''}`;
  });
  return said.trim().replace(/(\d)\s+(?=(?:st|nd|rd|th)\b)/gi, '$1').replace(/\s+/g, '\\ ');
}
