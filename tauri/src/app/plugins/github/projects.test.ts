import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ModelInfo, Run, RunOptions } from '../../core/ai.ts';

/**
 * A GitHub repo read into a project (repos.ts `addProject`), against GitHub's API stood in for by `fetch`: which of
 * its files are read and how, what the briefing is with a model on the phone and without one, GitHub's refusals as
 * sentences, and what is kept - the project, which notes link to it, the token. The pure parts (parsing a repo,
 * choosing files, the outline, a README's words) are repos.test.ts.
 */

// In a browser there is no model, and the briefing is the README's opening; each test that wants a phone says so.
let native = false;
vi.mock('../../core/tauri.ts', () => ({ isTauri: () => native, invoke: () => Promise.reject(new Error('no binary in a test')) }));
let present: string[] = [];
let written: string | Error = '';
const asked: RunOptions[] = [];
vi.mock('../../core/ai.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../core/ai.ts')>()),
  listModels: async (): Promise<ModelInfo[]> => present.map((id) => ({ id, present: true }) as ModelInfo),
  generate: (options: RunOptions): Run => {
    asked.push(options);
    options.onProgress({ phase: 'generating', tokensPerSecond: 12, partial: 'AttackFM is' } as never);
    return { done: written instanceof Error ? Promise.reject(written) : Promise.resolve({ text: written }), cancel: () => undefined } as unknown as Run;
  },
}));

const { addProject, projects, projectFor, linkProject, removeProject, projectContextFor, projectContextVersion, setGithubToken, githubToken } = await import('./repos.ts');
const { setPreferences, DEFAULT_PREFERENCES } = await import('../../core/preferences.ts');

const README = '# AttackFM\n\n[![CI](https://x/badge.svg)](https://x)\n\nA radio for [bands](https://docs).';

/** GitHub's answers for one repo: its meta, its tree, and each file's text by path. */
function github({ files = { 'README.md': README, 'package.json': '{"name":"attackfm"}' } as Record<string, string>, status = 200 } = {}) {
  const fetcher = vi.fn(async (input: RequestInfo | URL, _init?: RequestInit) => {
    const url = String(input);
    if (status !== 200) return new Response(null, { status });
    if (url === 'https://api.github.com/repos/infamousvague/attackfm') {
      return Response.json({ default_branch: 'main', description: 'A radio.', html_url: 'https://github.com/InfamousVague/AttackFM', full_name: 'InfamousVague/AttackFM' });
    }
    if (url === 'https://api.github.com/repos/InfamousVague/AttackFM/git/trees/main?recursive=1') {
      return Response.json({ tree: [...Object.keys(files), 'src/main.ts', 'src/'].map((path) => ({ path, type: path.endsWith('/') ? 'tree' : 'blob' })) });
    }
    const file = /\/contents\/(.+)\?ref=main$/.exec(url)?.[1];
    if (file !== undefined) {
      const text = files[decodeURIComponent(file)];
      return text === undefined ? new Response(null, { status: 404 }) : new Response(text);
    }
    return new Response(null, { status: 404 });
  });
  vi.stubGlobal('fetch', fetcher);
  return fetcher;
}

beforeEach(() => {
  native = false;
  present = [];
  written = '';
  asked.length = 0;
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
});

afterEach(() => {
  vi.unstubAllGlobals();
  setPreferences(DEFAULT_PREFERENCES);
});

describe('adding a project', () => {
  it('reads the repo and the files that say what it is, and keeps the README’s words where there is no model', async () => {
    const fetcher = github();
    const steps: string[] = [];
    const project = await addProject('https://github.com/infamousvague/attackfm', (step) => steps.push(step.kind === 'files' ? `files ${step.done}/${step.total}` : step.kind));
    // The name as GitHub spells it, and the id as a key.
    expect(project).toMatchObject({ id: 'infamousvague/attackfm', owner: 'InfamousVague', repo: 'AttackFM', packModel: null });
    expect(project.pack).toBe('# AttackFM\n\nA radio for bands.');
    expect(steps).toEqual(['reading', 'files 0/2', 'files 1/2', 'files 2/2']);
    expect(projects().map((p) => p.id)).toEqual(['infamousvague/attackfm']);
    // The files as raw text, the rest as GitHub's JSON, and no token asked for when none was kept.
    const contents = fetcher.mock.calls.filter(([url]) => String(url).includes('/contents/'));
    expect(contents.map(([url]) => String(url))).toEqual([
      'https://api.github.com/repos/InfamousVague/AttackFM/contents/README.md?ref=main',
      'https://api.github.com/repos/InfamousVague/AttackFM/contents/package.json?ref=main',
    ]);
    expect(new Headers(contents[0]![1]?.headers).get('Accept')).toBe('application/vnd.github.raw+json');
    expect(new Headers(fetcher.mock.calls[0]![1]?.headers).get('Authorization')).toBeNull();
  });

  it('skips a file that will not read rather than failing the project, and falls back to the description', async () => {
    // The README is listed but will not read when it is asked for.
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.includes('/contents/')) return new Response(null, { status: 500 });
        if (url.endsWith('recursive=1')) return Response.json({ tree: [{ path: 'README.md', type: 'blob' }] });
        return Response.json({ default_branch: 'main', description: 'A radio.', html_url: 'u', full_name: 'InfamousVague/AttackFM' });
      }),
    );
    const project = await addProject('infamousvague/attackfm', () => undefined);
    expect(project.pack).toBe('A radio.');
  });

  it('sends the token kept on this phone, trimmed, and forgets it when it is cleared', async () => {
    const fetcher = github();
    setGithubToken('  ghp_secret  ');
    expect(githubToken()).toBe('ghp_secret');
    await addProject('infamousvague/attackfm', () => undefined);
    expect(new Headers(fetcher.mock.calls[0]![1]?.headers).get('Authorization')).toBe('Bearer ghp_secret');
    setGithubToken('   ');
    expect(githubToken()).toBe('');
    expect(localStorage.getItem('glyph-github-token')).toBeNull();
  });

  it('says what GitHub refused, as a person would need to hear it', async () => {
    github({ status: 404 });
    await expect(addProject('o/r', () => undefined)).rejects.toThrow('GitHub can’t find that repo. If it’s private, add a token.');
    setGithubToken('ghp_secret');
    await expect(addProject('o/r', () => undefined)).rejects.toThrow('GitHub can’t find that repo with this token.');
    github({ status: 401 });
    await expect(addProject('o/r', () => undefined)).rejects.toThrow('GitHub didn’t accept that token.');
    github({ status: 403 });
    await expect(addProject('o/r', () => undefined)).rejects.toThrow('GitHub is limiting requests right now. Try again in a while, or add a token.');
    github({ status: 500 });
    await expect(addProject('o/r', () => undefined)).rejects.toThrow('GitHub answered 500.');
    await expect(addProject('not a repo', () => undefined)).rejects.toThrow('That doesn’t look like a GitHub repo. Paste a link like github.com/owner/repo.');
    expect(projects()).toEqual([]);
  });
});

