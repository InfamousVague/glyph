import { useEffect, useState, useSyncExternalStore } from 'react';
import { EditorView } from '@codemirror/view';
import { isSpot, type Jump, type Spot, type Whereabouts } from '../core/live/presence.ts';
import type { TeamRoom } from '../core/live/team.ts';
import { noteTitle } from '../core/noteTitle.ts';
import type { TeamDoc } from '../core/team/doc.ts';
import { deviceDocs } from '../core/team/docs.ts';
import { isOrgWorkspace, onWorkspaces, orgIdOf, workspaceOf } from '../core/workspaces.ts';
import { isCanvasBody } from '../canvas/jsonCanvas.ts';
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
 * room is told this device is editing this note, with the caret as it moves - or, on a canvas (S9), the pointer -
 * for the dashboard's "editing Roadmap" and its Jump to cursor. Opened at a `jump` - a member's caret - the
 * selection is put there once the document is bound; a spot on a canvas is the canvas view's to go to. Nothing of
 * this needs the live-typing trial switch: a team's notes are live by being the team's.
 *
 * Answers the binding - the document, the room, the organization - once it is made, for a canvas to draw and edit
 * through (canvas/CanvasView.tsx `team`); null for a note that is not a team's, or not bound yet.
 */

/** A team note as this screen holds it: its document, its room (null without the key), and whose it is. */
export interface TeamBinding {
  doc: TeamDoc;
  room: TeamRoom | null;
  orgId: string;
}

/** How often at most the organization's room hears where the caret or the pointer is: its exact place matters only to a jump. */
const CARET_EVERY_MS = 400;

export function useTeamNote(view: EditorView | null, noteId: string, jump?: Jump): TeamBinding | null {
  const team = useSyncExternalStore(onWorkspaces, () => isTeamNote(noteId), () => isTeamNote(noteId));
  const [binding, setBinding] = useState<TeamBinding | null>(null);
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
        // A canvas is its structure (S9; core/team/canvas.ts), edited through the view: its editor, which shows its
        // JSON behind the view switch, stays the note's own and reaches the team by the pass, not by the binding.
        if (!isCanvasBody(view.state.doc.toString())) {
          bindLive(view, { text: held.text, awareness: room?.awareness ?? null });
          bound = true;
        }
        if (!orgId) return;
        setBinding({ doc: held, room, orgId });
        leave = tellWhere(presence.announce, orgId, noteId, view, room);
      })
      .catch(() => {
        // Without a document the note is still itself, synced by the pass from its words.
      });
    return () => {
      gone = true;
      leave?.();
      setBinding(null);
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
    if (!view || !binding || !jump || isSpot(jump)) return undefined;
    let gone = false;
    void import('../core/live/team.ts').then(({ caretIndexes }) => {
      if (gone) return;
      const place = caretIndexes(binding.doc, jump);
      if (!place) return;
      const limit = view.state.doc.length;
      const anchor = Math.min(place.anchor, limit);
      view.dispatch({ selection: { anchor, head: Math.min(place.head, limit) }, effects: EditorView.scrollIntoView(anchor, { y: 'center' }) });
      view.focus();
    });
    return () => {
      gone = true;
    };
  }, [view, binding, jump]);
  return binding;
}

/**
 * Where this device is, for the organization's dashboard (core/live/presence.ts): this note, by its title as it is
 * now, and the caret as the note's room sees it move - or the pointer, on a canvas - at most every CARET_EVERY_MS,
 * since the exact place matters only to a jump. The last place stands while the editor is blurred, or the pointer
 * off the canvas. Answers the way to stop, which says nowhere.
 */
function tellWhere(announce: (orgId: string, at: Whereabouts | null) => void, orgId: string, noteId: string, view: EditorView, room: TeamRoom | null): () => void {
  let cursor: Whereabouts['cursor'] = null;
  let pointer: Spot | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const tell = () => {
    const words = view.state.doc.toString();
    announce(orgId, { note: noteId, title: noteTitle(words), kind: isCanvasBody(words) ? 'canvas' : 'note', cursor, pointer });
  };
  tell();
  const soon = () => {
    if (timer) return;
    timer = setTimeout(() => {
      timer = null;
      tell();
    }, CARET_EVERY_MS);
  };
  const onChange = (change: { updated: number[] }, origin: unknown) => {
    if (origin !== 'local' || !room || !change.updated.includes(room.awareness.clientID)) return;
    const state = room.awareness.getLocalState() ?? {};
    const caret = state.cursor as Whereabouts['cursor'] | undefined;
    const spot = state.pointer as Spot | null | undefined;
    if (caret) cursor = { anchor: caret.anchor, head: caret.head };
    if (spot) pointer = { x: spot.x, y: spot.y };
    if (caret || spot) soon();
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
