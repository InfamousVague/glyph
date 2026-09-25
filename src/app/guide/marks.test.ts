import { afterEach, describe, expect, it } from 'vitest';
import { renderNote } from '../capture/markdown.ts';
import { setLinkTitles } from '../capture/spoken/extras.ts';
import { setSpokenFormats } from '../capture/spoken/inline.ts';
import { markGroups } from './marks.ts';
import { GUIDE_PAGES } from './pages.ts';
import { BUILT_IN, plugins } from '../plugins/registry.ts';

const rows = () => markGroups().flatMap((group) => group.rows);

describe('the guide’s table of marks', () => {
  it('has a page of its own in the walkthrough', () => {
    expect(GUIDE_PAGES.indexOf('marks')).toBeGreaterThan(0);
  });

  it('shows every mark the app writes, each with its own example', () => {
    const symbols = rows().map((row) => row.symbol);
    for (const mark of ['**', '_', '~~', '`', '#', '##', '-', '1.', '- [ ]', '>', '---', '| |', '![ ]( )', '```', '[ ]( )']) {
      expect(symbols, mark).toContain(mark);
    }
    for (const row of rows()) {
      expect(row.typed, row.name).toBeTruthy();
      expect(row.name, row.typed).toBeTruthy();
    }
    expect(new Set(rows().map((row) => row.name)).size).toBe(rows().length);
  });

  it('gives every mark an icon, which is what both pages lead the row with', () => {
    for (const row of rows()) expect(row.icon, row.name).toBeTruthy();
  });

  it('teaches the board: a name for an item, a pointer at it, and the fence itself', () => {
    const symbols = rows().map((row) => row.symbol);
    for (const mark of ['^', '[[#^ ]]', '```board']) expect(symbols, mark).toContain(mark);
    const board = rows().find((row) => row.looks === 'board');
    // The example is a working board: the fence, and the items its columns name (docs/BOARDS.md).
    expect(board?.typed).toContain('```board');
    expect(board?.typed).toContain('^ship-page');
    expect(rows().find((row) => row.looks === 'anchor')?.typed).toContain('- [ ] Ship the pricing page ^ship-page');
    expect(rows().find((row) => row.looks === 'itemRef')?.typed).toContain('[[#^ask-sam]]');
  });

  it('shows each mark a switched-on plugin adds, with the words it would say', () => {
    const formats = BUILT_IN.flatMap((plugin) => plugin.formats ?? []);
    const own = markGroups().find((group) => group.title === 'Ghost.md’s own');
    // The plugin's own marks, then the two rows about what goes in brackets after one: a colour, and a note
    // (plugins/marks/index.tsx, editor/markNotes.ts).
    expect(own?.rows).toHaveLength(formats.length + 2);
    for (const format of formats) {
      const row = own?.rows.find((r) => r.name === format.name);
      expect(row, format.name).toBeTruthy();
      expect(row?.symbol).toBe(format.delimiter);
      // The example ends in the mark around its words, so a person can copy it as it stands. Heat's has a line above
      // them first, for its haze to rise into (editor/textEffects.ts).
      const last = row?.typed.split('\n').pop() ?? '';
      expect(last.startsWith(format.delimiter) && last.endsWith(format.delimiter), format.name).toBe(true);
      if (format.cue) expect(row?.say).toContain(format.cue);
    }
  });

  it('says each mark with a cue, never a “Hey Ghost” command, since the recorder makes no mark from one', () => {
    // At Done the recorder acts on two commands only - words into a note by its name, and a new list by name
    // (capture/finalInstruction.ts) - and says any other, a table or a board among them, is not supported.
    for (const row of rows()) if (row.say) expect(row.say, row.name).not.toMatch(/hey ghost|glyph,/i);
  });

  it('draws a plugin’s look from the CSS the plugin declares', () => {
    const own = markGroups().find((group) => group.title === 'Ghost.md’s own');
    const highlight = own?.rows.find((row) => row.name === 'Highlight');
    expect(highlight?.looks).toBe('style');
    expect(highlight?.css).toContain('background');
    expect(own?.rows.find((row) => row.name === 'Spoiler')?.looks).toBe('wisp');
  });
});

describe('a note on a mark', () => {
  it('is shown last, with the brackets in the example and the words the popover says', () => {
    const own = markGroups().find((group) => group.title === 'Ghost.md’s own');
    const row = own?.rows.at(-1);
    expect(row?.name).toBe('A note on a mark');
    expect(row?.looks).toBe('note');
    expect(row?.typed).toBe('??four hundred??(Sam said 400)');
    expect(row?.note).toBe('Sam said 400');
  });
});