describe('the briefing on a phone', () => {
  it('is the chosen model’s, when that model is on the phone', async () => {
    native = true;
    present = ['qwen3.5-2b', 'qwen3.5-9b'];
    setPreferences({ formatModel: 'qwen3.5-9b' });
    written = '  AttackFM is a radio for bands.  ';
    github();
    const steps: string[] = [];
    const project = await addProject('infamousvague/attackfm', (step) => steps.push(step.kind === 'distilling' ? `${step.model}: ${step.text}` : step.kind));
    expect(project).toMatchObject({ pack: 'AttackFM is a radio for bands.', packModel: 'qwen3.5-9b' });
    expect(asked[0]!.model).toBe('qwen3.5-9b');
    expect(asked[0]!.prompt).toContain('Repository: InfamousVague/AttackFM');
    expect(asked[0]!.prompt).toContain('--- README.md ---');
    expect(steps).toContain('Qwen3.5 9B: AttackFM is');
  });

  it('is the smallest model on the phone when the chosen one is not there', async () => {
    native = true;
    present = ['qwen3.5-9b', 'qwen3.5-2b'];
    setPreferences({ formatModel: 'qwen3.5-4b' });
    written = 'A radio.';
    github();
    expect((await addProject('infamousvague/attackfm', () => undefined)).packModel).toBe('qwen3.5-2b');
  });

  it('keeps the README’s words when the model fails or writes nothing', async () => {
    native = true;
    present = ['qwen3.5-4b'];
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    try {
      written = new Error('out of memory');
      github();
      expect(await addProject('infamousvague/attackfm', () => undefined)).toMatchObject({ pack: '# AttackFM\n\nA radio for bands.', packModel: null });
      written = '   ';
      expect(await addProject('infamousvague/attackfm', () => undefined)).toMatchObject({ packModel: null });
    } finally {
      warn.mockRestore();
    }
  });
});

describe('what a note is linked to', () => {
  async function added() {
    github();
    return addProject('infamousvague/attackfm', () => undefined);
  }

  it('gives a linked note the project as context for the model, and its version', async () => {
    const project = await added();
    expect(projectContextFor('n1')).toBeNull();
    expect(projectContextVersion('n1')).toBe(0);
    linkProject('n1', project.id);
    expect(projectFor('n1')?.id).toBe(project.id);
    expect(projectContextFor('n1')).toBe(
      'This note is about the project InfamousVague/AttackFM. What is known about it, for spelling names and understanding terms (do not add any of it to the note):\n\n# AttackFM\n\nA radio for bands.',
    );
    expect(projectContextVersion('n1')).toBe(project.packedAt);
    linkProject('n1', null);
    expect(projectFor('n1')).toBeNull();
  });

  it('keeps one copy of a project read twice, the newest first', async () => {
    await added();
    await added();
    expect(projects()).toHaveLength(1);
  });

  it('unlinks every note from a project that is removed, and leaves the rest linked', async () => {
    const project = await added();
    localStorage.setItem('glyph-github-projects', JSON.stringify([...projects(), { ...project, id: 'o/other', owner: 'o', repo: 'other' }]));
    linkProject('n1', project.id);
    linkProject('n2', project.id);
    linkProject('n3', 'o/other');
    removeProject(project.id);
    expect(projects().map((p) => p.id)).toEqual(['o/other']);
    expect(projectFor('n1')).toBeNull();
    expect(projectFor('n2')).toBeNull();
    expect(projectFor('n3')?.id).toBe('o/other');
  });

  it('reads a kept list from another shape as no projects rather than failing', () => {
    localStorage.setItem('glyph-github-projects', JSON.stringify([{ id: 'x' }, 'nonsense', null]));
    expect(projects()).toEqual([]);
    localStorage.setItem('glyph-github-projects', JSON.stringify({ not: 'a list' }));
    expect(projects()).toEqual([]);
  });
});
