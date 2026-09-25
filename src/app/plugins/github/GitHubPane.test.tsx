import { beforeEach, describe, expect, it } from 'vitest';
import { button, press, show, typeInto } from '../../../test/render.tsx';
import { GitHubPane } from './GitHubPane.tsx';
import { githubToken, linkProject, projectFor, projects, type Project } from './repos.ts';

/**
 * The GitHub plugin's page in Settings: the repos read on this phone and a way to forget each, and the token, typed
 * once and then only said to be kept. Reading a repo is the note's, from its cog (ProjectPicker.tsx), and the rules
 * of what is kept are projects.test.ts.
 */

const kept = (over: Partial<Project> = {}): Project => ({
  id: 'infamousvague/attackfm',
  owner: 'InfamousVague',
  repo: 'AttackFM',
  url: 'https://github.com/InfamousVague/AttackFM',
  branch: 'main',
  description: '',
  files: ['README.md'],
  pack: 'A radio.',
  packModel: null,
  packedAt: Date.UTC(2026, 8, 20),
  ...over,
});

beforeEach(() => {
  localStorage.clear();
});

describe('the GitHub page', () => {
  it('says there are no repos yet, and where one is linked from', () => {
    const pane = show(<GitHubPane />);
    expect(pane.textContent).toContain('No repos yet.');
    expect(pane.textContent).toContain('choose GitHub repo to link one');
  });

  it('lists each repo with what wrote its briefing, and forgets one along with its links', () => {
    localStorage.setItem('glyph-github-projects', JSON.stringify([kept(), kept({ id: 'o/r', owner: 'o', repo: 'r', packModel: 'qwen3.5-4b' })]));
    linkProject('n1', 'infamousvague/attackfm');
    const pane = show(<GitHubPane />);
    const rows = [...pane.querySelectorAll('.setk-row')].filter((row) => row.querySelector('.setk-row__label')?.textContent?.includes('/'));
    expect(rows.map((row) => row.querySelector('.setk-row__label')?.textContent)).toEqual(['InfamousVague/AttackFM', 'o/r']);
    expect(rows[0]!.textContent).toContain('Kept from its README');
    expect(rows[1]!.textContent).toContain('Read by qwen3.5-4b');
    press(button('Forget', rows[0]!));
    expect(projects().map((p) => p.id)).toEqual(['o/r']);
    expect(projectFor('n1')).toBeNull();
    expect(pane.textContent).not.toContain('InfamousVague/AttackFM');
  });

  it('keeps a token typed in, trimmed, and then only says one is kept until it is forgotten', () => {
    const pane = show(<GitHubPane />);
    const keep = button('Keep it', pane);
    expect(keep.disabled).toBe(true);
    typeInto(pane.querySelector<HTMLInputElement>('input[aria-label="GitHub token"]')!, '  github_pat_abc  ');
    expect(keep.disabled).toBe(false);
    press(keep);
    expect(githubToken()).toBe('github_pat_abc');
    // The token is never shown again, only that there is one.
    expect(pane.textContent).toContain('A token is kept');
    expect(pane.querySelector('input[aria-label="GitHub token"]')).toBeNull();
    press(button('Forget', pane));
    expect(githubToken()).toBe('');
    expect(pane.querySelector('input[aria-label="GitHub token"]')).not.toBeNull();
  });
});
