import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Output, Progress, RunOptions } from '../core/ai.ts';

/**
 * A model that answers when the test says so: `generate` is the seam, and each
 * call hands back its progress callback and a way to end it.
 */
interface Fake {
  options: RunOptions;
  report: (progress: Partial<Progress>) => void;
  finish: (text: string, extra?: Partial<Output>) => void;
  fail: (message: string) => void;
  cancelled: boolean;
}
const fakes: Fake[] = [];

vi.mock('../core/ai.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/ai.ts')>();
  return {
    ...real,
    generate: (options: RunOptions) => {
      let resolve: (output: Output) => void = () => undefined;
      let reject: (failure: Error) => void = () => undefined;
      const done = new Promise<Output>((res, rej) => {
        resolve = res;
        reject = rej;
      });
      const fake: Fake = {
        options,
        cancelled: false,
        report: (progress) =>
          options.onProgress({
            id: 'x',
            phase: 'generating',
            promptTokens: 100,
            promptTokensDone: 100,
            outputTokens: 10,
            tokensPerSecond: 12,
            elapsedMs: 1000,
            partial: '',
            ...progress,
          }),
        finish: (text, extra = {}) =>
          resolve({ text, promptTokens: 100, outputTokens: 20, ms: 2000, cachedTokens: 0, prefillMs: 100, loadMs: 100, tokensPerSecond: 12, truncated: false, ...extra }),
        fail: (message) => reject(new Error(message)),
      };
      fakes.push(fake);
      return {
        done,
        cancel: () => {
          fake.cancelled = true;
          reject(new Error('cancelled'));
        },
      };
    },
  };
});

const { allLines, cancelRun, dismissRun, forgetAllRuns, isRunning, runFor, splitLines, startRun, subscribeRuns } = await import('./runs.ts');
const { runsOf } = await import('./log.ts');

const tick = () => new Promise((r) => setTimeout(r, 0));

const request = (noteId: string) => ({ noteId, kind: 'format' as const, model: 'qwen3.5-4b', system: 'Format.', prompt: 'hello', maxTokens: 200 });

beforeEach(() => {
  localStorage.clear();
  fakes.length = 0;
});

afterEach(() => {
  forgetAllRuns();
});

describe('cutting the text at whole lines', () => {
  it('keeps the line under the pen apart from the lines that are finished', () => {
    expect(splitLines('')).toEqual({ lines: [], partial: '' });
    expect(splitLines('# Trip')).toEqual({ lines: [], partial: '# Trip' });
    expect(splitLines('# Trip\n')).toEqual({ lines: ['# Trip'], partial: '' });
    expect(splitLines('# Trip\n\n- [ ] Call the plum')).toEqual({ lines: ['# Trip', ''], partial: '- [ ] Call the plum' });
  });

  it('reads a finished text as all its lines, the trailing newline not one of them', () => {
    expect(allLines('# Trip\n\n- a\n')).toEqual(['# Trip', '', '- a']);
    expect(allLines('')).toEqual([]);
  });
});

