import { useEffect, useMemo, useRef, useState } from 'react';
import { convertFileSrc } from '@tauri-apps/api/core';
import type { ToastOptions } from '@glacier/react';
import type { Segment } from '../capture/markdown.ts';
import { hasClips, setTapeId, tapeId } from '../core/clips.ts';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { getNote, setNoteRecording, type Note } from '../core/store.ts';
import { useTape, type Tape } from '../tapes/useTape.ts';

/**
 * A spoken note's recording, on the note screen: the tape at the top plays it (tapes/NoteTape.tsx), and the tape's
 * Remove takes it off with an Undo.
 *
 * The removal is held here rather than waited on from the store, so the tape goes at once and Undo brings it back
 * without a trip there. Its length and phrases are forgotten; the audio file stays until the note is spoken into again
 * or deleted, which is what lets Undo put it back - so a new take (the screen's `forgetRemoved`, before the recorder
 * opens) makes that Undo untrue, and it is dropped. The tape's id goes with the recording, so the note's voice memos
 * read as quiet marks until it is back (core/clips.ts).
 */

export interface NoteTape {
  tape: Tape;
  /** Where the recording plays from in the app, or null: no recording, or a browser, which has no file to play. */
  recording: string | null;
  /** The tape's Remove. */
  removeRecording: () => void;
  /** A new take is on its way: the last removal can no longer be undone. */
  forgetRemoved: () => void;
}

/** The recording of `note`; `body` is the live document, for whether it has voice memos to fall quiet. */
export function useNoteTape(note: Note, body: { readonly current: string }, toast: (options: ToastOptions) => void): NoteTape {
  const [kept, setKept] = useState<{
    ms: number | null;
    segments: Segment[] | null;
  } | null>(null);
  const spoken = useMemo(() => (kept ? { ...note, recordingMs: kept.ms, segments: kept.segments } : note), [note, kept]);
  const tape = useTape(spoken);
  /** The recording just removed, while its Undo still means something: cleared when the note is spoken into or left. */
  const removed = useRef<{ ms: number; segments: Segment[] } | null>(null);
  useEffect(
    () => () => {
      removed.current = null;
    },
    [],
  );

  const removeRecording = () => {
    const memos = hasClips(body.current);
    void (async () => {
      tape.audio.ref.current?.pause();
      const full = await getNote(note.id).catch(() => null);
      const ms = tape.length;
      const segments = full?.segments ?? tape.segments ?? [];
      const heldTape = tapeId(note.id);
      removed.current = { ms, segments };
      setKept({ ms: null, segments: null });
      fireNativeHaptic('warning');
      setTapeId(note.id, null);
      try {
        await setNoteRecording(note.id, null, []);
      } catch (failure) {
        removed.current = null;
        setKept({ ms, segments });
        setTapeId(note.id, heldTape);
        toast({
          message: `The recording couldn’t be removed: ${failureText(failure)}`,
        });
        return;
      }
      toast({
        message: memos ? 'Recording removed. Its voice memos are quiet until you undo.' : 'Recording removed.',
        duration: 5000,
        action: {
          label: 'Undo',
          onPress: () => {
            const back = removed.current;
            if (!back) return;
            removed.current = null;
            setKept({ ms: back.ms, segments: back.segments });
            setTapeId(note.id, heldTape);
            void setNoteRecording(note.id, back.ms, back.segments);
          },
        },
      });
    })();
  };

  const forgetRemoved = () => {
    removed.current = null;
  };

  // Asked only where there is a file to play: the bridge that names it is the app's, and a browser has none.
  const recording = !tape.web && tape.length > 0 ? convertFileSrc(`${note.id}.wav`, 'rec') : null;

  return { tape, recording, removeRecording, forgetRemoved };
}
