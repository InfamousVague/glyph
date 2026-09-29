import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { ToastOptions } from '@glacier/react';
import type { Output, Run, RunOptions } from '../../core/ai.ts';
import { blanksIn } from '../../core/blanks.ts';
import { createNote, getNote } from '../../core/store.ts';
import { runsOf } from '../log.ts';
import { forgetAllRuns, simulateRuns, startRun } from '../runs.ts';
import { applyChanges } from './edits.ts';
import { blankKey, fillOutcome, fillStatus, forgetFills, openForFills, pressFill, resumeParked, setFillWorld, startFills, type FillHost, type FillTarget } from './queue.ts';
import forecast from './recorded/forecast-lisbon.json';
import geocode from './recorded/geocode-lisbon.json';

/** A model the test answers: each generation waits until the test finishes it. */
interface Fake {
  options: RunOptions;
  finish: (text: string, extra?: Partial<Output>) => void;
}
let fakes: Fake[] = [];
const toasts: ToastOptions[] = [];
let stop: () => void = () => undefined;

beforeEach(() => {
  fakes = [];
  toasts.length = 0;
  localStorage.clear();
  simulateRuns((options): Run => {
    let resolve: (output: Output) => void = () => undefined;
    let reject: (failure: Error) => void = () => undefined;
    const done = new Promise<Output>((res, rej) => {
      resolve = res;
      reject = rej;
    });
    fakes.push({ options, finish: (text, extra = {}) => resolve({ text, promptTokens: 900, outputTokens: 12, ms: 1500, cachedTokens: 800, prefillMs: 100, loadMs: 0, tokensPerSecond: 20, truncated: false, ...extra }) });
    return { done, cancel: () => reject(new Error('cancelled')) };
  });
  setFillWorld({ now: () => new Date(2026, 8, 28, 12) });
  stop = startFills(
    (options) => void toasts.push(options),
    () => undefined,
  );
});

afterEach(() => {
  stop();
  simulateRuns(null);
  forgetAllRuns();
  forgetFills();
});

/** Waits for the queue to reach a state: every step of it is a promise. */
async function until(test: () => boolean): Promise<void> {
  for (let i = 0; i < 200 && !test(); i += 1) await new Promise((r) => setTimeout(r, 0));
  expect(test()).toBe(true);
}

/** An open note's editor, as a string: its ranges tracked by their start, its landings applied. */
function host(initial: string): FillHost & { body: string; lands: number; ranges: Map<string, { from: number; to: number }> } {
  const me = {
    body: initial,
    lands: 0,
    ranges: new Map<string, { from: number; to: number }>(),
    text: () => me.body,
    rangeOf: (key: string) => me.ranges.get(key) ?? null,
    track: (targets: readonly { key: string; from: number; to: number }[]) => targets.forEach((t) => me.ranges.set(t.key, { from: t.from, to: t.to })),
    land: (changes: readonly { from: number; to: number; insert: string }[], sign: { from: number; to: number; insert: string } | null) => {
      me.lands += 1;
      me.body = applyChanges(me.body, [...changes, ...(sign ? [sign] : [])]);
      return me.body;
    },
  };
  return me;
}

/** Every blank of `text` as a press's targets. */
function targets(text: string): FillTarget[] {
  const blanks = blanksIn(text);
  return blanks.map((b) => {
    const order = blanks.filter((o) => o.question === b.question && o.from < b.from).length;
    return { key: blankKey(b.question, order), question: b.question, order };
  });
}

const TOKYO = '# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}\n\nThe capital of Australia is {?}.';

