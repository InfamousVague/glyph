import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Progress } from '../core/ai.ts';
import { readArray } from '../review/findings.ts';
import { reviewMessage } from '../review/prompt.ts';
import { simulatedReview } from './reviewSimulation.ts';

/**
 * `?review` in a browser plays the review's model with a script, and the script reads its findings back out of the
 * prompt the page really sends (review/prompt.ts `reviewMessage`): the `[heard → careful]` pairs and the note after
 * "AS SAVED:". A change to either format empties the simulation without a word, so this holds the two together.
 */
function prompt(body: string, pairs: { heard: string; careful: string }[]): string {
  return reviewMessage({
    title: 'Player',
    body,
    heard: 'fix the seat bar',
    careful: 'fix the seek bar',
    changes: pairs.map((p) => ({ ...p, before: 'the', after: '' })),
    commands: [],
    titles: ['Player'],
    touched: [],
  });
}

beforeEach(() => {
  vi.useFakeTimers();
});
afterEach(() => {
  vi.useRealTimers();
});

describe('the review’s model, played by a script', () => {
  it('streams its thinking, then answers with a finding for each word the note still has', async () => {
    const reports: Progress[] = [];
    const run = simulatedReview({
      model: 'qwen3.5-4b',
      temperature: 0.2,
      system: '',
      prompt: prompt('# Player\n- [ ] Fix the seat bar.\n', [
        { heard: 'seat.', careful: 'seek.' },
        { heard: 'nowhere', careful: 'else' },
      ]),
      maxTokens: 1000,
      onProgress: (progress) => reports.push(progress),
    });
    await vi.runAllTimersAsync();
    const output = await run.done;
    expect(output.thinking).toBe(true);
    expect(reports.length).toBeGreaterThan(10);
    expect(reports.every((r) => r.phase === 'generating' && r.thinking)).toBe(true);
    // What streams is the answer as far as it has got, a little more each time.
    const partials = reports.map((r) => r.partial);
    expect(partials.every((partial, i) => output.text.startsWith(partial) && partial.length >= (partials[i - 1]?.length ?? 0))).toBe(true);
    expect(output.text.length - (partials.at(-1)?.length ?? 0)).toBeLessThan(6);
    const [thought, answer] = output.text.split('</think>');
    expect(thought).toContain('Thinking Process:');
    expect(readArray(answer ?? '')).toEqual([
      { check: 'words', what: '“seek”, not “seat”', why: expect.any(String), find: '- [ ] Fix the seat bar.', replace: '- [ ] Fix the seek bar.' },
    ]);
  });

  it('takes the words it looks for as words, whatever their punctuation', async () => {
    const run = simulatedReview({ model: 'qwen3.5-4b', system: '', temperature: 0.2, prompt: prompt('Call (Sam) about it\n', [{ heard: '(Sam', careful: 'Sam' }]), maxTokens: 1000, onProgress: () => undefined });
    await vi.runAllTimersAsync();
    const answer = (await run.done).text.split('</think>')[1] ?? '';
    expect(readArray(answer)).toMatchObject([{ find: 'Call (Sam) about it', replace: 'Call Sam) about it' }]);
  });

  it('stops when it is cancelled', async () => {
    const run = simulatedReview({ model: 'qwen3.5-4b', system: '', temperature: 0.2, prompt: prompt('x\n', []), maxTokens: 1000, onProgress: () => undefined });
    run.cancel();
    const ended = run.done.catch((failure: unknown) => failure);
    await vi.runAllTimersAsync();
    expect(await ended).toEqual(new Error('cancelled'));
  });
});
