/**
 * Comments on a note, in the markdown itself (docs/SHARED.md, S8; Matt: "leave comments on documents in a common
 * format that renders as a comment on the document as well as allowing for threads on the comment, make this a
 * standard format within the markdown documents themselves"). Two parts, both plain text any other app shows as it is:
 *
 * - **An anchor** in the prose: `[^c1]` after the words a thread is about, or `==the words==[^c1]` round a selection.
 *   It reads as a footnote's marker anywhere else, and the selection as a highlight.
 * - **One fence at the end of the note** holding every thread:
 *
 *       ```comments
 *       c1 matt 2026-10-04T19:00:12Z
 *       The venue needs confirming - the hall or the barn?
 *         sam 2026-10-04T19:05:40Z
 *         The hall. Confirmed this morning.
 *         resolved sam 2026-10-04T19:06:02Z
 *       ```
 *
 * A thread opens with its head line - its id, its author's handle and the time, ISO in UTC - and the comment's words
 * under it on lines of their own. A reply is the same shape indented two spaces, its words indented two as well; a
 * comment's words may run to several lines, each one a line of the fence, and an empty line in what was typed is not
 * kept (the fence has no blank lines of its own to be confused with). `resolved <handle> <time>`, indented two, closes
 * the thread: its words stay, its wash goes. A words line that would read as one of those heads, or that begins with
 * a backslash or three backticks, is written with a backslash in front, which reading takes off again.
 *
 * Reading never rewrites. What is read keeps each part's place in the note - its lines and offsets - and every change
 * is a few edits at those places (`Edit`), so an unchanged note reads and writes back as the same text, a fence edited
 * by hand keeps the lines it does not understand, and a malformed entry is kept as the text it is: its words read as
 * the thread above's, or as nobody's, and are never dropped. The edits go through the editor as one dispatch
 * (editor/useNoteComments.ts), so a comment is one undo step, saved the way typing is, and in a team note a few
 * characters for the CRDT to merge rather than the whole note written again.
 *
 * Pure, and importing nothing, so the title rule (core/noteTitle.ts) and anything bundled for the server can read it.
 */

/** One comment: the thread's first, or a reply. */
export interface Comment {
  /** The author's handle, or `me` written without an account (core/comments/author.ts). */
  by: string;
  /** When, as written: ISO 8601 in UTC. */
  at: string;
  /** The words, their lines joined by newlines. */
  words: string;
  /** The head line, counting from 1. */
  line: number;
}

export interface Thread {
  id: string;
  /** The comment that opened it. */
  head: Comment;
  replies: Comment[];
  /** Who closed it and when; null while it is open. */
  resolved: { by: string; at: string; line: number } | null;
  /** The thread's lines in the note, its head's to its last that is its own, counting from 1. */
  from: number;
  to: number;
}

/** Where a thread is anchored in the prose. */
export interface Anchor {
  id: string;
  /** The `[^c1]` itself, as offsets into the note. */
  from: number;
  to: number;
  /** The `==the words==` before it, delimiters included, where the anchor is round a selection; null after the words. */
  wash: { from: number; to: number } | null;
}

export interface CommentFence {
  /** The opening line, counting from 1. */
  open: number;
  /** The closing line; null for a fence never closed, which runs to the end of the note as CommonMark has it. */
  close: number | null;
  /** Offsets of the fence's first character and its last line's end. */
  from: number;
  to: number;
}

export interface NoteComments {
  fence: CommentFence | null;
  /** In the order the fence has them. */
  threads: Thread[];
  /** In the order the note has them; only anchors whose thread is in the fence. */
  anchors: Anchor[];
  /** Lines of the fence that are no thread's, counting from 1: kept as they are. */
  strays: number[];
}

/** A change to the note: offsets into the text it was read from, as CodeMirror's changes are. */
export interface Edit {
  from: number;
  to: number;
  insert: string;
}

/** Who and when, for a new comment, a reply or a resolution. */
export interface Stamp {
  by: string;
  /** ISO 8601 in UTC; `stampNow` writes one. */
  at: string;
}