describe('a press of Fill in an open note', () => {
  it('asks every blank in one generation and lands the answers in one change, signed, with one line in the log', async () => {
    const note = host(TOKYO);
    openForFills('n1', note);
    pressFill('n1', targets(TOKYO), 'qwen3.5-4b');
    expect(fillStatus('n1', blankKey('', 0))).toEqual({ phase: 'waiting' });
    await until(() => fakes.length === 1);
    expect(fakes[0]!.options.prompt).toContain('{?1 what day / time?}');
    expect(fakes[0]!.options.prompt).toContain('{?2 }');
    expect(fakes[0]!.options.temperature).toBe(0);
    fakes[0]!.finish('[1] midweek\n[2] Canberra');
    await until(() => note.lands === 1);
    expect(note.body).toContain('Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)');
    expect(note.body).toContain('The capital of Australia is ??Canberra??(Qwen3.5 4B from memory, 2026-09-28).');
    expect(note.body).toMatch(/^---\nauthors: Ghost\n---/);
    await until(() => runsOf('n1').length === 1);
    const [record] = runsOf('n1');
    expect(record).toMatchObject({ kind: 'fill', filled: 2, before: TOKYO, after: note.body });
    expect(fillStatus('n1', blankKey('', 0))).toBeNull();
    expect(toasts.map((t) => t.message)).toContain('The model’s answers have a dotted line. Tap one to see where it came from.');
    openForFills('n1', null);
  });

  it('says what did not fill, and keeps it after the blank for the session', async () => {
    const note = host(TOKYO);
    openForFills('n1', note);
    pressFill('n1', targets(TOKYO), 'qwen3.5-4b');
    await until(() => fakes.length === 1);
    fakes[0]!.finish('[1] midweek\n[2] UNKNOWN');
    await until(() => toasts.some((t) => t.message === '1 filled. 1 not known.'));
    expect(fillOutcome('n1', blankKey('', 0))).toMatchObject({ why: 'unknown' });
    openForFills('n1', null);
  });

  it('lets a summary say what the same press wrote beside it, and nothing else the note lacks', async () => {
    // Found by the shots: "In one line" was refused for naming Lisbon, which the capital blank had just written.
    const TRIP = '# Trip prep\n\nThe capital of Portugal is {?}.\n\n- Passport\n\nIn one line: {?summary}';
    const note = host(TRIP);
    openForFills('n8', note);
    pressFill('n8', targets(TRIP), 'qwen3.5-4b');
    await until(() => fakes.length === 1);
    fakes[0]!.finish('[1] Lisbon\n[2] A trip to Lisbon, with a passport packed.');
    await until(() => note.lands === 1);
    expect(note.body).toContain('In one line: ??A trip to Lisbon, with a passport packed.??');
    openForFills('n8', null);
    const again = host(TRIP);
    openForFills('n9', again);
    pressFill('n9', targets(TRIP), 'qwen3.5-4b');
    await until(() => fakes.length === 2);
    fakes[1]!.finish('[1] Lisbon\n[2] A trip to Porto, with a passport packed.');
    await until(() => toasts.some((t) => t.message === "1 filled. 1 didn't fit."));
    openForFills('n9', null);
  });

  it('drops an answer whose question changed while it ran, and says so', async () => {
    const note = host(TOKYO);
    openForFills('n1', note);
    pressFill('n1', targets(TOKYO), 'qwen3.5-4b');
    await until(() => fakes.length === 1);
    note.body = note.body.replace('{?}', '{?which city}');
    note.ranges.clear();
    fakes[0]!.finish('[1] midweek\n[2] Canberra');
    await until(() => toasts.some((t) => t.message === '1 answer was not written. Its question had changed.'));
    expect(note.body).toContain('??midweek??');
    expect(note.body).toContain('{?which city}');
    openForFills('n1', null);
  });
});

describe('the queue', () => {
  it('runs a second press after the first, never beside it', async () => {
    const note = host('# A\n\nThe capital of France is {?}.\n\nThe capital of Peru is {?which city}.');
    openForFills('n2', note);
    const [france, peru] = targets(note.body);
    pressFill('n2', [france!], 'qwen3.5-4b');
    pressFill('n2', [peru!], 'qwen3.5-4b');
    await until(() => fakes.length === 1);
    expect(fillStatus('n2', peru!.key)).toEqual({ phase: 'waiting' });
    fakes[0]!.finish('[1] Paris');
    await until(() => fakes.length === 2);
    fakes[1]!.finish('[1] Lima');
    await until(() => note.body.includes('??Lima??'));
    expect(runsOf('n2')).toHaveLength(2);
    openForFills('n2', null);
  });

  it('waits while Format runs on the note, and a Format asked while it fills stops it', async () => {
    const note = host(TOKYO);
    openForFills('n3', note);
    const format = startRun({ noteId: 'n3', kind: 'format', model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 10 });
    await until(() => fakes.length === 1);
    pressFill('n3', targets(TOKYO), 'qwen3.5-4b');
    // Pressed and waiting its turn behind the Format: no generation of its own has started.
    await until(() => fillStatus('n3', blankKey('', 0))?.phase === 'waiting');
    expect(fakes).toHaveLength(1);
    fakes[0]!.finish('formatted');
    await format.done;
    await until(() => fakes.length === 2);
    startRun({ noteId: 'n3', kind: 'format', model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 10 });
    await until(() => toasts.some((t) => t.message === 'Format stopped the fill. 2 blanks are still questions.'));
    expect(note.lands).toBe(0);
    openForFills('n3', null);
  });

  it('asks one blank a generation for a model at the second rung, and writes one line in the log', async () => {
    const note = host(TOKYO);
    openForFills('n4', note);
    pressFill('n4', targets(TOKYO), 'qwen3.5-model-nobody-measured');
    await until(() => fakes.length === 1);
    expect(fakes[0]!.options.prompt).not.toContain('{?2');
    fakes[0]!.finish('midweek');
    await until(() => fakes.length === 2);
    fakes[1]!.finish('Canberra');
    await until(() => runsOf('n4').length === 1);
    expect(runsOf('n4')[0]).toMatchObject({ filled: 2, before: TOKYO, after: note.body });
    expect(note.lands).toBe(2);
    openForFills('n4', null);
  });
});

