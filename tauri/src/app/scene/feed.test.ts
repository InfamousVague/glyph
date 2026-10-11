import { describe, expect, it } from 'vitest';
import type { RunState } from '../ai/runs.ts';
import { feedOf, findingsSoFar, noteLines, paneWindow, phrasesOf, thoughtLines } from './feed.ts';
import { PANE_LINES } from './steps.ts';

/**
 * What scrolls through the phone: the transcript's phrases, the note's lines, the thought and the findings, each
 * line by an absolute index that never moves.
 */

function run(over: Partial<RunState> = {}): RunState {
  return {
    id: 'run-1',
    noteId: 'n',
    kind: 'review',
    instruction: null,
    model: 'qwen3.5-4b',
    scope: null,
    phase: 'generating',
    lines: [],
    partial: '',
    thought: '',
    text: null,
    promptTokens: 0,
    promptTokensDone: 0,
    outputTokens: 0,
    maxTokens: 1900,
    tokensPerSecond: 0,
    elapsedMs: 0,
    hardware: null,
    truncated: false,
    message: null,
    startedAt: 0,
    endedAt: null,
    hash: null,
    ...over,
  };
}

const heard = 'Groceries for the week. Milk, eggs and coffee. Hey Ghost, add a task call the plumber about the seat bar. Then the garden.';
const body = '# Groceries\n\n- Milk, eggs and coffee\n- [ ] Call the plumber about the seat bar\n\nThen the garden.';

describe('phrases', () => {
  it('split at sentence ends, and about every fourteen words where there are none', () => {
    expect(phrasesOf(heard)).toEqual(['Groceries for the week.', 'Milk, eggs and coffee.', 'Hey Ghost, add a task call the plumber about the seat bar.', 'Then the garden.']);
    const long = Array.from({ length: 30 }, (_, i) => `word${i + 1}`).join(' ');
    const runs = phrasesOf(long);
    expect(runs.map((r) => r.split(' ').length)).toEqual([14, 16]);
    expect(runs.join(' ')).toBe(long);
  });

  it('keep a numbered line together and join a phrase of a word or two to the next', () => {
    expect(thoughtLines('1. Words. The two transcripts disagree in a few places. 2. Structure. The heading names the note.')).toEqual([
      '1. Words. The two transcripts disagree in a few places.',
      '2. Structure. The heading names the note.',
    ]);
    expect(phrasesOf('Thinking Process:\n\nFirst, the words. Is "seat bar" right? Probably not.')).toEqual(['Thinking Process: First, the words.', 'Is "seat bar" right?', 'Probably not.']);
  });

  it('leave a thought’s sentence whole, and cut only one past thirty words, at a clause end', () => {
    const twenty = 'The slower model heard "seek bar" where the fast one heard "seat bar", a seek bar is the scrubber in a player, so seek is right.';
    expect(thoughtLines(twenty)).toEqual([twenty]);
    // Past thirty words the sentence is cut at its semicolons and colons, never every fourteen words.
    const long = 'The slower model heard "seek bar" where the fast one heard "seat bar"; a seek bar is the scrubber in a player, so "seek" is right, and the task says the same words: the two agree once the spelling is put right.';
    expect(thoughtLines(long)).toEqual([
      'The slower model heard "seek bar" where the fast one heard "seat bar";',
      'a seek bar is the scrubber in a player, so "seek" is right, and the task says the same words:',
      'the two agree once the spelling is put right.',
    ]);
    // With no clause end, a long sentence is one line and left to wrap.
    const plain = Array.from({ length: 40 }, (_, i) => `word${i + 1}`).join(' ');
    expect(thoughtLines(plain)).toEqual([plain]);
  });

  it('drop the note’s blank lines and its Markdown marks', () => {
    expect(noteLines(body)).toEqual(['Groceries', 'Milk, eggs and coffee', 'Call the plumber about the seat bar', 'Then the garden.']);
    expect(noteLines('## Two\n> quoted\n1. first\n* [x] done\n- - nested')).toEqual(['Two', 'quoted', 'first', 'done', 'nested']);
  });
});

