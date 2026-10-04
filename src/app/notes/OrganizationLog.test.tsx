import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { makeNote } from '../../test/notes.ts';
import type { Session } from '../core/account/keystore.ts';
import type { Notification } from '../core/notifications/kinds.ts';
import { button, buttonSaying, show, typeInto, unmount, waitUntil } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks matchMedia as it loads; the page's wisp watches the bar's size, which jsdom never lays out.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
stubResizeObserver();
vi.mock('../art/wispEdge.ts', () => ({ useWispEdge: () => undefined }));
// Signed in as matt: the organization's row is the account's, and a version kept here is matt's.
let session: Session | null = null;
vi.mock('../core/account/account.ts', () => ({
  accountState: () => ({ session, unlocked: session !== null }),
  useAccount: () => ({ session, unlocked: session !== null }),
  accountKey: async () => null,
  onAccount: () => () => undefined,
  resume: async () => undefined,
}));

const { OrganizationLog } = await import('./OrganizationLog.tsx');
const { forgetOrgs, saveOrgs } = await import('../core/orgs/orgs.ts');
const { forgetNotifications, updateFeed, withFed } = await import('../core/notifications/feed.ts');
const { DEFAULT_PREFERENCES, reloadPreferences, setPreferences } = await import('../core/preferences.ts');
const { ensureOrgWorkspace, fileNote, orgWorkspaceId, reloadWorkspaces } = await import('../core/workspaces.ts');
const { keepVersion } = await import('../core/versions/record.ts');

/**
 * An organization's audit log (notes/OrganizationLog.tsx; Matt: "an "audit log" for organizations to be able to
 * browse history of changes across all files"): every version of every note filed in its workspace with the team's
 * news between them, newest first under the day; the filter and the pills; a change opened to what it changed.
 */

const ORG = 'org-1';
const DAY = 86_400_000;
let at = 1_000_000;

/** A row of the feed, as a pass would have fed it. */
function fed(row: Partial<Notification> & { kind: Notification['kind']; at?: number }): Notification {
  at += 60_000;
  const item: Notification = { id: row.id ?? `n${at}`, rev: at, readAt: null, hidden: false, ...row, at: row.at ?? at };
  updateFeed(7, (state) => ({ ...withFed(state, item, at), cursor: at }));
  return item;
}

type Props = Parameters<typeof OrganizationLog>[0];
const page = (over: Partial<Props> = {}) => show(<OrganizationLog orgId={ORG} notes={[]} onBack={() => undefined} onOpenNote={() => undefined} {...over} />);

const NOTES = [makeNote('a', '# Roadmap\n- ship'), makeNote('b', '# Standup'), makeNote('c', '# Groceries')];

/** Roadmap kept twice (two days ago, a minute ago) and Standup once (yesterday), all filed in the organization; Groceries kept once, filed nowhere. */
async function kept(now: number): Promise<void> {
  await keepVersion('a', '# Roadmap', { now: now - 2 * DAY });
  await keepVersion('b', '# Standup', { now: now - DAY });
  await keepVersion('a', '# Roadmap\n- ship', { now: now - 60_000 });
  await keepVersion('c', '# Groceries', { now: now - 30_000 });
  fileNote('a', orgWorkspaceId(ORG));
  fileNote('b', orgWorkspaceId(ORG));
}

const rows = (day?: string) => [...document.querySelectorAll<HTMLElement>(`${day ? `section[aria-label="${day}"] ` : ''}ol li`)].map((li) => li.textContent ?? '');
const days = () => [...document.querySelectorAll<HTMLElement>('section[aria-label]')].map((section) => section.getAttribute('aria-label'));
const figures = () => document.querySelector('[role="status"]')?.textContent;

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  reloadWorkspaces();
  setPreferences(DEFAULT_PREFERENCES);
  session = { token: 't', handle: 'matt', accountId: 7 };
  forgetOrgs(7);
  forgetNotifications(7);
  saveOrgs(7, { list: [{ id: ORG, name: 'Ghost', hue: 'sea', role: 'owner', state: 'member', members: 2, createdAt: 1 }], at: Date.now() });
  ensureOrgWorkspace({ id: ORG, name: 'Ghost', hue: 'sea' });
});

afterEach(() => {
  unmount();
  forgetOrgs(7);
  forgetNotifications(7);
  localStorage.clear();
});

