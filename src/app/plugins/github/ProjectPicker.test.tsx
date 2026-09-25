import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { buttonSaying, press, show, typeInto, waitUntil } from '../../../test/render.tsx';
import type { Project, ReadStep } from './repos.ts';

/**
 * The GitHub repo picker on a note's cog: a kept repo linked with a tap, and a new one read with its steps said as
 * they happen and linked once it is kept. Reading a repo is stood in for (projects.test.ts is the reading itself).
 */

const kept = (id: string, over: Partial<Project> = {}): Project => {
  const [owner = 'o', repo = 'r'] = id.split('/');
  return { id, owner, repo, url: '', branch: 'main', description: '', files: [], pack: 'A briefing.', packModel: null, packedAt: 1, ...over };
};

/** The reading: its steps as the test lets them out, and then the project, or a failure. */
let reading: { steps: ReadStep[]; then: Project | Error } = { steps: [], then: kept('o/new') };
vi.mock('./repos.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('./repos.ts')>();
  return {
    ...real,
    addProject: async (_input: string, onStep: (step: ReadStep) => void) => {
      for (const step of reading.steps) onStep(step);
      await Promise.resolve();
      if (reading.then instanceof Error) throw reading.then;
      localStorage.setItem('glyph-github-projects', JSON.stringify([reading.then, ...real.projects()]));
      return reading.then;
    },
  };
});

const { ProjectPicker } = await import('./ProjectPicker.tsx');
const { projectFor, githubToken } = await import('./repos.ts');

beforeEach(() => {
  localStorage.clear();
  reading = { steps: [], then: kept('o/new') };
});

describe('the repo picker', () => {
  it('links a kept repo with a tap, ticks it, and unlinks it again', () => {
    localStorage.setItem('glyph-github-projects', JSON.stringify([kept('o/app', { packModel: 'qwen3.5-4b' })]));
    const onDone = vi.fn();
    const host = show(<ProjectPicker noteId="n1" onDone={onDone} />);
    expect(host.textContent).toContain('Read by qwen3.5-4b.');
    press(buttonSaying(host, 'o/app'));
    expect(projectFor('n1')?.id).toBe('o/app');
    expect(onDone).toHaveBeenCalledOnce();
    expect(buttonSaying(host, 'o/app')?.getAttribute('aria-pressed')).toBe('true');
    press(buttonSaying(host, 'Don’t link a project'));
    expect(projectFor('n1')).toBeNull();
  });

  it('reads a pasted repo, keeps the token typed with it, and links the repo once it is kept', async () => {
    reading = { steps: [{ kind: 'reading' }, { kind: 'files', done: 1, total: 3 }], then: kept('o/new') };
    const onDone = vi.fn();
    const host = show(<ProjectPicker noteId="n1" onDone={onDone} />);
    const readAndLink = buttonSaying(host, 'Read and link')!;
    expect(readAndLink.disabled).toBe(true);
    typeInto(host.querySelector<HTMLInputElement>('input[type="url"]')!, 'github.com/o/new');
    press(buttonSaying(host, 'Private repo?'));
    typeInto(host.querySelector<HTMLInputElement>('input[type="password"]')!, 'ghp_secret');
    await act(async () => readAndLink.click());
    await waitUntil(() => expect(projectFor('n1')?.id).toBe('o/new'));
    expect(githubToken()).toBe('ghp_secret');
    expect(onDone).toHaveBeenCalledOnce();
    expect(host.textContent).toContain('o/new');
  });

  it('says why a repo would not read, and links nothing', async () => {
    reading = { steps: [{ kind: 'reading' }], then: new Error('GitHub can’t find that repo. If it’s private, add a token.') };
    const host = show(<ProjectPicker noteId="n1" onDone={() => undefined} />);
    typeInto(host.querySelector<HTMLInputElement>('input[type="url"]')!, 'o/missing');
    await act(async () => buttonSaying(host, 'Read and link')!.click());
    await waitUntil(() => expect(host.textContent).toContain('GitHub can’t find that repo. If it’s private, add a token.'));
    expect(projectFor('n1')).toBeNull();
    // Ready to try again.
    expect(buttonSaying(host, 'Read and link')?.disabled).toBe(false);
  });
});
