import { describe, expect, it } from 'vitest';
import { readInstruction } from '../ai/instruction.ts';
import { ASK, COMMAND, CUE_ALONE, PHRASES, renderExample } from './phrases.ts';
import { LiveTake } from '../capture/liveTake.ts';

/**
 * The guide may only teach what the speech rules do. Each example is rendered
 * by the real rules and must still produce its marker; a failure here means a
 * rule changed and the guide (src/app/guide/phrases.ts) has to change with it.
 */
describe('the spoken-markdown guide', () => {
  for (const group of PHRASES) {
    it(`"${group.title}" still produces ${JSON.stringify(group.example.expect)}`, () => {
      const markdown = renderExample(group.example);
      expect(markdown).toContain(group.example.expect);
    });
  }

  it('never shows a cue word left behind as text', () => {
    for (const group of PHRASES) {
      const markdown = renderExample(group.example);
      expect(markdown).not.toMatch(/\b(bullet point|next point|heading:|new paragraph|new section|quote:|check box|divider|end bold|end italic|number one|number two)\b/i);
    }
  });

  it('applies a cue said on its own to the next sentence, as the guide promises', () => {
    expect(renderExample(CUE_ALONE)).toContain(CUE_ALONE.expect);
  });

  it('shows beside each cue the mark its example really writes', () => {
    for (const group of PHRASES) {
      const first = group.symbol.split(' ')[0] ?? '';
      if (first) expect(renderExample(group.example), group.title).toContain(first);
    }
  });
});

/** The habits page's two phrases, bare as the page says them, and with "Hey Ghost" first, which is optional (docs/DESIGN.md §136). */
describe('what the habits page says to say, with or without “Hey Ghost” first', () => {
  const groceries = { id: 'g1', title: 'Groceries', note: { body: '# Groceries\n\n- Eggs\n' } };
  const library = [groceries, { id: 'w1', title: 'Work', note: { body: '# Work\n' } }];
  const keyed = (say: string) => `Hey Ghost, ${say.charAt(0).toLowerCase()}${say.slice(1)}`;
  const ways = (say: string) => [say, keyed(say)];

  it('is a command the recorder carries out as it is said, putting the words in the note it names', () => {
    for (const said of ways(COMMAND.say)) {
      const take = new LiveTake(library.map((c) => ({ id: c.id, body: c.note.body })));
      take.phrase({ text: `${said}.`, startMs: 0, endMs: 1500 }, 0);
      take.close(2000);
      expect(take.body('g1'), said).toBe(`# Groceries\n\n- Eggs\n- ${COMMAND.words.charAt(0).toUpperCase()}${COMMAND.words.slice(1)}\n`);
      expect(take.result().made, said).toEqual([]);
    }
  });

  it('is read the same by the reader at Done, putting the words in the note it names', async () => {
    for (const said of ways(COMMAND.say)) {
      const read = await readInstruction(said, library);
      expect(read.kind, said).toBe('command');
      if (read.kind !== 'command' || read.plan.kind !== 'place') throw new Error(`not a command to place words: ${read.kind}`);
      expect(read.plan.note.title).toBe(COMMAND.note);
      expect(read.plan.text).toBe(COMMAND.words);
      // One thing, not a list of them.
      expect(read.plan.items).toBeUndefined();
    }
  });

  it('is an ask the AI runs on the note, not words written into it', async () => {
    for (const said of ways(ASK.say)) expect(await readInstruction(said, library), said).toEqual({ kind: 'run', run: ASK.run });
  });
});
