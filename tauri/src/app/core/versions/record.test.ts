import { beforeEach, describe, expect, it } from 'vitest';
import { preferences, reloadPreferences } from '../preferences.ts';
import { addWorkspace, ensureOrgWorkspace, fileNote, reloadWorkspaces } from '../workspaces.ts';
import { keepsVersions, keepVersion, setKeepsVersions, versionsOf } from './record.ts';
import { unsentVersions } from './store.ts';

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  reloadWorkspaces();
});

describe('which notes keep a version history', () => {
  it('is every note in an organization, unless switched off, and a note of one’s own once switched on', () => {
    const team = ensureOrgWorkspace({ id: 'o1', name: 'Ghost', hue: 'sea' });
    const home = addWorkspace('Home')!;
    fileNote('team-note', team.id);
    fileNote('home-note', home.id);
    expect(keepsVersions('team-note')).toBe(true);
    expect(keepsVersions('home-note')).toBe(false);
    expect(keepsVersions('loose')).toBe(false);

    setKeepsVersions('home-note', true);
    setKeepsVersions('team-note', false);
    expect(keepsVersions('home-note')).toBe(true);
    expect(keepsVersions('team-note')).toBe(false);
    expect(preferences().versions).toEqual({ 'home-note': true, 'team-note': false });

    // A choice that is what the note would do anyway is not kept.
    setKeepsVersions('team-note', true);
    setKeepsVersions('home-note', false);
    expect(preferences().versions).toEqual({});
  });
});

describe('keeping versions', () => {
  it('keeps each change once, names one by hand, and owes the file to the account', async () => {
    expect(await keepVersion('n1', '# Plan', { now: 1000 })).toBe(true);
    expect(await keepVersion('n1', '# Plan', { now: 2000 })).toBe(false);
    expect(await keepVersion('n1', '# Plan\n- venue', { now: 3000 })).toBe(true);
    expect(await keepVersion('n1', '# Plan\n- venue', { now: 4000, label: 'Sent to Sam' })).toBe(true);
    const { versions, damaged } = await versionsOf('n1');
    expect(damaged).toBe(0);
    expect(versions.map((v) => [v.text, v.label, v.by])).toEqual([
      ['# Plan', undefined, 'me'],
      ['# Plan\n- venue', 'Sent to Sam', 'me'],
    ]);
    expect(unsentVersions()).toEqual(['n1']);
  });

  it('keeps two versions asked for at once in the order they were asked, neither lost', async () => {
    await Promise.all([keepVersion('n2', 'one', { now: 1 }), keepVersion('n2', 'one\ntwo', { now: 2 }), keepVersion('n2', 'one\ntwo\nthree', { now: 3 })]);
    expect((await versionsOf('n2')).versions.map((v) => v.text)).toEqual(['one', 'one\ntwo', 'one\ntwo\nthree']);
  });
});
