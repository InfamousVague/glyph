import type { ToastOptions } from '@glacier/react';
import { learntUntil, modelName } from '../../core/ai.ts';
import { BLANK, type Blank, blanksIn, type FillSource } from '../../core/blanks.ts';
import { deviceFlag } from '../../core/deviceFlag.ts';
import { externalStore } from '../../core/externalStore.ts';
import { failureText } from '../../core/failure.ts';
import { workOut } from '../../core/fillFacts.ts';
import { preferences } from '../../core/preferences.ts';
import { getNote, noteTitle, updateNote } from '../../core/store.ts';
import { syncNow } from '../../core/sync/engine.ts';
import { recordChange, recordRun } from '../log.ts';
import { isRunning, runFor, sayRun, startRun, subscribeRuns, type RunState } from '../runs.ts';
import { blanksWord, filledSentence } from '../words.ts';
import { allChanges, applyChanges, signatureChange, type Landing, type TextChange } from './edits.ts';
import { laneOf, type Lookups } from './lane.ts';
import { buildFill, fillPlan, type Ask, type Generation } from './message.ts';
import { FILL_WEB_PROMPT, rungFor } from './prompts.ts';
import { readAsks } from './read.ts';
import { checkShape, shapeOf } from './shape.ts';
import { fromThisNote } from './source.ts';
import { lookUp, type LookupPlan, pageFetch, type Fetcher, webMessage } from './web.ts';

/**
 * The fills' queue: every press of Fill, run to its end and landed, whether its note stays open or not (docs/DESIGN.md
 * §145, 4.4 and 6.3).
 *
 * A module of the page, beside the summaries' queue (ai/summaries.ts), and not owned by the note screen, so closing a
 * note changes nothing about a fill already pressed: its answers land in the closed note the way a write-up does, read
 * fresh and written with the revision it was read at, and one that cannot be written is kept for the session and lands
 * when the note is next opened. With the page in view, a toast says so, with Open.
 *
 * A press is a batch: its note, its blanks (each known by its question and its order among blanks with that question,
 * and while the note is open by its range too), the model, and an id. It is split into generations by the model's rung
 * and the room (ai/fills/message.ts), which run in order through the one engine (ai/runs.ts), so the strip, Stop and
 * the queue behind another note all work as for any run. A generation's answers are checked (ai/fills/shape.ts) and
 * land together in one change, the first with the AI's signature. A press is one line in the log with one Undo,
 * however many generations it took. A fill never stops another kind of run: it waits while Format or Summarize runs on
 * its note, and one of those asked while fills run is the newer ask, which stops them.
 *
 * A live blank (ai/fills/web.ts) is looked up first: offline it waits, "Waiting for a connection", and goes on by
 * itself once the phone is online, never started but by the press. Local only holds it.
 *
 * Only while the app runs: the queue is in memory, as every run is. Nothing is left half written, since each
 * generation lands in one change or not at all.
 */

/** A blank a press asks, as the editor found it. */
export interface FillTarget {
  /** Its question and its order among blanks with that question: `blankKey`. */
  key: string;
  question: string;
  order: number;
  /** An answer asked again: the whole mark as it stands, and its words, which the model is told it is not. */
  again?: { mark: string; words: string };
  /** Ask the model anyway: a blank the app refused, asked of the model from memory, never looked up. */
  anyway?: true;
}

/** Where a target is: the blank's identity, joined. */
export function blankKey(question: string, order: number): string {
  return `${question}\u0000${order}`;
}

/** What an open note's editor gives the queue, so it is the one writer of an open note (ai/fills/useFillLanding.ts). */
export interface FillHost {
  text(): string;
  /** A target's range as the editor has tracked it since the press, or null. */
  rangeOf(key: string): { from: number; to: number } | null;
  /** Tracks the targets' ranges through every edit from now. */
  track(targets: readonly { key: string; from: number; to: number }[]): void;
  /** Lands the changes in one transaction, signed when `sign` holds one; answers the note after, or null. */
  land(changes: readonly TextChange[], sign: TextChange | null): string | null;
}

/** What is going on with a blank a press took. */
export type FillStatus = { phase: 'waiting' } | { phase: 'filling'; runId: string } | { phase: 'looking' } | { phase: 'paused'; why: 'offline' | 'local-only' };

