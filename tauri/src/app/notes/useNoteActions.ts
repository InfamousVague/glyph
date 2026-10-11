import { useCallback, useEffect, useRef, useState } from 'react';
import { useToast } from '@glacier/react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { deleteNote, noteTitle, setNoteArchived, setNoteStarred, type Note } from '../core/store.ts';
import { capitalise } from '../core/text.ts';
import { forgetNote } from '../core/workspaces.ts';
import { forgetResults } from '../format/results.ts';
import { forgetRuns } from '../ai/log.ts';
import { forgetMarks } from '../ai/marks.ts';
import { dropSummary, enqueueSummary, summaryNative } from '../ai/summaries.ts';
import { forgetSummary } from '../ai/summaryKeep.ts';
import { summaryLine } from '../ai/summaryText.ts';
import { transcriptOf } from '../capture/markdown.ts';
import { cancelWriteUpOnHost, writeUpOnHost } from '../core/host.ts';
import { preferences } from '../core/preferences.ts';
import { recordingJobState } from '../core/recordings.ts';
import { setPendingTag } from '../core/location.ts';
import { forget as forgetTrashed, restoreNote, trashNote } from '../core/trash.ts';

/**
 * Star, archive, delete and the trash, each undoable.
 *
 * Deleting a note puts it in the trash (core/trash.ts; Matt: "Send deleted notes to a trash folder where we can empty
 * it to perma delete notes or restore notes"), which is a flag and so undone by clearing it. Only the trash deletes
 * for good: one note from it (`destroy`), or all of it (`emptyTrash`).
 *
 * DELETING FOR GOOD IS DEFERRED, not done and then undone. Undoing a real delete would
 * mean saving the note again, which gives it a new `createdAt` and loses its
 * pin; so a deleted note is hidden at once and removed from the store only
 * when its Undo runs out. The removal is also forced the moment anything could
 * outlive the toast: a second delete, the app going to the background (Android
 * freezes a cached app's timers, and a note that was "deleted" would come back
 * next launch), a capture starting over the list, and this hook unmounting.
 *
 * Archive and pin are real at once - they are flags, not edits, and undoing
 * one is just setting it back.
 *
 * A meeting's write-up runs on the phone with the app closed (docs/DESIGN.md §127 section 4): a meeting put in the
 * trash has its write-up cancelled and its job dropped, whether or not a summary was asked for (Summaries off still
 * writes the transcript). One taken out again, by Restore or by the toast's Undo alike (`resumeWriteUp`), is asked of
 * the phone once more only where there is something to write up: a job the phone still holds (cancelled by the
 * trash, failed, waiting for a model, or done and not landed yet), or a note that never got its transcript. A
 * meeting whose result the page already took has its words in the note, and asking again would transcribe the hour
 * afresh and write over whatever the person corrected in it.
 */

const UNDO_MS = 5000;

/**
 * What the app kept about a note beside the note itself, let go once the note is deleted for good: its filing
 * (core/workspaces.ts), its gist (format/results.ts), the runs it has seen (ai/log.ts), the changes marked in it
 * (ai/marks.ts), the summary it was written (ai/summaryKeep.ts), the job to write one (ai/summaries.ts) and a tag
 * waiting to say where it was written (core/location.ts). Its place in the trash goes with it too, which the caller
 * does, once for all of them when the whole trash is emptied.
 */
function forgetKept(id: string): void {
  forgetNote(id);
  forgetResults(id);
  forgetRuns(id);
  forgetMarks(id);
  forgetSummary(id);
  dropSummary(id);
  setPendingTag(id, null);
}

