import { useEffect, useState } from 'react';
import type { EditorView } from '@codemirror/view';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { adoptImagePath, pickImage } from '../core/images.ts';
import { insertImageAt, releaseImageSpot, reserveImageSpot } from './images.ts';

/**
 * Pictures put into the open note, and the line under the header that says when one did not come in.
 *
 * A picture goes in at the caret on its own line: from the phone's picker (the press-and-hold menu's Add image), or
 * one the activity copied out of the clipboard (the menu's Paste). Pasting with the keyboard is the editor's own
 * (editor/images.ts), and it reports its failures to the same line. So do plugins (plugins/types.ts
 * `NoteEditing.say`): the line is the note's one place for a sentence about the note, said once and then out of the
 * way.
 */

/** How long a sentence stays on the note before it gets out of the way. */
const SAID_MS = 6000;

export interface NotePictures {
  /** The sentence on the note now, or null. */
  problem: string | null;
  /** Puts a sentence on the note, or null to take it off. */
  say: (message: string | null) => void;
  /** Opens the phone's picker and puts what is chosen at the caret. */
  addPhoto: () => Promise<void>;
  /** Puts in the picture the activity copied out of the clipboard, by its path. */
  pasteImage: (path: string) => Promise<void>;
}

export function useNotePictures(view: EditorView | null): NotePictures {
  const [problem, setProblem] = useState<string | null>(null);
  useEffect(() => {
    if (!problem) return;
    const id = window.setTimeout(() => setProblem(null), SAID_MS);
    return () => window.clearTimeout(id);
  }, [problem]);

  const placeImage = async (fetch: () => Promise<string | null>) => {
    setProblem(null);
    // The place is taken now: the picker leaves the app, and the caret is not
    // guaranteed to be where it was when it comes back.
    const spot = view ? reserveImageSpot(view) : null;
    try {
      const name = await fetch();
      if (name && view && spot !== null) {
        insertImageAt(view, spot, name);
        fireNativeHaptic('light');
      }
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      if (view && spot !== null) releaseImageSpot(view, spot);
    }
  };

  return {
    problem,
    say: setProblem,
    addPhoto: () => placeImage(pickImage),
    pasteImage: (path) => placeImage(() => adoptImagePath(path)),
  };
}
