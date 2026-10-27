import type { DocsIndex } from './book.ts';

/**
 * Searching Ghost.md Docs (Matt, 2026-10-26: "add the ability to search the book"): the index the build writes
 * (book.ts `docsSearchIndex`, /docs/search.json) asked as you type, in the page, with nothing sent anywhere.
 *
 * A query is its words, and a section is found when every word starts a word of it: of the chapter's title, the
 * section's heading or the words under it, so "zoo" finds Zoom and "simple mode" finds a section that says both.
 * Accents and case are folded away on both sides. Where a word is found ranks the section: in the chapter's title
 * over in the heading over in the words, a word met whole over one only begun, and the query met as it was typed,
 * words together, over its words met apart. A chapter gives at most five sections, so one long chapter does not hide
 * the rest of the book.
 *
 * Pure: the search box (DocsSearch.tsx) draws what this answers, and the page finds the same words again in its
 * editor's text with [matchRanges] to mark them where the reader lands (reveal.ts).
 */

/** A run of a snippet or a heading: words, and whether they are what was searched for. */
export interface Part {
  text: string;
  hit: boolean;
}

/** A section found: where it is, how well it matched, and the words to show for it, the found ones marked. */
export interface SearchHit {
  /** The page's place in the index's `pages`. */
  page: number;
  slug: string;
  pageTitle: string;
  heading: string | null;
  anchor: string;
  score: number;
  headingParts: Part[];
  titleParts: Part[];
  snippet: Part[];
}

/** The index made ready to ask: each field folded once, as [fold] reads it, beside the words as they are. */
export interface Prepared {
  index: DocsIndex;
  titles: string[];
  sections: { page: number; heading: string | null; anchor: string; text: string; fHeading: string; fText: string }[];
}

/** The most sections one chapter gives, and the most there are. */
const PER_PAGE = 5;
const LIMIT = 30;

/**
 * Text with accents and case folded away, one character for one, so a place in the folded text is the same place in
 * the text: "Café" is "cafe", and the curly apostrophe is the straight one.
 */
export function fold(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i]!;
    if (c < '\u0080') {
      out += c.toLowerCase();
      continue;
    }
    if (c === '’' || c === '‘') {
      out += "'";
      continue;
    }
    const base = c.normalize('NFKD').replace(/\p{M}+/gu, '').toLowerCase();
    out += base.length ? base[0]! : c;
  }
  return out;
}

const WORD = /[\p{L}\p{N}]/u;
const isWord = (c: string | undefined) => c !== undefined && WORD.test(c);

/** A query's words, folded, each once, in the order typed. */
export function queryTerms(query: string): string[] {
  const words = fold(query).split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  return [...new Set(words)];
}

/** Where a word starts with `term` in folded text: each place, and whether the word is the term whole. */
function starts(folded: string, term: string): { at: number; whole: boolean }[] {
  const found: { at: number; whole: boolean }[] = [];
  for (let at = folded.indexOf(term); at >= 0; at = folded.indexOf(term, at + 1)) {
    if (isWord(folded[at - 1])) continue;
    found.push({ at, whole: !isWord(folded[at + term.length]) });
  }
  return found;
}

/**
 * Every run of folded text the terms are found in, at the start of a word, as `[from, to]` in the order they come,
 * overlapping runs joined: what a snippet marks, and what the page marks where the reader lands.
 */
export function matchRanges(folded: string, terms: readonly string[]): [number, number][] {
  const runs: [number, number][] = [];
  for (const term of terms) for (const { at } of starts(folded, term)) runs.push([at, at + term.length]);
  runs.sort((a, b) => a[0] - b[0] || b[1] - a[1]);
  const joined: [number, number][] = [];
  for (const run of runs) {
    const last = joined.at(-1);
    if (last && run[0] <= last[1]) last[1] = Math.max(last[1], run[1]);
    else joined.push([...run]);
  }
  return joined;
}

/** Text cut into runs, the found ones marked. */
export function marked(text: string, terms: readonly string[]): Part[] {
  const parts: Part[] = [];
  let at = 0;
  for (const [from, to] of matchRanges(fold(text), terms)) {
    if (from > at) parts.push({ text: text.slice(at, from), hit: false });
    parts.push({ text: text.slice(from, to), hit: true });
    at = to;
  }
  if (at < text.length || !parts.length) parts.push({ text: text.slice(at), hit: false });
  return parts;
}

