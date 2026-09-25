import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, unmount } from '../../test/render.tsx';
import { addWorkspace, fileNote, removeWorkspace, setWorkspaceHue, workspaces } from '../core/workspaces.ts';
import { LinkMarks } from './LinkMarks.tsx';

// Each note's links as its plugins would say them: a mark, the label of what it is linked to, and its name.
const RingMark = () => <svg data-testid="ring" />;
const linked: Record<string, { link: { id: string; label: string; icon: () => ReturnType<typeof RingMark> }; name: string }[]> = {
  n4: [
    { link: { id: 'notion-board', label: 'Notion board', icon: RingMark }, name: 'Roadmap' },
    { link: { id: 'github-repo', label: 'GitHub repo', icon: RingMark }, name: 'InfamousVague/AttackFM' },
  ],
};
vi.mock('./registry.ts', () => ({ useNoteLinks: (noteId: string) => linked[noteId] ?? [] }));

afterEach(() => {
  // Off the page first, so the workspaces going is a change no mounted mark hears.
  unmount();
  for (const w of workspaces().list) removeWorkspace(w.id);
});

describe('the workspace on the note', () => {
  it('wears the workspace the note is filed in as a pill in its hue, first in the row, and opens the cog on a tap', () => {
    const cabin = addWorkspace('Cabin', 'moss')!;
    fileNote('n1', cabin.id);
    const onPress = vi.fn();
    const shown = show(<LinkMarks noteId="n1" onPress={onPress} />);
    const pill = shown.querySelector('[data-hue]') as HTMLElement;
    expect(pill.textContent).toBe('Cabin');
    expect(pill.getAttribute('data-hue')).toBe('moss');
    const row = shown.querySelector('button')!;
    expect(row.getAttribute('aria-label')).toBe('In the workspace Cabin. Change in this note’s settings.');
    act(() => row.click());
    expect(onPress).toHaveBeenCalledTimes(1);
    // Filed elsewhere, or its hue changed, the pill follows.
    act(() => setWorkspaceHue(cabin.id, 'rose'));
    expect(shown.querySelector('[data-hue]')?.getAttribute('data-hue')).toBe('rose');
    act(() => fileNote('n1', null));
    expect(shown.querySelector('[data-hue]')).toBeNull();
    expect(shown.querySelector('button')).toBeNull();
  });

  it('says nothing on a note in no workspace with no links', () => {
    expect(show(<LinkMarks noteId="n2" onPress={() => {}} />).children).toHaveLength(0);
  });
});

describe('the links on the note', () => {
  it('wears a mark for each, named, after the workspace, and says them all to a screen reader', () => {
    const cabin = addWorkspace('Cabin')!;
    fileNote('n4', cabin.id);
    const shown = show(<LinkMarks noteId="n4" onPress={() => {}} />);
    const row = shown.querySelector('button')!;
    expect(row.textContent).toBe('CabinRoadmapInfamousVague/AttackFM');
    expect(row.querySelectorAll('[data-testid="ring"]')).toHaveLength(2);
    expect([...row.querySelectorAll('[title]')].map((mark) => mark.getAttribute('title'))).toEqual(['Workspace: Cabin', 'Notion board: Roadmap', 'GitHub repo: InfamousVague/AttackFM']);
    expect(row.getAttribute('aria-label')).toBe('In the workspace Cabin. Linked to Notion board Roadmap and GitHub repo InfamousVague/AttackFM. Change in this note’s settings.');
  });

  it('is a plain row with nothing to press when there is nowhere to open', () => {
    const shown = show(<LinkMarks noteId="n4" />);
    expect(shown.querySelector('button')).toBeNull();
    expect(shown.textContent).toBe('RoadmapInfamousVague/AttackFM');
  });
});