describe('with the Marks plugin switched off', () => {
  it('promises none of its marks, a hidden line included, which is the Spoiler’s', () => {
    plugins.setEnabled('marks', false);
    try {
      const groups = markGroups();
      expect(groups.find((group) => group.title === 'Ghost.md’s own')).toBeUndefined();
      const names = groups.flatMap((group) => group.rows).map((row) => row.name);
      expect(names).not.toContain('A hidden line');
      // The app's own marks are all still there.
      expect(names).toContain('A board');
    } finally {
      plugins.setEnabled('marks', true);
    }
    expect(rows().map((row) => row.name)).toContain('A hidden line');
  });
});

/**
 * What a person would say for each row with words to say, and what the recorder writes from it (capture/markdown.ts),
 * a note's first sentence first. Every phrase a row's `say` quotes is in one of its examples, and the words said are
 * gone from what is written, so a phrase the recorder stopped reading fails here rather than on the cheat sheet, and
 * so does one that writes the wrong thing ("calculate: four fifty plus one twenty" wrote 54 + 21). A plugin's mark is
 * said one way, its cue around the words, and its example is made from the plugin's own cue and delimiter below.
 */
const SAID: Record<string, readonly { said: readonly string[]; writes: string }[]> = {
  Bold: [{ said: ['The trip.', 'We leave on bold Friday at noon end bold.'], writes: '**Friday at noon**' }],
  Italic: [{ said: ['The trip.', 'Just italic a quiet aside end italic.'], writes: '_a quiet aside_' }],
  Both: [{ said: ['The trip.', 'Is it bold italic really now end bold italic.'], writes: '***really now***' }],
  'Struck through': [{ said: ['The trip.', 'We dropped strike the old plan end strike.'], writes: '~~the old plan~~' }],
  Code: [{ said: ['The trip.', 'Run code npm run dev end code.'], writes: '`npm run dev`' }],
  'A link': [{ said: ['The trip.', 'Read link our site to attack dot fm end link.'], writes: '[our site](https://attack.fm)' }],
  'A tag': [{ said: ['The trip.', 'Ship the pricing page hashtag web.'], writes: 'Ship the pricing page #web' }],
  Title: [
    { said: ['Title: weekend trip.', 'We need a tent.'], writes: '# Weekend trip' },
    { said: ['Call this note weekend trip.', 'We need a tent.'], writes: '# Weekend trip' },
  ],
  Heading: [
    { said: ['The trip.', 'Heading: the budget.'], writes: '## The budget' },
    { said: ['The trip.', 'New section: the budget.'], writes: '## The budget' },
  ],
  'Smaller heading': [{ said: ['The trip.', 'Subheading: Friday.'], writes: '### Friday' }],
  'A list': [{ said: ['The trip.', 'Bullet point: oat milk.'], writes: '- Oat milk' }],
  'In order': [
    { said: ['The trip.', 'Number one: unplug it.'], writes: '1. Unplug it' },
    { said: ['The trip.', 'First, unplug it.'], writes: '1. Unplug it' },
  ],
  'A to-do': [
    { said: ['The trip.', 'Remember to book the cabin.'], writes: '- [ ] Book the cabin' },
    { said: ['The trip.', 'Check box: book the cabin.'], writes: '- [ ] Book the cabin' },
  ],
  Done: [{ said: ['The trip.', 'Done task: call Sam.'], writes: '- [x] Call Sam' }],
  'A choice': [{ said: ['The trip.', 'Option: tent.', 'Picked option: cabin.'], writes: '- ( ) Tent\n- (x) Cabin' }],
  'A counter': [{ said: ['The trip.', 'Water counter three of eight.'], writes: 'Water [3/8]' }],
  'A sum': [{ said: ['The trip.', 'Calculate: four hundred plus one hundred twenty.'], writes: '= 400 + 120' }],
  'A quote': [{ said: ['The trip.', 'Quote: the plan is good.'], writes: '> The plan is good.' }],
  'A hidden line': [{ said: ['The trip.', 'Hidden line: the answer is forty-two.'], writes: '>| The answer is forty-two.' }],
  'A dividing line': [{ said: ['The trip.', 'That covers the morning.', 'Divider.', 'The afternoon is free.'], writes: '\n---\n' }],
  'Another note': [{ said: ['The trip.', 'The deposit is in note link The cabin trip end link.'], writes: '[[The cabin trip]]' }],
  'A name for an item': [{ said: ['The trip.', 'Check box: ship the pricing page anchor ship page end anchor.'], writes: '- [ ] Ship the pricing page ^ship-page' }],
  'That item, from the words': [{ said: ['The trip.', 'Remember item link ask Sam end link.'], writes: '[[#^ask-sam]]' }],
  'The bookmark': [{ said: ['The trip.', 'The deposit is four hundred bookmark this.'], writes: 'The deposit is four hundred. §§' }],
  'A footnote': [{ said: ['The trip.', 'The deposit is four hundred footnote Sam said so end footnote.'], writes: '[^1]: Sam said so.' }],
  Raised: [{ said: ['The trip.', 'The 2 superscript nd end superscript of June.'], writes: '2^nd^' }],
  Lowered: [{ said: ['The trip.', 'Water is H subscript 2 end subscript O.'], writes: 'H~2~O' }],
  'A definition': [{ said: ['The trip.', 'Define deposit as what you pay up front.'], writes: 'Deposit\n: What you pay up front' }],
  Maths: [{ said: ['The trip.', 'When maths x squared plus y end maths holds.'], writes: '$x^2 + y$' }],
  'An emoji': [{ said: ['The trip.', 'Shipped emoji party popper.'], writes: 'Shipped :tada:' }],
  'A block of code': [{ said: ['The trip.', 'Code block in bash.', 'npm run dev.', 'End code block.'], writes: '```bash\nnpm run dev\n```' }],
  'A callout': [
    { said: ['The trip.', 'Info box: the gate code is four two one.'], writes: '> [!NOTE]\n> The gate code is four two one.' },
    { said: ['The trip.', 'Warning callout: the road floods.'], writes: '> [!WARNING]\n> The road floods.' },
  ],
  'A note on a mark': [{ said: ['The trip.', 'The deposit is unsure four hundred end unsure, note Sam said 400, end note.'], writes: '??four hundred??(Sam said 400)' }],
  ...Object.fromEntries(
    BUILT_IN.flatMap((plugin) => plugin.formats ?? [])
      .filter((format) => format.cue)
      .map((format) => [format.name, [{ said: ['The trip.', `Keep ${format.cue} the cabin key end ${format.cue}.`], writes: `${format.delimiter}the cabin key${format.delimiter}` }]]),
  ),
};