/** A meeting out of the trash: its write-up asked of the phone again, where there is one to run (the header says when). */
export async function resumeWriteUp(note: Note): Promise<void> {
  if (!(note.id in preferences().meetings)) return;
  const jobs = await recordingJobState().catch(() => []);
  const held = jobs.some((job) => job.id === note.id);
  if (!held && transcriptOf(note.body) !== null) return;
  if (!writeUpOnHost(note.id, false)) return;
  if (preferences().summaries !== 'off' && summaryLine(note.body) === null) enqueueSummary(note.id, 'meeting', { native: true });
}

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
  /** Into the trash, with an Undo. */
  remove: (note: Note) => void;
  /** Out of the trash, back where it was. */
  restore: (note: Note) => void;
  /** Deleted for good, from the trash: hidden at once, and gone from the store when its Undo runs out. */
  destroy: (note: Note) => void;
  /** Every note given, deleted for good now: the trash emptied, once the person has said so. */
  emptyTrash: (notes: readonly Note[]) => Promise<void>;
  /** Make any pending delete final now. */
  flushDeletes: () => Promise<void>;
}

export function useNoteActions(refresh: () => Promise<void>): NoteActions {
  const { toast } = useToast();
  const [hidden, setHidden] = useState<ReadonlySet<string>>(() => new Set());
  const pending = useRef<{ id: string; timer: number } | null>(null);
  const committing = useRef<Promise<void>>(Promise.resolve());

  const unhide = useCallback((id: string) => {
    setHidden((prev) => {
      if (!prev.has(id)) return prev;
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
  }, []);

  const commit = useCallback((): Promise<void> => {
    const due = pending.current;
    if (!due) return committing.current;
    pending.current = null;
    window.clearTimeout(due.timer);
    const run = committing.current.then(async () => {
      try {
        await deleteNote(due.id);
        forgetKept(due.id);
        forgetTrashed([due.id]);
      } catch (error) {
        console.warn('[glyph] delete failed:', error);
      } finally {
        await refresh().catch((error: unknown) => console.warn('[glyph] refresh after delete failed:', error));
        unhide(due.id);
      }
    });
    committing.current = run.catch(() => undefined);
    return run;
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
      trashNote(note.id);
      // A meeting: its write-up on the phone stops (any meeting, since Summaries off makes no page job to ask by), and
      // a summary job waiting for it goes; restored, it is asked again.
      if (note.id in preferences().meetings) {
        cancelWriteUpOnHost(note.id);
        if (summaryNative(note.id)) dropSummary(note.id);
      }
      // A tag waiting for the note is not written into a note in the trash; Undo brings the note back, not the tag.
      setPendingTag(note.id, null);
      fireNativeHaptic('warning');
      toast({
        message: `Moved ${label(note)} to the Trash.`,
        duration: UNDO_MS,
        action: {
          label: 'Undo',
          onPress: () => {
            restoreNote(note.id);
            void resumeWriteUp(note);
            fireNativeHaptic('success');
          },
        },
      });
    },
    [toast],
  );

  const restore = useCallback(
    (note: Note) => {
      restoreNote(note.id);
      void resumeWriteUp(note);
      fireNativeHaptic('success');
      toast({ message: `${capitalise(label(note))} is back in your notes.`, duration: UNDO_MS });
    },
    [toast],
  );

  const emptyTrash = useCallback(
    async (notes: readonly Note[]) => {
      void commit();
      for (const note of notes) {
        try {
          await deleteNote(note.id);
          forgetKept(note.id);
        } catch (error) {
          console.warn('[glyph] delete failed:', error);
        }
      }
      forgetTrashed(notes.map((n) => n.id));
      await refresh();
      fireNativeHaptic('warning');
      toast({ message: notes.length === 1 ? 'Deleted 1 note for good.' : `Deleted ${notes.length} notes for good.` });
    },
    [commit, refresh, toast],
  );

  const destroy = useCallback(
    (note: Note) => {
      // One undo at a time: the toast is latest-wins, so an earlier delete
      // whose Undo is about to disappear from the screen becomes final now.
      void commit();
      setHidden((prev) => new Set(prev).add(note.id));
      pending.current = { id: note.id, timer: window.setTimeout(() => void commit(), UNDO_MS) };
      fireNativeHaptic('warning');
      toast({
        message: `Deleted ${label(note)} for good.`,
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

  return { hidden, pin, archive, remove, restore, destroy, emptyTrash, flushDeletes: commit };
}
