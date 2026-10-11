import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { buttonSaying, show, unmount } from '../../test/render.tsx';

// The kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

const { WorkspacePicker } = await import('./WorkspacePicker.tsx');
const { addWorkspace, ensureOrgWorkspace, fileNote, orgWorkspaceId, reloadWorkspaces, workspaceOf } = await import('../core/workspaces.ts');
const { DEFAULT_PREFERENCES, reloadPreferences, setPreferences } = await import('../core/preferences.ts');

/**
 * Where a note is filed (editor/WorkspacePicker.tsx): a workspace chosen at once, and a note that is a team's
 * (docs/SHARED.md, S1) taken out of its organization only on a second press, since that takes it from everyone.
 */

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  reloadWorkspaces();
  setPreferences(DEFAULT_PREFERENCES);
  vi.useFakeTimers();
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
});

describe('the workspace picker', () => {
  it('files a note in a personal workspace at once, and takes it out at once', () => {
    const onDone = vi.fn();
    const home = addWorkspace('Home')!;
    show(<WorkspacePicker noteId="n1" onDone={onDone} />);
    act(() => buttonSaying(document.body, 'Home')!.click());
    expect(workspaceOf('n1')?.id).toBe(home.id);
    expect(onDone).toHaveBeenCalledOnce();
    unmount();
    show(<WorkspacePicker noteId="n1" onDone={onDone} />);
    act(() => buttonSaying(document.body, 'Take this note out of Home')!.click());
    expect(workspaceOf('n1')).toBeNull();
    expect(onDone).toHaveBeenCalledTimes(2);
  });

  it('asks twice before a note leaves its team, and forgets the first press after a moment', () => {
    const onDone = vi.fn();
    ensureOrgWorkspace({ id: 'o1', name: 'Ghost', hue: 'sea' });
    addWorkspace('Home');
    fileNote('n1', orgWorkspaceId('o1'));
    show(<WorkspacePicker noteId="n1" onDone={onDone} />);
    expect(document.body.textContent).toContain('this note is the team’s');
    // Out of the organization: the first press arms, the words say what it means, the second goes through.
    act(() => buttonSaying(document.body, 'Take this note out of Ghost')!.click());
    expect(workspaceOf('n1')?.id).toBe(orgWorkspaceId('o1'));
    expect(onDone).not.toHaveBeenCalled();
    expect(document.body.textContent).toContain('This takes the note away from everyone in Ghost. Press again to go on.');
    act(() => buttonSaying(document.body, 'Press again to take it from the team')!.click());
    expect(workspaceOf('n1')).toBeNull();
    expect(onDone).toHaveBeenCalledOnce();
    // Into another workspace, the same: and a press left alone is forgotten.
    fileNote('n1', orgWorkspaceId('o1'));
    unmount();
    show(<WorkspacePicker noteId="n1" onDone={onDone} />);
    act(() => buttonSaying(document.body, 'Home')!.click());
    expect(workspaceOf('n1')?.id).toBe(orgWorkspaceId('o1'));
    act(() => {
      vi.advanceTimersByTime(4500);
    });
    expect(document.body.textContent).not.toContain('Press again to go on');
    act(() => buttonSaying(document.body, 'Home')!.click());
    // Armed again, not moved.
    expect(workspaceOf('n1')?.id).toBe(orgWorkspaceId('o1'));
    act(() => buttonSaying(document.body, 'Home')!.click());
    expect(workspaceOf('n1')?.name).toBe('Home');
  });
});
