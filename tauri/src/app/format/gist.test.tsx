import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ModelInfo, Output, RunOptions } from '../core/ai.ts';
import { makeNote } from '../../test/notes.ts';
import { show, unmount, waitUntil } from '../../test/render.tsx';
import { bodyHash } from './bodyHash.ts';
import { keepGist, readGist } from './results.ts';

/** The phone, stood in for: a model present, and what the runner asked it (core/ai.ts `generate`). */
const phone = vi.hoisted(() => ({ runs: [] as RunOptions[] }));
vi.mock('../core/tauri.ts', () => ({ isTauri: () => true, invoke: () => Promise.reject(new Error('no binary in a test')) }));
vi.mock('../core/ai.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/ai.ts')>()),
  listModels: async (): Promise<ModelInfo[]> => [{ id: 'qwen3.5-2b', file: 'qwen3.5-2b.gguf', bytes: 1, present: true, path: '/m' }],
  generate: (options: RunOptions) => {
    phone.runs.push(options);
    const output: Output = { text: 'A walk to the square', promptTokens: 10, outputTokens: 5, ms: 100, cachedTokens: 0, prefillMs: 10, loadMs: 10, tokensPerSecond: 9, truncated: false };
    return { done: Promise.resolve(output), cancel: () => undefined };
  },
}));

const { gistFor, gistStands, runGists, tidyGist, useGists } = await import('./gist.ts');

describe('the gist as a card line', () => {
  it('takes the first line, bare: no heading marks, bullets, quotes, bold or closing punctuation', () => {
    expect(tidyGist('# Call the plumber by Thursday.\n\nMore.')).toBe('Call the plumber by Thursday');
    expect(tidyGist('- "Pick up **eggs** and coffee!"\n')).toBe('Pick up eggs and coffee');
    expect(tidyGist('```\nPlans for the weekend\n```')).toBe('Plans for the weekend');
    expect(tidyGist('\n\n   Errands for tomorrow   \n')).toBe('Errands for tomorrow');
    expect(tidyGist('')).toBe('');
  });

  it('cuts a long answer at a word and says so', () => {
    const long = 'A very long line that goes on and on about the plumber and the tap and the eggs and the coffee and the cabin and the ferry';
    const cut = tidyGist(long);
    expect(cut.length).toBeLessThanOrEqual(91);
    expect(cut.endsWith('…')).toBe(true);
    expect(cut).not.toMatch(/\s…$/);
  });
});

describe('what the home page shows', () => {
  beforeEach(() => localStorage.clear());

  it('shows a gist while it stands for the note: the same body, or one changed in a small way', () => {
    const body = 'things for tomorrow\n- milk and the good coffee from the corner shop\n- call the dentist before ten\n';
    keepGist('n1', { text: 'Plans for tomorrow', for: bodyHash(body), model: 'qwen3.5-2b', len: body.length, head: 'things for tomorrow' });
    expect(gistFor('n1', body)).toBe('Plans for tomorrow');
    // A fixed word: still stands.
    expect(gistFor('n1', body.replace('good coffee', 'nice coffee'))).toBe('Plans for tomorrow');
    // A new paragraph, or a new first line: a meaningful change, asked again.
    expect(gistFor('n1', `${body}\nAnd the whole plan for the weekend trip to the cabin with Sam.\n`)).toBeNull();
    expect(gistFor('n1', body.replace('things for tomorrow', 'plans for the week'))).toBeNull();
    expect(gistFor('n2', 'anything')).toBeNull();
  });

  it('asks again for a gist kept before lengths were recorded, unless the body is the same', () => {
    keepGist('n3', { text: 'Old', for: bodyHash('a note'), model: 'qwen3.5-2b' });
    expect(gistStands({ for: bodyHash('a note') }, 'n3', 'a note')).toBe(true);
    expect(gistStands({ for: bodyHash('a note') }, 'n3', 'a note!')).toBe(false);
  });
});

describe('the runner', () => {
  beforeEach(() => {
    localStorage.clear();
    phone.runs.length = 0;
  });

  it('gives the model the words after the front matter, and keeps the gist against those words', async () => {
    const words = '# A walk\n\nDown to the square and back, before the rain.\n';
    const tagged = `---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n${words}`;
    const Probe = () => {
      useGists([makeNote('n1', tagged, { updatedAt: 1 })]);
      return null;
    };
    show(<Probe />);
    await runGists();
    await waitUntil(() => expect(phone.runs).toHaveLength(1));
    expect(phone.runs[0]!.prompt).toBe(words);
    expect(phone.runs[0]!.prompt).not.toContain('location:');
    await waitUntil(() => expect(readGist('n1')?.text).toBe('A walk to the square'));
    expect(readGist('n1')).toMatchObject({ for: bodyHash(words), len: words.length, head: '# A walk' });
    // A place written in changes the note but not its words: the gist still stands.
    expect(gistFor('n1', tagged.replace('Trafalgar Square, London', 'London'))).toBe('A walk to the square');
    expect(gistFor('n1', words)).toBe('A walk to the square');
    unmount();
  });

  it('gives the model a note’s blanks taken out and its fills as words (docs/DESIGN.md §145)', async () => {
    const body = '# Tokyo\n\nCheapest on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day) and {?which airport} too.\n';
    const Probe = () => {
      useGists([makeNote('n2', body, { updatedAt: 1 })]);
      return null;
    };
    show(<Probe />);
    await runGists();
    await waitUntil(() => expect(phone.runs).toHaveLength(1));
    expect(phone.runs[0]!.prompt).toBe('# Tokyo\n\nCheapest on midweek and too.\n');
    unmount();
  });
});
