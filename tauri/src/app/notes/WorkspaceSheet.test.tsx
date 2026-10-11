import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useState } from 'react';
import { preferences, reloadPreferences } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace, ensureOrgWorkspace, fileNote, useWorkspaces, workspaceOf, workspaces, type Workspace, type WorkspaceHue } from '../core/workspaces.ts';
import { button, buttonSaying, show, typeInto } from '../../test/render.tsx';
import { WorkspaceBar } from './WorkspaceBar.tsx';
import { WorkspaceSheet } from './WorkspaceSheet.tsx';
import { WorkspaceSwatch } from './WorkspaceSwatch.tsx';

/**
 * The workspaces as the home page offers them: the row of pills that chooses what the page shows, the sheet that
 * makes, renames, recolours and removes one, and the swatch of colours, a radio group the arrow keys walk round.
 * The model itself is core/workspaces.ts's.
 */

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  chooseWorkspace(null);
});

/** The bar and its sheet as the home page wires them, with what is chosen read back out. */
let spaces: ReturnType<typeof useWorkspaces>;
function Home({ onOrganization }: { onOrganization?: (orgId: string) => void } = {}) {
  spaces = useWorkspaces();
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  return (
    <>
      <WorkspaceBar onManage={setManage} onOrganization={onOrganization} />
      <WorkspaceSheet which={manage} onClose={() => setManage(null)} onOrganization={onOrganization} />
    </>
  );
}
const sheet = () => document.querySelector<HTMLElement>('[role="dialog"]');

describe('the workspace pills', () => {
  it('are not there until there is a workspace', () => {
    const host = show(<WorkspaceBar onManage={() => undefined} />);
    expect(host.innerHTML).toBe('');
  });

  it('choose what the page shows, and open the one already chosen to be managed', () => {
    const kitchen = addWorkspace('Kitchen')!;
    show(<Home />);
    expect(button('All').getAttribute('aria-pressed')).toBe('true');
    act(() => button('Kitchen').click());
    expect(spaces.current?.id).toBe(kitchen.id);
    expect(sheet()).toBeNull();
    act(() => button('Kitchen').click());
    expect(sheet()?.getAttribute('aria-label')).toBe('Kitchen');
    act(() => button('All').click());
    expect(spaces.current).toBeNull();
  });
});