describe('the feed', () => {
  it('shows the transcript through the stages, the head at the listen’s share of it', () => {
    const stage = { what: 'Listening again', detail: '', percent: 50 };
    const feed = feedOf({ stage, run: null, heard, body });
    expect(feed.mode).toBe('transcript');
    expect(feed.lines.map((l) => l.at)).toEqual([0, 1, 2, 3]);
    expect(feed.current).toBe(2);
    expect(feedOf({ stage: { ...stage, percent: 0 }, run: null, heard, body }).current).toBe(0);
    expect(feedOf({ stage: { ...stage, percent: 100 }, run: null, heard, body }).current).toBe(3);
    // Comparing, and a run not yet reading: every phrase, the head at the last.
    expect(feedOf({ stage: { what: 'Comparing', detail: '', percent: null }, run: null, heard, body }).current).toBe(3);
    expect(feedOf({ stage: null, run: run({ phase: 'loading' }), heard, body })).toMatchObject({ mode: 'transcript', current: 3 });
    expect(feedOf({ stage: null, run: null, heard: '', body })).toEqual({ lines: [], current: null, mode: 'transcript' });
  });

  it('walks the transcript again and then the note’s lines while the model reads, by its share of the prompt', () => {
    const reading = (done: number) => feedOf({ stage: null, run: run({ phase: 'prefill', promptTokens: 1000, promptTokensDone: done }), heard, body });
    const feed = reading(0);
    expect(feed.mode).toBe('reading');
    expect(feed.lines.length).toBe(8);
    expect(feed.lines[4]).toEqual({ at: 4, text: 'Groceries' });
    expect(feed.current).toBe(0);
    expect(reading(500).current).toBe(4);
    expect(reading(1000).current).toBe(7);
    // Before the first tick there is no share: the head stays at the top.
    expect(feedOf({ stage: null, run: run({ phase: 'prefill' }), heard, body }).current).toBe(0);
  });

  it('wraps the thought by sentence, the tail the line under the pen', () => {
    const feed = feedOf({ stage: null, run: run({ thought: 'The two transcripts disagree in a few places. The slower model heard "seek bar" where the fast' }), heard, body });
    expect(feed.mode).toBe('thought');
    expect(feed.lines).toEqual([
      { at: 0, text: 'The two transcripts disagree in a few places.' },
      { at: 1, text: 'The slower model heard "seek bar" where the fast' },
    ]);
    expect(feed.current).toBe(1);
  });

  it('reads the findings’ words out of the JSON as it is written, the open one typing in, and never the JSON', () => {
    const thought = 'One sentence of thought.';
    const partial = '[{"check": "words", "what": "“seek bar”, not “seat bar”", "why": "It fits."}, {"check": "structure", "what": "The to-dos are a li';
    const feed = feedOf({ stage: null, run: run({ thought, partial }), heard, body });
    expect(feed.mode).toBe('findings');
    expect(feed.lines).toEqual([
      { at: 0, text: 'One sentence of thought.' },
      { at: 1, text: '“seek bar”, not “seat bar”', strong: true },
      { at: 2, text: 'The to-dos are a li', strong: true },
    ]);
    expect(feed.current).toBe(2);
    expect(feed.lines.some((l) => l.text.includes('{') || l.text.includes('"check"'))).toBe(false);
    // Lines the engine finished, and the last complete finding with nothing open: the head on the last finding.
    const done = feedOf({ stage: null, run: run({ thought, lines: ['[{"what": "One", "why": "x"},'], partial: ' {"what": "Two", "why": "y"}]' }), heard, body });
    expect(done.lines.slice(1)).toEqual([
      { at: 1, text: 'One', strong: true },
      { at: 2, text: 'Two', strong: true },
    ]);
    expect(done.current).toBe(2);
  });

  it('unescapes a finding’s words and gives the open one as the pen line', () => {
    expect(findingsSoFar('[{"what": "Say \\"hello\\" here", "why": "x"}, {"what": "Then the g')).toEqual({ done: ['Say "hello" here'], open: 'Then the g' });
    expect(findingsSoFar('[{"what": "A"}, {"what": "B"}]')).toEqual({ done: ['A', 'B'], open: null });
    expect(findingsSoFar('[{"check": "words", ')).toEqual({ done: [], open: null });
  });

  it('shows another kind’s prose as it lands', () => {
    const feed = feedOf({ stage: null, run: run({ kind: 'summarize', lines: ['## Summary', 'The point.'], partial: 'And the' }), heard, body });
    expect(feed.mode).toBe('prose');
    expect(feed.lines.map((l) => l.text)).toEqual(['## Summary', 'The point.', 'And the']);
    expect(feed.current).toBe(2);
  });

  it('keeps every line’s key as the window slides', () => {
    const many = Array.from({ length: 60 }, (_, i) => `Sentence number ${i + 1} here.`).join(' ');
    const at = (percent: number) => feedOf({ stage: { what: 'Listening again', detail: '', percent }, run: null, heard: many, body: '' });
    const early = paneWindow(at(10));
    expect(early.length).toBe(PANE_LINES);
    expect(early[0]?.at).toBe(0);
    const mid = paneWindow(at(50));
    expect(mid.length).toBe(PANE_LINES);
    // Sixteen before the head (line 30), the head, and seven after.
    expect(mid[0]?.at).toBe(14);
    expect(mid[16]?.at).toBe(30);
    expect(mid.at(-1)?.at).toBe(37);
    // The lines kept between two windows keep their keys.
    const next = paneWindow(at(52));
    for (const line of next) if (line.at >= 14 && line.at <= 37) expect(mid.find((m) => m.at === line.at)?.text).toBe(line.text);
    const late = paneWindow(at(100));
    expect(late.at(-1)?.at).toBe(59);
    expect(late.length).toBe(PANE_LINES);
    // A streaming mode keeps the newest.
    const thought = Array.from({ length: 40 }, (_, i) => `Thought ${i + 1} is here.`).join(' ');
    const stream = paneWindow(feedOf({ stage: null, run: run({ thought }), heard: '', body: '' }));
    expect(stream.length).toBe(PANE_LINES);
    expect(stream.at(-1)?.at).toBe(39);
  });
});
