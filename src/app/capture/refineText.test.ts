import { describe, expect, it } from 'vitest';
import { LiveTake } from './liveTake.ts';
import type { RefineJob } from './refine.ts';
import { refinedBody, refinedSegments, withClips, withoutCommands } from './refineText.ts';

const job = (over: Partial<RefineJob> = {}): RefineJob => ({
  id: 'n1',
  fromMs: 0,
  recordingMs: 4000,
  baseBody: '',
  savedBody: '# Grocery run\n\nIt has to happen before Saturday.',
  titled: true,
  priorSegments: [],
  promptTail: '',
  tries: 0,
  ...over,
});

describe('the better words after a recording', () => {
  it('renders a first take with a title, from the better phrases', () => {
    const body = refinedBody(job(), [
      { text: 'Grocery run.', startMs: 0, endMs: 1000 },
      { text: 'It has to happen before Saturday morning.', startMs: 1300, endMs: 3000 },
    ]);
    expect(body).toBe('# Grocery run\n\nIt has to happen before Saturday morning.');
  });

  it('puts a later take under the note it continued, without a new title', () => {
    const body = refinedBody(
      job({ baseBody: '# Grocery run\n\nBook the cabin.', fromMs: 10_000, titled: false }),
      [{ text: 'Ask Sam about the dog.', startMs: 10_000, endMs: 12_000 }],
    );
    expect(body).toBe('# Grocery run\n\nBook the cabin.\n\nAsk Sam about the dog.');
  });

  it("replaces only the take's phrases in the recording's list", () => {
    const prior = [
      { text: 'Book the cabin.', startMs: 0, endMs: 2000 },
      { text: 'live guess of the take', startMs: 10_000, endMs: 12_000 },
    ];
    const merged = refinedSegments(job({ fromMs: 10_000, priorSegments: prior }), [
      { text: 'Ask Sam about the dog.', startMs: 10_000, endMs: 12_000 },
    ]);
    expect(merged.map((s) => s.text)).toEqual(['Book the cabin.', 'Ask Sam about the dog.']);
  });
});

describe('the better words leave commands out', () => {
  const seg = (text: string, startMs: number, endMs: number) => ({ text, startMs, endMs });
  it('drops phrases inside a command’s stretch and cuts a phrase at “hey Ghost”', () => {
    const refined = [seg('Pick up the parcel.', 0, 1800), seg('Pick up milk, hey Ghost, add eggs to', 2000, 4000), seg('work.', 4000, 4800), seg('Yes.', 5200, 5600), seg('Call Sam.', 6000, 7000)];
    const kept = withoutCommands({ skip: [{ startMs: 3950, endMs: 4900 }, { startMs: 5100, endMs: 5700 }], keywordAt: [{ startMs: 2100, endMs: 3900 }] }, refined);
    expect(kept.map((s) => s.text)).toEqual(['Pick up the parcel.', 'Pick up milk', 'Call Sam.']);
  });

  it('keeps everything for a job from before commands were kept out', () => {
    const refined = [seg('Ghost is the app.', 0, 1000)];
    expect(withoutCommands({}, refined)).toEqual(refined);
  });
});

describe('voice memos in the better words', () => {
  const clip = { text: '![voice 0:05](tape:12000-17000)', startMs: 12_000, endMs: 17_000 };
  const refined = [
    { text: 'Before the memo.', startMs: 8_000, endMs: 11_000 },
    { text: 'After it.', startMs: 18_000, endMs: 20_000 },
  ];

  it('puts each memo back where it was spoken', () => {
    const job = { clips: [clip] };
    expect(withClips(job, refined).map((s) => s.text)).toEqual(['Before the memo.', '![voice 0:05](tape:12000-17000)', 'After it.']);
  });

  it('leaves a take with no memo exactly as it was', () => {
    expect(withClips({}, refined)).toEqual(refined);
    expect(withClips({ clips: [] }, refined)).toEqual(refined);
  });
});