/** An id: `c` and a short tail of letters and digits. */
const ID = 'c[0-9a-z]+';
/** An ISO time, to the minute or finer, in UTC or with an offset. */
const TIME = String.raw`\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})`;
/** A handle as a head writes it: no space, and no backslash first, which is how a words line is told from a head. */
const HANDLE = String.raw`[^\s\\]\S*`;
const HEAD = new RegExp(`^(${ID}) (${HANDLE}) (${TIME})\\s*$`);
const REPLY = new RegExp(`^  (${HANDLE}) (${TIME})\\s*$`);
const RESOLVED = new RegExp(`^(?:  )?resolved (${HANDLE}) (${TIME})\\s*$`);
const OPEN = /^(`{3,}|~{3,})\s*comments\s*$/i;

/** An anchor in the prose, by its id. Global: reset `lastIndex` before each use. */
export const COMMENT_ANCHOR = new RegExp(String.raw`\[\^(${ID})\]`, 'g');

/** The note with its comment anchors taken out, for a label: a title commented on is still called what it was. */
export function withoutAnchors(text: string): string {
  return text.replace(COMMENT_ANCHOR, '');
}

/** Each line's start offset, and the lines. */
function linesOf(body: string): { lines: string[]; starts: number[] } {
  const lines = body.split('\n');
  const starts: number[] = [];
  let at = 0;
  for (const line of lines) {
    starts.push(at);
    at += line.length + 1;
  }
  return { lines, starts };
}

/** A fenced block in the note: its lines, counting from 1, the closing one null for a block never closed. */
interface Block {
  open: number;
  close: number | null;
  comments: boolean;
}

/**
 * Every fenced block in the note, read top to bottom as CommonMark reads them: a fence of three or more backticks or
 * tildes, up to three spaces in, closed by the same character at least as long with nothing after it. A ```comments
 * line inside another block - the Guide's own example of one - is that block's words, not a fence.
 */
function blocksOf(lines: readonly string[]): Block[] {
  const blocks: Block[] = [];
  for (let i = 0; i < lines.length; i += 1) {
    const text = lines[i] ?? '';
    const open = /^\s{0,3}(`{3,}|~{3,})/.exec(text);
    if (!open) continue;
    const mark = open[1]!;
    const close = new RegExp(`^\\s{0,3}${mark[0] === '~' ? '~' : '`'}{${mark.length},}\\s*$`);
    let end: number | null = null;
    for (let j = i + 1; j < lines.length; j += 1) {
      if (close.test(lines[j] ?? '')) {
        end = j;
        break;
      }
    }
    blocks.push({ open: i + 1, close: end === null ? null : end + 1, comments: OPEN.test(text) });
    if (end === null) break;
    i = end;
  }
  return blocks;
}

/** The comments fence: the last one in the note, since it is kept at the end and an earlier one may be an example. */
function fenceOf(blocks: readonly Block[], lines: readonly string[], starts: readonly number[]): CommentFence | null {
  const block = [...blocks].reverse().find((each) => each.comments);
  if (!block) return null;
  const last = (block.close ?? lines.length) - 1;
  return { open: block.open, close: block.close, from: starts[block.open - 1] ?? 0, to: (starts[last] ?? 0) + (lines[last] ?? '').length };
}

/** A words line as written: its backslash taken off. */
const unescape = (line: string) => (line.startsWith('\\') ? line.slice(1) : line);

/** The threads in a fence's lines, and the lines that are no thread's. */
function threadsOf(lines: readonly string[], fence: CommentFence): { threads: Thread[]; strays: number[] } {
  const threads: Thread[] = [];
  const strays: number[] = [];
  let thread: Thread | null = null;
  /** The comment words are being read for: the head, a reply, or none after a resolution. */
  let current: Comment | null = null;
  const last = fence.close === null ? lines.length : fence.close - 1;
  for (let n = fence.open + 1; n <= last; n += 1) {
    const text = lines[n - 1] ?? '';
    const head = HEAD.exec(text);
    if (head) {
      current = { by: head[2]!, at: head[3]!, words: '', line: n };
      thread = { id: head[1]!, head: current, replies: [], resolved: null, from: n, to: n };
      threads.push(thread);
      continue;
    }
    if (!thread) {
      strays.push(n);
      continue;
    }
    const resolved = RESOLVED.exec(text);
    if (resolved) {
      thread.resolved = { by: resolved[1]!, at: resolved[2]!, line: n };
      thread.to = n;
      current = null;
      continue;
    }
    const reply = REPLY.exec(text);
    if (reply) {
      current = { by: reply[1]!, at: reply[2]!, words: '', line: n };
      thread.replies.push(current);
      thread.to = n;
      continue;
    }
    // A comment's words: unindented under the head before any reply, indented two under a reply.
    const isHead = current !== null && current === thread.head;
    const isReply = current !== null && !isHead;
    if (text.trim() && ((isHead && !text.startsWith(' ')) || (isReply && text.startsWith('  ')))) {
      const words = unescape(isReply ? text.slice(2) : text);
      current!.words = current!.words ? `${current!.words}\n${words}` : words;
      thread.to = n;
      continue;
    }
    strays.push(n);
  }
  return { threads, strays };
}

/** The lines inside a fenced block other than the comments fence, counting from 1: their brackets are code. */
function codeLines(blocks: readonly Block[], fence: CommentFence | null, total: number): Set<number> {
  const code = new Set<number>();
  for (const block of blocks) {
    if (fence && block.open === fence.open) continue;
    for (let n = block.open; n <= (block.close ?? total); n += 1) code.add(n);
  }
  return code;
}

/**
 * The `==words==` that ends where an anchor starts, on the same line: the opening `==` nearest before it with words
 * between that do not start or end with a space, as a highlight's do.
 */
function washBefore(line: string, lineFrom: number, at: number): { from: number; to: number } | null {
  const end = at - lineFrom;
  if (end < 4 || line.slice(end - 2, end) !== '==') return null;
  const open = line.lastIndexOf('==', end - 3);
  if (open < 0) return null;
  const words = line.slice(open + 2, end - 2);
  if (!words || /^\s|\s$/.test(words) || words.includes('==')) return null;
  return { from: lineFrom + open, to: lineFrom + end };
}

/** Every thread in the note's comments fence, and every anchor to one of them. */
export function readComments(body: string): NoteComments {
  const { lines, starts } = linesOf(body);
  const blocks = blocksOf(lines);
  const fence = fenceOf(blocks, lines, starts);
  if (!fence) return { fence: null, threads: [], anchors: [], strays: [] };
  const { threads, strays } = threadsOf(lines, fence);
  const ids = new Set(threads.map((thread) => thread.id));
  const code = codeLines(blocks, fence, lines.length);
  const anchors: Anchor[] = [];
  for (let i = 0; i < fence.open - 1; i += 1) {
    if (code.has(i + 1)) continue;
    const line = lines[i] ?? '';
    const lineFrom = starts[i] ?? 0;
    COMMENT_ANCHOR.lastIndex = 0;
    for (let match = COMMENT_ANCHOR.exec(line); match; match = COMMENT_ANCHOR.exec(line)) {
      const id = match[1]!;
      // `[^c1]:` at the start of a line is a footnote's definition, not an anchor.
      if (!ids.has(id) || (line.slice(match.index + match[0].length).startsWith(':') && !line.slice(0, match.index).trim())) continue;
      const from = lineFrom + match.index;
      anchors.push({ id, from, to: from + match[0].length, wash: washBefore(line, lineFrom, from) });
    }
  }
  return { fence, threads, anchors, strays };
}

/** The thread by its id: the first, should a hand-edited fence say one twice. */
export function threadOf(comments: NoteComments, id: string): Thread | null {
  return comments.threads.find((thread) => thread.id === id) ?? null;
}

/** The edits applied to the text they were made against, for a test or a write outside the editor. */
export function applyEdits(body: string, edits: readonly Edit[]): string {
  let out = body;
  for (const edit of [...edits].sort((a, b) => b.from - a.from || b.to - a.to)) out = out.slice(0, edit.from) + edit.insert + out.slice(edit.to);
  return out;
}

/** Now, as a comment's time is written: ISO in UTC, to the second. */
export function stampNow(now: Date = new Date()): string {
  return now.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** Whether a words line would be read as something else, and so is written behind a backslash. */
function needsEscape(line: string): boolean {
  return line.startsWith('\\') || line.startsWith('```') || line.startsWith('~~~') || HEAD.test(line) || RESOLVED.test(line) || REPLY.test(`  ${line}`);
}

/** Typed words as a comment's lines: each trimmed, empty ones left out, any that would misread escaped. */
function wordLines(words: string, indent: string): string[] {
  return words
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => `${indent}${needsEscape(line) ? `\\${line}` : line}`);
}

/** Whether `by` can head a line: a handle, with no space in it. */
const handleOf = (by: string) => by.replace(/\s+/g, '-') || 'me';

/** A fresh id: `c` and four letters or digits, none this note has used for a thread, an anchor or a footnote. */
export function freshId(body: string, random: () => number = Math.random): string {
  const taken = new Set<string>();
  for (const match of body.matchAll(/\[\^([^\]\s]+)\]/g)) taken.add(match[1]!);
  for (const match of body.matchAll(new RegExp(`^(${ID}) `, 'gm'))) taken.add(match[1]!);
  for (let tries = 0; ; tries += 1) {
    const length = 4 + Math.floor(tries / 50);
    let tail = '';
    for (let i = 0; i < length; i += 1) tail += '0123456789abcdefghijklmnopqrstuvwxyz'[Math.floor(random() * 36)] ?? '0';
    const id = `c${tail}`;
    if (!taken.has(id)) return id;
  }
}

/** The edit that puts `lines` into the fence as its last lines, or makes the fence at the note's end to hold them. */
function intoFence(body: string, comments: NoteComments, lines: readonly string[]): Edit {
  const text = lines.join('\n');
  const fence = comments.fence;
  if (fence && fence.close !== null) {
    const at = linesOf(body).starts[fence.close - 1] ?? body.length;
    return { from: at, to: at, insert: `${text}\n` };
  }
  if (fence) return { from: body.length, to: body.length, insert: `${body.endsWith('\n') ? '' : '\n'}${text}` };
  // A blank line between the words and the fence, as a fence is set off anywhere.
  const lead = !body ? '' : body.endsWith('\n\n') ? '' : body.endsWith('\n') ? '\n' : '\n\n';
  return { from: body.length, to: body.length, insert: `${lead}\`\`\`comments\n${text}\n\`\`\`\n` };
}

/** Where a new thread is anchored: round a stretch of the note, or after the words of a line (from 1). */
export type Target = { from: number; to: number } | { line: number };

/**
 * A new thread: its anchor in the prose and its entry in the fence. Round a selection, `==the words==[^id]`, when the
 * selection is words on one line; a selection over several lines, or one that is already a highlight, is anchored
 * after its words without a wash of its own. After a line's words, `[^id]`, for a line. Null where there are no words
 * to say or nowhere to anchor them: in the fence itself, or past the note.
 */
export function addThread(body: string, target: Target, stamp: Stamp, words: string, id: string = freshId(body)): Edit[] | null {
  const lines = wordLines(words, '');
  if (!lines.length) return null;
  const comments = readComments(body);
  const { lines: noteLines, starts } = linesOf(body);
  const anchor = `[^${id}]`;
  const edits: Edit[] = [];
  const inFence = (pos: number) => comments.fence !== null && pos >= comments.fence.from;
  if ('line' in target) {
    const text = noteLines[target.line - 1];
    if (text === undefined) return null;
    const end = (starts[target.line - 1] ?? 0) + text.trimEnd().length;
    if (inFence(end)) return null;
    edits.push({ from: end, to: end, insert: anchor });
  } else {
    let { from, to } = target;
    if (from > to) [from, to] = [to, from];
    from = Math.max(0, from);
    to = Math.min(body.length, to);
    // Whitespace at either end is not what was meant, and a highlight cannot start or end with it.
    while (from < to && /\s/.test(body[from]!)) from += 1;
    while (to > from && /\s/.test(body[to - 1]!)) to -= 1;
    if (inFence(from) || inFence(to)) return null;
    const picked = body.slice(from, to);
    const n = body.slice(0, to).split('\n').length;
    const lineFrom = starts[n - 1] ?? 0;
    const text = noteLines[n - 1] ?? '';
    // Inside a highlight already (an odd number of `==` before it on its line): that highlight is the wash, and the
    // anchor goes after its closing marks rather than a highlight being opened inside another.
    const inside = !picked.includes('\n') && (text.slice(0, from - lineFrom).split('==').length - 1) % 2 === 1;
    const closing = inside ? text.indexOf('==', to - lineFrom) : -1;
    if (picked.length > 4 && picked.startsWith('==') && picked.endsWith('==') && !picked.includes('\n') && !picked.slice(2, -2).includes('==')) {
      // A highlight picked whole: it is the wash.
      edits.push({ from: to, to, insert: anchor });
    } else if (closing >= 0) {
      const at = lineFrom + closing + 2;
      edits.push({ from: at, to: at, insert: anchor });
    } else if (!picked || picked.includes('\n') || picked.includes('==')) {
      // Words over several lines, or none: after the words of the line where the selection ends.
      const at = lineFrom + text.trimEnd().length;
      edits.push({ from: at, to: at, insert: anchor });
    } else {
      edits.push({ from, to: from, insert: '==' }, { from: to, to, insert: `==${anchor}` });
    }
  }
  edits.push(intoFence(body, comments, [`${id} ${handleOf(stamp.by)} ${stamp.at}`, ...lines]));
  return edits;
}

/** The offset at the end of line `n` (from 1), its line break after it. */
function afterLine(body: string, n: number): number {
  const { lines, starts } = linesOf(body);
  return (starts[n - 1] ?? 0) + (lines[n - 1] ?? '').length;
}

/** A reply under a thread, after its last comment and before its resolution, if it has one. Null for no words or no thread. */
export function addReply(body: string, id: string, stamp: Stamp, words: string): Edit[] | null {
  const lines = wordLines(words, '  ');
  const thread = threadOf(readComments(body), id);
  if (!lines.length || !thread) return null;
  const text = [`  ${handleOf(stamp.by)} ${stamp.at}`, ...lines].join('\n');
  if (thread.resolved) {
    const at = linesOf(body).starts[thread.resolved.line - 1] ?? body.length;
    return [{ from: at, to: at, insert: `${text}\n` }];
  }
  const at = afterLine(body, thread.to);
  return [{ from: at, to: at, insert: `\n${text}` }];
}

/** The thread closed: `resolved <handle> <time>` under it. Nothing for a thread already closed, or none. */
export function resolveThread(body: string, id: string, stamp: Stamp): Edit[] | null {
  const thread = threadOf(readComments(body), id);
  if (!thread || thread.resolved) return null;
  const at = afterLine(body, thread.to);
  return [{ from: at, to: at, insert: `\n  resolved ${handleOf(stamp.by)} ${stamp.at}` }];
}

/** The line from its start to the next one's, or to the end of the line before it for the note's last line. */
function wholeLines(body: string, first: number, last: number): Edit {
  const { lines, starts } = linesOf(body);
  const from = starts[first - 1] ?? 0;
  if (last < lines.length) return { from, to: starts[last] ?? body.length, insert: '' };
  return { from: Math.max(0, from - 1), to: body.length, insert: '' };
}

/** The thread open again: its resolution's line taken out. Nothing for a thread that is open, or none. */
export function reopenThread(body: string, id: string): Edit[] | null {
  const thread = threadOf(readComments(body), id);
  if (!thread?.resolved) return null;
  return [wholeLines(body, thread.resolved.line, thread.resolved.line)];
}

/**
 * The thread gone: its lines out of the fence, and every anchor to it out of the prose, a wash's `==` with it so the
 * words are as they were before the comment. The fence goes too when nothing is left in it, with the blank line it was
 * set off by. Lines in the fence that were no thread's stay.
 */
export function deleteThread(body: string, id: string): Edit[] | null {
  const comments = readComments(body);
  const thread = threadOf(comments, id);
  if (!thread || !comments.fence) return null;
  const edits: Edit[] = [];
  for (const anchor of comments.anchors) {
    if (anchor.id !== id) continue;
    if (anchor.wash) {
      edits.push({ from: anchor.wash.from, to: anchor.wash.from + 2, insert: '' }, { from: anchor.wash.to - 2, to: anchor.to, insert: '' });
    } else edits.push({ from: anchor.from, to: anchor.to, insert: '' });
  }
  const others = comments.threads.filter((each) => each !== thread);
  if (!others.length && !comments.strays.some((n) => (linesOf(body).lines[n - 1] ?? '').trim())) {
    // Nothing left: the fence and the blank lines before it, back to the words' last line.
    let from = comments.fence.from;
    while (from > 0 && body[from - 1] === '\n') from -= 1;
    const tail = body.slice(comments.fence.to);
    edits.push({ from, to: comments.fence.to + (tail.startsWith('\n') ? 1 : 0), insert: from > 0 && tail.startsWith('\n') ? '\n' : '' });
    return edits;
  }
  edits.push(wholeLines(body, thread.from, thread.to));
  return edits;
}

/** How many threads the note has, and how many of them are open. */
export function threadCounts(threads: readonly { resolved: unknown }[]): { threads: number; open: number } {
  return { threads: threads.length, open: threads.filter((thread) => !thread.resolved).length };
}

/** "3 comments, 1 open", or null for none: the More sheet's line. */
export function countWords(threads: readonly { resolved: unknown }[]): string | null {
  const { threads: all, open } = threadCounts(threads);
  if (!all) return null;
  if (all === 1) return open ? '1 comment, open' : '1 comment, resolved';
  const said = `${all} comments`;
  return open === all ? `${said}, all open` : open ? `${said}, ${open} open` : `${said}, all resolved`;
}

/**
 * Each person's comments and replies, by handle (S8: "a member's profile card counts their comments and replies"):
 * from parsed threads, not the fence's text, so a canvas's threads (S9, a JSON array) are counted the same way.
 */
export function countsBy(threads: readonly Pick<Thread, 'head' | 'replies'>[]): Map<string, { comments: number; replies: number }> {
  const counts = new Map<string, { comments: number; replies: number }>();
  const of = (by: string) => {
    let count = counts.get(by);
    if (!count) {
      count = { comments: 0, replies: 0 };
      counts.set(by, count);
    }
    return count;
  };
  for (const thread of threads) {
    of(thread.head.by).comments += 1;
    for (const reply of thread.replies) of(reply.by).replies += 1;
  }
  return counts;
}
