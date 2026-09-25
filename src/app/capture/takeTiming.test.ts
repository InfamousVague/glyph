import { describe, expect, it, vi } from 'vitest';
import { quietHost } from '../../test/takeHost.ts';
import type { Plan } from './command.ts';
import type { Offer } from './offers.ts';
import type { TakeCandidate, TakeNote } from './takeTypes.ts';
import { TAKE_TIMING, Take } from './take.ts';
import type { RouteView, TakeHost } from './takeHost.ts';

/**
 * The take's clock and its second reader (capture/take.ts): what gives up, and when, and what the phone's command
 * model may and may not do. Every time here is an explicit `now`, the way the recorder's quarter-second tick and the
 * voice suite's clock pass it, so nothing waits on a real timer.
 */

interface Note extends TakeNote {
  title: string;
}

const work: Note = { id: 'w', title: 'Work', body: '# Work\n\n- Email Jo' };

function harness(over: Partial<TakeHost<Note>> = {}) {
  const routes: RouteView[] = [];
  const offers: (Offer<Note> | null)[] = [];
  const log: string[] = [];
  const tables: unknown[] = [];
  const host = quietHost<Note>({
    notes: () => [{ id: work.id, title: work.title, note: work }],
    route: (view) => routes.push(view),
    offer: (offer) => offers.push(offer),
    table: (draft) => tables.push(draft),
    log: (line) => log.push(line),
    clip: (span) => `![voice](tape:${span.startMs}-${span.endMs})`,
    ...over,
  });
  const take = new Take(host);
  /** A phrase said from `at` for 900 ms, committed 100 ms after it ends. */
  const say = (text: string, at: number) => take.phrase({ text, startMs: at, endMs: at + 900 }, at + 1000);
  const said = (phase: string) => routes.filter((view): view is Extract<RouteView, { text: string }> => view !== null && view.phase === phase && 'text' in view).map((view) => view.text);
  return { take, say, routes, offers, log, tables, said };
}

describe('after the keyword', () => {
  it('gives the words back to the note when no command comes of them, and not a moment before', () => {
    const { take, say, said } = harness();
    say('Pick up the parcel. Hey Ghost, that was a long day.', 0);
    take.tick(1000 + TAKE_TIMING.commandQuietMs);
    expect(said('said')).toEqual([]);
    take.tick(1000 + TAKE_TIMING.commandQuietMs + 1);
    expect(take.segments.map((s) => s.text)).toEqual(['Pick up the parcel.', 'that was a long day.']);
    expect(said('said')).toEqual(['No command there, so the words stay in the note.']);
    expect(take.commanding).toBe(false);
  });

  it('asks for a command when only the keyword was said, and keeps nothing of it', () => {
    const { take, say, said } = harness();
    say('Hey Ghost.', 0);
    take.tick(1000 + TAKE_TIMING.commandQuietMs + 1);
    expect(take.segments).toEqual([]);
    expect(said('said')).toEqual(['Say a command after “hey Ghost”.']);
  });

  it('waits a while for what a named note should get, then gives up with nothing added', () => {
    const { take, say, said, offers } = harness();
    say('Hey Ghost, add to work.', 0);
    expect(take.commanding).toBe(true);
    take.tick(1000 + TAKE_TIMING.awaitMs);
    expect(said('said')).toEqual([]);
    take.tick(1000 + TAKE_TIMING.awaitMs + 1);
    expect(said('said')).toEqual(['Nothing said for Work, so nothing was added.']);
    expect(offers.filter(Boolean)).toEqual([]);
    expect(take.commanding).toBe(false);
  });

  it('gathers items said one after another, and asks about them all once the talking pauses', () => {
    const { take, say, offers } = harness();
    say('Hey Ghost, new items for work.', 0);
    say('Call the bank. Email the landlord.', 2000);
    take.tick(3000 + TAKE_TIMING.itemsQuietMs);
    expect(offers.filter(Boolean)).toEqual([]);
    take.tick(3000 + TAKE_TIMING.itemsQuietMs + 1);
    expect(offers.at(-1)).toMatchObject({ kind: 'place', title: 'Work', added: ['- Call the bank', '- Email the landlord'] });
  });
});