describe('the better words for a take the live reader read', () => {
  const seg = (text: string, startMs: number, endMs: number) => ({ text, startMs, endMs });
  const live = [seg('Kevin owns the release.', 0, 1500), seg('Check box: call the electrician.', 2000, 4000), seg('The budget is Friday.', 4200, 5500)];
  const spans = { skip: [{ startMs: 2000, endMs: 4000 }], keywordAt: [], live };

  it('keeps the live item where a better phrase ran the command and its item together, and never the command', () => {
    const refined = [seg('Kevin owns the release.', 0, 1500), seg('Hey Ghost, add call the electrician to house to-dos.', 1900, 4100), seg('The budget is Friday.', 4200, 5500)];
    expect(withoutCommands(spans, refined).map((s) => s.text)).toEqual(['Kevin owns the release.', 'Check box: call the electrician.', 'The budget is Friday.']);
  });

  it('drops a better phrase that is only the command, where no live phrase kept anything', () => {
    const refined = [seg('Hey Ghost, move this to work.', 2000, 4000)];
    expect(withoutCommands({ skip: [{ startMs: 2000, endMs: 4000 }], live: [] }, refined)).toEqual([]);
  });

  it('puts the better words into the list the live ones went into', () => {
    const body = refinedBody(
      job({ baseBody: '# House TODOs\n\n- [ ] Fix the gutter\n', titled: false, placing: { kind: 'lists', task: true, heading: null, fresh: null } }),
      [seg('Call an electrician to fix the light sockets.', 0, 3000)],
    );
    expect(body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n');
  });

  it('still lands an old job, with no placing, at the end', () => {
    expect(refinedBody(job({ baseBody: '# House TODOs\n\n- [ ] Fix the gutter\n', titled: false }), [seg('Call Sam.', 0, 1000)])).toBe('# House TODOs\n\n- [ ] Fix the gutter\n\nCall Sam.');
  });
});

/**
 * A take played through the live reader (capture/liveTake.ts), then its better words, as the model would hear the same
 * phrases: what the live reader changed or sent elsewhere must not come back raw.
 */
describe('the better words of what the live reader changed', () => {
  const HOUSE = '# House TODOs\n\n- [ ] Fix the gutter\n';
  const play = (lines: string[], notes = [{ id: 'house', body: HOUSE }, { id: 'groceries', body: '# Groceries\n\n- Eggs\n' }]) => {
    const take = new LiveTake(notes);
    const heard = lines.map((text, i) => ({ text, startMs: i * 1000, endMs: i * 1000 + 900 }));
    heard.forEach((segment, i) => take.phrase(segment, i * 1000));
    take.close(lines.length * 1000);
    return { take, heard };
  };
  const refined = (take: LiveTake, heard: { text: string; startMs: number; endMs: number }[], over: Partial<RefineJob>) =>
    refinedBody(job({ titled: false, skip: take.commandSpans, keywordAt: take.keywordSpans, live: take.segments, placing: take.placing, ...over }), heard);

  it('keeps "The note is" out of the to-do written after a switch', () => {
    const { take, heard } = play(["Hey Ghost, add a note to house to do's.", 'The note is call an electrician to fix the light sockets.']);
    expect(refined(take, heard, { baseBody: HOUSE })).toBe(`${HOUSE}- [ ] Call an electrician to fix the light sockets\n`);
  });

  it('keeps things said as a list as the items they were written as', () => {
    const base = '# Groceries\n\n- Eggs\n';
    const { take, heard } = play(['Hey Ghost, add a note to groceries.', 'Milk, butter and bread.']);
    expect(refined(take, heard, { baseBody: base })).toBe('# Groceries\n\n- Eggs\n- Milk\n- Butter\n- Bread\n');
  });

  it('leaves what was taken back out, keeps what replaced it, and never brings “scratch that” back', () => {
    const dropped = play(['Pick up the parcel.', 'Call Sam.', 'Scratch that.']);
    expect(refined(dropped.take, dropped.heard, { baseBody: '', titled: true })).toBe('# Pick up the parcel');
    // The larger model heard the drop and the sentence after it as one phrase.
    const merged = [{ text: 'Scratch that. We need eggs and milk.', startMs: 1900, endMs: 4000 }];
    const after = play(['Pick up the parcel.', 'Call Sam.', 'Scratch that.', 'We need eggs and milk.']);
    expect(refinedBody(job({ titled: true, skip: after.take.commandSpans, keywordAt: after.take.keywordSpans, live: after.take.segments }), [after.heard[0]!, ...merged])).toBe('# Pick up the parcel\n\nWe need eggs and milk.');

    const replaced = play(['Pick up the parcel.', 'The meeting is at three.', 'Actually, the meeting is at four.']);
    expect(refined(replaced.take, replaced.heard, { baseBody: '', titled: true })).toBe('# Pick up the parcel\n\nThe meeting is at four.');

    const changed = play(['Pick up the parcel.', 'The meeting is at three.', 'No wait, four.']);
    expect(refined(changed.take, changed.heard, { baseBody: '', titled: true })).toBe('# Pick up the parcel\n\nThe meeting is at four.');
  });

  it('after Undo, keeps the sentence and the opener as words, and leaves the keyword out', () => {
    const take = new LiveTake([{ id: 'groceries', body: '# Groceries\n\n- Eggs\n' }]);
    const heard = [
      { text: 'Call Sam.', startMs: 0, endMs: 900 },
      { text: 'Hey Ghost, scratch that.', startMs: 1000, endMs: 1900 },
    ];
    heard.forEach((segment, i) => take.phrase(segment, i * 1000));
    const chip = take.chips.at(-1);
    take.undo(chip?.phase === 'tookBack' ? chip.undo! : -1);
    take.close(2000);
    expect(take.segments.map((s) => s.text)).toEqual(['Call Sam.', 'Scratch that.']);
    expect(refined(take, heard, { baseBody: '', titled: true })).toBe('# Call Sam\n\nScratch that.');
  });

  it('leaves what a one-shot sent to another note out of the take’s own', () => {
    const { take, heard } = play(['Kevin owns the release.', 'Hey Ghost, add to House TODOs.', 'Call the electrician.', 'Buy fuses.', 'Ring the plumber.', 'Next, the budget review is Friday.']);
    expect(refined(take, heard, { baseBody: '', titled: true })).toBe('# Kevin owns the release\n\nNext, the budget review is Friday.');
  });
});
