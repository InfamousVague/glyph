import { plugins } from '../plugins/registry.ts';

/**
 * Every mark a note can carry, as a table: what you type, what it does, and a
 * line showing it at work (guide/MarksTable.tsx). Matt: "create a guide page,
 * it should show every formatting mode we have in a table and show you an
 * example of how it works."
 *
 * The rows are the app's own Markdown, then the marks Glyph's plugins add,
 * read from the registry so a plugin switched off is not promised and a new
 * one shows up here by itself (plugins/types.ts `InlineFormat`). The `looks`
 * field says how the example should be drawn: the page has one style per
 * kind, matching what the editor does to the same text.
 */

export type Looks =
  | 'plain'
  | 'h1'
  | 'h2'
  | 'h3'
  | 'bold'
  | 'italic'
  | 'both'
  | 'struck'
  | 'code'
  | 'link'
  | 'quote'
  | 'bullet'
  | 'number'
  | 'todo'
  | 'done'
  | 'rule'
  | 'table'
  | 'picture'
  | 'fence'
  | 'wisp'
  | 'style'
  | 'note'
  | 'sup'
  | 'sub'
  | 'callout';

export interface MarkRow {
  /** The mark itself, as a person would type it: `**`, `- [ ]`. */
  symbol: string;
  name: string;
  /** What to type, whole: the example's markdown. */
  typed: string;
  /** The words that carry the mark in the example, for the drawn side. */
  words: string;
  looks: Looks;
  /** How it is drawn, where the page needs the plugin's own CSS. */
  css?: string;
  /** Said while recording, where there is a way to say it. */
  say?: string;
  /** What the popover says, for the row that shows a note on a mark (editor/markNotes.ts). */
  note?: string;
}

export interface MarkGroup {
  title: string;
  lead: string;
  rows: MarkRow[];
}

/** The marks the app itself knows, in the order the page shows them. */
const OWN: MarkGroup[] = [
  {
    title: 'Words',
    lead: 'Around the words they mark, anywhere in a line.',
    rows: [
      { symbol: '**', name: 'Bold', typed: '**Friday at noon**', words: 'Friday at noon', looks: 'bold', say: '“bold” … “end bold”' },
      { symbol: '_', name: 'Italic', typed: '_a quiet aside_', words: 'a quiet aside', looks: 'italic', say: '“italic” … “end italic”' },
      { symbol: '***', name: 'Both', typed: '***really now***', words: 'really now', looks: 'both' },
      { symbol: '~~', name: 'Struck through', typed: '~~the old plan~~', words: 'the old plan', looks: 'struck' },
      { symbol: '`', name: 'Code', typed: '`npm run dev`', words: 'npm run dev', looks: 'code' },
      { symbol: '[ ]( )', name: 'A link', typed: '[Glyph](https://attack.fm/glyph)', words: 'Glyph', looks: 'link' },
    ],
  },
  {
    title: 'Lines',
    lead: 'At the start of a line, with a space after them.',
    rows: [
      { symbol: '#', name: 'Title', typed: '# Weekend trip', words: 'Weekend trip', looks: 'h1', say: '“title” or “call this note”' },
      { symbol: '##', name: 'Heading', typed: '## The budget', words: 'The budget', looks: 'h2', say: '“heading” or “new section”' },
      { symbol: '###', name: 'Smaller heading', typed: '### Friday', words: 'Friday', looks: 'h3' },
      { symbol: '-', name: 'A list', typed: '- Oat milk', words: 'Oat milk', looks: 'bullet', say: '“bullet point”' },
      { symbol: '1.', name: 'In order', typed: '1. Unplug it', words: 'Unplug it', looks: 'number', say: '“number one”, “first”' },
      { symbol: '- [ ]', name: 'A to-do', typed: '- [ ] Book the cabin', words: 'Book the cabin', looks: 'todo', say: '“remember to”, “check box”' },
      { symbol: '- [x]', name: 'Done', typed: '- [x] Call Sam', words: 'Call Sam', looks: 'done' },
      { symbol: '>', name: 'A quote', typed: '> The deposit comes back in full.', words: 'The deposit comes back in full.', looks: 'quote', say: '“quote”' },
      { symbol: '---', name: 'A dividing line', typed: '---', words: '', looks: 'rule', say: '“divider”' },
    ],
  },
  {
    title: 'Raised and lowered',
    lead: 'Around one part of a word, the way the rest of markdown writes them.',
    rows: [
      { symbol: '^ ^', name: 'Raised', typed: 'the 2^nd^ of June', words: 'nd', looks: 'sup' },
      { symbol: '~ ~', name: 'Lowered', typed: 'H~2~O', words: '2', looks: 'sub' },
    ],
  },
  {
    title: 'Blocks',
    lead: 'A few lines that work together.',
    rows: [
      {
        symbol: '| |',
        name: 'A table',
        typed: '| What | Packed |\n| --- | --- |\n| Tent | Yes |',
        words: '',
        looks: 'table',
        say: '“Glyph, add a table to this note”',
      },
      { symbol: '![ ]( )', name: 'A picture', typed: '![A cassette](image/tape.jpg)', words: 'A cassette', looks: 'picture' },
      { symbol: '```', name: 'A block of code', typed: '```js\nconst note = "hello";\n```', words: 'const note = "hello";', looks: 'fence' },
      {
        symbol: '[! ]',
        name: 'A callout',
        typed: '> [!NOTE]\n> The deposit comes back in full.',
        words: 'The deposit comes back in full.',
        looks: 'callout',
        note: 'NOTE',
      },
    ],
  },
];

/** Every group the page shows: the app's own marks, then the ones the switched-on plugins add. */
export function markGroups(): MarkGroup[] {
  const formats = plugins.formats();
  if (!formats.length) return OWN;
  const rows = formats.map((format): MarkRow => {
    const words = format.name === 'Spoiler' ? 'the cabin key' : `${format.name.toLowerCase()} this`;
    return {
      symbol: format.delimiter,
      name: format.name,
      typed: `${format.delimiter}${words}${format.delimiter}`,
      words,
      looks: format.look.kind === 'wisp' ? 'wisp' : 'style',
      css: format.look.kind === 'style' ? format.look.css : undefined,
      say: format.cue ? `“${format.cue}” … “end ${format.cue}”` : undefined,
    };
  });
  // A note on a mark is shown last, because it is written on top of any of the marks above it (editor/markNotes.ts).
  const noted: MarkRow = {
    symbol: '( )',
    name: 'A note on a mark',
    typed: '??four hundred??(Sam said 400)',
    words: 'four hundred',
    looks: 'note',
    note: 'Sam said 400',
  };
  return [...OWN, { title: 'Glyph’s own', lead: 'Marks the app adds, each from a plugin you can switch off.', rows: [...rows, noted] }];
}