describe('a question asked', () => {
  it('is a no when nobody answers it for twenty seconds, and the review is told so', () => {
    const { take, say, offers, said, log } = harness();
    say('Hey Ghost, add call Sam to work.', 0);
    expect(take.offering).toMatchObject({ kind: 'place', added: ['- Call Sam'] });
    take.tick(1000 + TAKE_TIMING.confirmMs);
    expect(take.offering).not.toBeNull();
    take.tick(1000 + TAKE_TIMING.confirmMs + 1);
    expect(take.offering).toBeNull();
    expect(offers.at(-1)).toBeNull();
    expect(said('said')).toEqual(['Not done. Say “yes” or tap to confirm a command.']);
    expect(log).toEqual(['Offered to add “Call Sam” to Work’s list; nobody answered, so it was not done']);
  });

  it('is told to the review as declined when the person says no or taps Cancel, and as unanswered when it was dropped', () => {
    const { take, say, log } = harness();
    say('Hey Ghost, add call Sam to work.', 0);
    say('No.', 2000);
    say('Hey Ghost, add email Jo to work.', 4000);
    take.cancel(null, 5500, 'declined');
    say('Hey Ghost, add ring Kim to work.', 7000);
    // A new command said over the question drops it.
    say('Hey Ghost, add book flights to work.', 9000);
    expect(log).toEqual([
      'Offered to add “Call Sam” to Work’s list; the person said no',
      'Offered to add “Email Jo” to Work’s list; the person said no',
      'Offered to add “Ring Kim” to Work’s list; nobody answered, so it was not done',
    ]);
  });

  it('is answered by a spoken yes, which does it, or a no, which says so', () => {
    const addItems = vi.fn();
    const { take, say, said } = harness({ addItems });
    say('Hey Ghost, add call Sam to work.', 0);
    say('Yes.', 2000);
    expect(addItems).toHaveBeenCalledWith(work, 'call Sam', expect.objectContaining({ how: 'leave' }));
    expect(take.touched.has('w')).toBe(true);
    say('Hey Ghost, add email Jo to work.', 4000);
    say('No.', 6000);
    expect(addItems).toHaveBeenCalledTimes(1);
    expect(said('said')).toEqual(['Not done.']);
    // Neither answer is the note's words.
    expect(take.segments).toEqual([]);
  });
});

describe('a table being said', () => {
  it('is dropped when nothing is said for it for a while', () => {
    const { take, say, tables, said } = harness();
    say('Hey Ghost, add a table.', 0);
    expect(tables.at(-1)).toMatchObject({ note: null, title: 'this note', columns: [] });
    take.tick(1000 + TAKE_TIMING.tableQuietMs + 1);
    expect(tables.at(-1)).toBeNull();
    expect(said('said')).toEqual(['No table: nothing was said for it for a while.']);
  });
});

