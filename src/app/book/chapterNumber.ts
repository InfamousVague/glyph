/**
 * A chapter's number, read from its title (Matt: "make chapters numbered with some standard identifiers for books
 * maybe at the end of the title and that should let us lay out the chapters in order when there is no book"). The
 * number lets chapters be put in order when no book's index says the order (aside/aside.ts). docs/BOOKS.md has
 * the standard.
 *
 * The standard, at the end of the title:
 *
 *   The risks, and a glossary · Ch. 8
 *   The risks, and a glossary (Chapter 8)
 *   The risks, and a glossary · Chapter VIII
 *
 * "Ch." or "Chapter", then an Arabic or Roman number, after a middle dot, a dash, a comma or a colon, or in
 * brackets. The way many chapters are already titled, a number in front, is read too:
 *
 *   08 · The risks, and a glossary
 *   Chapter 8: The risks, and a glossary
 *
 * A bare number at the end ("Top 10") is not a chapter number: too many titles end with one.
 */

export interface ChapterNumber {
  number: number;
  /** The title without its number. */
  name: string;
}

/** Before "Ch." at the end: a mark, a bracket or at least a space, so "Batch 5" isn't chapter 5. */
const SEP = String.raw`(?:\s*[·•|:,—–-]\s*|\s*[(\[]\s*|\s+)`;
const WORD = String.raw`(?:ch(?:apter)?\.?|§)`;
/** Roman numbers up to C's: no book has a thousand chapters, and "mix" is 1009. */
const NUM = String.raw`(\d{1,3}|[ivxlc]{1,8})`;
const AT_END = new RegExp(String.raw`^(.*?\S)${SEP}${WORD}\s*${NUM}\s*[)\]]?\s*$`, 'i');
const WORD_FIRST = new RegExp(String.raw`^\s*${WORD}\s*${NUM}\s*[·•|:.—–-]\s*(\S.*)$`, 'i');
const NUMBER_FIRST = /^\s*(\d{1,3})\s*[·•|—–]\s*(\S.*)$/;

const ROMAN: Record<string, number> = { i: 1, v: 5, x: 10, l: 50, c: 100 };

/** An Arabic or Roman number, or null for letters that aren't one written the usual way. */
function valueOf(written: string): number | null {
  if (/^\d+$/.test(written)) return Number(written);
  const lower = written.toLowerCase();
  let total = 0;
  for (let n = 0; n < lower.length; n += 1) {
    const here = ROMAN[lower[n]!]!;
    const next = ROMAN[lower[n + 1] ?? ''] ?? 0;
    total += here < next ? -here : here;
  }
  // "civil" or "ill" are words, not numbers: only a numeral that writes back the same way counts.
  return total > 0 && toRoman(total) === lower ? total : null;
}

function toRoman(value: number): string {
  const steps: [number, string][] = [
    [100, 'c'], [90, 'xc'],
    [50, 'l'], [40, 'xl'], [10, 'x'], [9, 'ix'], [5, 'v'], [4, 'iv'], [1, 'i'],
  ];
  let out = '';
  let left = value;
  for (const [size, mark] of steps) {
    while (left >= size) {
      out += mark;
      left -= size;
    }
  }
  return out;
}

/** The chapter number a title carries, and the title without it; null for a title with none. */
export function chapterOf(title: string): ChapterNumber | null {
  const clean = title.trim();
  const end = AT_END.exec(clean);
  if (end) {
    const number = valueOf(end[2]!);
    if (number !== null) return { number, name: end[1]!.trim() };
  }
  const word = WORD_FIRST.exec(clean);
  if (word) {
    const number = valueOf(word[1]!);
    if (number !== null) return { number, name: word[2]!.trim() };
  }
  const first = NUMBER_FIRST.exec(clean);
  if (first) return { number: Number(first[1]), name: first[2]!.trim() };
  return null;
}