describe('an organization’s audit log', () => {
  it('is every change to the notes filed in the workspace, newest first under the day, with who, which note, how much and the first line', async () => {
    await kept(Date.now());
    page({ notes: NOTES });
    expect(document.querySelector('h1')?.textContent).toBe('GhostAudit log');
    expect(document.querySelector('h1 [data-hue="sea"]')).not.toBeNull();
    await waitUntil(() => expect(figures()).toBe('3 changes across 2 notes · 1 person'));
    expect(days().slice(0, 2)).toEqual(['Today', 'Yesterday']);
    expect(days()).toHaveLength(3);
    expect(rows('Today')).toHaveLength(1);
    expect(rows('Today')[0]).toContain('matt');
    expect(rows('Today')[0]).toContain('edited');
    expect(rows('Today')[0]).toContain('Roadmap');
    expect(rows('Today')[0]).toContain('+1 −0');
    expect(rows('Today')[0]).toContain('+ - ship');
    expect(rows('Today')[0]).toContain('v2');
    expect(rows('Yesterday')[0]).toContain('matt');
    expect(rows('Yesterday')[0]).toContain('created');
    expect(rows('Yesterday')[0]).toContain('Standup');
    expect(rows('Yesterday')[0]).toContain('First version');
    // Groceries is not filed here: its versions are not the organization's.
    expect(document.body.textContent).not.toContain('Groceries');
  });

  it('puts the team’s news between the changes, and shows the notes or the team alone', async () => {
    const now = Date.now();
    await kept(now);
    fed({ kind: 'member-joined', from: 'sam', org: { id: ORG, name: 'Ghost' }, body: { name: 'Ghost' }, at: now - 45_000 });
    fed({ kind: 'member-joined', from: 'lee', org: { id: 'elsewhere', name: 'Elsewhere' }, body: { name: 'Elsewhere' }, at: now - 40_000 });
    page({ notes: NOTES });
    await waitUntil(() => expect(rows('Today')).toHaveLength(2));
    expect(rows('Today')[0]).toContain('sam joined Ghost');
    expect(rows('Today')[1]).toContain('Roadmap');
    expect(document.body.textContent).not.toContain('Elsewhere');
    act(() => button('Team').click());
    expect(rows()).toHaveLength(1);
    expect(rows()[0]).toContain('sam joined Ghost');
    expect(figures()).toBe('3 changes across 2 notes · 1 person · 1 line shown');
    act(() => button('Notes').click());
    expect(rows()).toHaveLength(3);
    expect(rows().some((row) => row.includes('sam joined'))).toBe(false);
    act(() => button('Everything').click());
    expect(rows()).toHaveLength(4);
  });

  it('narrows to a note, a person or a version’s name by the filter', async () => {
    await kept(Date.now());
    page({ notes: NOTES });
    await waitUntil(() => expect(rows()).toHaveLength(3));
    typeInto(document.querySelector<HTMLInputElement>('input[aria-label="Filter the log"]')!, 'stand');
    expect(rows()).toHaveLength(1);
    expect(rows()[0]).toContain('Standup');
    typeInto(document.querySelector<HTMLInputElement>('input[aria-label="Filter the log"]')!, 'MATT');
    expect(rows()).toHaveLength(3);
    typeInto(document.querySelector<HTMLInputElement>('input[aria-label="Filter the log"]')!, 'nothing like it');
    expect(rows()).toHaveLength(0);
    expect(document.body.textContent).toContain('Nothing matches.');
    act(() => button('Clear the filter').click());
    expect(rows()).toHaveLength(3);
  });

  it('opens a change to what that version changed, with the way to the note and to only that note', async () => {
    const onOpenNote = vi.fn();
    await kept(Date.now());
    page({ notes: NOTES, onOpenNote });
    await waitUntil(() => expect(rows('Today')).toHaveLength(1));
    act(() => document.querySelector<HTMLButtonElement>('section[aria-label="Today"] li button')!.click());
    expect(document.querySelector('h2')?.textContent).toBe('Roadmap · Version 2');
    await waitUntil(() => expect(document.querySelector('ol[aria-label="What this version changed"]')).not.toBeNull());
    const lines = [...document.querySelectorAll<HTMLElement>('ol[aria-label="What this version changed"] li')].map((li) => `${li.dataset.kind}:${li.textContent}`);
    expect(lines).toEqual(['same:# Roadmap', 'add:+- ship']);
    act(() => buttonSaying(document.body, 'Open the note')!.click());
    expect(onOpenNote).toHaveBeenCalledWith('a');
    act(() => buttonSaying(document.body, 'The log')!.click());
    expect(rows()).toHaveLength(3);
    // Only this note: Roadmap's two changes, under a pill that takes the narrowing off again.
    act(() => document.querySelector<HTMLButtonElement>('section[aria-label="Today"] li button')!.click());
    act(() => buttonSaying(document.body, 'Only this note')!.click());
    expect(rows()).toHaveLength(2);
    expect(rows().every((row) => row.includes('Roadmap'))).toBe(true);
    act(() => button('Only Roadmap; press for every note').click());
    expect(rows()).toHaveLength(3);
  });

  it('hears a version kept while it is open', async () => {
    await kept(Date.now());
    page({ notes: NOTES });
    await waitUntil(() => expect(rows()).toHaveLength(3));
    await act(async () => {
      await keepVersion('b', '# Standup\n- yesterday: shipped', { label: 'After standup' });
    });
    await waitUntil(() => expect(rows()).toHaveLength(4));
    expect(rows('Today')[0]).toContain('Standup');
    expect(rows('Today')[0]).toContain('After standup');
    expect(rows('Today')[0]).toContain('+1 −0');
  });

  it('says so when nothing has changed yet, which notes keep no history, and goes back by its arrow', async () => {
    const onBack = vi.fn();
    fileNote('b', orgWorkspaceId(ORG));
    setPreferences({ versions: { b: false } });
    page({ notes: NOTES, onBack });
    await waitUntil(() => expect(figures()).toBe('0 changes across 1 note'));
    expect(document.body.textContent).toContain('Nothing has changed here yet.');
    expect(document.body.textContent).toContain('History is off for Standup.');
    act(() => button('Back to Ghost').click());
    expect(onBack).toHaveBeenCalledOnce();
  });
});
