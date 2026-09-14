/**
 * Links through the model, kept by construction rather than by asking.
 *
 * Matt: "AI formatting drops links". A note carries links three ways: as
 * markdown, `[the words](https://www.notion.so/…)` from a Notion send; as an
 * autolink, `<https://…>`; and bare, `https://…` in the middle of a sentence.
 * A small model rewriting the note loses them: an address is a hundred
 * characters it cannot copy and will not keep. So before the note goes in,
 * every address is swapped for a short token it can copy (`link-1`,
 * `link-2`), the way a picture line is kept whole, and after the rewrite
 * comes out the tokens are swapped back. A markdown link keeps its words in
 * the note, so the model can rewrite the sentence around them:
 * `[the words](link-1)`.
 *
 * A token that does not come back is not a lost link. If the link's words
 * survived, they are made the link again; if not, the link is added at the
 * end of the note on its own line. None of this depends on the prompt,
 * though the prompt asks as well (prompt.ts).
 */

export interface ProtectedLink {
  /** `link-3`: what stands in for the address while the model works. */
  token: string;
  /** The link's own words, for a markdown link; null for an address on its own. */
  text: string | null;
  url: string;
  /** How the link was written, to put it back the same way: `[words](url)`, `<url>`, or the bare address. */
  original: string;
}

export interface Protected {
  text: string;
  links: ProtectedLink[];
}

/** `[words](https://…)`, but not a picture `![…](…)`. */
const MARKDOWN = /(?<!!)\[([^\]\n]*)\]\(\s*(https?:\/\/[^\s()]+)\s*\)/g;
const AUTOLINK = /<(https?:\/\/[^\s<>]+)>/g;
const BARE = /https?:\/\/[^\s<>()[\]]+/g;
/** Punctuation that ends the sentence, not the address. */
const TRAILING = /[.,;:!?'"]+$/;

/** The note with every link replaced by a token, and the links to put back. */
export function protectLinks(body: string): Protected {
  const links: ProtectedLink[] = [];
  const next = () => `link-${links.length + 1}`;
  let text = body.replace(MARKDOWN, (whole, words: string, url: string) => {
    const token = next();
    links.push({ token, text: words, url, original: whole });
    return `[${words}](${token})`;
  });
  text = text.replace(AUTOLINK, (whole, url: string) => {
    const token = next();
    links.push({ token, text: null, url, original: whole });
    return `<${token}>`;
  });
  text = text.replace(BARE, (match) => {
    const trailing = TRAILING.exec(match)?.[0] ?? '';
    const url = trailing ? match.slice(0, -trailing.length) : match;
    const token = next();
    links.push({ token, text: null, url, original: url });
    return `<${token}>${trailing}`;
  });
  return { text, links };
}

/**
 * The rewrite with its links back. Every way the model may have written a
 * token is taken - `[words](link-1)`, `<link-1>`, `link-1` or `link 1` on its
 * own - and the model's words around it are kept. With `final`, a link whose
 * token never came back is restored around its words or added at the end;
 * a partial rewrite still streaming is only substituted.
 */
export function restoreLinks(text: string, links: readonly ProtectedLink[], final = true): string {
  let out = text;
  const missing: ProtectedLink[] = [];
  for (const link of links) {
    const number = link.token.slice('link-'.length);
    // `link-1` and not `link-10`; `link 1` too, a model's likeliest slip.
    const token = `link[\\s-]?${number}(?!\\d)`;
    let found = false;
    out = out.replace(new RegExp(`\\[([^\\]\\n]*)\\]\\s*\\(\\s*${token}\\s*\\)`, 'gi'), (_, words: string) => {
      found = true;
      return `[${words}](${link.url})`;
    });
    out = out.replace(new RegExp(`<\\s*${token}\\s*>`, 'gi'), () => {
      found = true;
      return link.original;
    });
    out = out.replace(new RegExp(`\\b${token}\\b`, 'gi'), () => {
      found = true;
      return link.original;
    });
    if (!found) missing.push(link);
  }
  if (!final) return out;

  const orphans: string[] = [];
  for (const link of missing) {
    const words = link.text?.trim() ?? '';
    const at = words ? indexOfWords(out, words) : -1;
    if (at >= 0) {
      out = `${out.slice(0, at)}[${out.slice(at, at + words.length)}](${link.url})${out.slice(at + words.length)}`;
    } else {
      orphans.push(link.original);
    }
  }
  if (orphans.length) out = `${out.replace(/\s+$/, '')}\n\n${orphans.join('\n')}\n`;
  return out;
}

/** Where `words` appear in `haystack`, regardless of case, and not already as a link's words. */
function indexOfWords(haystack: string, words: string): number {
  const lower = haystack.toLowerCase();
  const needle = words.toLowerCase();
  let from = 0;
  while (from <= lower.length) {
    const at = lower.indexOf(needle, from);
    if (at < 0) return -1;
    const linked = haystack[at - 1] === '[' && haystack.startsWith('](', at + needle.length);
    if (!linked) return at;
    from = at + needle.length;
  }
  return -1;
}