/** What came of a blank that did not fill, kept for the session and drawn after it (6.7). */
export interface FillOutcome {
  why: 'unknown' | 'none' | 'didnt-fit' | 'nothing';
  /** The source's own sentence, for a lookup that found nothing. */
  words?: string;
  model: string;
}

interface Target extends FillTarget {
  /** Looked up on the web first, by this plan. */
  plan?: LookupPlan;
}

interface Batch {
  id: string;
  noteId: string;
  model: string;
  targets: Target[];
  /** The note before its first landing, for Undo; null until then. */
  before: string | null;
  after: string | null;
  landed: number;
  firstStart: number | null;
  lastEnd: number;
  lastRunId: string | null;
  outputTokens: number;
  counts: { unknown: number; none: number; didntFit: number; nothing: number; changed: number };
  stopped: 'stopped' | { by: string } | null;
  failed: string | null;
  /** The note's title when it landed closed, for the toast. */
  closedTitle: string | null;
  /** Web jobs still waiting for a connection. */
  parked: number;
}

// ---- state --------------------------------------------------------------------------------------------------

const hosts = new Map<string, FillHost>();
const statuses = new Map<string, Map<string, FillStatus>>();
const outcomes = new Map<string, Map<string, FillOutcome>>();
/** Answers a closed note could not take, kept to land when it is next opened. */
const pending = new Map<string, { batch: Batch; ready: Ready[] }[]>();
const batches: Batch[] = [];
const parked: { batch: Batch; target: Target }[] = [];
let working = false;
let count = 0;
/** Bumped on every change a screen draws from. */
const version = externalStore(0);
const bump = () => version.update((n) => n + 1);

let toaster: ((options: ToastOptions) => void) | null = null;
let opener: ((id: string) => void) | null = null;
let fetcher: Fetcher = pageFetch;
let now: () => Date = () => new Date();

/** Follows every change to what the queue knows; answers the way to stop. */
export const subscribeFills = version.subscribe;
export const useFillsVersion = version.use;

/** A blank's status, while a press has it. */
export function fillStatus(noteId: string, key: string): FillStatus | null {
  return statuses.get(noteId)?.get(key) ?? null;
}

/** What came of a blank that did not fill, this session. */
export function fillOutcome(noteId: string, key: string): FillOutcome | null {
  return outcomes.get(noteId)?.get(key) ?? null;
}

/** Whether any press of this note is going or waiting. */
export function fillsGoing(noteId: string): boolean {
  return batches.some((b) => b.noteId === noteId) || parked.some((p) => p.batch.noteId === noteId);
}

function setStatus(noteId: string, key: string, status: FillStatus | null): void {
  const mine = statuses.get(noteId) ?? new Map<string, FillStatus>();
  if (status) mine.set(key, status);
  else mine.delete(key);
  statuses.set(noteId, mine);
  bump();
}

function setOutcome(noteId: string, key: string, outcome: FillOutcome | null): void {
  const mine = outcomes.get(noteId) ?? new Map<string, FillOutcome>();
  if (outcome) mine.set(key, outcome);
  else mine.delete(key);
  outcomes.set(noteId, mine);
  bump();
}

/** Wire the queue to the app: how it says what happened, how Open opens a note. Called once (shell/useHousekeeping.ts). */
export function startFills(toast: (options: ToastOptions) => void, open: (id: string) => void): () => void {
  toaster = toast;
  opener = open;
  const online = () => resumeParked();
  window.addEventListener('online', online);
  const timer = window.setInterval(() => {
    if (parked.length && document.visibilityState === 'visible') resumeParked();
  }, 60_000);
  return () => {
    window.removeEventListener('online', online);
    window.clearInterval(timer);
    toaster = null;
    opener = null;
  };
}

/** For tests: the network and the clock the queue uses. */
export function setFillWorld(world: { fetch?: Fetcher; now?: () => Date }): void {
  if (world.fetch) fetcher = world.fetch;
  if (world.now) now = world.now;
}

/** Nothing going, nothing remembered: for a reset, and for tests. */
export function forgetFills(): void {
  batches.length = 0;
  parked.length = 0;
  statuses.clear();
  outcomes.clear();
  pending.clear();
  working = false;
  bump();
}

/** Whether this device may look live blanks up now. */
export function lookupsHere(): Lookups {
  const prefs = preferences();
  if (prefs.localOnly) return 'local-only';
  return prefs.lookUpBlanks ? 'on' : 'off';
}

/**
 * A note open in its editor: its answers land through it, in one transaction each, and anything kept for it while it
 * was closed lands now. Given null as the note is left.
 */
