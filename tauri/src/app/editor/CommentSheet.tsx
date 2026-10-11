import { ArrowLeft } from '../art/Icons.tsx';
import { SheetNote, SheetTitle } from '../plugins/kit.tsx';
import { CommentList, CommentThread, NewComment, type CardPeople, type CardThread } from './CommentCard.tsx';
import { Sheet } from './Sheet.tsx';
import sheet from './NoteSettings.module.css';

/**
 * The note's comments in the app's sheet (editor/Sheet.tsx: a centred card on a desktop, a drawer from the bottom on
 * a phone): one thread's card, a new comment's field, or every thread in the note as a list, each row opening its
 * card. What each press does is the note screen's (editor/useNoteComments.ts), which writes it into the editor.
 */

/** What the sheet is showing. */
export type CommentPage = { kind: 'thread'; id: string } | { kind: 'new'; quote: string | null } | { kind: 'list' };

interface CommentSheetProps {
  page: CommentPage;
  threads: readonly CardThread[];
  people: CardPeople;
  /** The words a thread is about, as the note has them now; null for one after a line's words. */
  quoteOf: (id: string) => string | null;
  onClose: () => void;
  onOpen: (id: string) => void;
  /** Back to the list from a thread, where there is more than one. */
  onList: () => void;
  onAdd: (words: string) => void;
  onReply: (id: string, words: string) => void;
  onResolve: (id: string) => void;
  onReopen: (id: string) => void;
  onDelete: (id: string) => void;
}

export function CommentSheet({ page, threads, people, quoteOf, onClose, onOpen, onList, onAdd, onReply, onResolve, onReopen, onDelete }: CommentSheetProps) {
  if (page.kind === 'new') {
    return (
      <Sheet label="New comment" onClose={onClose}>
        <SheetTitle>New comment</SheetTitle>
        <NewComment quote={page.quote} onSave={onAdd} />
      </Sheet>
    );
  }
  if (page.kind === 'list') {
    return (
      <Sheet label="Comments" onClose={onClose}>
        <SheetTitle>Comments</SheetTitle>
        {threads.length ? <CommentList threads={threads} people={people} onOpen={onOpen} /> : <SheetNote>No comments yet. Select some words, or put the caret on a line, and press Comment.</SheetNote>}
      </Sheet>
    );
  }
  const thread = threads.find((each) => each.id === page.id);
  return (
    <Sheet label="Comment thread" onClose={onClose} onBack={threads.length > 1 ? onList : onClose}>
      {threads.length > 1 ? (
        <button type="button" className={sheet.back} onClick={onList}>
          <ArrowLeft /> All comments
        </button>
      ) : null}
      {thread ? (
        <CommentThread
          thread={thread}
          people={people}
          quote={quoteOf(thread.id)}
          onReply={(words) => onReply(thread.id, words)}
          onResolve={() => onResolve(thread.id)}
          onReopen={() => onReopen(thread.id)}
          onDelete={() => onDelete(thread.id)}
        />
      ) : (
        <SheetNote>This thread is not in the note any more.</SheetNote>
      )}
    </Sheet>
  );
}
