import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate } from 'y-protocols/awareness';
import * as Y from 'yjs';
import { show, unmount, waitUntil } from '../../test/render.tsx';
import { newAccountKey, settle } from '../core/sync/crypto.ts';
import { TeamRoom } from '../core/live/team.ts';
import { hasTeamCanvas } from '../core/team/canvas.ts';
import { teamDoc, forgetTeamDocs, type TeamDoc } from '../core/team/doc.ts';
import { memoryDocs } from '../core/team/docs.ts';
import { setPreferences } from '../core/preferences.ts';
import type { TeamBinding } from '../editor/useTeamNote.ts';
import { CanvasView } from './CanvasView.tsx';
import { canvasOf, type Canvas } from './jsonCanvas.ts';

vi.mock('mermaid', () => ({ default: { initialize: () => undefined, render: async (id: string) => ({ svg: `<svg id="${id}"></svg>` }) } }));

/**
 * A team's canvas in the view (docs/SHARED.md, S9; canvas/useTeamCanvas.ts): drawn from the structure in the team's
 * document and edited through it, a member's change arriving as a card moved on the screen; the other members'
 * pointers drawn in their colours with their handles, the card one of them is writing in ringed, and Jump to cursor
 * centring on a member's pointer.
 */

const BODY = `---
title: "Plan"
---
{
  "nodes": [
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin" },
    { "id": "site", "type": "link", "x": 0, "y": 160, "width": 260, "height": 100, "url": "https://attack.fm/glyph" }
  ],
  "edges": []
}
`;

let doc: TeamDoc;
let room: TeamRoom;
let sam: Awareness;
let changes: Canvas[];

beforeEach(async () => {
  setPreferences({ canvasSnap: false });
  forgetTeamDocs();
  doc = (await teamDoc('n1', memoryDocs(), BODY))!;
  const key = await settle(await newAccountKey());
  const transport = { join: () => undefined, leave: () => undefined, send: () => undefined, close: () => undefined };
  room = new TeamRoom('org-1', 'n1', { name: 'matt', hue: 'rose', color: 'red', colorLight: 'pink' }, { key, doc, hold: () => transport, release: () => undefined });
  // sam's device on the same canvas: what the relay would carry of them.
  sam = new Awareness(new Y.Doc());
  sam.setLocalStateField('user', { name: 'sam', hue: 'sea', color: 'blue', colorLight: 'lightblue' });
  changes = [];
});

afterEach(() => {
  unmount();
  room.close();
  sam.destroy();
});

const binding = (): TeamBinding => ({ doc, room, orgId: 'org-1' });
const heard = () => applyAwarenessUpdate(room.awareness, encodeAwarenessUpdate(sam, [sam.clientID]), 7);
const card = (shown: HTMLElement, id: string) => shown.querySelector<HTMLElement>(`[data-card="${id}"]`)!;

