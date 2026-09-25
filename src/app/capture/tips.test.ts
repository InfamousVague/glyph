import { describe, expect, it } from 'vitest';
import { bareWords, runOf } from '../ai/instruction.ts';
import { bookNoteBody } from '../book/book.ts';
import { ASKS, starters, tipInPause, tips } from './tips.ts';

describe('tips in a pause', () => {
  it('teach the newer cues, and a note’s board lanes when it has a board', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true, lane: 'Doing' }).map((tip) => tip.say);
    expect(said).toContain('Info box');
    expect(said).toContain('Option');
    expect(said).toContain('Hey Ghost, add … to Doing');
    expect(said).toContain('Hey Ghost, move … to Doing');
    expect(tips({ noteTitle: null, continuing: false }).some((tip) => tip.say.includes('to Doing'))).toBe(false);
  });

  it('teach a chapter for a book the library has, or how to make one', () => {
    expect(tips({ noteTitle: 'Groceries', continuing: false, book: 'Field guide' }).map((tip) => tip.say)).toContain('Hey Ghost, add a chapter to Field guide');
    expect(tips({ noteTitle: null, continuing: false }).map((tip) => tip.say)).toContain('Hey Ghost, make a book called …');
  });
});

describe('a note with a board', () => {
  it('still comes round to every routing line, the ones past the cues’ slots after them', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true, lane: 'Doing', book: 'Field guide' }).map((tip) => tip.say);
    for (const line of ['Hey Ghost, add … to Groceries', 'Hey Ghost, move … to Doing', 'Hey Ghost, add a table to Groceries', 'Hey Ghost, add a chapter to Field guide']) expect(said).toContain(line);
    expect(said.some((line) => /fix the spelling|summarize/i.test(line))).toBe(false);
  });
});

describe('the card before the first word', () => {
  it('shows a couple of each kind, naming a note of theirs and a book’s chapter over moving the take', () => {
    const card = starters({ noteTitle: 'Groceries', book: 'Field guide', asking: true });
    expect(card.shape.map((tip) => tip.say)).toEqual(['Bullet point', 'The next item is …']);
    expect(card.send.map((tip) => tip.say)).toEqual(['Hey Ghost, add … to Groceries', 'Hey Ghost, add a chapter to Field guide']);
    expect(card.ask.map((tip) => tip.say)).toEqual(['Hey Ghost, fix the spelling', 'Hey Ghost, summarize this']);
    expect(starters({ noteTitle: 'Groceries' }).send.map((tip) => tip.say)).toEqual(['Hey Ghost, add … to Groceries', 'Hey Ghost, move this to Groceries']);
  });

  it('still sends somewhere with no note to name, drops the keyword when it is off, and offers no ask where none can run', () => {
    const card = starters({ noteTitle: null, keyword: false });
    expect(card.send.map((tip) => tip.say)).toEqual(['Make a list called …', 'Make a book called …']);
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

describe('the tip for a pause', () => {
  const groceries = { id: 'groceries', title: 'Groceries', note: { body: '# Groceries\n\n- Eggs' } };
  const work = { id: 'work', title: 'Work', note: { body: '# Work' } };
  const guide = { id: 'guide', title: 'Field guide', note: { body: bookNoteBody('Field guide', ['Birds']) } };
  const board = '# Launch\n\n```board\nTo do:\nDoing:\nDone:\n```';
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

  it('names a continued board’s second lane, where things go once started, and its first when it has only one', () => {
    expect(all({ target: { body: board } })).toContain('Hey Ghost, move … to Doing');
    expect(all({ target: { body: '# Solo\n\n```board\nTo do:\n```' } })).toContain('Hey Ghost, move … to To do');
    expect(all().some((say) => say.startsWith('Hey Ghost, move … to'))).toBe(false);
  });

  it('teaches a chapter for a book in the library, never the book being written to', () => {
    expect(all({ notes: [groceries, guide] })).toContain('Hey Ghost, add a chapter to Field guide');
    const own = all({ notes: [groceries, guide], own: 'guide', target: guide.note });
    expect(own).not.toContain('Hey Ghost, add a chapter to Field guide');
    expect(own).toContain('Hey Ghost, make a book called …');
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