describe('the phone’s command model', () => {
  /** A model whose answer the test gives, when it chooses to. */
  function model() {
    let answer: (plan: Plan<TakeCandidate<Note>> | null) => void = () => undefined;
    const cancel = vi.fn();
    const understand = vi.fn(() => ({ done: new Promise<Plan<TakeCandidate<Note>> | null>((resolve) => (answer = resolve)), cancel }));
    return { understand, cancel, answer: (plan: Plan<TakeCandidate<Note>> | null) => answer(plan) };
  }
  const place: Plan<TakeCandidate<Note>> = { kind: 'place', note: { id: work.id, title: work.title, note: work }, text: 'oat milk', how: 'leave', task: false, many: false, target: null };

  it('is asked in a pause after words the rules cannot read, and its plan is offered like the rules’ own', async () => {
    const reader = model();
    const { take, say, routes, offers, log } = harness({ understand: reader.understand });
    say('Hey Ghost, do the thing with the oat milk.', 0);
    take.tick(1000 + TAKE_TIMING.understandAfterMs);
    expect(reader.understand).not.toHaveBeenCalled();
    take.tick(1000 + TAKE_TIMING.understandAfterMs + 1);
    expect(reader.understand).toHaveBeenCalledWith('do the thing with the oat milk.');
    expect(routes.at(-1)).toEqual({ phase: 'command', words: 'do the thing with the oat milk.', thinking: true });
    reader.answer(place);
    await vi.waitFor(() => expect(offers.at(-1)).toMatchObject({ kind: 'place', title: 'Work', added: ['- Oat milk'] }));
    expect(log).toEqual(['The on-device model read “hey Ghost do the thing with the oat milk.”']);
  });

  it('is stopped the moment speech resumes, and what it answered after that is thrown away', async () => {
    const reader = model();
    const { take, say, offers } = harness({ understand: reader.understand });
    say('Hey Ghost, do the thing with the oat milk.', 0);
    take.tick(1000 + TAKE_TIMING.understandAfterMs + 1);
    take.heardPartial(2300);
    expect(reader.cancel).toHaveBeenCalledOnce();
    reader.answer(place);
    await Promise.resolve();
    await Promise.resolve();
    expect(offers.filter(Boolean)).toEqual([]);
  });

  it('is asked at once for a name that matched no note, and when it has nothing either the words go back', async () => {
    const reader = model();
    const { take, say, said } = harness({ understand: reader.understand });
    say('Hey Ghost, add to shopping, oat milk.', 0);
    expect(reader.understand).toHaveBeenCalledOnce();
    reader.answer(null);
    await vi.waitFor(() => expect(said('said')).toEqual(['No note called “shopping, oat milk”, so it stays here.']));
    expect(take.segments.map((s) => s.text)).toEqual(['add to shopping, oat milk.']);
  });
});

describe('a voice memo', () => {
  it('keeps the sound from the cue to "end memo", written where it was said', () => {
    const clip = vi.fn((span: { startMs: number; endMs: number }) => `![voice](tape:${span.startMs}-${span.endMs})`);
    const { take, say, said } = harness({ clip });
    say('Before it.', 0);
    say('Voice memo.', 1000);
    say('La la la, the tune goes like this.', 2000);
    say('End memo.', 3000);
    expect(clip).toHaveBeenCalledWith({ startMs: 1900, endMs: 2900 });
    expect(take.segments.map((s) => s.text)).toEqual(['Before it.', '![voice](tape:1900-2900)']);
    expect(take.clips).toHaveLength(1);
    expect(said('done')).toEqual(['Voice memo, 0:01']);
  });

  it('keeps nothing for a memo under half a second', () => {
    const { take, said } = harness();
    take.phrase({ text: 'Voice memo.', startMs: 0, endMs: 900 }, 1000);
    take.phrase({ text: 'End memo.', startMs: 1000, endMs: 1300 }, 1400);
    expect(take.clips).toEqual([]);
    expect(said('said').at(-1)).toBe('Nothing was said, so no voice memo was kept.');
  });
});

describe('what counts as the keyword', () => {
  it('takes a sound-alike of it at the start of a phrase when a command follows, but not while one is under way', () => {
    const { take, say } = harness();
    say('Life. Add eggs to work.', 0);
    expect(take.offering).toMatchObject({ kind: 'place', text: 'eggs' });

    const waiting = harness();
    waiting.say('Hey Ghost, add to work.', 0);
    waiting.say('Life. Add eggs to work.', 2000);
    expect(waiting.take.offering).toMatchObject({ kind: 'place', text: 'Life. Add eggs to work' });
  });

  it('reads a phrase as a command with the keyword switched off only when it reads as one', () => {
    const { take, say } = harness({ commandWord: () => false });
    say('I went to work early.', 0);
    expect(take.offering).toBeNull();
    expect(take.segments.map((s) => s.text)).toEqual(['I went to work early.']);
    say('Add call Sam to work.', 2000);
    expect(take.offering).toMatchObject({ kind: 'place', text: 'call Sam' });
  });
});
