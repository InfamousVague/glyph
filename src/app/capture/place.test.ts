import { describe, expect, it } from 'vitest';
import { appendBody } from './appendBody.ts';
import { END, itemsOf, placeTake, placingFor } from './place.ts';

const HOUSE = '# House TODOs\n\n- [ ] Fix the gutter\n';
const JOBS = '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n';

describe('the kind of place a note has for the words', () => {
  it('is the end of a note’s own Speak, byte for byte, unless its title says what it holds', () => {
    expect(placingFor('# Daily Life\n\n- Walked\n\nSome words.', { own: true })).toEqual(END);
    // A title that is about tasks is not a list of them.
    expect(placingFor('# Task Management\n\nHow I keep on top of work.', { own: true })).toEqual(END);
    expect(placingFor('# Task list\n', { own: true })).toEqual({ kind: 'lists', task: true, heading: null, fresh: 'task' });
    expect(placingFor(HOUSE, { own: true })).toEqual({ kind: 'lists', task: true, heading: null, fresh: null });
    expect(placingFor('# Groceries\n\n- Eggs', { own: true })).toEqual({ kind: 'lists', task: false, heading: null, fresh: null });
  });

  it('is the end for a move, or words asked for as a paragraph', () => {
    expect(placingFor(HOUSE, { move: true })).toEqual(END);
    expect(placingFor(HOUSE, { said: { paragraph: true } })).toEqual(END);
  });

  it('is the note’s lists, a new one when its title or the command says which, or the end', () => {
    expect(placingFor(JOBS)).toEqual({ kind: 'lists', task: true, heading: null, fresh: null });
    expect(placingFor(JOBS, { said: { task: true }, heading: 'Kitchen' })).toEqual({ kind: 'lists', task: true, heading: 'Kitchen', fresh: null });
    expect(placingFor('# House TODOs\n')).toEqual({ kind: 'lists', task: true, heading: null, fresh: 'task' });
    expect(placingFor('# Packing list\n')).toEqual({ kind: 'lists', task: false, heading: null, fresh: 'bullet' });
    expect(placingFor('# Daily Life\n\nWords.')).toEqual(END);
    expect(placingFor('# Daily Life\n\nWords.', { said: { task: true } })).toEqual({ kind: 'lists', task: true, heading: null, fresh: 'task' });
  });

  it('reads the title and the lists after the front matter', () => {
    expect(placingFor('---\ntitle: Chores\nbook: false\n---\nWords.')).toEqual({ kind: 'lists', task: true, heading: null, fresh: 'task' });
  });
});

describe('the take as items', () => {
  it('makes each sentence a thing, with the sentences that carry one on under it', () => {
    expect(itemsOf('Call an electrician to fix the light sockets. Because the switch sparks. Ask about the porch light too.')).toEqual({
      items: [
        { text: 'Call an electrician to fix the light sockets.', more: ['Because the switch sparks.'] },
        { text: 'Ask about the porch light too.', more: [] },
      ],
      after: [],
    });
  });

  it('takes list lines as they are, strips the words that join items, and keeps what is not an item for the end', () => {
    expect(itemsOf('- Milk\n- Eggs\n  free range\n\nAnd also bread.\n\n## Later\n\n| a | b |')).toEqual({
      items: [
        { text: 'Milk', more: [] },
        { text: 'Eggs', more: ['free range'] },
        { text: 'bread.', more: [] },
      ],
      after: ['## Later', '| a | b |'],
    });
  });

  it('keeps a long thought said first as a paragraph, and one said later under the item before it', () => {
    const long = `Word ${'word '.repeat(30).trim()}.`;
    expect(itemsOf(long)).toEqual({ items: [], after: [long] });
    expect(itemsOf(`Call Sam. ${long}`)).toEqual({ items: [{ text: 'Call Sam.', more: [long] }], after: [] });
  });
});

