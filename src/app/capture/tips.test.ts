import { describe, expect, it } from 'vitest';
import { bareWords, readInstruction, runOf } from '../ai/instruction.ts';
import { bookNoteBody } from '../book/book.ts';
import { LiveTake } from './liveTake.ts';
import { ASKS, starters, tipInPause, tips, type Tip } from './tips.ts';

describe('tips in a pause', () => {
  it('teach the newer cues', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true }).map((tip) => tip.say);
    expect(said).toContain('Info box');
    expect(said).toContain('Option');
  });

  // A take-back is a cue, not a command (docs/DESIGN.md §130): said without any keyword, and taught early.
  it('teach taking back the last thing said, and it works as taught', () => {
    const tip = tips({ noteTitle: 'Groceries', continuing: true }).find((candidate) => candidate.say === 'Scratch that');
    expect(tip).toEqual({ say: 'Scratch that', does: 'to take back the last thing you said' });
    const take = new LiveTake([]);
    take.phrase({ text: 'Pick up the parcel.', startMs: 0, endMs: 900 }, 0);
    take.phrase({ text: 'Call Sam.', startMs: 1000, endMs: 1900 }, 1000);
    take.phrase({ text: `${tip!.say}.`, startMs: 2000, endMs: 2900 }, 2000);
    take.close(3000);
    expect(take.result().made).toEqual(['# Pick up the parcel']);
  });

  // Changed on purpose (docs/DESIGN.md §127): a recording no longer makes a voice memo, so no tip offers one. The clips
  // already in notes still play.
  it('offer no voice memo', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true }).flatMap((tip) => [tip.say, tip.does]);
    expect(said.some((line) => /\bmemo\b/i.test(line))).toBe(false);
  });

  // Changed on purpose (docs/DESIGN.md §126, §127): a recording no longer carries out a table, a book or a chapter, so
  // no tip teaches one. A board's lane is carried out on its own Speak but not taught yet, until Matt says whether a
  // tip for it should come back (§127, question 5).
  // A command needs no keyword (docs/DESIGN.md §136): every tip says it bare, in a form the bare gate takes.
  it('teach only the commands a recording carries out as they are said, without the keyword', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true }).map((tip) => tip.say);
    for (const line of ['Add … to Groceries', 'New item for Groceries, …', 'New note', 'Move this to Groceries']) expect(said).toContain(line);
    expect(said.some((line) => /\b(?:table|chapter|book|lane)\b/i.test(line))).toBe(false);
    expect(said.some((line) => /fix the spelling|summari[sz]e/i.test(line))).toBe(false);
    expect(said.some((line) => /Hey Ghost/i.test(line))).toBe(false);
    // A note whose title does not say it is a list: "a note" said is the evidence the gate wants.
    expect(tips({ noteTitle: 'Work', continuing: true }).map((tip) => tip.say)).toContain('Add a note to Work, …');
  });
});

describe('the card before the first word', () => {
  it('shows a couple of each kind, naming a note of theirs', () => {
    const card = starters({ noteTitle: 'Groceries', asking: true });
    expect(card.shape.map((tip) => tip.say)).toEqual(['Bullet point', 'The next item is …']);
    expect(card.send.map((tip) => tip.say)).toEqual(['Add … to Groceries', 'Move this to Groceries']);
    expect(card.ask.map((tip) => tip.say)).toEqual(['Fix the spelling', 'Summarise this']);
  });

  it('still sends somewhere with no note to name, and offers no ask where none can run', () => {
    const card = starters({ noteTitle: null });
    expect(card.send.map((tip) => tip.say)).toEqual(['Make a list called … with …']);
    expect(card.ask).toEqual([]);
    expect(starters({ noteTitle: null, asking: true }).ask[0]?.say).toBe('Fix the spelling');
  });

  // Its items said the natural way, in a sentence after the name, would be the reader's title: the tip teaches "with".
  it('makes a new list with its items, as the reader at Done reads it, with the keyword or without', async () => {
    const [tip] = starters({ noteTitle: null }).send;
    for (const lead of ['', 'Hey Ghost, ']) {
      const said = `${lead}${lead ? tip!.say.charAt(0).toLowerCase() + tip!.say.slice(1) : tip!.say}`.replace('…', 'packing').replace('…', 'toothbrush, socks and charger');
      await expect(readInstruction(`${said}.`, []), said).resolves.toEqual({ kind: 'command', plan: { kind: 'create-list', title: 'packing', items: ['toothbrush', 'socks', 'charger'] } });
    }
  });

  it('never suggests an ask the reader would not take: each one, spoken first, is read as its run, bare as the whole phrase', () => {
    expect(ASKS.length).toBe(5);
    for (const ask of ASKS) {
      const bare = bareWords(ask.say);
      expect(bare?.keyed, ask.say).toBe(false);
      expect(runOf(bare!.words, { whole: true }), ask.say).not.toBeNull();
      const keyed = bareWords(`Hey Ghost, ${ask.say.charAt(0).toLowerCase()}${ask.say.slice(1)}`);
      expect(keyed?.keyed, ask.say).toBe(true);
      expect(runOf(keyed!.words), ask.say).not.toBeNull();
    }
  });
});

