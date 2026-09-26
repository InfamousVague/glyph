import { describe, expect, it } from 'vitest';
import { bareWords, runOf } from '../ai/instruction.ts';
import { bookNoteBody } from '../book/book.ts';
import { LiveTake } from './liveTake.ts';
import { ASKS, starters, tipInPause, tips, type Tip } from './tips.ts';

describe('tips in a pause', () => {
  it('teach the newer cues', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true }).map((tip) => tip.say);
    expect(said).toContain('Info box');
    expect(said).toContain('Option');
  });

  // Changed on purpose (docs/DESIGN.md §126): a recording no longer carries out a table, a book, a chapter or a
  // board's lane, so no tip teaches one.
  it('teach only the commands a recording carries out as they are said', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true }).map((tip) => tip.say);
    for (const line of ['Hey Ghost, add … to Groceries', 'Hey Ghost, new item for Groceries', 'Hey Ghost, new note', 'Hey Ghost, move this to Groceries']) expect(said).toContain(line);
    expect(said.some((line) => /\b(?:table|chapter|book|lane)\b/i.test(line))).toBe(false);
    expect(said.some((line) => /fix the spelling|summarize/i.test(line))).toBe(false);
  });
});

describe('the card before the first word', () => {
  it('shows a couple of each kind, naming a note of theirs', () => {
    const card = starters({ noteTitle: 'Groceries', asking: true });
    expect(card.shape.map((tip) => tip.say)).toEqual(['Bullet point', 'The next item is …']);
    expect(card.send.map((tip) => tip.say)).toEqual(['Hey Ghost, add … to Groceries', 'Hey Ghost, move this to Groceries']);
    expect(card.ask.map((tip) => tip.say)).toEqual(['Hey Ghost, fix the spelling', 'Hey Ghost, summarize this']);
  });

  it('still sends somewhere with no note to name, drops the keyword when it is off, and offers no ask where none can run', () => {
    const card = starters({ noteTitle: null, keyword: false });
    expect(card.send.map((tip) => tip.say)).toEqual(['Make a list called …']);
    expect(card.ask).toEqual([]);
    expect(starters({ noteTitle: null, keyword: false, asking: true }).ask[0]?.say).toBe('Fix the spelling');
  });

  it('never suggests an ask the reader would not take: each one, spoken first with the keyword, is read as its run', () => {
    expect(ASKS.length).toBe(5);
    for (const ask of ASKS) {
      const said = `Hey Ghost, ${ask.say.charAt(0).toLowerCase()}${ask.say.slice(1)}`;
      const bare = bareWords(said);
      expect(bare?.keyed, said).toBe(true);
      expect(runOf(bare!.words), said).not.toBeNull();
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

  it('are each carried out, mid-take on a note’s own Speak, as the tip says', () => {
    const list = sending([...tips({ noteTitle: 'Groceries', continuing: true }), ...starters({ noteTitle: 'Groceries' }).send]);
    expect(list.length).toBeGreaterThan(3);
    for (const tip of list) {
      const take = new LiveTake([groceries, work], { own: work });
      take.phrase({ text: 'First words.', startMs: 0, endMs: 900 }, 0);
      const said = `${tip.say.replace('…', 'oat milk')}${/new item for/i.test(tip.say) ? ', oat milk' : ''}.`;
      take.phrase({ text: said, startMs: 1000, endMs: 1900 }, 1000);
      take.close(2000);
      const { bodies, made } = take.result();
      if (/move this/i.test(tip.say)) expect(take.aim?.id, said).toBe('groceries');
      else if (/new note/i.test(tip.say)) expect(take.parts, said).toHaveLength(1);
      else expect(bodies.get('groceries'), said).toContain('Oat milk');
      expect(made.join(''), said).not.toMatch(/Hey Ghost/i);
    }
  });
});

describe('the tip for a pause', () => {
  const groceries = { id: 'groceries', title: 'Groceries', note: { body: '# Groceries\n\n- Eggs' } };
  const work = { id: 'work', title: 'Work', note: { body: '# Work' } };
  const guide = { id: 'guide', title: 'Field guide', note: { body: bookNoteBody('Field guide', ['Birds']) } };
  const pause = (turn: number, over: Partial<Parameters<typeof tipInPause>[0]> = {}) =>
    tipInPause({ notes: [groceries, work], own: 'new', target: null, keyword: true, pluginTips: () => [], turn, ...over });
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

  it('names the most recent note that is not the one being written to', () => {
    expect(all()).toContain('Hey Ghost, add … to Groceries');
    const aimed = all({ own: 'groceries', target: groceries.note });
    expect(aimed).toContain('Hey Ghost, add … to Work');
    expect(aimed.some((say) => say.includes('Groceries'))).toBe(false);
  });

  it('teaches nothing for a book or a board', () => {
    expect(all({ notes: [groceries, guide] }).some((say) => /\b(?:chapter|book)\b/i.test(say))).toBe(false);
    expect(all({ target: { body: '# Launch\n\n```board\nTo do:\nDoing:\n```' } }).some((say) => /Doing/.test(say))).toBe(false);
  });

  it('adds the plugins’ own tips for the note it names, said after the keyword only when it is on', () => {
    const asked: (string | null)[] = [];
    const pluginTips = (recent: string | null) => {
      asked.push(recent);
      return [{ say: 'Send that to Notion', does: 'to make it a task' }];
    };
    expect(all({ pluginTips })).toContain('Hey Ghost, send that to Notion');
    expect(asked[0]).toBe('Groceries');
    const plain = all({ pluginTips, keyword: false });
    expect(plain).toContain('Send that to Notion');
    expect(plain).toContain('Add … to Groceries');
    expect(plain.some((say) => say.startsWith('Hey Ghost'))).toBe(false);
  });
});
