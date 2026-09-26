import { useEffect, useRef } from 'react';
import type { EditorView } from '@codemirror/view';
import type { ToastOptions } from '@glacier/react';
import { landingLine, takeOut, type CaptureLanding } from '../capture/landing.ts';
import { dropRefine, holdNote } from '../capture/refine.ts';
import { undoCommandMutation } from '../core/store.ts';

/**
 * A note opened by the recording that just wrote into it (capture/CaptureScreen.tsx `finish`): "Added to House TODOs",
 * with an Undo, for ten seconds.
 *
 * The Undo is an edit in this note's editor, which takes out exactly the pieces of text the recording put in, found
 * where they were written. The note's own saving (editor/useNoteSaving.ts) writes it like typing, and the editor's
 * undo can bring it back; nothing else writes the open note, so the next keystroke's save cannot conflict. A piece
 * edited since is left alone, and the toast says so. Writes the recording made to other notes are reversed through
 * `undo_command`, which checks each is still as it left it. The tape is never touched: the words go as if deleted by
 * hand, and the recording's queued better words are dropped (capture/refine.ts `dropRefine`) so they never write the
 * undone words back.
 *
 * And while any note is open, the better words wait to write it (`holdNote`): the editor is its one writer.
 */
export function useLanding(
  noteId: string,
  landing: (CaptureLanding & { key: number }) | undefined,
  view: EditorView | null,
  { toast, dismiss }: { toast: (options: ToastOptions) => void; dismiss: () => void },
): void {
  useEffect(() => {
    holdNote(noteId, true);
    return () => holdNote(noteId, false);
  }, [noteId]);

  const editor = useRef(view);
  editor.current = view;

  useEffect(() => {
    if (!landing || landing.noteId !== noteId) return undefined;
    if (!landing.blocks.length && !landing.others.length) return undefined;
    const undo = async () => {
      let missing = 0;
      let removed = false;
      const open = editor.current;
      if (landing.blocks.length) {
        if (open) {
          const out = takeOut(open.state.doc.toString(), landing.blocks);
          missing = out.missing;
          if (out.changes.length) {
            open.dispatch({ changes: out.changes.map((change) => ({ ...change, insert: '' })), userEvent: 'delete' });
            removed = true;
          }
        } else {
          missing = landing.blocks.length;
        }
      }
      for (const mutationId of landing.others) {
        const undone = await undoCommandMutation(mutationId).catch(() => null);
        if (undone?.status !== 'undone' && undone?.status !== 'already-undone') missing += 1;
      }
      // Only for words taken out of this note: the better words of what stays in it still come.
      if (removed && landing.fromMs !== undefined) dropRefine(noteId, landing.fromMs);
      // After the pressed toast has gone, which pressing its action does just after this returns.
      await Promise.resolve();
      if (missing) toast({ message: `${landing.title} has changed since, so it was left as it is.`, duration: 5000 });
    };
    toast({ message: landingLine(landing), duration: 10_000, action: { label: 'Undo', onPress: () => void undo() } });
    // Leaving the note takes its toast with it: an Undo for words no longer on screen would undo them unseen.
    return () => dismiss();
    // One toast for each recording's landing, told apart by its key.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [landing?.key, noteId]);
}