export function openForFills(noteId: string, host: FillHost | null): void {
  if (!host) {
    hosts.delete(noteId);
    return;
  }
  hosts.set(noteId, host);
  const kept = pending.get(noteId);
  if (!kept?.length) return;
  pending.delete(noteId);
  for (const { batch, ready } of kept) {
    landOpen(batch, host, ready);
    finishBatch(batch);
  }
}

// ---- a press ------------------------------------------------------------------------------------------------

/**
 * A press of Fill, Fill the blanks, Ask again or Ask the model anyway: its targets queue behind every earlier press.
 * The model is one on the phone (ai/available.ts `modelFor`); the caller has said why not where there is none.
 */
export function pressFill(noteId: string, targets: readonly FillTarget[], model: string): void {
  if (!targets.length) return;
  const text = hosts.get(noteId)?.text() ?? null;
  const batch: Batch = {
    id: `fill-${Date.now().toString(36)}-${(count += 1)}`,
    noteId,
    model,
    targets: targets.map((t) => ({ ...t })),
    before: null,
    after: null,
    landed: 0,
    firstStart: null,
    lastEnd: 0,
    lastRunId: null,
    outputTokens: 0,
    counts: { unknown: 0, none: 0, didntFit: 0, nothing: 0, changed: 0 },
    stopped: null,
    failed: null,
    closedTitle: null,
    parked: 0,
  };
  // Which are looked up on the web first: a live blank this device may look up.
  if (text !== null) {
    const lookups = lookupsHere();
    for (const target of batch.targets) {
      if (target.again || target.anyway) continue;
      const blank = locate(noteId, target, text);
      if (!blank) continue;
      const lane = laneOf(blank, text, { clock: { now: now() }, learntUntil: learntUntil(model), lookups });
      if (lane.lane === 'live' && lane.can === 'look') target.plan = lane.plan;
    }
  }
  for (const target of batch.targets) {
    setOutcome(noteId, target.key, null);
    setStatus(noteId, target.key, { phase: 'waiting' });
  }
  batches.push(batch);
  bump();
  void pump();
}

/** The blank or the asked-again mark a target is in `text`: by the editor's tracked range, else by its identity. */
function locate(noteId: string, target: Target, text: string): Blank | null {
  const range = hosts.get(noteId)?.rangeOf(target.key);
  if (target.again) {
    const at = range && text.slice(range.from, range.to) === target.again.mark ? range.from : text.indexOf(target.again.mark);
    return at < 0 ? null : { from: at, to: at + target.again.mark.length, question: target.question };
  }
  if (range) {
    const found = new RegExp(`^${BLANK.source}$`).exec(text.slice(range.from, range.to));
    if (found && (found[1] ?? '').trim() === target.question) return { from: range.from, to: range.to, question: target.question };
  }
  const same = blanksIn(text).filter((b) => b.question === target.question);
  return same[target.order] ?? null;
}

/** An ask for a target in `text`: a blank's shape, or an asked-again mark's shape as its blank had it. */
function askFor(target: Target, blank: Blank, text: string): Ask {
  if (!target.again) return { blank, info: shapeOf(blank, text) };
  const written = `{?${target.question}}`;
  const pseudo = `${text.slice(0, blank.from)}${written}${text.slice(blank.to)}`;
  return { blank, info: shapeOf({ from: blank.from, to: blank.from + written.length, question: target.question }, pseudo), again: { words: target.again.words } };
}

/** The note's text now: its editor's, or the store's. */
async function currentText(noteId: string): Promise<string | null> {
  const host = hosts.get(noteId);
  if (host) return host.text();
  const note = await getNote(noteId).catch(() => null);
  return note?.body ?? null;
}

// ---- running ------------------------------------------------------------------------------------------------

async function pump(): Promise<void> {
  if (working) return;
  working = true;
  try {
    while (batches.length) {
      const batch = batches[0]!;
      await runBatch(batch);
      batches.shift();
      finishBatch(batch);
    }
  } finally {
    working = false;
  }
}

/** Resolves once the note has no run but a fill's: a fill never stops Format or Summarize. */
function noOtherRun(noteId: string): Promise<void> {
  const other = () => isRunning(noteId) && runFor(noteId)?.kind !== 'fill';
  if (!other()) return Promise.resolve();
  return new Promise((resolve) => {
    const stop = subscribeRuns(() => {
      if (other()) return;
      stop();
      resolve();
    });
  });
}

