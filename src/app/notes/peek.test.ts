import { describe, expect, it } from 'vitest';
import { bareWords, notePeek, PEEK_LINES } from './peek.ts';

describe('the note drawn small', () => {
  it('starts after the title, because the card already says it', () => {
    const peek = notePeek('# Weekend trip\n\nBooking the cottage on Friday.');
    expect(peek).toEqual([{ kind: 'text', text: 'Booking the cottage on Friday.' }]);
  });

  it('takes the title from behind front matter, and shows what follows it', () => {
    const peek = notePeek('---\ntitle: Bread\ntags: baking\n---\n\n500g strong white.');
    expect(peek).toEqual([{ kind: 'text', text: '500g strong white.' }]);
  });

  it('keeps the shape of every line, which is the part worth seeing small', () => {
    const body = ['# Packing', '## To pack', '- [ ] Boots', '- [x] Waterproof', '- The camera', '1. First', '> The abbey shuts at four'].join('\n');
    expect(notePeek(body)).toEqual([
      { kind: 'heading', level: 2, text: 'To pack' },
      { kind: 'task', done: false, text: 'Boots' },
      { kind: 'task', done: true, text: 'Waterproof' },
      { kind: 'bullet', text: 'The camera' },
      { kind: 'number', text: 'First' },
      { kind: 'quote', text: 'The abbey shuts at four' },
    ]);
  });

  it('stands a block of code up as its first line, and passes over the rest', () => {
    const peek = notePeek('# Standup\n\n```bash\nnpm run check\nnpm test\n```\n\nAfter that.');
    expect(peek).toEqual([
      { kind: 'code', text: 'npm run check' },
      { kind: 'text', text: 'After that.' },
    ]);
  });

  it('is not fooled by a line inside a block of code', () => {
    // `# comment` and `- flag` are code, not a heading and a bullet.
    const peek = notePeek('# Setup\n\n```\n# comment\n- flag\n```');
    expect(peek).toEqual([{ kind: 'code', text: '# comment' }]);
  });

  it('reads a table as its cells and draws the rule under the header rather than reading it', () => {
    const peek = notePeek('# Sizes\n\n| Name | Size | Where | Spare |\n| --- | --- | --- | --- |\n| Tent | 2kg | Loft | x |');
    expect(peek).toEqual([
      { kind: 'table', cells: ['Name', 'Size', 'Where'] },
      { kind: 'table', cells: ['Tent', '2kg', 'Loft'] },
    ]);
  });

  it('knows a rule and a picture from words', () => {
    const peek = notePeek('# Reading\n\n---\n\n![The abbey at dusk](photo.jpg)');
    expect(peek).toEqual([{ kind: 'rule' }, { kind: 'image', text: 'The abbey at dusk' }]);
  });

  it('is titled by the words under a picture, and then shows the picture is there', () => {
    // noteTitle skips a leading picture to find the name; the peek picks up from that name.
    const peek = notePeek('![cover](cover.jpg)\n# Bread\n\n500g strong white.');
    expect(peek).toEqual([{ kind: 'text', text: '500g strong white.' }]);
  });

  it('draws no more than it is asked for', () => {
    const body = `# Many\n${Array.from({ length: 30 }, (_, i) => `- Item ${i}`).join('\n')}`;
    expect(notePeek(body)).toHaveLength(PEEK_LINES);
    expect(notePeek(body, 3)).toHaveLength(3);
  });

  it('has nothing to draw for a note that is only its title', () => {
    expect(notePeek('# Just a name')).toEqual([]);
    expect(notePeek('')).toEqual([]);
    // A line of marks with no words in it is not a line worth drawing.
    expect(notePeek('# Name\n\n- \n>  \n## ')).toEqual([]);
  });

  it('leaves alone what only looks like a mark', () => {
    // Underscores and asterisks inside a word are the word, and a hidden line is a mark, not a table row.
    expect(notePeek('Title\nsnake_case and 2*3*4')).toEqual([{ kind: 'text', text: 'snake_case and 2*3*4' }]);
    expect(notePeek('Title\n||under the stone||')).toEqual([{ kind: 'text', text: 'under the stone' }]);
  });

  it('says the words rather than the marks', () => {
    expect(bareWords('**Bold** and _quiet_ and `code`')).toBe('Bold and quiet and code');
    // Every paired mark the plugins add, so a line reads as its words (plugins/marks/).
    expect(bareWords('Ask ??Sam?? about the ==deposit==, %%quietly%%, and ++bring++ ^^ice^^.')).toBe('Ask Sam about the deposit, quietly, and bring ice.');
    expect(bareWords('Something with **negative space** and one ~~gone~~ colour.')).toBe('Something with negative space and one gone colour.');
    expect(bareWords('See [the handbook](https://tauri.app/guides/x) for it')).toBe('See the handbook for it');
    // The bookmark's mark is where the note opens, not part of what the line says.
    expect(bareWords('The deposit is four hundred §§')).toBe('The deposit is four hundred');
    // A board's name for the item is not something it says: `^flights` stayed in the preview as if it were a word.
    expect(bareWords('Book flights ^flights')).toBe('Book flights');
    expect(bareWords('E = mc^2^ holds')).toBe('E = mc^2^ holds');
    // Addresses are shortened the way the list shortens them (core/shortUrl.ts): the host, and the middle elided.
    expect(bareWords('Read https://tauri.app/guides/the-long-one today')).toMatch(/^Read tauri\.app\S* today$/);
  });
});
