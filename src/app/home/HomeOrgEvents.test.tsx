import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { makeNote } from '../../test/notes.ts';
import { show, unmount } from '../../test/render.tsx';

/**
 * The card docked beside the home page's notes while it is filtered to an organization (home/HomeOrgEvents.tsx;
 * Matt: "a right side docked card somewhere with recent events in the org when an organization is selected"): who is
 * editing now first, then the workspace's notes as they changed and the team's news, newest first.
 */
const feed = vi.hoisted(() => ({ rows: [] as unknown[] }));
vi.mock('../core/notifications/feed.ts', () => ({ useNotifications: () => feed.rows }));
const presence = vi.hoisted(() => ({ seen: [] as unknown[] }));
vi.mock('../core/live/presence.ts', () => ({ usePresence: () => presence.seen }));

const { HomeOrgEvents } = await import('./HomeOrgEvents.tsx');
const { ensureOrgWorkspace, fileNote, orgWorkspaceId, reloadWorkspaces } = await import('../core/workspaces.ts');
const lines = () => [...document.querySelectorAll<HTMLElement>('[data-section="org-events"] ol li')].map((li) => li.textContent);

beforeEach(() => {
  localStorage.clear();
  reloadWorkspaces();
  feed.rows = [];
  presence.seen = [];
  ensureOrgWorkspace({ id: 'o1', name: 'Ghost', hue: 'sea' });
});
afterEach(() => unmount());

describe('recent events in the organization the home page is filtered to', () => {
  it('says so when nothing has happened, and opens the organization from its foot', () => {
    const opened: string[] = [];
    show(<HomeOrgEvents orgId="o1" name="Ghost" notes={[]} onOpenNote={() => undefined} onOpen={(id) => opened.push(id)} />);
    expect(document.querySelector('#home-org-events')?.textContent).toBe('Recent in Ghost');
    expect(document.body.textContent).toContain('Nothing has happened here yet.');
    act(() => [...document.querySelectorAll('button')].find((b) => b.textContent === 'Open Ghost')!.click());
    expect(opened).toEqual(['o1']);
  });

  it('lists who is editing now, then its notes and its news by time, and opens a note from its line', () => {
    const now = Date.now();
    const notes = [makeNote('a', '# Roadmap', { updatedAt: now - 60_000 }), makeNote('b', '# Budget', { updatedAt: now - 3 * 3_600_000 }), makeNote('c', '# Mine alone', { updatedAt: now })];
    fileNote('a', orgWorkspaceId('o1'));
    fileNote('b', orgWorkspaceId('o1'));
    feed.rows = [
      { id: 'n1', kind: 'member-joined', at: now - 3_600_000, rev: 1, readAt: null, hidden: false, org: { id: 'o1', name: 'Ghost' }, from: 'kebim' },
      { id: 'n2', kind: 'member-joined', at: now, rev: 2, readAt: null, hidden: false, org: { id: 'o2', name: 'Other' }, from: 'zed' },
    ];
    presence.seen = [{ handle: 'kebim', hue: 'sea', at: { note: 'a', title: 'Roadmap', kind: 'note', cursor: null, pointer: null }, client: 1 }];
    const openedNotes: string[] = [];
    show(<HomeOrgEvents orgId="o1" name="Ghost" notes={notes} onOpenNote={(id) => openedNotes.push(id)} onOpen={() => undefined} />);
    const shown = lines();
    expect(shown).toHaveLength(4);
    expect(shown[0]).toBe('kebim is editing Roadmapnow');
    expect(shown[1]).toContain('Roadmap changed');
    expect(shown[2]).toContain('kebim');
    expect(shown[3]).toContain('Budget changed');
    expect(shown.join(' ')).not.toContain('Mine alone');
    expect(shown.join(' ')).not.toContain('zed');
    act(() => [...document.querySelectorAll<HTMLButtonElement>('[data-section="org-events"] ol button')].find((b) => b.textContent === 'Budget changed')!.click());
    expect(openedNotes).toEqual(['b']);
  });
});