async function runBatch(batch: Batch): Promise<void> {
  const model = batch.targets.filter((t) => !t.plan);
  const web = batch.targets.filter((t) => t.plan);
  if (model.length) {
    await noOtherRun(batch.noteId);
    const text = await currentText(batch.noteId);
    if (text === null) return;
    const located = model.map((target) => ({ target, blank: locate(batch.noteId, target, text) }));
    for (const { target, blank } of located) {
      if (blank) continue;
      batch.counts.changed += 1;
      setStatus(batch.noteId, target.key, null);
    }
    const asks = located.filter((l) => l.blank).map((l) => ({ target: l.target, ask: askFor(l.target, l.blank!, text) }));
    const plan = fillPlan(
      text,
      asks.map((a) => a.ask),
      rungFor(batch.model),
      now(),
    );
    let before = 0;
    const total = asks.length;
    for (const generation of plan) {
      if (batch.stopped || batch.failed) break;
      const targets = generation.asks.map((ask) => asks.find((a) => a.ask === ask)!.target);
      await runGeneration(batch, targets, generation, { before, total });
      before += generation.asks.length;
    }
    // Anything a stop left: back to rest, a question still.
    for (const target of model) {
      const phase = fillStatus(batch.noteId, target.key)?.phase;
      if (phase === 'waiting' || phase === 'filling') setStatus(batch.noteId, target.key, null);
    }
  }
  for (const target of web) {
    if (batch.stopped || batch.failed) {
      setStatus(batch.noteId, target.key, null);
      continue;
    }
    await runWeb(batch, target);
  }
}

/** One generation: the targets found again in the note as it reads now, the model asked, the answers landed. */
async function runGeneration(batch: Batch, targets: Target[], generation: Generation, progress: { before: number; total: number }): Promise<void> {
  await noOtherRun(batch.noteId);
  const text = await currentText(batch.noteId);
  if (text === null) return;
  const asks: { target: Target; ask: Ask }[] = [];
  for (const target of targets) {
    const blank = locate(batch.noteId, target, text);
    if (!blank) {
      batch.counts.changed += 1;
      setStatus(batch.noteId, target.key, null);
      continue;
    }
    asks.push({ target, ask: askFor(target, blank, text) });
  }
  if (!asks.length) return;
  const rung = rungFor(batch.model);
  const today = now();
  const worked = (blank: Blank) => {
    const found = workOut(blank, text, { now: today });
    return found?.kind === 'answer' ? found.answer : null;
  };
  const built = buildFill(
    text,
    asks.map((a) => a.ask),
    { rung, today, worked, tight: generation.tight },
  );
  const state = await runOne(batch, asks, { system: built.system, prompt: built.prompt, maxTokens: built.maxTokens }, progress);
  if (!state) return;
  const lines = readAsks(state.text ?? '', built.numbers);
  await land(
    batch,
    asks.map(({ target, ask }, i) => ({ target, ask, lines: lines[i] ?? [], truncated: state.truncated && i === asks.length - 1, source: null })),
  );
}

/** A live target: looked up, then written by the model from what came back. Offline, it waits for a connection. */
async function runWeb(batch: Batch, target: Target): Promise<void> {
  if (lookupsHere() !== 'on') {
    park(batch, target, 'local-only');
    return;
  }
  setStatus(batch.noteId, target.key, { phase: 'looking' });
  const found = await lookUp(target.plan!, fetcher);
  if (!found.ok && found.why === 'offline') {
    park(batch, target, 'offline');
    return;
  }
  if (!found.ok) {
    batch.counts.nothing += 1;
    setStatus(batch.noteId, target.key, null);
    setOutcome(batch.noteId, target.key, { why: 'nothing', words: found.words, model: batch.model });
    return;
  }
  await noOtherRun(batch.noteId);
  const text = await currentText(batch.noteId);
  if (text === null) return;
  const blank = locate(batch.noteId, target, text);
  if (!blank) {
    batch.counts.changed += 1;
    setStatus(batch.noteId, target.key, null);
    return;
  }
  const ask = askFor(target, blank, text);
  const today = now();
  const built = buildFill(text, [ask], { rung: 1, today });
  const state = await runOne(batch, [{ target, ask }], { system: FILL_WEB_PROMPT, prompt: webMessage(built.prompt, found.source, found.facts), maxTokens: built.maxTokens }, { before: 0, total: 1 });
  if (!state) return;
  await land(batch, [{ target, ask, lines: readAsks(state.text ?? '', built.numbers)[0] ?? [], truncated: state.truncated, source: { kind: 'web', name: found.source } }]);
}