/** The phrases a row's `say` quotes, each without the "…" that stands for the words and the colon before them. */
const phrasesOf = (say: string) => [...say.matchAll(/“([^”]+)”/g)].map((found) => found[1]!.replace(/…/g, ' ').trim().replace(/[:,]$/, '').trim());

/** The same shape the capture tests use: a second per phrase, with a breath between. */
function written(said: readonly string[]): string {
  return renderNote(said.map((text, index) => ({ text, startMs: index * 1300, endMs: index * 1300 + 1000 }))).markdown;
}

describe('what the cheat sheet says to say', () => {
  afterEach(() => {
    setSpokenFormats([]);
    setLinkTitles([]);
  });

  it('writes each row’s mark when said to the recorder, and leaves none of the words said behind', () => {
    // As the recorder sets them when it opens (capture/CaptureScreen.tsx): the switched-on plugins' cues, and the
    // library's titles for a spoken link to take the note's own spelling.
    setSpokenFormats(BUILT_IN.flatMap((plugin) => plugin.formats ?? []).flatMap((format) => (format.cue ? [{ word: format.cue, delimiter: format.delimiter }] : [])));
    setLinkTitles(['The cabin trip']);
    const said = rows().filter((row) => row.say);
    expect(Object.keys(SAID).sort()).toEqual(said.map((row) => row.name).sort());
    for (const row of said) {
      const examples = SAID[row.name]!;
      const phrases = phrasesOf(row.say!);
      for (const phrase of phrases) {
        expect(
          examples.some((example) => example.said.join(' ').toLowerCase().includes(phrase.toLowerCase())),
          `${row.name}: “${phrase}” is said in an example`,
        ).toBe(true);
      }
      for (const example of examples) {
        const markdown = written(example.said);
        expect(markdown, row.name).toContain(example.writes);
        for (const phrase of phrases) {
          if (example.said.join(' ').toLowerCase().includes(phrase.toLowerCase())) expect(markdown.toLowerCase(), `${row.name}: “${phrase}”`).not.toContain(phrase.toLowerCase());
        }
      }
    }
  });
});
