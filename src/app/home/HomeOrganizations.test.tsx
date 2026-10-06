import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { makeNote } from '../../test/notes.ts';
import { show, unmount } from '../../test/render.tsx';
import type { OrgRow } from '../core/orgs/types.ts';

/**
 * The organizations on the home page (home/HomeOrganizations.tsx; Matt: "add organizations to the home page"): a card
 * for each one joined, with its members, the notes filed in its workspace and who is in the app now, opening its
 * dashboard; nothing for an account in none, and no card for an invitation.
 */
const orgs = vi.hoisted(() => ({ list: [] as unknown[] }));
vi.mock('../core/orgs/orgs.ts', () => ({ useOrgs: () => ({ list: orgs.list, at: null, colour: null }) }));
const presence = vi.hoisted(() => ({ seen: {} as Record<string, unknown[]> }));
vi.mock('../core/live/presence.ts', () => ({ usePresence: (id: string) => presence.seen[id] ?? [] }));

const { HomeOrganizations } = await import('./HomeOrganizations.tsx');
const { ensureOrgWorkspace, fileNote, orgWorkspaceId, reloadWorkspaces } = await import('../core/workspaces.ts');

const row = (id: string, name: string, over: Partial<OrgRow> = {}): OrgRow => ({ id, name, hue: 'sea', role: 'member', state: 'member', members: 3, createdAt: 1, ...over });
const cards = () => [...document.querySelectorAll<HTMLElement>('ul[aria-label="Organizations"] li')].map((li) => li.textContent);

beforeEach(() => {
  localStorage.clear();
  reloadWorkspaces();
  orgs.list = [];
  presence.seen = {};
});
afterEach(() => unmount());

describe('the organizations on the home page', () => {
  it('draws nothing for an account in none, or only invited', () => {
    show(<HomeOrganizations notes={[]} onOpen={() => undefined} />);
    expect(document.querySelector('[data-section="organizations"]')).toBeNull();
    unmount();
    orgs.list = [row('o1', 'Ghost', { state: 'invited' })];
    show(<HomeOrganizations notes={[]} onOpen={() => undefined} />);
    expect(document.querySelector('[data-section="organizations"]')).toBeNull();
  });

  it('is a card for each one joined, in its colour, with its members, its notes and who is here, opening its dashboard', () => {
    orgs.list = [row('o1', 'Ghost'), row('o2', 'Attack', { hue: null, members: 1 }), row('o3', 'Later', { state: 'invited' })];
    ensureOrgWorkspace({ id: 'o1', name: 'Ghost', hue: 'sea' });
    const notes = [makeNote('a'), makeNote('b'), makeNote('c', '# C', { archivedAt: 5 }), makeNote('d')];
    for (const id of ['a', 'b', 'c']) fileNote(id, orgWorkspaceId('o1'));
    presence.seen = { o1: [{ handle: 'sam', hue: 'rose', at: { note: 'a', title: 'Roadmap', kind: 'note', cursor: null, pointer: null }, client: 1 }, { handle: 'lee', hue: null, at: null, client: 2 }], o2: [{ handle: 'lee', hue: null, at: null, client: 3 }] };
    const opened: string[] = [];
    show(<HomeOrganizations notes={notes} onOpen={(id) => opened.push(id)} />);
    expect(document.querySelector('#home-organizations')?.textContent).toBe('Organizations2');
    expect(cards()).toEqual(['Ghost3 members · 2 notessam is editing Roadmap, 1 more here', 'Attack1 member · 0 noteslee is here now']);
    const buttons = document.querySelectorAll<HTMLButtonElement>('ul[aria-label="Organizations"] button');
    expect([buttons[0]?.dataset.hue, buttons[1]?.dataset.hue]).toEqual(['sea', 'ink']);
    act(() => buttons[1]!.click());
    expect(opened).toEqual(['o2']);
  });

  // Matt: "i don't like how the heights are different on the organization cards when there is or is not people online".
  it('keeps the line with nobody in, said quietly, so every card is three lines', () => {
    orgs.list = [row('o1', 'Ghost'), row('o2', 'Attack', { hue: null, members: 1 })];
    presence.seen = { o1: [{ handle: 'sam', hue: 'rose', at: null, client: 1 }] };
    show(<HomeOrganizations notes={[]} onOpen={() => undefined} />);
    expect(cards()).toEqual(['Ghost3 members · 0 notessam is here now', 'Attack1 member · 0 notesNobody here now']);
    const lines = [...document.querySelectorAll<HTMLElement>('ul[aria-label="Organizations"] button')].map((card) => card.querySelector('span > span:last-child'));
    expect(lines.map((line) => line?.hasAttribute('data-quiet'))).toEqual([false, true]);
  });
});
