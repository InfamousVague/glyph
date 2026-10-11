import { useCallback, useEffect, useRef, useState } from 'react';
import type { Spot } from '../core/live/presence.ts';
import type { TeamRoom } from '../core/live/team.ts';
import type { TeamCanvas } from '../core/team/canvas.ts';
import type { TeamBinding } from '../editor/useTeamNote.ts';
import type { Canvas } from './jsonCanvas.ts';

/**
 * A team's canvas in the view (docs/SHARED.md, S9): drawn from and edited through its structure in the team's
 * document (core/team/canvas.ts) when the note is a team's, so two members' edits merge field by field; the note's
 * own canvas otherwise, handed back whole as ever. Every change still goes to the note (`onChange`), which writes
 * the JSON and saves it. Loaded on demand with the adapter, so a canvas of one's own carries none of it.
 */
export function useTeamCanvas(team: TeamBinding | null | undefined, canvas: Canvas, onChange: ((canvas: Canvas) => void) | undefined): { canvas: Canvas; onChange: ((canvas: Canvas) => void) | undefined } {
  const [adapter, setAdapter] = useState<TeamCanvas | null>(null);
  const [shown, setShown] = useState<Canvas | null>(null);
  useEffect(() => {
    if (!team) {
      setAdapter(null);
      setShown(null);
      return undefined;
    }
    let gone = false;
    void import('../core/team/canvas.ts').then(async ({ hasTeamCanvas, teamCanvas }) => {
      // No structure yet: another member's may be on its way through the room, so it is given its moment to
      // arrive before this device seeds one from the words.
      if (!hasTeamCanvas(team.doc.doc) && team.room) await team.room.caughtUp();
      if (gone) return;
      const made = teamCanvas(team.doc);
      setAdapter(made);
      setShown(made?.canvas() ?? null);
    });
    return () => {
      gone = true;
    };
  }, [team]);
  useEffect(() => adapter?.onChange(setShown), [adapter]);
  const change = useCallback(
    (next: Canvas) => {
      adapter?.apply(next);
      onChange?.(next);
    },
    [adapter, onChange],
  );
  if (!adapter || !shown) return { canvas, onChange };
  return { canvas: shown, onChange: onChange ? change : undefined };
}

/** Another member on this canvas, as the note's room has them: their colour, their pointer, and the card they have open. */
export interface Other {
  client: number;
  name: string;
  hue: string | null;
  color: string;
  pointer: Spot | null;
  card: string | null;
}

const NOBODY: readonly Other[] = [];

/** The other members on this canvas, read from the room's awareness as it changes; nobody without a room. */
export function useOthers(room: TeamRoom | null | undefined): readonly Other[] {
  const [others, setOthers] = useState<readonly Other[]>(NOBODY);
  useEffect(() => {
    if (!room) {
      setOthers(NOBODY);
      return undefined;
    }
    const read = () => {
      const list: Other[] = [];
      for (const [client, state] of room.awareness.getStates()) {
        if (client === room.awareness.clientID) continue;
        const user = state.user as { name?: string; hue?: string | null; color?: string } | undefined;
        if (!user?.name) continue;
        const pointer = state.pointer as Spot | null | undefined;
        list.push({ client, name: user.name, hue: user.hue ?? null, color: user.color ?? 'var(--app-ink)', pointer: pointer ? { x: pointer.x, y: pointer.y } : null, card: typeof state.card === 'string' ? state.card : null });
      }
      setOthers(list);
    };
    read();
    room.awareness.on('change', read);
    return () => room.awareness.off('change', read);
  }, [room]);
  return others;
}

/** How often at most the room hears where this pointer is. */
const POINTER_EVERY_MS = 80;

/**
 * This device's pointer and open card said in the room for the others: the pointer at most every POINTER_EVERY_MS,
 * the card as it opens and closes. Answers how to say where the pointer is, in the canvas's pixels or off it.
 */
export function useSaying(room: TeamRoom | null | undefined, card: string | null): (at: Spot | null) => void {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latest = useRef<Spot | null>(null);
  useEffect(() => {
    room?.awareness.setLocalStateField('card', card);
  }, [room, card]);
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );
  return useCallback(
    (at: Spot | null) => {
      if (!room) return;
      latest.current = at;
      if (at === null) {
        if (timer.current) clearTimeout(timer.current);
        timer.current = null;
        room.awareness.setLocalStateField('pointer', null);
        return;
      }
      if (timer.current) return;
      timer.current = setTimeout(() => {
        timer.current = null;
        const spot = latest.current;
        room.awareness.setLocalStateField('pointer', spot ? { x: Math.round(spot.x), y: Math.round(spot.y) } : null);
      }, POINTER_EVERY_MS);
    },
    [room],
  );
}