/**
 * Every tip that sends words to a note, said with a sample of words, as the live reader hears it (capture/liveRoute.ts):
 * a tip is always something that works.
 */
describe('the tips that send words to a note', () => {
  const groceries = { id: 'groceries', body: '# Groceries\n\n- Eggs\n' };
  const work = { id: 'work', body: '# Work\n\nNotes.\n' };
  const sending = (list: readonly Tip[]) => list.filter((tip) => /Groceries|new note/i.test(tip.say));

  it('are each carried out, mid-take on a note’s own Speak, as the tip says, without the keyword', () => {
    const list = sending([...tips({ noteTitle: 'Groceries', continuing: true }), ...starters({ noteTitle: 'Groceries' }).send]);
    expect(list.length).toBeGreaterThan(3);
    for (const tip of list) {
      const take = new LiveTake([groceries, work], { own: work });
      take.phrase({ text: 'First words.', startMs: 0, endMs: 900 }, 0);
      const said = `${tip.say.replace('…', 'oat milk')}.`;
      take.phrase({ text: said, startMs: 1000, endMs: 1900 }, 1000);
      take.close(2000);
      const { bodies, made } = take.result();
      if (/move this/i.test(tip.say)) expect(take.aim?.id, said).toBe('groceries');
      else if (/new note/i.test(tip.say)) expect(take.parts, said).toHaveLength(1);
      else expect(bodies.get('groceries'), said).toContain('Oat milk');
      expect(made.join(''), said).not.toMatch(/Hey Ghost/i);
    }
  });

  // The item after the name in the same breath, as the tip says: mid-take a bare command needs its words in its own
  // phrase, so "New item for Groceries." | "Oat milk." is two lines of the take, which is why the tip does not teach it.
  it('teach the item in the same breath as its note, since the two breaths apart are words mid-take', () => {
    const tip = tips({ noteTitle: 'Groceries', continuing: true }).find((candidate) => candidate.say.startsWith('New item for'));
    expect(tip).toEqual({ say: 'New item for Groceries, …', does: 'with the item after it, to add to its list' });
    const take = new LiveTake([groceries, work], { own: work });
    take.phrase({ text: 'First words.', startMs: 0, endMs: 900 }, 0);
    take.phrase({ text: 'New item for Groceries.', startMs: 1000, endMs: 1900 }, 1000);
    take.phrase({ text: 'Oat milk.', startMs: 2000, endMs: 2900 }, 2000);
    take.close(3000);
    expect(take.result().bodies.get('groceries')).toBe(groceries.body);
  });

  // A note whose title does not say it is a list gets the "a note" form, which the gate takes into any note.
  it('send words into a note whose title does not say it is a list, with “a note” said', () => {
    const [tip] = starters({ noteTitle: 'Work' }).send;
    expect(tip!.say).toBe('Add a note to Work, …');
    const take = new LiveTake([groceries, work], { own: groceries });
    take.phrase({ text: 'First words.', startMs: 0, endMs: 900 }, 0);
    take.phrase({ text: `${tip!.say.replace('…', 'call Sam')}.`, startMs: 1000, endMs: 1900 }, 1000);
    take.close(2000);
    expect(take.result().bodies.get('work')).toBe('# Work\n\nNotes.\n\nCall Sam.');
  });

  // A title that starts with a verb is read as what to do ("Call log" is "call log"), so no tip names it: bare, "Add a
  // note to Call log, call Sam" and "Move this to Book club" are words. The tips name the next note, and the card
  // offers a new list instead.
  it('never name a note whose title starts with a verb, and each tip they give instead is carried out', () => {
    const calls = { id: 'calls', title: 'Call log', note: { body: '# Call log\n\n- Jo\n' } };
    const club = { id: 'club', title: 'Book club', note: { body: '# Book club\n\n- Dune\n' } };
    const named = [...new Set(Array.from({ length: 120 }, (_, turn) => tipInPause({ notes: [calls, club, { id: 'work', title: 'Work', note: { body: work.body } }], own: 'new', target: null, pluginTips: () => [], turn })?.say ?? ''))];
    expect(named.some((say) => /Call log|Book club/.test(say))).toBe(false);
    const routing = named.filter((say) => /Work|new note/i.test(say));
    expect(routing).toEqual(['Add a note to Work, …', 'New item for Work, …', 'Move this to Work']);
    for (const say of routing) {
      const take = new LiveTake([groceries, work], { own: groceries });
      take.phrase({ text: 'First words.', startMs: 0, endMs: 900 }, 0);
      take.phrase({ text: `${say.replace('…', 'call Sam')}.`, startMs: 1000, endMs: 1900 }, 1000);
      take.close(2000);
      if (/move this/i.test(say)) expect(take.aim?.id, say).toBe('work');
      else expect(take.result().bodies.get('work'), say).toContain('Call Sam');
    }
    expect(starters({ noteTitle: 'Call log' }).send.map((tip) => tip.say)).toEqual(['Make a list called … with …']);
  });
});

