import { useEffect, useState, useSyncExternalStore } from 'react';
import { EditorView } from '@codemirror/view';
import type { Caret } from '../core/live/presence.ts';
import type { TeamRoom } from '../core/live/team.ts';
import { noteTitle } from '../core/noteTitle.ts';
import type { TeamDoc } from '../core/team/doc.ts';
import { deviceDocs } from '../core/team/docs.ts';
import { isOrgWorkspace, onWorkspaces, orgIdOf, workspaceOf } from '../core/workspaces.ts';
import { bindLive, unbindLive } from './liveBinding.ts';

/**
 * A team note's editor bound to its document (docs/SHARED.md, S5; core/team/doc.ts): every keystroke a change of
 * the CRDT, which the next pass posts to the team, and every update the pass applies put into the editor by the
 * binding. Bound while the note is filed in an organization's workspace, and let go when it is taken out.
 *
 * What the editor holds when the binding is made is reconciled into the document first, so words typed before it
 * was ready are a change and not a loss. Undo becomes the document's (editor/undoSlot.ts), as it is live.
 *
 * And live (S6; core/live/team.ts): the note's room is held while it is open, so a member's typing arrives as it is
 * made and their caret and selection are drawn in their colour with their handle on it; and the organization's own
 * room is told this device is editing this note, with the caret as it moves, for the dashboard's "editing Roadmap"
 * and its Jump to cursor. Opened at a `jump` - a member's caret - the selection is put there once the document is
 * bound. Nothing of this needs the live-typing trial switch: a team's notes are live by being the team's.
 */

/** How often at most the organization's room hears where the caret is: its exact place matters only to a jump. */
const CARET_EVERY_MS = 400;

export function useTeamNote(view: EditorView | null, noteId: string, jump?: Caret): void {
  const team = useSyncExternalStore(onWorkspaces, () => isTeamNote(noteId), () => isTeamNote(noteId));
  const [doc, setDoc] = useState<TeamDoc | null>(null);
  useEffect(() => {
    if (!view || !team) return undefined;
    let gone = false;
    let bound = false;
    let leave: (() => void) | null = null;
    void Promise.all([import('../core/team/doc.ts'), import('../core/live/team.ts'), import('../core/live/presence.ts')])
      .then(async ([{ teamDoc }, { openTeamRoom }, presence]) => {
        const held = await teamDoc(noteId, deviceDocs(), view.state.doc.toString());
        if (gone || !held) return;
        held.reconcile(view.state.doc.toString());
        const space = workspaceOf(noteId);
        const orgId = space ? orgIdOf(space.id) : null;
        const room = orgId ? openTeamRoom(orgId, noteId, held) : null;
        bindLive(view, { text: held.text, awareness: room?.awareness ?? null });
        bound = true;
        setDoc(held);
        if (!orgId) return;
        leave = tellWhere(presence.announce, orgId, noteId, view, room);
      })
      .catch(() => {
        // Without a document the note is still itself, synced by the pass from its words.
      });
    return () => {
      gone = true;
      leave?.();
      setDoc(null);
      if (!bound) return;
      try {
        unbindLive(view);
      } catch {
        // The editor went first.
      }
    };
  }, [view, noteId, team]);

  // Opened at a member's caret (shell/screen.ts `cursor`): the selection put there once the document is bound, and
  // the place scrolled to the middle. A caret the document cannot place any more - its words gone - is left alone.
  useEffect(() => {
    if (!view || !doc || !jump) return undefined;
    let gone = false;
    void import('../core/live/team.ts').then(({ caretIndexes }) => {
      if (gone) return;
      const place = caretIndexes(doc, jump);
      if (!place) return;
      const limit = view.state.doc.length;
      const anchor = Math.min(place.anchor, limit);
      view.dispatch({ selection: { anchor, head: Math.min(place.head, limit) }, effects: EditorView.scrollIntoView(anchor, { y: 'center' }) });
      view.focus();
    });
    return () => {
      gone = true;
    };
  }, [view, doc, jump]);
}

/**
 * Where this device is, for the organization's dashboard (core/live/presence.ts): this note, by its title as it is
 * now, and the caret as the note's room sees it move - at most every CARET_EVERY_MS, since the exact place matters
 * only to a jump. The last place stands while the editor is blurred. Answers the way to stop, which says nowhere.
 */
function tellWhere(announce: (orgId: string, at: Parameters<typeof import('../core/live/presence.ts')['announce']>[1]) => void, orgId: string, noteId: string, view: EditorView, room: TeamRoom | null): () => void {
  let cursor: Caret | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const tell = () => announce(orgId, { note: noteId, title: noteTitle(view.state.doc.toString()), kind: 'note', cursor, pointer: null });
  tell();
  const onChange = (change: { updated: number[] }, origin: unknown) => {
    if (origin !== 'local' || !room || !change.updated.includes(room.awareness.clientID)) return;
    const place = room.awareness.getLocalState()?.cursor as Caret | null | undefined;
    if (!place) return;
    cursor = { anchor: place.anchor, head: place.head };
    if (timer) return;
    timer = setTimeout(() => {
      timer = null;
      tell();
    }, CARET_EVERY_MS);
  };
  room?.awareness.on('change', onChange);
  return () => {
    if (timer) clearTimeout(timer);
    room?.awareness.off('change', onChange);
    room?.close();
    announce(orgId, null);
  };
}

/** Whether a note is a team's: filed in an organization's workspace. */
export function isTeamNote(noteId: string): boolean {
  const space = workspaceOf(noteId);
  return space !== null && isOrgWorkspace(space);
}
