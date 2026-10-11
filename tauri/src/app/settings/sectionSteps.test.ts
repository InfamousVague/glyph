import { describe, expect, it } from 'vitest';
import { backWord, clustersOf, currentRow, listedOf, stepBack, stepForward, type SectionPlace } from './sectionSteps.ts';

/**
 * Settings' two depths (docs/DESIGN.md §138): five panes on the list, and sub-pages that are not, each stepping back to
 * the page it was opened from. The shape below is the app's, cut to what these answers read.
 */

const sections: SectionPlace[] = [
  { id: 'account', label: 'Account', group: 0 },
  { id: 'theme', label: 'Appearance', group: 1 },
  { id: 'recording', label: 'Recording', group: 1 },
  { id: 'plugins', label: 'Plugins', group: 1 },
  { id: 'plugin:notion', label: 'Notion', group: 1, listed: false, parent: 'plugins' },
  { id: 'about', label: 'About', group: 2 },
  { id: 'cheatsheet', label: 'Cheat sheet', group: 2, listed: false, parent: 'about' },
  { id: 'examples', label: 'Examples', group: 2, listed: false, parent: 'about' },
  { id: 'developer', label: 'Developer', group: 3 },
  { id: 'test-results', label: 'Test results', group: 3 },
];

const ids = (list: SectionPlace[]) => list.map((s) => s.id);

describe('the list', () => {
  it('has the panes and not the sub-pages', () => {
    expect(ids(listedOf(sections))).toEqual(['account', 'theme', 'recording', 'plugins', 'about', 'developer', 'test-results']);
  });

  it('clusters the rows by group, a sub-page between two rows of one group not splitting their card', () => {
    expect(clustersOf(sections).map(ids)).toEqual([['account'], ['theme', 'recording', 'plugins'], ['about'], ['developer', 'test-results']]);
  });
});

describe('back', () => {
  it('steps a sub-page to its parent, a pane to the list, and closes from the list', () => {
    expect(stepBack(sections, 'plugin:notion')).toBe('plugins');
    expect(stepBack(sections, 'examples')).toBe('about');
    expect(stepBack(sections, 'plugins')).toBeNull();
    expect(stepBack(sections, null)).toBe('close');
  });

  it('steps a sub-page whose parent is not there to the list, not to nothing', () => {
    expect(stepBack([{ id: 'orphan', label: 'Orphan', group: 0, listed: false, parent: 'gone' }], 'orphan')).toBeNull();
  });

  it('names where it goes in the head', () => {
    expect(backWord(sections, sections.find((s) => s.id === 'plugin:notion')!)).toBe('Plugins');
    expect(backWord(sections, sections.find((s) => s.id === 'cheatsheet')!)).toBe('About');
    expect(backWord(sections, sections.find((s) => s.id === 'theme')!)).toBe('Settings');
    expect(backWord(sections, null)).toBe('Settings');
  });

  it('names the screen itself as the root over a pane, when it is not Settings: an organization’s own screen', () => {
    expect(backWord(sections, sections.find((s) => s.id === 'theme')!, 'Ghost')).toBe('Ghost');
    expect(backWord(sections, null, 'Ghost')).toBe('Ghost');
    // A sub-page still steps to its parent, whatever the screen is called.
    expect(backWord(sections, sections.find((s) => s.id === 'plugin:notion')!, 'Ghost')).toBe('Plugins');
  });
});

describe('forward', () => {
  it('re-enters the page back just left, from where back landed', () => {
    // A pane left for the list comes back from the list.
    expect(stepForward(sections, null, 'theme')).toBe('theme');
    // A sub-page left for its parent comes back from the parent, not from the list or another page.
    expect(stepForward(sections, 'plugins', 'plugin:notion')).toBe('plugin:notion');
    expect(stepForward(sections, null, 'plugin:notion')).toBeNull();
    expect(stepForward(sections, 'about', 'plugin:notion')).toBeNull();
  });

  it('stays put with nothing left behind, or with what was left gone from the sections', () => {
    expect(stepForward(sections, null, null)).toBeNull();
    expect(stepForward(sections, null, 'developer-gone')).toBeNull();
  });
});

describe('the split view', () => {
  it('keeps the parent’s row current while a sub-page shows', () => {
    expect(currentRow(sections, sections.find((s) => s.id === 'examples')!)).toBe('about');
    expect(currentRow(sections, sections.find((s) => s.id === 'recording')!)).toBe('recording');
    expect(currentRow(sections, null)).toBeNull();
  });
});
