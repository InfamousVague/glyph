import { useMemo, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from 'react';
import { commentHandle, stampHere } from '../core/comments/author.ts';
import { useCommentColours } from '../core/comments/colours.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { CommentSheet, type CommentPage } from '../editor/CommentSheet.tsx';
import { quoteOf, reopenedThread, resolvedThread, threadsOf, threadsOn, withReply, withThread, withoutThread } from './comments.ts';
import type { Canvas } from './jsonCanvas.ts';

/**
 * A canvas's comments on its screen (docs/SHARED.md, S9): a round on a card's corner for its threads, in the colour
 * of who started the first open one, with how many are open; Comment on the picked card's bar starts one; and the
 * card a thread is drawn in is the note's own (editor/CommentSheet.tsx), from the same shape. Every change is the
 * canvas handed back whole (`onChange`), as a card moved is, so a team's structure merges it (core/team/canvas.ts).
 */

export interface CanvasComments {
  /** Starts a thread on a card. */
  start: (nodeId: string) => void;
  /** Opens a card's threads: the one, or the list of them. */
  open: (nodeId: string) => void;
  /** The sheet, while one is open. */
  sheet: ReactNode;
}

export function useCanvasComments(canvas: Canvas, noteId: string | undefined, onChange: ((canvas: Canvas) => void) | undefined): CanvasComments {
  const colours = useCommentColours(noteId ?? '');
  const [page, setPage] = useState<CommentPage | null>(null);
  /** The card the comment being written is for, or whose threads the list shows. */
  const [card, setCard] = useState<string | null>(null);
  const threads = useMemo(() => threadsOf(canvas), [canvas]);
  const close = () => setPage(null);
  const change = (next: Canvas | null, felt: Parameters<typeof fireNativeHaptic>[0]): boolean => {
    if (!next || !onChange) return false;
    onChange(next);
    fireNativeHaptic(felt);
    return true;
  };
  const start = (nodeId: string) => {
    if (!onChange) return;
    setCard(nodeId);
    fireNativeHaptic('selection');
    setPage({ kind: 'new', quote: quoteOf(canvas, nodeId) });
  };
  const open = (nodeId: string) => {
    const on = threadsOn(canvas, nodeId);
    if (on.length === 0) return;
    setCard(nodeId);
    fireNativeHaptic('selection');
    setPage(on.length === 1 ? { kind: 'thread', id: on[0]!.id } : { kind: 'list' });
  };
  const shown = page?.kind === 'list' && card ? threads.filter((thread) => threadsOn(canvas, card).some((on) => on.id === thread.id)) : threads;
  const sheet =
    page && onChange ? (
      // The sheet's scrim takes its presses, so a tap to close it is not a tap on the canvas under it.
      <div onPointerDown={stop} onClick={stop}>
        <CommentSheet
          page={page}
          threads={shown}
          people={{ colour: colours.of, me: commentHandle() }}
          quoteOf={(id) => {
            const thread = (canvas.comments ?? []).find((each) => each.id === id);
            return thread ? quoteOf(canvas, thread.node) : null;
          }}
          onClose={close}
          onOpen={(id) => setPage({ kind: 'thread', id })}
          onList={() => setPage({ kind: 'list' })}
          onAdd={(words) => {
            if (card && change(withThread(canvas, card, stampHere(), words), 'success')) close();
          }}
          onReply={(id, words) => void change(withReply(canvas, id, stampHere(), words), 'success')}
          onResolve={(id) => void change(resolvedThread(canvas, id, stampHere()), 'success')}
          onReopen={(id) => void change(reopenedThread(canvas, id), 'selection')}
          onDelete={(id) => {
            if (change(withoutThread(canvas, id), 'warning')) close();
          }}
        />
      </div>
    ) : null;
  return { start, open, sheet };
}

const stop = (event: ReactPointerEvent | { stopPropagation: () => void }) => event.stopPropagation();
