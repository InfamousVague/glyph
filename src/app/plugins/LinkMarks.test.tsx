import { afterEach, describe, expect, it, vi } from 'vitest';
import { show, unmount } from '../../test/render.tsx';
import { addWorkspace, fileNote, removeWorkspace, workspaces } from '../core/workspaces.ts';
import { LinkMarks } from './LinkMarks.tsx';

// Each note's links as its plugins would say them: a mark, the label of what it is linked to, and its name.
const RingMark = () => <svg data-testid="ring" />;
const linked: Record<string, { link: { id: string; label: string; icon: () => ReturnType<typeof RingMark> }; name: string }[]> = {
  n4: [
    { link: { id: 'notion-board', label: 'Notion board', icon: RingMark }, name: 'Roadmap' },
    { link: { id: 'github-repo', label: 'GitHub repo', icon: RingMark }, name: 'InfamousVague/AttackFM' },
  ],
};
vi.mock('./hooks.ts', () => ({ useNoteLinks: (noteId: string) => linked[noteId] ?? [] }));

afterEach(() => {
  // Off the page first, so the workspaces going is a change no mounted mark hears.
  unmount();
  for (const w of workspaces().list) removeWorkspace(w.id);
});

describe('the workspace on the note', () => {
  it('leaves the workspace to the tab, which wears it: a note filed with no links says nothing here', () => {
    const cabin = addWorkspace('Cabin', 'moss')!;
    fileNote('n1', cabin.id);
    const shown = show(<LinkMarks noteId="n1" onPress={() => {}} />);
    expect(shown.children).toHaveLength(0);
    expect(shown.querySelector('[data-hue]')).toBeNull();
  });

  it('says nothing on a note in no workspace with no links', () => {
    expect(show(<LinkMarks noteId="n2" onPress={() => {}} />).children).toHaveLength(0);
  });
});

describe('the links on the note', () => {
  it('wears a mark for each, named, with no workspace pill, and says them all to a screen reader', () => {
    const cabin = addWorkspace('Cabin')!;
    fileNote('n4', cabin.id);
    const shown = show(<LinkMarks noteId="n4" onPress={() => {}} />);
    const row = shown.querySelector('button')!;
    expect(row.textContent).toBe('RoadmapInfamousVague/AttackFM');
    expect(row.querySelectorAll('[data-testid="ring"]')).toHaveLength(2);
    expect([...row.querySelectorAll('[title]')].map((mark) => mark.getAttribute('title'))).toEqual(['Notion board: Roadmap', 'GitHub repo: InfamousVague/AttackFM']);
    expect(row.getAttribute('aria-label')).toBe('Linked to Notion board Roadmap and GitHub repo InfamousVague/AttackFM. Change in this note’s settings.');
  });

  it('is a plain row with nothing to press when there is nowhere to open', () => {
    const shown = show(<LinkMarks noteId="n4" />);
    expect(shown.querySelector('button')).toBeNull();
    expect(shown.textContent).toBe('RoadmapInfamousVague/AttackFM');
  });
});