describe('a run', () => {
  it('streams whole lines as they finish, then lands the whole text', async () => {
    const seen: string[][] = [];
    const off = subscribeRuns((run) => seen.push([...run.lines]));
    const handle = startRun(request('n1'));
    await tick();
    expect(runFor('n1')?.phase).toBe('loading');
    const fake = fakes[0]!;
    fake.report({ phase: 'prefill', promptTokensDone: 40 });
    expect(runFor('n1')?.phase).toBe('prefill');
    expect(runFor('n1')?.promptTokensDone).toBe(40);
    fake.report({ partial: '# Trip\n\n- [ ] Call the plum' });
    expect(runFor('n1')?.lines).toEqual(['# Trip', '']);
    expect(runFor('n1')?.partial).toBe('- [ ] Call the plum');
    fake.report({ partial: '# Trip\n\n- [ ] Call the plumber.\n- [ ] Eggs' });
    expect(runFor('n1')?.lines).toEqual(['# Trip', '', '- [ ] Call the plumber.']);
    fake.finish('# Trip\n\n- [ ] Call the plumber.\n- [ ] Eggs and coffee.\n');
    const last = await handle.done;
    expect(last.phase).toBe('done');
    expect(last.text).toBe('# Trip\n\n- [ ] Call the plumber.\n- [ ] Eggs and coffee.\n');
    expect(last.lines).toEqual(['# Trip', '', '- [ ] Call the plumber.', '- [ ] Eggs and coffee.']);
    expect(last.partial).toBe('');
    // Lines only ever grew.
    for (let i = 1; i < seen.length; i += 1) expect(seen[i]!.length).toBeGreaterThanOrEqual(seen[i - 1]!.length);
    off();
    expect(runsOf('n1')[0]).toMatchObject({ kind: 'format', model: 'qwen3.5-4b', outcome: 'done' });
  });

  it('puts the links and tables back with the caller’s restore, and tidies once at the end', async () => {
    const handle = startRun({ ...request('n2'), restore: (text, final) => (final ? `${text.trim()}!\n` : text.replace(/link-1/g, 'https://a')) });
    await tick();
    fakes[0]!.report({ partial: 'see [a](link-1)\nmore' });
    expect(runFor('n2')?.lines).toEqual(['see [a](https://a)']);
    fakes[0]!.finish('see [a](link-1)\nmore\n');
    const last = await handle.done;
    expect(last.text).toBe('see [a](link-1)\nmore!\n');
  });

  it('keeps a thinking model’s reasoning apart from its answer', async () => {
    const handle = startRun({ ...request('n3'), think: true });
    await tick();
    fakes[0]!.report({ partial: '<think>Is the name right?', thinking: true });
    expect(runFor('n3')?.thought).toBe('Is the name right?');
    expect(runFor('n3')?.lines).toEqual([]);
    fakes[0]!.report({ partial: '<think>Is the name right?</think>[]\n', thinking: true });
    expect(runFor('n3')?.lines).toEqual(['[]']);
    fakes[0]!.finish('<think>Is the name right?</think>[]\n', { thinking: true });
    const last = await handle.done;
    expect(last.thought).toBe('Is the name right?');
    expect(last.text).toBe('[]\n');
  });

  it('waits behind a run on another note, and goes once it ends', async () => {
    const first = startRun(request('a'));
    const second = startRun(request('b'));
    await tick();
    expect(fakes.length).toBe(1);
    expect(runFor('b')?.phase).toBe('queued');
    expect(isRunning('b')).toBe(true);
    fakes[0]!.finish('done a\n');
    await first.done;
    await tick();
    expect(fakes.length).toBe(2);
    expect(runFor('b')?.phase).toBe('loading');
    fakes[1]!.finish('done b\n');
    expect((await second.done).text).toBe('done b\n');
  });

  it('takes the place of an earlier run on the same note', async () => {
    const first = startRun(request('same'));
    await tick();
    const second = startRun({ ...request('same'), kind: 'summarize' });
    const ended = await first.done;
    expect(ended.phase).toBe('stopped');
    expect(fakes[0]!.cancelled).toBe(true);
    await tick();
    expect(runFor('same')?.kind).toBe('summarize');
    fakes[1]!.finish('short\n');
    expect((await second.done).phase).toBe('done');
  });

  it('stops when asked, and says so; and says why it failed', async () => {
    const handle = startRun(request('s'));
    await tick();
    fakes[0]!.report({ partial: 'one\ntwo' });
    await cancelRun('s');
    const last = await handle.done;
    expect(last.phase).toBe('stopped');
    expect(last.lines).toEqual(['one']);
    expect(last.text).toBeNull();
    expect(runsOf('s')[0]?.outcome).toBe('stopped');

    const failing = startRun(request('f'));
    await tick();
    fakes[1]!.fail('The model is not on this phone yet.');
    const failed = await failing.done;
    expect(failed.phase).toBe('failed');
    expect(failed.message).toBe('The model is not on this phone yet.');
    expect(runsOf('f')[0]).toMatchObject({ outcome: 'failed', message: 'The model is not on this phone yet.' });
  });

  it('stops a run that was still waiting without ever starting it', async () => {
    startRun(request('going'));
    const waiting = startRun(request('later'));
    await tick();
    await cancelRun('later');
    expect((await waiting.done).phase).toBe('stopped');
    expect(fakes.length).toBe(1);
    fakes[0]!.finish('x\n');
  });

  it('is put away once dismissed, and only once it has ended', async () => {
    const handle = startRun(request('d'));
    await tick();
    dismissRun('d');
    expect(runFor('d')).not.toBeNull();
    fakes[0]!.finish('x\n');
    await handle.done;
    dismissRun('d');
    expect(runFor('d')).toBeNull();
  });
});
