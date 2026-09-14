import { useCallback, useEffect, useRef, useState } from 'react';
import { useToast } from '@glacier/react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { deleteNote, noteTitle, setNoteArchived, setNoteStarred, type Note } from '../core/store.ts';

/**
 * Star, archive and delete, each undoable - what a swipe on a row does.
 *
 * DELETE IS DEFERRED, not done and then undone. Undoing a real delete would
 * mean saving the note again, which gives it a new `createdAt` and loses its
 * pin; so a deleted note is hidden at once and removed from the store only
 * when its Undo runs out. The removal is also forced the moment anything could
 * outlive the toast: a second delete, the app going to the background (Android
 * freezes a cached app's timers, and a note that was "deleted" would come back
 * next launch), a capture starting over the list, and this hook unmounting.
 *
 * Archive and pin are real at once - they are flags, not edits, and undoing
 * one is just setting it back.
 */

const UNDO_MS = 5000;

const capitalise = (text: string): string => text.charAt(0).toUpperCase() + text.slice(1);

function label(note: Note): string {
  const title = noteTitle(note.body);
  // A long title is not cut short with an ellipsis: it is simply not named.
  return title && title.length <= 28 ? `“${title}”` : 'the note';
}

export interface NoteActions {
  /** Notes deleted but still undoable: hidden from every list meanwhile. */
  hidden: ReadonlySet<string>;
  /** Pin or unpin: a pinned note sits at the top of the list (stored as `starred`). */
  pin: (note: Note) => void;
  archive: (note: Note, archived: boolean) => void;
  remove: (note: Note) => void;
  /** Make any pending delete final now. */
  flushDeletes: () => void;
}

export function useNoteActions(refresh: () => Promise<void>): NoteActions {
  const { toast } = useToast();
  const [hidden, setHidden] = useState<ReadonlySet<string>>(() => new Set());
  const pending = useRef<{ id: string; timer: number } | null>(null);

  const unhide = useCallback((id: string) => {
    setHidden((prev) => {
      if (!prev.has(id)) return prev;
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
  }, []);

  const commit = useCallback(async () => {
    const due = pending.current;
    if (!due) return;
    pending.current = null;
    window.clearTimeout(due.timer);
    try {
      await deleteNote(due.id);
    } catch (error) {
      console.warn('[glyph] delete failed:', error);
    } finally {
      await refresh();
      unhide(due.id);
    }
  }, [refresh, unhide]);

  useEffect(() => {
    const onHide = () => {
      if (document.visibilityState === 'hidden') void commit();
    };
    const onPageHide = () => void commit();
    document.addEventListener('visibilitychange', onHide);
    window.addEventListener('pagehide', onPageHide);
    return () => {
      document.removeEventListener('visibilitychange', onHide);
      window.removeEventListener('pagehide', onPageHide);
      void commit();
    };
  }, [commit]);

  const remove = useCallback(
    (note: Note) => {
      // One undo at a time: the toast is latest-wins, so an earlier delete
      // whose Undo is about to disappear from the screen becomes final now.
      void commit();
      setHidden((prev) => new Set(prev).add(note.id));
      pending.current = { id: note.id, timer: window.setTimeout(() => void commit(), UNDO_MS) };
      fireNativeHaptic('warning');
      toast({
        message: `Deleted ${label(note)}.`,
        duration: UNDO_MS,
        action: {
          label: 'Undo',
          onPress: () => {
            if (pending.current?.id !== note.id) return;
            window.clearTimeout(pending.current.timer);
            pending.current = null;
            unhide(note.id);
            fireNativeHaptic('success');
          },
        },
      });
    },
    [commit, toast, unhide],
  );

  const archive = useCallback(
    (note: Note, archived: boolean) => {
      void (async () => {
        await setNoteArchived(note.id, archived);
        await refresh();
        fireNativeHaptic('success');
        toast({
          message: archived ? `Archived ${label(note)}.` : `${capitalise(label(note))} is back in your notes.`,
          duration: UNDO_MS,
          action: {
            label: 'Undo',
            onPress: () => void setNoteArchived(note.id, !archived).then(refresh),
          },
        });
      })();
    },
    [refresh, toast],
  );

  const pin = useCallback(
    (note: Note) => {
      void (async () => {
        await setNoteStarred(note.id, !note.starred);
        await refresh();
        fireNativeHaptic('success');
      })();
    },
    [refresh],
  );

  return { hidden, pin, archive, remove, flushDeletes: () => void commit() };
}
