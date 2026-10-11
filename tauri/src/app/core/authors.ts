import { frontMatterValue, withFrontMatterValue } from './frontMatter.ts';

/**
 * Who wrote a note (Matt: "Add authors to notes, since in the future we'll have shared / collaborative notes and I
 * want the AI to provide it's logo and name so we can have it listed when they co author books and pages and stuff").
 *
 * A note's authors are its front matter's `authors:`, names separated by commas: `authors: infamousvague, Claude`. A
 * note with none is the person's own, and says nothing about it. An AI that writes a note through the notes connector
 * (mcp/server.ts) adds its own name there, after the account's, so the note is listed as written by both. The line is
 * part of the words, so it goes wherever the note does: every device, a shared link, a download.
 */

/** The names in a note's `authors:`, in order, each once. Empty for a note that names none. */
export function authorsOf(body: string): string[] {
  const said = frontMatterValue(body, 'authors');
  if (!said) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const part of said.split(',')) {
    const name = part.trim().replace(/^(["'])(.*)\1$/, '$2').trim();
    if (!name || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    out.push(name);
  }
  return out;
}

/**
 * The body with `author` among its authors. A note that named none takes `owner` first, since it was theirs before
 * anyone wrote in it with them; `owner` absent, the author alone. A name already there is not added again.
 */
export function withAuthor(body: string, author: string, owner?: string): string {
  const name = cleanName(author);
  if (!name) return body;
  const now = authorsOf(body);
  const next = now.length ? [...now] : owner && cleanName(owner) ? [cleanName(owner)] : [];
  if (!next.some((n) => n.toLowerCase() === name.toLowerCase())) next.push(name);
  if (next.length === now.length && next.every((n, i) => n === now[i])) return body;
  return withFrontMatterValue(body, 'authors', next.join(', '));
}

/** Every author across notes, in the order first met: a book's own and its chapters'. */
export function authorsAcross(bodies: readonly string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const body of bodies) {
    for (const name of authorsOf(body)) {
      if (seen.has(name.toLowerCase())) continue;
      seen.add(name.toLowerCase());
      out.push(name);
    }
  }
  return out;
}

/** A name as the line can hold it: one line, no commas (they separate names), a sensible length. */
function cleanName(name: string): string {
  return name.replace(/[,\n\r]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 40);
}

/**
 * The name an AI goes by, from what its app calls itself when it connects (MCP's clientInfo) or what it said it is.
 * Said beats known; known names read as the product ("claude-ai" is Claude). Null when there is nothing to go on.
 */
export function aiName(said: string | undefined, client: { name?: string; title?: string } | undefined): string | null {
  const given = said?.trim();
  if (given) return cleanName(given);
  const from = `${client?.title ?? ''} ${client?.name ?? ''}`.toLowerCase();
  for (const [pattern, name] of KNOWN) if (pattern.test(from)) return name;
  const raw = client?.title?.trim() || client?.name?.trim();
  return raw ? cleanName(raw) : null;
}

/** The name the app's own model signs with (ai/useLanding.ts): the ghost is the app, whichever model wrote. */
export const AI_AUTHOR = 'Ghost';

const KNOWN: [RegExp, string][] = [
  [/^ghost$/, AI_AUTHOR],
  [/claude/, 'Claude'],
  [/chatgpt|openai/, 'ChatGPT'],
  [/gemini/, 'Gemini'],
  [/copilot/, 'Copilot'],
  [/cursor/, 'Cursor'],
];

/** Whether a name is an AI's the app knows how to mark, for a byline to draw its sign rather than an initial. */
export function isKnownAi(name: string): boolean {
  return KNOWN.some(([, known]) => known.toLowerCase() === name.toLowerCase());
}
