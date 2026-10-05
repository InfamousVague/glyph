import type { Stamp } from '../core/comments/format.ts';
import type { CardThread } from '../editor/CommentCard.tsx';
import { fileTitle } from './cardLooks.ts';
import type { Canvas, CanvasComment, CanvasNode } from './jsonCanvas.ts';

/**
 * A canvas's comment threads (docs/SHARED.md, S9): a `comments` array in its JSON, a thread each, anchored to a
 * card by its id, with the shape a note's threads have (core/comments/format.ts) so the same card draws them
 * (editor/CommentCard.tsx). Every change here is a new canvas, as every other edit is (canvas/edits.ts): the view
 * hands it back whole, and a team's structure writes only what changed (core/team/canvas.ts).
 */

/** The threads as the card draws them, oldest first. */
export function threadsOf(canvas: Canvas): CardThread[] {
  return [...(canvas.comments ?? [])]
    .sort((a, b) => a.at.localeCompare(b.at) || a.id.localeCompare(b.id))
    .map((thread) => ({
      id: thread.id,
      head: { by: thread.by, at: thread.at, words: thread.text },
      replies: thread.replies.map((reply) => ({ by: reply.by, at: reply.at, words: reply.text })),
      resolved: thread.resolved ?? null,
    }));
}

/** The threads on one card, oldest first. */
export function threadsOn(canvas: Canvas, nodeId: string): CanvasComment[] {
  return (canvas.comments ?? []).filter((thread) => thread.node === nodeId).sort((a, b) => a.at.localeCompare(b.at) || a.id.localeCompare(b.id));
}

/** What a card's threads say: how many are open, and who started the first open one (or the first), for the round's colour. */
export function markOf(canvas: Canvas, nodeId: string): { count: number; open: number; by: string } | null {
  const on = threadsOn(canvas, nodeId);
  if (on.length === 0) return null;
  const open = on.filter((thread) => !thread.resolved);
  return { count: on.length, open: open.length, by: (open[0] ?? on[0])!.by };
}

/** The words a thread is about: the card's first line, its name, its address or its note's title; null for nothing to quote. */
export function quoteOf(canvas: Canvas, nodeId: string): string | null {
  const node = canvas.nodes.find((each) => each.id === nodeId);
  if (!node) return null;
  const line = firstLine(node);
  return line ? (line.length > 90 ? `${line.slice(0, 89).trimEnd()}…` : line) : null;
}

function firstLine(node: CanvasNode): string {
  switch (node.type) {
    case 'text':
      return node.text.split('\n').find((each) => each.trim())?.trim() ?? '';
    case 'group':
      return node.label ?? '';
    case 'link':
      return node.url;
    case 'file':
      return fileTitle(node.file);
  }
}

/** An id a canvas's thread is called by: `c` and a short tail, none it has already. */
export function freshThreadId(canvas: Canvas, random: () => number = Math.random): string {
  const taken = new Set((canvas.comments ?? []).map((thread) => thread.id));
  for (let tries = 0; ; tries += 1) {
    const length = 4 + Math.floor(tries / 50);
    let tail = '';
    for (let i = 0; i < length; i += 1) tail += '0123456789abcdefghijklmnopqrstuvwxyz'[Math.floor(random() * 36)] ?? '0';
    const id = `c${tail}`;
    if (!taken.has(id)) return id;
  }
}

/** A thread started on a card; null for a card that is not there, or no words. */
export function withThread(canvas: Canvas, nodeId: string, stamp: Stamp, text: string, id: string = freshThreadId(canvas)): Canvas | null {
  const words = text.trim();
  if (!words || !canvas.nodes.some((node) => node.id === nodeId)) return null;
  return { ...canvas, comments: [...(canvas.comments ?? []), { id, node: nodeId, by: stamp.by, at: stamp.at, text: words, replies: [] }] };
}

/** A reply under a thread; null for a thread that is not there, or no words. */
export function withReply(canvas: Canvas, id: string, stamp: Stamp, text: string): Canvas | null {
  const words = text.trim();
  if (!words) return null;
  return changed(canvas, id, (thread) => ({ ...thread, replies: [...thread.replies, { by: stamp.by, at: stamp.at, text: words }] }));
}

export function resolvedThread(canvas: Canvas, id: string, stamp: Stamp): Canvas | null {
  return changed(canvas, id, (thread) => ({ ...thread, resolved: { by: stamp.by, at: stamp.at } }));
}

export function reopenedThread(canvas: Canvas, id: string): Canvas | null {
  return changed(canvas, id, ({ resolved: _gone, ...thread }) => thread);
}

/** A thread taken off; null for one that is not there. */
export function withoutThread(canvas: Canvas, id: string): Canvas | null {
  if (!canvas.comments?.some((thread) => thread.id === id)) return null;
  const comments = canvas.comments.filter((thread) => thread.id !== id);
  return comments.length ? { ...canvas, comments } : withoutComments(canvas);
}

function changed(canvas: Canvas, id: string, change: (thread: CanvasComment) => CanvasComment): Canvas | null {
  if (!canvas.comments?.some((thread) => thread.id === id)) return null;
  return { ...canvas, comments: canvas.comments.map((thread) => (thread.id === id ? change(thread) : thread)) };
}

function withoutComments(canvas: Canvas): Canvas {
  const { comments: _gone, ...rest } = canvas;
  return rest;
}
