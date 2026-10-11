import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { EditorView } from '@codemirror/view';
import { takeCommentAsk, useCommentAsk } from '../core/comments/ask.ts';
import { commentHandle, stampHere } from '../core/comments/author.ts';
import { useCommentColours } from '../core/comments/colours.ts';
import { addReply, addThread, countWords, deleteThread, readComments, reopenThread, resolveThread, type Edit, type Target } from '../core/comments/format.ts';
import { frontMatterEnd } from '../core/frontMatter.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { CommentSheet, type CommentPage } from './CommentSheet.tsx';
import { quoteOf, refreshComments, type CommentHooks } from './comments.ts';

/**
 * The note's comments on its screen (docs/SHARED.md, S8): what the editor's drawing opens (editor/comments.ts), what
 * every way in starts - Comment on the press-and-hold band, in More and in the bar, "Add a comment" on a note's menu
 * in a list (Matt: "add them to the context menu for a note and the popover toolbar so we can quickly click to add
 * comments") - and the sheet the card is drawn in.
 *
 * Every change is a few edits from core/comments/format.ts put through the editor as one dispatch, as the More
 * sheet's Look is (editor/NoteScreen.tsx `chooseLook`): one undo step, saved the way typing is, and in a team note a
 * change the CRDT merges with everyone else's rather than the note written again.
 */

export interface NoteComments {
  /** What the editor is handed (Editor.tsx `comments`): one object for the screen's life, its answers read live. */
  hooks: CommentHooks;
  /** Starts a comment on the selection, or on the caret's line; `range` is a selection the caller holds. */
  start: (range?: { from: number; to: number }) => void;
  /** Opens the list of threads. */
  openList: () => void;
  /** "3 comments, 1 open", read now; null for none. */
  summary: () => string | null;
  /** The sheet, while one is open. */
  sheet: ReactNode;
}

/** The line a note is called by, counting from 1: its first line of words after its front matter. */
function titleLine(doc: string): number {
  const lines = doc.split('\n');
  const from = frontMatterEnd(lines);
  for (let i = from; i < lines.length; i += 1) if (lines[i]!.trim()) return i + 1;
  return Math.min(from + 1, lines.length);
}

export function useNoteComments(noteId: string, view: EditorView | null, say: (message: string) => void): NoteComments {
  const colours = useCommentColours(noteId);
  const [page, setPage] = useState<CommentPage | null>(null);
  /** Where the comment being written goes: held from the press, so the caret moving under the sheet does not move it. */
  const target = useRef<Target | null>(null);
  // Drawn again when the note changes under an open card: a reply from another member arriving live.
  const [, setTick] = useState(0);
  const latest = useRef({ page, colours, view });
  latest.current = { page, colours, view };

  const hooks = useMemo<CommentHooks>(
    () => ({
      open: (id) => {
        fireNativeHaptic('selection');
        setPage({ kind: 'thread', id });
      },
      colour: (handle) => latest.current.colours.of(handle),
      me: commentHandle,
      changed: () => {
        if (latest.current.page) setTick((n) => n + 1);
      },
    }),
    [],
  );

  // A colour read or changed: the rounds and the washes drawn again in it.
  useEffect(() => {
    if (view?.dom.isConnected) view.dispatch({ effects: refreshComments.of(null) });
  }, [view, colours.key]);

  const editable = (editor: EditorView | null): editor is EditorView => !!editor && editor.dom.isConnected && editor.state.facet(EditorView.editable) && !editor.state.readOnly;

  /** The edits into the editor as one change; false where there was nothing to write. */
  const write = (edits: Edit[] | null): boolean => {
    const editor = latest.current.view;
    if (!edits || !editable(editor)) return false;
    editor.dispatch({ changes: edits, userEvent: 'input.comment' });
    return true;
  };

  const begin = (wanted: Target) => {
    const editor = latest.current.view;
    if (!editable(editor)) {
      say('This note can’t take a comment while it is being written by something else.');
      return;
    }
    // Tried with words first, so a place a thread cannot go - inside the comments themselves - is said now, not after
    // the words are written.
    if (!addThread(editor.state.doc.toString(), wanted, stampHere(), 'x', 'cx')) {
      say('Comments go on the note’s words. Put the caret on a line, or select some words, and try again.');
      return;
    }
    target.current = wanted;
    const quote = 'from' in wanted ? editor.state.sliceDoc(wanted.from, wanted.to).trim() || null : null;
    fireNativeHaptic('selection');
    setPage({ kind: 'new', quote: quote && !quote.includes('\n') ? quote : quote ? `${quote.split('\n')[0]}…` : null });
  };

  const start = (range?: { from: number; to: number }) => {
    const editor = latest.current.view;
    if (!editor) return;
    const { from, to, head } = range ? { ...range, head: range.to } : editor.state.selection.main;
    begin(from !== to ? { from: Math.min(from, to), to: Math.max(from, to) } : { line: editor.state.doc.lineAt(head).number });
  };

  // "Add a comment" from a note's menu in a list: once the editor is here, a comment on the note's first line.
  const asked = useCommentAsk();
  useEffect(() => {
    if (!view || !asked || asked.noteId !== noteId || !takeCommentAsk(noteId)) return;
    begin({ line: titleLine(view.state.doc.toString()) });
    // `begin` reads the view through `latest`; the ask and the editor's arrival are what this follows.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [asked, view, noteId]);

  const close = () => setPage(null);
  const doc = () => latest.current.view?.state.doc.toString() ?? '';

  let sheet: ReactNode = null;
  if (page && view) {
    const comments = readComments(view.state.doc.toString());
    sheet = (
      <CommentSheet
        page={page}
        threads={comments.threads}
        people={{ colour: colours.of, me: commentHandle() }}
        quoteOf={(id) => quoteOf(view.state, comments, id)}
        onClose={close}
        onOpen={(id) => setPage({ kind: 'thread', id })}
        onList={() => setPage({ kind: 'list' })}
        onAdd={(words) => {
          const wanted = target.current;
          if (!wanted || !write(addThread(doc(), wanted, stampHere(), words))) return;
          target.current = null;
          fireNativeHaptic('success');
          close();
        }}
        onReply={(id, words) => {
          if (write(addReply(doc(), id, stampHere(), words))) fireNativeHaptic('success');
        }}
        onResolve={(id) => {
          if (write(resolveThread(doc(), id, stampHere()))) fireNativeHaptic('success');
        }}
        onReopen={(id) => {
          if (write(reopenThread(doc(), id))) fireNativeHaptic('selection');
        }}
        onDelete={(id) => {
          if (!write(deleteThread(doc(), id))) return;
          fireNativeHaptic('warning');
          close();
          say('Thread deleted. Undo puts it back.');
        }}
      />
    );
  }

  return {
    hooks,
    start,
    openList: () => setPage({ kind: 'list' }),
    summary: () => countWords(readComments(doc()).threads),
    sheet,
  };
}
