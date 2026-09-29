import { useEffect, useRef } from 'react';
import type { EditorView } from '@codemirror/view';
import { fireFelt } from '../../core/haptics.ts';
import { aiEdit } from '../../editor/aiChanges.ts';
import { blanksField, trackBlanks } from '../../editor/blanks.ts';
import { wisp } from '../../editor/wispArrivals.ts';
import { signatureChange, type TextChange } from './edits.ts';
import { openForFills, type FillHost } from './queue.ts';

/**
 * A fill's answers into the open note (docs/DESIGN.md §145, 6.3): the note screen's editor is the one writer of an open
 * note, so the fills' queue hands it each generation's answers and it lands them in one transaction, with the AI's
 * signature in the same change on a press's first landing, told from the person's own edits (`aiEdit`), arriving out
 * of smoke as rewritten words do when the wisp is on, and a light tick under the thumb.
 *
 * The queue finds a blank by the range this editor has tracked since the press (editor/blanks.ts `blanksField`), and
 * by its question and order where the note was closed in between. The run itself is never landed by the lines-as-they-
 * finish lander (ai/useLanding.ts skips a fill), since a fill's answers go where its blanks are, not over the note.
 */
export function useFillLanding(noteId: string, view: EditorView | null, options: { wisp: boolean; owner: string | undefined }): void {
  const optionsRef = useRef(options);
  optionsRef.current = options;
  useEffect(() => {
    if (!view) return undefined;
    const host: FillHost = {
      text: () => view.state.doc.toString(),
      rangeOf: (key) => view.state.field(blanksField, false)?.get(key) ?? null,
      track: (targets) => view.dispatch({ effects: trackBlanks.of(targets) }),
      land: (changes: readonly TextChange[], sign: TextChange | null) => {
        if (!view.dom.isConnected) return null;
        // The signature is worked out afresh on the note as it reads now, with the owner the screen knows.
        const signature = sign ? signatureChange(view.state.doc.toString(), optionsRef.current.owner) : null;
        const all = [...changes, ...(signature ? [signature] : [])].sort((a, b) => a.from - b.from);
        view.dispatch({
          changes: all,
          annotations: [aiEdit.of('land'), ...(optionsRef.current.wisp ? [wisp.of({ kind: 'rewrite' })] : [])],
          userEvent: 'ai.land',
        });
        fireFelt('light');
        return view.state.doc.toString();
      },
    };
    openForFills(noteId, host);
    return () => openForFills(noteId, null);
  }, [noteId, view]);
}