describe('the tip for a pause', () => {
  const groceries = { id: 'groceries', title: 'Groceries', note: { body: '# Groceries\n\n- Eggs' } };
  const work = { id: 'work', title: 'Work', note: { body: '# Work' } };
  const guide = { id: 'guide', title: 'Field guide', note: { body: bookNoteBody('Field guide', ['Birds']) } };
  const pause = (turn: number, over: Partial<Parameters<typeof tipInPause>[0]> = {}) =>
    tipInPause({ notes: [groceries, work], own: 'new', target: null, pluginTips: () => [], turn, ...over });
  /** Every tip a recording's pauses come round to: more turns than there are tips, so each is seen. */
  const all = (over: Partial<Parameters<typeof tipInPause>[0]> = {}) => [...new Set(Array.from({ length: 120 }, (_, turn) => pause(turn, over)?.say ?? ''))];

  it('comes round the tips in turn, and back to the first after the last', () => {
    const list = tips({ noteTitle: 'Groceries', continuing: false });
    expect(pause(0)).toEqual(list[0]);
    expect(pause(1)).toEqual(list[1]);
    expect(pause(4)).toEqual(list[4]);
    expect(pause(list.length)).toEqual(list[0]);
    expect(pause(list.length + 2)).toEqual(list[2]);
  });

  it('names the most recent note that is not the one being written to, in the form its title allows', () => {
    expect(all()).toContain('Add … to Groceries');
    const aimed = all({ own: 'groceries', target: groceries.note });
    expect(aimed).toContain('Add a note to Work, …');
    expect(aimed.some((say) => say.includes('Groceries'))).toBe(false);
  });

  it('teaches nothing for a book or a board', () => {
    expect(all({ notes: [groceries, guide] }).some((say) => /\b(?:chapter|book)\b/i.test(say))).toBe(false);
    // The book the most recent note: the tip names the next note, never the book.
    expect(all({ notes: [guide, work] })).toContain('Add a note to Work, …');
    expect(all({ notes: [guide, work] }).some((say) => /Field guide/.test(say))).toBe(false);
    expect(all({ target: { body: '# Launch\n\n```board\nTo do:\nDoing:\n```' } }).some((say) => /Doing/.test(say))).toBe(false);
  });

  // No plugin gives a tip now (Notion's, which taught a command that had gone, went with it: docs/DESIGN.md §127);
  // the seam stays, and is held here with one of a plugin's own making.
  it('adds the plugins’ own tips for the note it names, as the plugin wrote them', () => {
    const asked: (string | null)[] = [];
    const pluginTips = (recent: string | null) => {
      asked.push(recent);
      return [{ say: 'Ring the bell', does: 'to try a plugin’s tip' }];
    };
    const plain = all({ pluginTips });
    expect(plain).toContain('Ring the bell');
    expect(asked[0]).toBe('Groceries');
    expect(plain).toContain('Add … to Groceries');
    expect(plain.some((say) => say.startsWith('Hey Ghost'))).toBe(false);
  });
});
