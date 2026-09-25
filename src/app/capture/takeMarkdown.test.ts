import { describe, expect, it } from 'vitest';
import { quietHost } from '../../test/takeHost.ts';
import { asBoardMarkdown, Take, takeMarkdown } from './take.ts';

/**
 * A take as markdown (capture/take.ts `takeMarkdown`): the one way the page it is spoken onto and the note saved at
 * Done are made from it, so the two cannot disagree.
 */

const said = (text: string, startMs: number) => ({ text, startMs, endMs: startMs + 900 });
const table = '| Bug | Owner |\n| --- | --- |\n| Login | Sam |';

describe('a take’s markdown', () => {
  it('lays the words out by their cues, with the phrase still being guessed after them and marked as pending', () => {
    const shown = takeMarkdown({ segments: [said('Grocery run.', 0), said('Bullet point, eggs.', 1000)], tables: [], asBoard: false }, { titled: true, partial: 'and milk' });
    expect(shown.markdown).toBe('# Grocery run\n\n- Eggs\n\nand milk');
    expect(shown.pendingFrom).toBe(shown.markdown.indexOf('and milk'));
  });

  it('keeps an opening sentence as a sentence when the words go on the end of a note that has a title', () => {
    expect(takeMarkdown({ segments: [said('Grocery run.', 0)], tables: [], asBoard: false }, { titled: false }).markdown).toBe('Grocery run.');
  });

  it('puts its tables after the words, as blocks of their own and with no line break at the end', () => {
    const shown = takeMarkdown({ segments: [said('Bug bash on Friday.', 0)], tables: [table], asBoard: false }, { titled: false });
    expect(shown.markdown).toBe(`Bug bash on Friday.\n\n${table}`);
  });

  it('applies links and the board, after which there is no telling where the guess starts', () => {
    const linked = takeMarkdown({ segments: [said('Book the cabin.', 0)], tables: [], asBoard: false }, { titled: false, partial: 'soon', link: (text) => text.replace('cabin', '[cabin](https://example.com)') });
    expect(linked.markdown).toBe('Book the [cabin](https://example.com). soon');
    expect(linked.pendingFrom).toBeNull();

    const list = [said('Bullet point, eggs.', 0), said('Bullet point, milk.', 1000)];
    expect(takeMarkdown({ segments: list, tables: [], asBoard: false }, { titled: false, board: () => 'a board' }).markdown).toBe('- Eggs\n- Milk');
    const board = takeMarkdown({ segments: list, tables: [], asBoard: true }, { titled: false, board: asBoardMarkdown });
    expect(board.markdown).toBe(asBoardMarkdown('- Eggs\n- Milk'));
    expect(board.markdown).not.toBe('- Eggs\n- Milk');
    expect(board.pendingFrom).toBeNull();
  });

  it('leaves words with no list to make a board of as they are', () => {
    expect(asBoardMarkdown('Just a sentence.')).toBe('Just a sentence.');
  });
});

describe('what a take has to save', () => {
  it('is words that come to something, a table, or a voice memo', () => {
    const take = new Take(quietHost());
    expect(take.hasContent).toBe(false);
    take.listen(said('Hello.', 0));
    expect(take.hasContent).toBe(true);
    const tables = new Take(quietHost());
    tables.tables = [table];
    expect(tables.hasContent).toBe(true);
    const clips = new Take(quietHost());
    clips.clips = [said('![voice 0:01](tape:0-1000)', 0)];
    expect(clips.hasContent).toBe(true);
  });

  it('is not a cue said on its own, which is held for a sentence that never comes', () => {
    const take = new Take(quietHost());
    take.listen(said('Bullet point.', 0));
    expect(take.segments).toHaveLength(1);
    expect(take.hasContent).toBe(false);
  });
});