function park(batch: Batch, target: Target, why: 'offline' | 'local-only'): void {
  setStatus(batch.noteId, target.key, { phase: 'paused', why });
  parked.push({ batch, target });
  batch.parked += 1;
}

/** A connection came back, or Local only went off: the parked lookups go on, in a press of their own each. */
export function resumeParked(): void {
  if (!parked.length || lookupsHere() === 'local-only' || (typeof navigator !== 'undefined' && navigator.onLine === false)) return;
  const going = parked.splice(0);
  for (const { batch, target } of going) {
    batch.parked -= 1;
    const again: Batch = { ...batch, id: `${batch.id}-web`, targets: [target], before: null, after: null, landed: 0, firstStart: null, lastEnd: 0, lastRunId: null, outputTokens: 0, counts: { unknown: 0, none: 0, didntFit: 0, nothing: 0, changed: 0 }, stopped: null, failed: null, closedTitle: null, parked: 0 };
    batches.push(again);
  }
  bump();
  void pump();
}

/** Runs one generation through the engine, the targets filling meanwhile; the run's end, or null for a stop or a failure. */
async function runOne(batch: Batch, asks: { target: Target; ask: Ask }[], request: { system: string; prompt: string; maxTokens: number }, progress: { before: number; total: number }): Promise<RunState | null> {
  const handle = startRun({
    noteId: batch.noteId,
    kind: 'fill',
    instruction: asks.map((a) => a.target.question).filter(Boolean).join(' · ') || undefined,
    model: batch.model,
    system: request.system,
    prompt: request.prompt,
    maxTokens: request.maxTokens,
    temperature: 0,
    think: false,
    batch: { id: batch.id, before: progress.before, asked: asks.length, total: progress.total },
  });
  batch.firstStart ??= Date.now();
  for (const { target } of asks) setStatus(batch.noteId, target.key, { phase: 'filling', runId: handle.id });
  const state = await handle.done;
  batch.lastRunId = handle.id;
  batch.lastEnd = Date.now();
  batch.outputTokens += state.outputTokens;
  if (state.phase === 'done') return state;
  for (const { target } of asks) setStatus(batch.noteId, target.key, null);
  if (state.phase === 'stopped') {
    const newer = runFor(batch.noteId);
    batch.stopped = newer && newer.id !== handle.id && newer.kind !== 'fill' ? { by: newer.kind } : 'stopped';
    // The newer ask for the note is the one meant: every press of it still waiting goes too.
    for (const other of batches) if (other !== batch && other.noteId === batch.noteId) other.stopped = batch.stopped;
  } else batch.failed = state.message ?? 'The model stopped.';
  return null;
}

// ---- landing ------------------------------------------------------------------------------------------------

/** One answer as read, before it is checked against the note as it reads when it lands. */
interface Ready {
  target: Target;
  ask: Ask;
  lines: string[];
  truncated: boolean;
  /** From the web, named; null for the model's own, whose source is worked out at landing. */
  source: FillSource | null;
}