/**
 * A few words of a section round where the search found it, at most `width` characters cut at a space, with … where
 * words were cut away: round the query as typed where the words are together, else round the first word found. A
 * section found only by its title or heading shows its first words.
 */
export function snippetOf(text: string, terms: readonly string[], width = 160): Part[] {
  if (!text) return [];
  const folded = fold(text);
  const phrase = terms.length > 1 ? starts(folded, terms.join(' '))[0]?.at : undefined;
  const first = phrase ?? matchRanges(folded, terms)[0]?.[0] ?? 0;
  if (text.length <= width) return marked(text, terms);
  let from = Math.max(0, Math.min(first - Math.floor(width / 3), text.length - width));
  let to = Math.min(text.length, from + width);
  if (from > 0) {
    const space = text.indexOf(' ', from);
    from = space >= 0 && space < first ? space + 1 : from;
  }
  if (to < text.length) {
    const space = text.lastIndexOf(' ', to);
    to = space > first ? space : to;
  }
  const parts = marked(text.slice(from, to), terms);
  if (from > 0) parts.unshift({ text: '…', hit: false });
  if (to < text.length) parts.push({ text: '…', hit: false });
  return parts;
}

export function prepare(index: DocsIndex): Prepared {
  return {
    index,
    titles: index.pages.map((p) => fold(p.title)),
    sections: index.sections.map(([page, heading, anchor, text]) => ({ page, heading, anchor, text, fHeading: fold(heading ?? ''), fText: fold(text) })),
  };
}

/** How well one field holds a term: met whole, met only begun, or not at all. */
function grade(folded: string, term: string, whole: number, begun: number): number {
  const found = starts(folded, term);
  if (!found.length) return 0;
  return found.some((f) => f.whole) ? whole : begun;
}

/**
 * The sections a query finds, best first, by the rules at the top of this file: every term must be met in the section or
 * its chapter's title. A term in the title is worth 12 (8 begun), in the heading 8 (5 begun), and in the words 2,
 * and a little more for each time it comes again, up to six. The query typed whole earns 6 more in a heading, 3 in
 * the words. A chapter's opening section, the one with no heading, stands for the chapter its title names.
 */
export function searchDocs(prepared: Prepared, query: string, limit = LIMIT): SearchHit[] {
  const terms = queryTerms(query);
  if (!terms.length) return [];
  const phrase = terms.length > 1 ? terms.join(' ') : null;
  const scored: { at: number; score: number }[] = [];
  prepared.sections.forEach((section, at) => {
    const title = prepared.titles[section.page] ?? '';
    let score = 0;
    for (const term of terms) {
      const inTitle = grade(title, term, 12, 8);
      const inHeading = grade(section.fHeading, term, 8, 5);
      const times = starts(section.fText, term).length;
      const inText = times ? 2 + Math.min(times - 1, 6) * 0.25 : 0;
      if (!inTitle && !inHeading && !inText) return;
      score += inTitle + inHeading + inText;
    }
    if (phrase) {
      if (starts(section.fHeading, phrase).length || starts(title, phrase).length) score += 6;
      else if (starts(section.fText, phrase).length) score += 3;
    }
    // The chapter itself, when its title is what was asked for: its top over its sections.
    if (section.heading === null && terms.every((t) => starts(title, t).length)) score += 4;
    scored.push({ at, score });
  });
  scored.sort((a, b) => b.score - a.score || a.at - b.at);
  const perPage = new Map<number, number>();
  const hits: SearchHit[] = [];
  for (const { at, score } of scored) {
    const section = prepared.sections[at]!;
    const taken = perPage.get(section.page) ?? 0;
    if (taken >= PER_PAGE) continue;
    perPage.set(section.page, taken + 1);
    const page = prepared.index.pages[section.page]!;
    hits.push({
      page: section.page,
      slug: page.slug,
      pageTitle: page.title,
      heading: section.heading,
      anchor: section.anchor,
      score,
      titleParts: marked(page.title, terms),
      headingParts: section.heading ? marked(section.heading, terms) : [],
      snippet: snippetOf(section.text, terms),
    });
    if (hits.length >= limit) break;
  }
  return hits;
}
