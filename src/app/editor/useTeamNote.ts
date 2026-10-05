import { useEffect, useSyncExternalStore } from 'react';
import type { EditorView } from '@codemirror/view';
import { deviceDocs } from '../core/team/docs.ts';
import { isOrgWorkspace, onWorkspaces, workspaceOf } from '../core/workspaces.ts';
import { bindLive, unbindLive } from './liveBinding.ts';

/**
 * A team note's editor bound to its document (docs/SHARED.md, S5; core/team/doc.ts): every keystroke a change of
 * the CRDT, which the next pass posts to the team, and every update the pass applies put into the editor by the
 * binding. Bound while the note is filed in an organization's workspace, and let go when it is taken out.
 *
 * What the editor holds when the binding is made is reconciled into the document first, so words typed before it
 * was ready are a change and not a loss. Undo becomes the document's (editor/undoSlot.ts), as it is live.
 */
export function useTeamNote(view: EditorView | null, noteId: string): void {
  const team = useSyncExternalStore(onWorkspaces, () => isTeamNote(noteId), () => isTeamNote(noteId));
  useEffect(() => {
    if (!view || !team) return undefined;
    let gone = false;
    let bound = false;
    void import('../core/team/doc.ts')
      .then(async ({ teamDoc }) => {
        const doc = await teamDoc(noteId, deviceDocs(), view.state.doc.toString());
        if (gone || !doc) return;
        doc.reconcile(view.state.doc.toString());
        bindLive(view, doc);
        bound = true;
      })
      .catch(() => {
        // Without a document the note is still itself, synced by the pass from its words.
      });
    return () => {
      gone = true;
      if (!bound) return;
      try {
        unbindLive(view);
      } catch {
        // The editor went first.
      }
    };
  }, [view, noteId, team]);
}

/** Whether a note is a team's: filed in an organization's workspace. */
export function isTeamNote(noteId: string): boolean {
  const space = workspaceOf(noteId);
  return space !== null && isOrgWorkspace(space);
}
