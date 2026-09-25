import type { Output, Progress, Run, RunOptions } from '../core/ai.ts';

/**
 * The review's model, played by a script in a browser (`?review`): a thought
 * streamed, then findings from the word changes in the prompt. Handed to the
 * engine (ai/runs.ts `simulateRuns`) for the review's run, so the strip, the
 * card and the landing can all be tried without a phone.
 */
export function simulatedReview(options: RunOptions): Run {
  let cancelled = false;
  const thought = [
    'Thinking Process:',
    '',
    '1. Words. The two transcripts disagree in a few places. The slower model heard "seek bar" where the fast one heard "seat bar"; a seek bar is the scrubber in a player, so "seek" is right.',
    '2. Structure. The heading names the note, the to-dos are things to do, nothing else looks like a list.',
    '3. Commands. Each "hey Ghost" command landed where its words said.',
    '4. Names. HelloTrade is written as one word in the note titles.',
  ].join('\n');
  const changes = options.prompt.match(/\[([^\]]*?) → ([^\]]*?)\]/g) ?? [];
  const note = /AS SAVED:\n([\s\S]*)$/.exec(options.prompt)?.[1] ?? '';
  const findings = changes.flatMap((pair) => {
    const [, heard = '', careful = ''] = /\[([^\]]*?) → ([^\]]*?)\]/.exec(pair) ?? [];
    const find = heard.replace(/[.,;:!?]+$/, '');
    const line = note.split('\n').find((l) => l.toLowerCase().includes(find.toLowerCase()));
    if (!find || !line) return [];
    return [{ check: 'words', what: `“${careful.replace(/[.,;:!?]+$/, '')}”, not “${find}”`, why: 'The slower speech model heard it this way, and it fits the note.', find: line, replace: line.replace(new RegExp(find, 'i'), careful.replace(/[.,;:!?]+$/, '')) }];
  });
  const text = `<think>\n${thought}\n</think>\n\n${JSON.stringify(findings)}`;
  const done = (async (): Promise<Output> => {
    const started = Date.now();
    for (let at = 0; at <= text.length; at += 6) {
      if (cancelled) throw new Error('cancelled');
      await new Promise((resolve) => window.setTimeout(resolve, 30));
      const progress: Progress = { id: 'sim', phase: 'generating', promptTokens: 0, promptTokensDone: 0, outputTokens: Math.round(at / 4), tokensPerSecond: 11, elapsedMs: Date.now() - started, partial: text.slice(0, at), thinking: true };
      options.onProgress(progress);
    }
    return { text, promptTokens: 0, outputTokens: Math.round(text.length / 4), ms: Date.now() - started, cachedTokens: 0, prefillMs: 0, loadMs: 0, tokensPerSecond: 11, truncated: false, thinking: true };
  })();
  return { done, cancel: () => void (cancelled = true) };
}