describe('the workspace sheet', () => {
  it('makes a workspace in the colour chosen for it, and chooses it', () => {
    addWorkspace('Kitchen');
    show(<Home />);
    act(() => button('New workspace').click());
    const add = buttonSaying(sheet()!, 'Add')!;
    // No name, nothing to add.
    expect(add.disabled).toBe(true);
    typeInto(sheet()!.querySelector('input')!, 'Garden');
    act(() => button('Moss').click());
    act(() => buttonSaying(sheet()!, 'Add')!.click());
    expect(sheet()).toBeNull();
    expect(spaces.current).toMatchObject({ name: 'Garden', hue: 'moss' });
  });

  it('renames one, recolours it as the colour is tapped, and deletes it', () => {
    const kitchen = addWorkspace('Kitchen')!;
    chooseWorkspace(kitchen.id);
    show(<Home />);
    act(() => button('Kitchen').click());
    // The same name is not a rename.
    expect(buttonSaying(sheet()!, 'Rename')!.disabled).toBe(true);
    act(() => button('Sea').click());
    expect(spaces.list[0]?.hue).toBe('sea');
    typeInto(sheet()!.querySelector('input')!, 'Pantry');
    act(() => void sheet()!.querySelector('input')!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
    expect(spaces.list[0]?.name).toBe('Pantry');
    act(() => button('Pantry').click());
    act(() => buttonSaying(sheet()!, 'Delete workspace')!.click());
    // Asked first: with no notes in it, only whether to delete it.
    expect(spaces.list).toHaveLength(1);
    expect(sheet()!.textContent).toContain('There are no notes in it.');
    act(() => buttonSaying(sheet()!, 'Delete workspace')!.click());
    expect(spaces.list).toEqual([]);
  });

  it('asks what becomes of the notes: kept and unfiled, or moved to the Trash with it', () => {
    const kitchen = addWorkspace('Kitchen')!;
    fileNote('n1', kitchen.id);
    fileNote('n2', kitchen.id);
    const host = show(<WorkspaceSheet which={kitchen} onClose={() => undefined} />);
    act(() => buttonSaying(host, 'Delete workspace')!.click());
    expect(host.textContent).toContain('What happens to its 2 notes?');
    // Cancel goes back, and nothing is gone.
    act(() => buttonSaying(host, 'Cancel')!.click());
    expect(workspaces().list).toHaveLength(1);
    act(() => buttonSaying(host, 'Delete workspace')!.click());
    act(() => buttonSaying(host, 'Delete, and move the notes to Trash')!.click());
    expect(workspaces().list).toEqual([]);
    expect(Object.keys(preferences().trash).sort()).toEqual(['n1', 'n2']);
  });

  it('keeps the notes, unfiled, when asked to', () => {
    const kitchen = addWorkspace('Kitchen')!;
    fileNote('n1', kitchen.id);
    const host = show(<WorkspaceSheet which={kitchen} onClose={() => undefined} />);
    act(() => buttonSaying(host, 'Delete workspace')!.click());
    expect(host.textContent).toContain('What happens to its 1 note?');
    act(() => buttonSaying(host, 'Delete, keep the notes')!.click());
    expect(workspaces().list).toEqual([]);
    expect(workspaceOf('n1')).toBeNull();
    expect(preferences().trash).toEqual({});
  });
});

/** An organization's workspace (docs/TEAMS.md, D5): marked on its pill, and managed on the organization's own screen. */
describe('an organization’s workspace', () => {
  it('wears the mark on its pill, and a second tap opens the organization rather than the sheet', () => {
    ensureOrgWorkspace({ id: 'o1', name: 'Ghost', hue: 'sea' });
    addWorkspace('Ghost');
    const onOrganization = vi.fn();
    show(<Home onOrganization={onOrganization} />);
    const pills = [...document.querySelectorAll<HTMLButtonElement>('[aria-label="Workspaces"] button')].filter((b) => b.textContent?.includes('Ghost'));
    expect(pills).toHaveLength(2);
    const [org, personal] = pills;
    expect(org!.getAttribute('data-org')).toBe('o1');
    expect(org!.querySelector('[role="img"][aria-label="Organization"]')).not.toBeNull();
    expect(personal!.hasAttribute('data-org')).toBe(false);
    expect(personal!.querySelector('[role="img"]')).toBeNull();
    act(() => org!.click());
    expect(spaces.current?.id).toBe('org-o1');
    act(() => org!.click());
    expect(onOrganization).toHaveBeenCalledWith('o1');
    expect(sheet()).toBeNull();
  });

  it('has no name, swatch or Remove in its sheet, only the way to the organization’s settings', () => {
    ensureOrgWorkspace({ id: 'o1', name: 'Ghost', hue: 'sea' });
    chooseWorkspace('org-o1');
    const onOrganization = vi.fn();
    show(<Home onOrganization={onOrganization} />);
    // Without the organization's screen to open, the pill's second tap falls back to the sheet.
    const host = show(<WorkspaceSheet which={spaces.list[0]!} onClose={() => undefined} onOrganization={onOrganization} />);
    expect(host.querySelector('input')).toBeNull();
    expect(host.querySelector('[role="radiogroup"]')).toBeNull();
    expect(buttonSaying(host, 'Delete workspace')).toBeUndefined();
    expect(buttonSaying(host, 'Rename')).toBeUndefined();
    expect(host.textContent).toContain('Notes filed here are the team’s');
    act(() => buttonSaying(host, 'Organization settings')!.click());
    expect(onOrganization).toHaveBeenCalledWith('o1');
  });
});

describe('the colour swatch', () => {
  it('is a radio group with the chosen colour ticked, and the arrow keys walk round it', () => {
    const onHue = vi.fn();
    const host = show(<WorkspaceSwatch hue="ink" onHue={onHue} />);
    const chosen = host.querySelector<HTMLButtonElement>('[role="radio"][aria-checked="true"]')!;
    expect(chosen.getAttribute('aria-label')).toBe('Ink');
    expect(chosen.tabIndex).toBe(0);
    expect(chosen.querySelector('svg')).not.toBeNull();
    const key = (name: string) => act(() => void chosen.dispatchEvent(new KeyboardEvent('keydown', { key: name, bubbles: true })));
    key('ArrowRight');
    expect(onHue).toHaveBeenLastCalledWith('ember' satisfies WorkspaceHue);
    // From the first, back round to the last.
    key('ArrowLeft');
    expect(onHue).toHaveBeenLastCalledWith('rose' satisfies WorkspaceHue);
    key('Enter');
    expect(onHue).toHaveBeenCalledTimes(2);
  });
});