describe('a team’s canvas in the view', () => {
  it('draws the structure, writes a change into it and tells the note, and shows a member’s change as it arrives', async () => {
    const shown = show(<CanvasView canvas={canvasOf(BODY)!} dark={false} team={binding()} onChange={(next) => changes.push(next)} />);
    // Alone in the room: the structure is seeded from the words at once.
    act(() => room.joined(true, 0));
    await waitUntil(() => expect(hasTeamCanvas(doc.doc)).toBe(true));
    expect(card(shown, 'book').style.left).toBe('0px');
    // sam's device moves the card: the structure's update arrives, and the card is drawn where they put it.
    const theirs = new Y.Doc();
    Y.applyUpdate(theirs, Y.encodeStateAsUpdate(doc.doc));
    const { teamCanvas } = await import('../core/team/canvas.ts');
    const samsCanvas = teamCanvas({ doc: theirs, text: theirs.getText('body') })!;
    samsCanvas.apply({ ...samsCanvas.canvas(), nodes: samsCanvas.canvas().nodes.map((n) => (n.id === 'book' ? { ...n, x: 120, y: 48 } : n)) });
    act(() => doc.applyRemote([Y.encodeStateAsUpdate(theirs, Y.encodeStateVector(doc.doc))]));
    await waitUntil(() => expect(card(shown, 'book').style.left).toBe('120px'));
    expect(card(shown, 'book').style.top).toBe('48px');
    // And the document's words say it too, read from the structure, without this device writing anything.
    expect(canvasOf(doc.words())!.nodes[0]).toMatchObject({ x: 120, y: 48 });
    expect(changes).toEqual([]);
  });

  it('draws the other members’ pointers in their colours with their handles, and rings the card one is writing in', async () => {
    const shown = show(<CanvasView canvas={canvasOf(BODY)!} dark={false} team={binding()} onChange={() => undefined} />);
    act(() => room.joined(true, 0));
    await waitUntil(() => expect(hasTeamCanvas(doc.doc)).toBe(true));
    sam.setLocalStateField('pointer', { x: 300, y: 80 });
    sam.setLocalStateField('card', 'book');
    act(() => heard());
    const pointer = shown.querySelector<HTMLElement>('[data-handle="sam"]');
    expect(pointer).not.toBeNull();
    expect(pointer?.style.left).toBe('300px');
    expect(pointer?.style.top).toBe('80px');
    expect(pointer?.style.getPropertyValue('--pointer')).toBe('blue');
    expect(pointer?.textContent).toBe('sam');
    expect(card(shown, 'book').dataset.editedBy).toBe('sam');
    expect(card(shown, 'book').style.getPropertyValue('--editor')).toBe('blue');
    expect(card(shown, 'site').dataset.editedBy).toBeUndefined();
    // Off the canvas and done writing: the arrow and the ring go.
    sam.setLocalStateField('pointer', null);
    sam.setLocalStateField('card', null);
    act(() => heard());
    expect(shown.querySelector('[data-handle="sam"]')).toBeNull();
    expect(card(shown, 'book').dataset.editedBy).toBeUndefined();
  });

  it('waits for the room before seeding a structure, so one about to arrive is not seeded over', async () => {
    const late = (await teamDoc('n2', memoryDocs(), BODY))!;
    const key = await settle(await newAccountKey());
    const transport = { join: () => undefined, leave: () => undefined, send: () => undefined, close: () => undefined };
    const lateRoom = new TeamRoom('org-1', 'n2', { name: 'matt', hue: null, color: 'c', colorLight: 'w' }, { key, doc: late, hold: () => transport, release: () => undefined });
    show(<CanvasView canvas={canvasOf(BODY)!} dark={false} team={{ doc: late, room: lateRoom, orgId: 'org-1' }} onChange={() => undefined} />);
    // Not alone: the others are asked, and nothing is seeded while their answer may be on its way.
    act(() => lateRoom.joined(false, 1));
    await new Promise((tick) => setTimeout(tick, 30));
    expect(hasTeamCanvas(late.doc)).toBe(false);
    // The room closing settles it, as an answer or the catch-up timeout would.
    lateRoom.close();
    await waitUntil(() => expect(hasTeamCanvas(late.doc)).toBe(true));
  });

  it('centres on a member’s pointer when asked to jump there', async () => {
    const shown = show(<CanvasView canvas={canvasOf(BODY)!} dark={false} team={binding()} onChange={() => undefined} goTo={{ x: 640, y: 400 }} />);
    act(() => room.joined(true, 0));
    await waitUntil(() => expect(hasTeamCanvas(doc.doc)).toBe(true));
    const world = shown.querySelector<HTMLElement>('[class*="world"]')!;
    // The frame has no size here, so its middle is its corner: the world is moved so the spot sits at the origin.
    await waitUntil(() => expect(world.style.transform).toContain('translate(-640px, -400px)'));
  });
});
