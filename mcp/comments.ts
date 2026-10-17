import { addReply, addThread, freshId, readComments, resolveThread, stampNow, withoutAnchors, type Edit, type Stamp } from '../tauri/src/app/core/comments/format.ts';
import { frontMatterEnd } from '../tauri/src/app/core/frontMatter.ts';

/**
 * The edits applied as the editor applies one dispatch of them: two inserted at one place land in the order given.
 * (format.ts `applyEdits` puts the later first at a tie, which is only ever met at the end of a note with no line
 * break after it: a selection's closing `==[^c1]` and the fence made after it.)
 */
function applyEdits(body: string, edits: readonly Edit[]): string {
  const order = edits.map((edit, at) => ({ edit, at })).sort((a, b) => b.edit.from - a.edit.from || b.edit.to - a.edit.to || b.at - a.at);
  let out = body;
  for (const { edit } of order) out = out.slice(0, edit.from) + edit.insert + out.slice(edit.to);
  return out;
}

/**
 * A note's comment threads for the connector (docs/CLAUDE_LIVE.md, "Comments"): read and written in the format
 * tauri/docs/SHARED.md (S8) defines - `[^c1]` after the words or `==the words==[^c1]` round them, and the ```comments
 * fence at the end holding every thread - by the app's own module (core/comments/format.ts), so what Claude writes is
 * what the editor draws and what a member's phone writes Claude reads. The author is the AI's name, as a head line's
 * handle (a space in it written as a dash, as the format has it).
 *
 * Every write answers the new body whole, for `GlyphAccount.edit` to put as it puts any other change, or a sentence
 * saying why there is nothing to write.
 */

/** A thread as list_comments answers it. */
export interface ThreadView {
  id: string;
  /** The words it is on: a selection's, or the line's it is after; null for the note as a whole or an anchor gone. */
  on: string | null;
  resolved: { by: string; at: string } | null;
  messages: { author: string; at: string; text: string }[];
}

/** At most this many characters of the line a thread is after: the words it is about, not the whole paragraph. */
const ON_CHARS = 200;

/** Every thread in the note, in the fence's order. */
export function threadsIn(body: string): ThreadView[] {
  const comments = readComments(body);
  return comments.threads.map((thread) => {
    const anchor = comments.anchors.find((each) => each.id === thread.id);
    let on: string | null = null;
    if (anchor?.wash) on = body.slice(anchor.wash.from + 2, anchor.wash.to - 2);
    else if (anchor) {
      const start = body.lastIndexOf('\n', anchor.from - 1) + 1;
      const words = withoutAnchors(body.slice(start, anchor.from)).replace(/^\s*(?:[-*+]|\d+[.)]|#{1,6})?\s*(?:\[[ xX-]\]\s*)?/, '').trim();
      on = words ? words.slice(-ON_CHARS) : null;
    }
    return {
      id: thread.id,
      on,
      resolved: thread.resolved ? { by: thread.resolved.by, at: thread.resolved.at } : null,
      messages: [thread.head, ...thread.replies].map((comment) => ({ author: comment.by, at: comment.at, text: comment.words })),
    };
  });
}

/** What a write made: the body, or why nothing was written. */
export type Written = { body: string; id: string } | { refused: string };

/** The first line of the note's words, from 1: past the front matter, the first that says anything. */
function firstWordsLine(body: string): number | null {
  const lines = body.split('\n');
  for (let i = frontMatterEnd(lines); i < lines.length; i += 1) if (lines[i]!.trim()) return i + 1;
  return null;
}

/**
 * A new thread by `stamp.by`: on the exact words `on`, the first place the note's words have them outside its front
 * matter, its fences and the comments fence; or with `on` left out, on the note as a whole, anchored after its first
 * line of words as the app's "Add a comment" on a note does. Its id is fresh: none the note has used.
 */
export function commentOn(body: string, on: string | undefined, stamp: Stamp, words: string, id: string = freshId(body)): Written {
  if (!words.trim()) return { refused: 'Say what the comment says.' };
  const want = on?.trim();
  let edits;
  if (want) {
    const at = placeOf(body, want);
    if (at === null) return { refused: `The note’s words do not read “${want}” anywhere a comment can go (not its front matter, a fenced block, or the comments). Give words exactly as the note has them, on one line.` };
    edits = addThread(body, { from: at, to: at + want.length }, stamp, words, id);
  } else {
    const line = firstWordsLine(body);
    if (line === null) return { refused: 'The note has no words to comment on.' };
    edits = addThread(body, { line }, stamp, words, id);
  }
  if (!edits) return { refused: 'There is nowhere in the note to anchor that comment.' };
  return { body: applyEdits(body, edits), id };
}

/** Where `words` first are in the note's prose: past its front matter, outside every fenced block, on one line. */
function placeOf(body: string, words: string): number | null {
  if (words.includes('\n')) return null;
  const lines = body.split('\n');
  const fence = readComments(body).fence;
  let from = 0;
  for (let i = 0; i < frontMatterEnd(lines); i += 1) from += lines[i]!.length + 1;
  const code = fencedRanges(lines);
  for (let at = body.indexOf(words, from); at >= 0; at = body.indexOf(words, at + 1)) {
    if (fence && at >= fence.from) return null;
    if (code.some(([start, end]) => at < end && at + words.length > start)) continue;
    return at;
  }
  return null;
}

/** The offsets of every fenced block, fence lines included. */
function fencedRanges(lines: readonly string[]): [number, number][] {
  const ranges: [number, number][] = [];
  const starts: number[] = [];
  let at = 0;
  for (const line of lines) {
    starts.push(at);
    at += line.length + 1;
  }
  for (let i = 0; i < lines.length; i += 1) {
    const open = /^\s{0,3}(`{3,}|~{3,})/.exec(lines[i]!);
    if (!open) continue;
    const mark = open[1]!;
    const close = new RegExp(`^\\s{0,3}${mark[0] === '~' ? '~' : '`'}{${mark.length},}\\s*$`);
    let j = i + 1;
    while (j < lines.length && !close.test(lines[j]!)) j += 1;
    const last = Math.min(j, lines.length - 1);
    ranges.push([starts[i]!, starts[last]! + lines[last]!.length]);
    i = j;
  }
  return ranges;
}

/** The ids the note's threads have, for a refusal that says which there are. */
function idsOf(body: string): string {
  const ids = readComments(body).threads.map((thread) => thread.id);
  return ids.length ? `Its threads are: ${ids.join(', ')}.` : 'It has no comments.';
}

/** A reply under thread `id`, before its resolution if it has one. */
export function replyTo(body: string, id: string, stamp: Stamp, words: string): Written {
  if (!words.trim()) return { refused: 'Say what the reply says.' };
  const edits = addReply(body, id, stamp, words);
  if (!edits) return { refused: `The note has no comment ${id}. ${idsOf(body)}` };
  return { body: applyEdits(body, edits), id };
}

/** Thread `id` closed. */
export function resolve(body: string, id: string, stamp: Stamp): Written {
  const thread = readComments(body).threads.find((each) => each.id === id);
  if (!thread) return { refused: `The note has no comment ${id}. ${idsOf(body)}` };
  if (thread.resolved) return { refused: `The comment ${id} was already resolved by ${thread.resolved.by} at ${thread.resolved.at}.` };
  const edits = resolveThread(body, id, stamp);
  if (!edits) return { refused: `The comment ${id} could not be resolved.` };
  return { body: applyEdits(body, edits), id };
}

/** `by`, now: what a comment the AI writes is stamped with. */
export function stampOf(by: string, now: Date = new Date()): Stamp {
  return { by, at: stampNow(now) };
}