describe('writing the words in', () => {
  const lists = (base: string, said = {}, heading: string | null = null) => placingFor(base, { said, heading });

  it('writes Matt’s to-do into House TODOs’ list, after its last item', () => {
    expect(placeTake(HOUSE, 'Call an electrician to fix the light sockets.', lists(HOUSE))).toEqual({
      body: '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n',
      blocks: ['- [ ] Call an electrician to fix the light sockets'],
      spot: 'in its to-do list',
    });
  });

  it('starts a to-do list in a to-do note that has none', () => {
    expect(placeTake('# House TODOs\n', 'Call an electrician.', lists('# House TODOs\n')).body).toBe('# House TODOs\n\n- [ ] Call an electrician\n');
  });

  it('puts an item under the heading it shares words with, not one that only shares a verb', () => {
    const placed = placeTake(JOBS, 'Call an electrician to fix the light sockets.', lists(JOBS));
    expect(placed.body).toBe('# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call an electrician to fix the light sockets\n');
    expect(placed.spot).toBe('under Electrical');
  });

  it('puts it under a heading said for it, whatever it would otherwise fit', () => {
    // "Call Sam" shares nothing with either list, and would go to Kitchen, the first with something still to do.
    expect(placeTake(JOBS, 'Call Sam.', lists(JOBS)).body).toContain('- [ ] Fix tap\n- [ ] Call Sam\n\n## Electrical');
    expect(placeTake(JOBS, 'Call Sam.', lists(JOBS, {}, 'electrical')).body).toBe('# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call Sam\n');
  });

  it('keeps related things said together in one list, and sends one that plainly fits another there', () => {
    const base = '# Home\n\n## Electrical\n- [ ] Rewire porch light\n\n## Garden\n- [ ] Mow the lawn\n';
    const placed = placeTake(base, 'Call an electrician about the porch light. Get a spare fuse. And for the garden, trim the hedge.', lists(base));
    expect(placed.body).toBe(
      '# Home\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call an electrician about the porch light\n- [ ] Get a spare fuse\n\n## Garden\n- [ ] Mow the lawn\n- [ ] For the garden, trim the hedge\n',
    );
    expect(placed.blocks).toEqual(['- [ ] Call an electrician about the porch light\n- [ ] Get a spare fuse', '- [ ] For the garden, trim the hedge']);
  });

  it('with nothing to go by, goes to the first to-do list with something still to do, else the last list', () => {
    const base = '# Plans\n\n- [x] Done thing\n\n- [ ] Open thing\n\n- plain\n';
    expect(placeTake(base, 'Zebra crossing.', lists(base)).body).toBe('# Plans\n\n- [x] Done thing\n\n- [ ] Open thing\n- [ ] Zebra crossing\n\n- plain\n');
    const plain = '# Plans\n\n- one\n\n1. two\n';
    expect(placeTake(plain, 'Zebra.', lists(plain)).body).toBe('# Plans\n\n- one\n\n1. two\n2. Zebra\n');
  });

  it('keeps only to-do lists for a to-do, and writes in each list’s own style', () => {
    const base = '# Mixed\n\n* [ ] Starred to-do\n\nShopping:\n- eggs\n';
    expect(placeTake(base, 'Call Sam.', lists(base, { task: true })).body).toBe('# Mixed\n\n* [ ] Starred to-do\n* [ ] Call Sam\n\nShopping:\n- eggs\n');
    const numbered = 'Steps\n\n  1) Build\n  2) Test\n';
    expect(placeTake(numbered, 'Ship it. Celebrate.', lists(numbered)).body).toBe('Steps\n\n  1) Build\n  2) Test\n  3) Ship it\n  4) Celebrate\n');
  });

  it('puts what is not an item after the lists, at the end', () => {
    expect(placeTake(HOUSE, 'Call Sam.\n\n## Later', lists(HOUSE)).body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n\n## Later\n');
  });

  it('writes the end exactly as appendBody does, and nothing for nothing said', () => {
    expect(placeTake('# Daily Life\n\nWords.\n', 'More words.', END).body).toBe(appendBody('# Daily Life\n\nWords.\n', 'More words.'));
    expect(placeTake(HOUSE, '', lists(HOUSE))).toEqual({ body: HOUSE, blocks: [], spot: null });
  });

  it('adds a card to a board’s lane', () => {
    const board = '# Launch\n\n```board\nTo do: write-copy\nDoing: pricing-page\n```\n\n- [ ] Write the copy ^write-copy\n- [ ] Pricing page ^pricing-page\n';
    const placing = placingFor(board, { lane: 'Doing', own: true });
    expect(placing).toEqual({ kind: 'lane', lane: 'Doing' });
    const placed = placeTake(board, 'Fix the login bug.', placing);
    expect(placed.body).toMatch(/\nDoing: fix-[a-z-]+, pricing-page\n/);
    expect(placed.body).toMatch(/\n- \[ \] Fix the login bug \^fix-[a-z-]+\n/);
    expect(placed.spot).toBe('in Doing');
  });
});