describe('a note closed while it fills', () => {
  it('lands its answers in the store, with the revision it was read at, and says so with Open', async () => {
    const made = await createNote('n5', TOKYO);
    const note = host(TOKYO);
    openForFills('n5', note);
    pressFill('n5', targets(TOKYO), 'qwen3.5-4b');
    await until(() => fakes.length === 1);
    openForFills('n5', null);
    fakes[0]!.finish('[1] midweek\n[2] Canberra');
    await until(() => toasts.some((t) => String(t.message).startsWith('Filled 2 blanks in Tokyo trip.')));
    const stored = await getNote('n5');
    expect(stored!.body).toContain('??Canberra??(Qwen3.5 4B from memory, 2026-09-28)');
    expect(stored!.revision).toBe((made.revision ?? 1) + 1);
    expect(toasts.find((t) => String(t.message).startsWith('Filled 2'))?.action?.label).toBe('Open');
    expect(runsOf('n5')[0]).toMatchObject({ filled: 2, before: TOKYO });
  });
});

describe('a live blank, looked up by the phone', () => {
  const WEATHER = '# Lisbon\n\nWeather in Lisbon tomorrow: {?weather}';

  it('waits for a connection offline, then asks Open-Meteo and writes the answer from what came back', async () => {
    setFillWorld({
      fetch: async () => {
        throw new Error('offline');
      },
    });
    const note = host(WEATHER);
    openForFills('n6', note);
    pressFill('n6', targets(WEATHER), 'qwen3.5-4b');
    await until(() => fillStatus('n6', blankKey('weather', 0))?.phase === 'paused');
    expect(fillStatus('n6', blankKey('weather', 0))).toEqual({ phase: 'paused', why: 'offline' });
    expect(fakes).toHaveLength(0);
    // The press says what it did with the blank, where it used to say nothing at all (found by the shots).
    await until(() => toasts.length === 1);
    expect(toasts[0]!.message).toBe('Waiting for a connection. The phone looks it up once it is online.');
    const asked: string[] = [];
    setFillWorld({
      fetch: async (url) => {
        asked.push(url);
        return { status: 200, json: url.includes('geocoding') ? geocode : forecast };
      },
    });
    resumeParked();
    await until(() => fakes.length === 1);
    expect(asked[0]).toContain('name=Lisbon');
    expect(fakes[0]!.options.system).toContain('Answer only from what the source returned.');
    expect(fakes[0]!.options.prompt).toContain('What Open-Meteo returned:');
    fakes[0]!.finish('[1] Rain showers, 19 to 25 °C');
    await until(() => note.lands === 1);
    expect(note.body).toContain('??Rain showers, 19 to 25 °C??(Qwen3.5 4B from Open-Meteo, 2026-09-28. Asked: weather)');
    openForFills('n6', null);
  });

  it('says so when the source had nothing', async () => {
    setFillWorld({ fetch: async () => ({ status: 200, json: { results: [] } }) });
    const note = host('# Nowhere\n\nWeather in Qqqzzxxy today: {?weather}');
    openForFills('n7', note);
    pressFill('n7', targets(note.body), 'qwen3.5-4b');
    await until(() => fillOutcome('n7', blankKey('weather', 0)) !== null);
    expect(fillOutcome('n7', blankKey('weather', 0))).toMatchObject({ why: 'nothing', words: 'Open-Meteo doesn’t know a place called Qqqzzxxy.' });
    expect(fakes).toHaveLength(0);
    openForFills('n7', null);
  });
});
