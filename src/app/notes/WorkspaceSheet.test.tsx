import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useState } from 'react';
import { reloadPreferences } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace, useWorkspaces, type Workspace, type WorkspaceHue } from '../core/workspaces.ts';
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
function Home() {
  spaces = useWorkspaces();
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  return (
    <>
      <WorkspaceBar onManage={setManage} />
      <WorkspaceSheet which={manage} onClose={() => setManage(null)} />
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

  it('renames one, recolours it as the colour is tapped, and removes it', () => {
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
    act(() => buttonSaying(sheet()!, 'Remove workspace')!.click());
    expect(spaces.list).toEqual([]);
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