const isoDay = (date: Date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;

/** The note and the blank an answer is checked against: an asked-again mark read as the blank it was. */
function asAsked(target: Target, blank: Blank, text: string): { note: string; blank: Blank } {
  if (!target.again) return { note: text, blank };
  const written = `{?${target.question}}`;
  return { note: `${text.slice(0, blank.from)}${written}${text.slice(blank.to)}`, blank: { from: blank.from, to: blank.from + written.length, question: target.question } };
}

/**
 * The answers checked against their shapes and turned into landings on `text`: a refused answer writes nothing and is
 * counted. `text` is the note as it reads now; a target no longer there is dropped and counted. Asked again, the old
 * answer stays unless a different one passes, and a toast says which (7.2).
 */
function landings(batch: Batch, text: string, ready: readonly Ready[]): Landing[] {
  const out: Landing[] = [];
  const name = modelName(batch.model);
  // A title or a summary is checked last, against the note with this press's other answers in it: once the capital
  // blank beside it has landed, "Lisbon" is the note's own word, and a summary of the note may say it. The shots found
  // "In one line" refused for naming what the press itself had just written.
  const found = ready.map((one) => {
    const blank = locate(batch.noteId, one.target, text);
    const shape = blank ? askFor(one.target, blank, text).info.shape : null;
    return { one, blank, late: shape === 'title' || shape === 'summary' };
  });
  for (const { one, blank, late } of [...found.filter((f) => !f.late), ...found.filter((f) => f.late)]) {
    setStatus(batch.noteId, one.target.key, null);
    if (!blank) {
      batch.counts.changed += 1;
      continue;
    }
    const ask = askFor(one.target, blank, text);
    const asked = asAsked(one.target, blank, text);
    const others = late && out.length ? `${asked.note}\n\n${out.map((landing) => landing.words.join('\n')).join('\n')}` : asked.note;
    const checked = checkShape(one.lines, asked.blank, ask.info, others, one.truncated);
    if (!checked.ok) {
      if (one.target.again) {
        toaster?.({ message: checked.why === 'unknown' ? `${name} said it did not know this time.` : checked.why === 'didnt-fit' ? 'The new answer didn’t fit, so the old one stays.' : 'No new answer came, so the old one stays.' });
        continue;
      }
      if (checked.why === 'unknown') batch.counts.unknown += 1;
      else if (checked.why === 'none') batch.counts.none += 1;
      else batch.counts.didntFit += 1;
      setOutcome(batch.noteId, one.target.key, { why: checked.why, model: batch.model });
      continue;
    }
    if (one.target.again && checked.text.trim().toLowerCase() === one.target.again.words.trim().toLowerCase()) {
      toaster?.({ message: 'The same answer came back.' });
      continue;
    }
    const fromNote = checked.items.every((item) => fromThisNote(item, asked.blank, ask.info.shape, asked.note, asked.note));
    const source: FillSource = one.source ?? (fromNote ? { kind: 'note' } : { kind: 'memory' });
    out.push({ from: blank.from, to: blank.to, question: one.target.question, info: ask.info, words: checked.items, source, model: name, date: isoDay(now()) });
    setOutcome(batch.noteId, one.target.key, null);
  }
  return out;
}

/** A generation's answers into its note: through its editor when it is open, else written to the store. */
async function land(batch: Batch, ready: Ready[]): Promise<void> {
  const host = hosts.get(batch.noteId);
  if (host) landOpen(batch, host, ready);
  else await landClosed(batch, ready);
}

function landOpen(batch: Batch, host: FillHost, ready: readonly Ready[]): void {
  const text = host.text();
  const answers = landings(batch, text, ready);
  if (!answers.length) return;
  const sign = batch.landed === 0 ? signatureChange(text) : null;
  const after = host.land(allChanges(text, answers), sign);
  if (after === null) return;
  batch.before ??= text;
  batch.after = after;
  batch.landed += answers.length;
  noteFirstFill();
}

/**
 * Into a closed note, the way a write-up lands in one (ai/summaries.ts `write`): synced, read fresh, found again by
 * question and order, written with the revision it was read at, read again once on a conflict, synced after. A note
 * opened meanwhile takes the answers through its editor; a write that still does not go through keeps them for the
 * next open.
 */
async function landClosed(batch: Batch, ready: Ready[]): Promise<void> {
  await syncNow().catch(() => undefined);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const host = hosts.get(batch.noteId);
    if (host) {
      landOpen(batch, host, ready);
      return;
    }
    const note = await getNote(batch.noteId).catch(() => null);
    if (!note) return;
    const answers = landings(batch, note.body, ready);
    if (!answers.length) return;
    const sign = batch.landed === 0 ? signatureChange(note.body) : null;
    const next = applyChanges(note.body, [...allChanges(note.body, answers), ...(sign ? [sign] : [])]);
    try {
      await updateNote(batch.noteId, next, note.revision ?? 1);
    } catch (error) {
      if (/changed|deleted|revision/i.test(failureText(error))) continue;
      break;
    }
    batch.before ??= note.body;
    batch.after = next;
    batch.landed += answers.length;
    batch.closedTitle = noteTitle(next) || 'Untitled';
    await syncNow().catch(() => undefined);
    noteFirstFill();
    return;
  }
  // Kept for the session: they land when the note is next opened, while their blanks are still there.
  const kept = pending.get(batch.noteId) ?? [];
  kept.push({ batch, ready });
  pending.set(batch.noteId, kept);
}

/** Once per device, after the first model answer lands: how to read one (6.4). */
const told = deviceFlag('glyph-fill-told');
function noteFirstFill(): void {
  if (told.read()) return;
  told.set(true);
  toaster?.({ message: 'The model’s answers have a dotted line. Tap one to see where it came from.', duration: 8000 });
}

/** The press is over: its one line in the log, the strip's last word, and a toast for what did not fill. */
function finishBatch(batch: Batch): void {
  const { noteId } = batch;
  if (batch.lastRunId && batch.landed) {
    const ms = Math.max(0, batch.lastEnd - (batch.firstStart ?? batch.lastEnd));
    recordRun({
      id: batch.lastRunId,
      noteId,
      kind: 'fill',
      instruction: batch.targets.map((t) => t.question).filter(Boolean).join(' · ') || null,
      model: batch.model,
      at: batch.firstStart ?? Date.now(),
      ms,
      outputTokens: batch.outputTokens,
      outcome: batch.stopped ? 'stopped' : 'done',
      message: null,
      truncated: false,
      filled: batch.landed,
    });
    if (batch.before !== null && batch.after !== null && batch.before !== batch.after) recordChange(noteId, batch.lastRunId, batch.before, batch.after);
    sayRun(noteId, batch.lastRunId, filledSentence(batch.landed, batch.model, ms));
  } else if (batch.lastRunId && !batch.stopped && !batch.failed) sayRun(noteId, batch.lastRunId, filledSentence(0, batch.model, 0));
  for (const target of batch.targets) if (fillStatus(noteId, target.key)?.phase !== 'paused') setStatus(noteId, target.key, null);
  const said = pressToast(batch);
  if (said) toaster?.(said);
  bump();
}

/** The toast after a press, built from its counts (6.5): none when everything filled. */
export function pressToast(batch: Pick<Batch, 'landed' | 'counts' | 'stopped' | 'failed' | 'closedTitle' | 'noteId' | 'targets' | 'parked'>): ToastOptions | null {
  const { counts } = batch;
  if (batch.failed) return { message: /too long/i.test(batch.failed) ? 'This part of the note is too long for the model. Try a shorter section.' : batch.failed };
  if (batch.stopped && typeof batch.stopped === 'object') {
    const left = batch.targets.length - batch.landed - batch.parked;
    const kind = batch.stopped.by;
    const name = kind === 'summarize' ? 'Summarize' : kind.charAt(0).toUpperCase() + kind.slice(1);
    return { message: `${name} stopped the fill. ${left === 1 ? '1 blank is still a question.' : `${left} blanks are still questions.`}` };
  }
  if (batch.stopped) return null;
  const parts: string[] = [];
  if (counts.unknown) parts.push(`${counts.unknown} not known`);
  if (counts.didntFit) parts.push(`${counts.didntFit} didn't fit`);
  if (counts.none) parts.push(`${counts.none} had no answer`);
  if (counts.nothing) parts.push(`${counts.nothing} not found online`);
  // A live blank parked for a connection, or held by Local only, is said too: the press did something with it.
  const held = lookupsHere() === 'local-only';
  if (batch.parked) parts.push(`${batch.parked} ${held ? 'held by Local only' : 'waiting for a connection'}`);
  const changed = counts.changed ? (counts.changed === 1 ? '1 answer was not written. Its question had changed.' : `${counts.changed} answers were not written. Their questions had changed.`) : '';
  let message = '';
  const onlyNone = counts.none > 0 && parts.length === 1;
  if (batch.landed && parts.length) message = `${batch.landed} filled. ${parts.join(', ')}.`;
  else if (!batch.landed && onlyNone) message = 'Nothing filled. No answer came.';
  else if (!batch.landed && batch.parked && parts.length === 1) message = held ? 'Local only is on, so the phone looks nothing up.' : `Waiting for a connection. The phone looks ${batch.parked === 1 ? 'it' : 'them'} up once it is online.`;
  else if (!batch.landed && parts.length) message = `Nothing filled. ${parts.join(', ')}.`;
  if (changed) message = message ? `${message} ${changed}` : changed;
  if (batch.closedTitle && batch.landed && typeof document !== 'undefined' && document.visibilityState === 'visible') {
    const filled = `Filled ${blanksWord(batch.landed)} in ${batch.closedTitle}.`;
    return { message: message ? `${filled} ${message}` : filled, duration: 10_000, action: { label: 'Open', onPress: () => opener?.(batch.noteId) } };
  }
  return message ? { message } : null;
}
