import { ensureSyntaxTree } from '@codemirror/language';
import { EditorState, Text, type Extension } from '@codemirror/state';
import { boardsIn, itemsIn, refsIn } from '../core/boards.ts';
import { shortcodesIn } from '../core/emoji.ts';
import { BOX, BULLET, MARKER, NUMBER } from '../core/itemSyntax.ts';
import { readStored, writeStored } from '../core/stored.ts';
import { bookmarkLineIn } from '../editor/bookmarkLine.ts';
import { choiceOn } from '../editor/choices.ts';
import { countersIn } from '../editor/counters.ts';
import { calloutKind } from '../editor/extended.ts';
import { footnotesIn } from '../editor/footnotes.ts';
import { headingCounts } from '../editor/headingProgress.ts';
import { glyphMarkdown } from '../editor/language.ts';
import { isTint, notePattern, notesIn } from '../editor/markNotes.ts';
import { sumOnLine } from '../editor/sums.ts';
import { tagsIn } from '../editor/tags.ts';
import { wikiLinksIn } from '../editor/wikiLinks.ts';
import { plugins } from '../plugins/registry.ts';

/**
 * Ghost.md Academy's lessons (academy/AcademyScreen.tsx): what each mark is, what to type, and how the Academy knows
 * it worked.
 *
 * Matt: "we need a Glyph Academy section that teaches you markdown then teaches you the extra stuff we have. Build
 * the academy section start with just the markdown basics set it up as a live code type thing where it teaches you
 * then you type it and see it format below."
 *
 * So a lesson is one mark: a line or two on what it does, an example to copy, something to write of your own, and a
 * check run on what was really typed - not on it matching the example. Any title passes the title lesson. The
 * checks are forgiving on purpose: extra lines, other marks and different words are all fine, since a person
 * learning is usually trying things.
 *
 * Markdown basics came first; the chapters after it are the extra stuff, and together they teach every row of the
 * cheat sheet (guide/marks.ts), each row by exactly one lesson (`rows`), which lessons.test.ts holds them to. A check
 * reads what was typed the way the note does wherever the note has a reader of its own: the parser for a mark it
 * parses (`parsed`), and the editor's own finders for the marks drawn by what a line says - a tag, a counter, a sum,
 * a choice. A lesson for a plugin's mark (`needs`) is offered only while that mark is switched on, as the cheat
 * sheet shows its row only then.
 *
 * Pure, so every lesson's own example is a test that its check passes (academy/lessons.test.ts). The marks
 * themselves are the app's (guide/marks.ts, docs/MARKDOWN.md); this file is only the teaching order and the words.
 */

export interface Lesson {
  id: string;
  chapter: Chapter;
  /** What the lesson is called: the mark, in words. */
  title: string;
  /** The mark itself, as the cheat sheet writes it (guide/marks.ts): `**`, `- [ ]`. */
  symbol: string;
  /** The cheat sheet's rows this lesson teaches, by name (guide/marks.ts `MarkRow.name`); the first is its own. */
  rows: readonly string[];
  /** The plugin mark it needs switched on, by name (plugins/marks/index.tsx); without it, the lesson is not offered. */
  needs?: string;
  /** What it does, in a line or two. */
  teach: string;
  /** The example to look at, and what **Show me** writes into the field. */
  example: string;
  /** What to write of your own. */
  task: string;
  /** Read what is typed: true the moment this lesson's mark is in it. */
  passes: (text: string) => boolean;
  /** Said when it passes. */
  praise: string;
  /** Offered when it is asked for. */
  hint: string;
}

export const CHAPTERS = ['Markdown basics', 'More Markdown', 'Lines that do more', 'Pointing somewhere', 'Marks and effects'] as const;
export type Chapter = (typeof CHAPTERS)[number];

/** A line of its own, anywhere in what was typed. */
const line = (pattern: RegExp) => (text: string) => pattern.test(text);

/** The lines of what was typed as the editor holds them, for the finders that read a document. */
const docOf = (text: string) => Text.of(text.split('\n'));

/** The parser, for the plugin marks switched on now, kept while they stay the same. */
let language: { key: string; extension: Extension } | null = null;
/** The node names in the last text read, so a check run on every keystroke parses each text once. */
let last: { text: string; key: string; names: Set<string> } | null = null;

/** Every node the note's own parser finds in `text` (editor/language.ts), the switched-on plugins' marks included. */
function nodesIn(text: string): Set<string> {
  const formats = plugins.formats();
  const key = formats.map((format) => format.delimiter).join(' ');
  if (last?.text === text && last.key === key) return last.names;
  if (language?.key !== key) language = { key, extension: glyphMarkdown(formats, []) };
  const state = EditorState.create({ doc: text, extensions: [language.extension] });
  const names = new Set<string>();
  ensureSyntaxTree(state, state.doc.length, 1000)?.iterate({ enter: (node) => void names.add(node.name) });
  last = { text, key, names };
  return names;
}

/** True when the note's parser finds a `name` node in what was typed: the mark, read the way the note reads it. */
const parsed = (name: string) => (text: string) => nodesIn(text).has(name);

/** A mark written with a note in brackets after it: a colour for a highlight (`tint`), or else a note on the mark. */
function noted(text: string, tint: boolean): boolean {
  const formats = plugins.formats();
  const pattern = notePattern(formats);
  return pattern !== null && notesIn(text, pattern).some((note) => isTint(note, formats) === tint);
}

/** A footnote: a definition line, and its mark in the words. */
function footnoted(text: string): boolean {
  const marks = [...text.matchAll(/\[\^([^\]\s]+)\](?!:)/g)].map((mark) => mark[1]);
  return footnotesIn(text).some((note) => marks.includes(note.name));
}

export const LESSONS: Lesson[] = [
  // ---- Markdown basics: what every Markdown app reads the same way ----------------------------------------------
  {
    id: 'title',
    chapter: 'Markdown basics',
    symbol: '#',
    rows: ['Title'],
    title: 'A title',
    teach: 'A note usually starts with its name. One # and a space makes that line the title, and it is what the note is called in your list.',
    example: '# Weekend trip',
    task: 'Give a note a title of your own.',
    passes: line(/^[ \t]*#[ \t]+\S/m),
    praise: 'That is a title.',
    hint: 'Start the line with # and a space, then the words.',
  },
  {
    id: 'heading',
    chapter: 'Markdown basics',
    symbol: '##',
    rows: ['Heading', 'Smaller heading'],
    title: 'A heading',
    teach: 'More hashes, smaller heading: ## for a part of the note, ### for a part of that. It is how a long note gets somewhere to look.',
    example: '## The budget',
    task: 'Write a heading for part of a note.',
    // Any heading below a title, since the lesson itself offers ### as well as ## (Matt, of three hashes: "the
    // lesson isn't passed").
    passes: line(/^[ \t]*#{2,6}[ \t]+\S/m),
    praise: 'That is a heading.',
    hint: 'Two hashes and a space: ## The budget.',
  },
  {
    id: 'bold',
    chapter: 'Markdown basics',
    symbol: '**',
    rows: ['Bold'],
    title: 'Bold',
    teach: 'Two stars either side of some words make them bold. The stars themselves go once the line is written.',
    example: 'The train leaves **Friday at noon**',
    task: 'Write a line with something bold in it.',
    passes: line(/\*\*\S(?:[^*]*\S)?\*\*/),
    praise: 'Bold.',
    hint: 'Two stars, the words, two stars: **like this**.',
  },
  {
    id: 'italic',
    chapter: 'Markdown basics',
    symbol: '_',
    rows: ['Italic'],
    title: 'Italic',
    teach: 'One underscore either side leans the words over. It is quieter than bold: an aside, a name, a word said with a shrug.',
    example: 'we could take the coast road _if the weather holds_',
    task: 'Write a line with something in italics.',
    // Underscores are what the lesson teaches, but markdown's stars lean words over too, and the page below shows
    // them leaning: a lesson must never refuse what the note plainly did.
    passes: (text) => /(?:^|[^\w_])_\S(?:[^_\n]*\S)?_(?![\w_])/m.test(text) || /(?<![*\w])\*[^*\n]+\*(?!\*)/.test(text),
    praise: 'Italic.',
    hint: 'An underscore either side: _like this_.',
  },
  {
    id: 'both',
    chapter: 'Markdown basics',
    symbol: '***',
    rows: ['Both'],
    title: 'Bold and italic',
    teach: 'Three stars either side make words bold and italic at once. Keep it for the one thing that must not be missed.',
    example: 'the deposit is ***not*** refundable',
    task: 'Make a word or two bold and italic at once.',
    passes: line(/(\*\*\*|___)\S(?:[^*_\n]*\S)?\1/),
    praise: 'Both at once.',
    hint: 'Three stars either side: ***like this***.',
  },
  {
    id: 'struck',
    chapter: 'Markdown basics',
    symbol: '~~',
    rows: ['Struck through'],
    title: 'Struck through',
    teach: 'Two squiggles either side cross the words out. Good for a plan that changed, where you still want to see what it was.',
    example: 'we are going ~~on Thursday~~ on Friday',
    task: 'Cross some words out.',
    passes: line(/~~\S(?:[^~\n]*\S)?~~/),
    praise: 'Crossed out, and still readable.',
    hint: 'Two squiggles either side: ~~like this~~.',
  },
  {
    id: 'code',
    chapter: 'Markdown basics',
    symbol: '`',
    rows: ['Code'],
    title: 'Code',
    teach: 'A backtick either side sets the words in the typewriter face and leaves them exactly as you typed them: a command, a filename, a password to read out.',
    example: 'run `npm run dev` first',
    task: 'Write a line with a bit of code in it.',
    passes: line(/`[^`\n]+`/),
    praise: 'That stays exactly as typed.',
    hint: 'A backtick either side: `like this`. The key is usually under Escape.',
  },
  {
    id: 'link',
    chapter: 'Markdown basics',
    symbol: '[ ]( )',
    rows: ['A link'],
    title: 'A link',
    teach: 'The words people read go in square brackets, and where they point goes in round ones after it. The note shows the words, not the address.',
    example: '[Ghost.md](https://attack.fm/glyph) is the app this is in',
    task: 'Write a link of your own.',
    passes: line(/\[[^\]\n]+\]\([^)\s]+\)/),
    praise: 'That is a link.',
    hint: 'Words in square brackets, then the address in round ones: [words](https://example.com).',
  },
  {
    id: 'list',
    chapter: 'Markdown basics',
    symbol: '-',
    rows: ['A list'],
    title: 'A list',
    teach: 'A dash and a space starts a list, one line each. Press Enter and the next line is a bullet too.',
    example: '- Oat milk\n- Rye bread\n- Coffee',
    task: 'Write a list of two or three things.',
    passes: line(new RegExp(String.raw`^[ \t]*${BULLET}[ \t]+\S`, 'm')),
    praise: 'That is a list.',
    hint: 'Start each line with a dash and a space.',
  },
  {
    id: 'number',
    chapter: 'Markdown basics',
    symbol: '1.',
    rows: ['In order'],
    title: 'In order',
    teach: 'A number, a dot and a space when the order is the point: steps to follow, one after another.',
    example: '1. Unplug it\n2. Wait a minute\n3. Plug it back in',
    task: 'Write two steps in order.',
    passes: line(new RegExp(String.raw`^[ \t]*${NUMBER}[ \t]+\S`, 'm')),
    praise: 'Numbered.',
    hint: 'Start the line with 1. and a space; the next one with 2.',
  },
  {
    id: 'todo',
    chapter: 'Markdown basics',
    symbol: '- [ ]',
    rows: ['A to-do', 'Done'],
    title: 'A to-do',
    teach: 'A dash, then a box: - [ ] and the thing to do. Tap the box in a note to tick it off, or type an x between the brackets.',
    example: '- [ ] Book the cabin\n- [x] Pick a date',
    task: 'Write something you have to do.',
    passes: line(new RegExp(String.raw`^[ \t]*${MARKER}[ \t]+${BOX}[ \t]*\S`, 'm')),
    praise: 'That is a to-do, and its box is real: tap it in a note.',
    hint: 'A dash, a space, then [ ] with a space between the brackets.',
  },
  {
    id: 'quote',
    chapter: 'Markdown basics',
    symbol: '>',
    rows: ['A quote'],
    title: 'A quote',
    teach: 'A > and a space sets a line apart: somebody else’s words, or something you want to stand away from the rest.',
    example: '> The deposit comes back in full.',
    task: 'Quote a line.',
    passes: line(/^[ \t]*>[ \t]*\S/m),
    praise: 'Set apart.',
    hint: 'Start the line with > and a space.',
  },
  {
    id: 'rule',
    chapter: 'Markdown basics',
    symbol: '---',
    rows: ['A dividing line'],
    title: 'A dividing line',
    teach: 'Three dashes on a line of their own draw a line across the note: one thing ends, another starts.',
    example: 'Packing\n\n---\n\nOn the way back',
    task: 'Put a line between two parts of a note.',
    passes: line(/^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$/m),
    praise: 'A clean break.',
    hint: 'Three dashes alone on a line: ---',
  },
  {
    id: 'fence',
    chapter: 'Markdown basics',
    symbol: '```',
    rows: ['A block of code'],
    title: 'A block of code',
    teach: 'Three backticks above and below a few lines keeps every one of them exactly as typed, and colours the code if you say what it is after the first three.',
    example: '```js\nconst note = "hello";\n```',
    task: 'Write a block with a line or two of code in it.',
    passes: (text) => /^[ \t]*(?:```|~~~)/m.test(text) && (text.match(/^[ \t]*(?:```|~~~)/gm)?.length ?? 0) >= 2,
    praise: 'A block, kept exactly as typed.',
    hint: 'Three backticks on their own line, your code, then three more.',
  },

  // ---- More Markdown: marks most Markdown apps read, which a note draws too ---------------------------------------
  {
    id: 'table',
    chapter: 'More Markdown',
    symbol: '| |',
    rows: ['A table'],
    title: 'A table',
    teach: 'Pipes between the cells, and a row of dashes under the first row. In a note the table is drawn as a table; a tap on it opens its pipes to change it, and it is drawn again when you leave it.',
    example: '| What | Packed |\n| --- | --- |\n| Tent | Yes |',
    task: 'Make a table with a row or two in it.',
    passes: parsed('Table'),
    praise: 'That is a table.',
    hint: 'A row of cells between pipes, then | --- | --- | under it, then the rest of the rows.',
  },
  {
    id: 'picture',
    chapter: 'More Markdown',
    symbol: '![ ]( )',
    rows: ['A picture'],
    title: 'A picture',
    teach: 'An exclamation mark, what the picture shows in square brackets, and where it is in round ones. In a note you seldom type it: paste a picture, or press and hold and choose Add image, and the line is written for you.',
    example: '![A cassette](image/tape.jpg)',
    task: 'Write the line for a picture.',
    passes: parsed('Image'),
    praise: 'That is a picture’s line.',
    hint: 'An exclamation mark, then [what it shows], then (where it is).',
  },
  {
    id: 'raised',
    chapter: 'More Markdown',
    symbol: '^ ^',
    rows: ['Raised'],
    title: 'Raised',
    teach: 'A caret either side lifts part of a word above the line: the 2nd of June, a power in a sum.',
    example: 'the 2^nd^ of June',
    task: 'Raise part of a word.',
    passes: parsed('Superscript'),
    praise: 'Raised.',
    hint: 'A caret either side of the part to lift: 2^nd^.',
  },
  {
    id: 'lowered',
    chapter: 'More Markdown',
    symbol: '~ ~',
    rows: ['Lowered'],
    title: 'Lowered',
    teach: 'One squiggle either side drops part of a word below the line, the way water is written. Two squiggles cross words out, which is a lesson of its own.',
    example: 'H~2~O',
    task: 'Lower part of a word.',
    passes: parsed('Subscript'),
    praise: 'Lowered.',
    hint: 'One squiggle either side: H~2~O.',
  },
  {
    id: 'footnote',
    chapter: 'More Markdown',
    symbol: '[^ ]',
    rows: ['A footnote'],
    title: 'A footnote',
    teach: 'A caret and a name in square brackets marks the words, and a line that starts with the same mark and a colon says what it is. In a note the mark is raised, and a tap on it shows the small print.',
    example: 'four hundred[^sam]\n\n[^sam]: Sam said so.',
    task: 'Write a line with a footnote, and the footnote.',
    passes: footnoted,
    praise: 'That is a footnote, and a tap reads it.',
    hint: 'A mark like [^sam] after the words, and a line under them that starts [^sam]: and says it.',
  },
  {
    id: 'definition',
    chapter: 'More Markdown',
    symbol: ':',
    rows: ['A definition'],
    title: 'A definition',
    teach: 'A word on one line, and its meaning on the next after a colon and a space. It is how a glossary is written.',
    example: 'Deposit\n: what you pay up front',
    task: 'Define a word.',
    passes: line(/^[ \t]*[^\s:].*\n[ \t]{0,3}:[ \t]+\S/m),
    praise: 'Defined.',
    hint: 'The word, then on the next line a colon, a space, and what it means.',
  },
  {
    id: 'maths',
    chapter: 'More Markdown',
    symbol: '$',
    rows: ['Maths'],
    title: 'Maths',
    teach: 'A dollar sign either side sets a formula apart, kept exactly as typed. Two either side, for a formula that needs lines of its own.',
    example: 'when $x^2 + y$ holds',
    task: 'Write a formula.',
    passes: line(/\$\$[^$]+\$\$|\$[^$\n]+\$/),
    praise: 'Set apart, exactly as typed.',
    hint: 'A dollar sign either side: $x^2$.',
  },
  {
    id: 'emoji',
    chapter: 'More Markdown',
    symbol: ': :',
    rows: ['An emoji'],
    title: 'An emoji',
    teach: 'A name between colons becomes its emoji: :tada: is a party popper. The name comes back while the caret is on the line, and a name Ghost.md does not know stays as it was typed.',
    example: 'shipped :tada:',
    task: 'Put an emoji in a line by its name.',
    passes: (text) => shortcodesIn(text).length > 0,
    praise: 'An emoji, from its name.',
    hint: 'A colon either side of the name: :tada:, :rocket:, :coffee:.',
  },
  {
    id: 'callout',
    chapter: 'More Markdown',
    symbol: '[! ]',
    rows: ['A callout'],
    title: 'A callout',
    teach: 'A quote whose first line is [!NOTE] becomes a box of its own. TIP, IMPORTANT, WARNING and CAUTION work the same way.',
    example: '> [!NOTE]\n> The deposit comes back in full.',
    task: 'Write a callout.',
    passes: (text) => text.split('\n').some((each) => calloutKind(each) !== null),
    praise: 'That is a callout.',
    hint: 'A quote with the kind on its first line: > [!TIP]',
  },
  {
    id: 'diagram',
    chapter: 'More Markdown',
    symbol: '```mermaid',
    rows: ['A diagram'],
    title: 'A diagram',
    teach: 'A block of code marked mermaid is drawn as the diagram it describes: boxes, and the arrows between them. Tap a drawn diagram in a note to change its words.',
    example: '```mermaid\nflowchart TD\n  A[Speak] --> B[Note]\n```',
    task: 'Draw two boxes and an arrow.',
    passes: line(/^[ \t]*```mermaid[ \t]*\n[\s\S]*?\n[ \t]*```/m),
    praise: 'That is a diagram.',
    hint: 'Three backticks and mermaid, then flowchart TD, then a line like A --> B, then three backticks.',
  },

  // ---- Lines that do more: plain characters a note does something with -------------------------------------------
  {
    id: 'tag',
    chapter: 'Lines that do more',
    symbol: '#',
    rows: ['A tag'],
    title: 'A tag',
    teach: 'A hash against a word, with no space between, tags the line: #web. A tag can hold a slash, #work/clients, which apps like Obsidian read as one tag inside another. A hash and a space at the start of a line is a heading instead.',
    example: '- [ ] Ship the pricing page #web',
    task: 'Tag a line.',
    passes: (text) => tagsIn(text).length > 0,
    praise: 'Tagged.',
    hint: 'A # and the word, with no space between: #web.',
  },
  {
    id: 'choice',
    chapter: 'Lines that do more',
    symbol: '- ( )',
    rows: ['A choice'],
    title: 'A choice',
    teach: 'Round brackets on a list make a choice. One in the group is picked, with an x; in a note a tap picks one and clears the rest.',
    example: 'Where do we stay?\n- ( ) Tent\n- (x) Cabin',
    task: 'Write a choice with two options.',
    passes: (text) => {
      const doc = docOf(text);
      for (let n = 1; n <= doc.lines; n += 1) if (choiceOn(doc, n)) return true;
      return false;
    },
    praise: 'That is a choice: tap one in a note to pick it.',
    hint: 'A dash, a space, then ( ) with a space between the brackets.',
  },
  {
    id: 'counter',
    chapter: 'Lines that do more',
    symbol: '[ / ]',
    rows: ['A counter'],
    title: 'A counter',
    teach: 'A count and a goal in square brackets, like [3/8], is a counter. In a note a tap adds one and a hold takes one away, never past the goal.',
    example: '- Water [3/8]',
    task: 'Count something towards a goal.',
    passes: (text) => countersIn(text).length > 0,
    praise: 'That is a counter.',
    hint: 'Two numbers with a slash between, in square brackets: [0/8].',
  },
  {
    id: 'sum',
    chapter: 'Lines that do more',
    symbol: '=',
    rows: ['A sum'],
    title: 'A sum',
    teach: 'A line that starts with = and a space shows its answer after it. The answer is never written into the note, so it changes when a number does.',
    example: '= $450 + 120 * 2',
    task: 'Do a sum.',
    passes: (text) => text.split('\n').some((each) => sumOnLine(each) !== null),
    praise: 'Worked out.',
    hint: 'An equals sign, a space, then the sum: = 12 * 4.',
  },
  {
    id: 'hiddenLine',
    chapter: 'Lines that do more',
    symbol: '>|',
    rows: ['A hidden line'],
    needs: 'Spoiler',
    title: 'A hidden line',
    teach: 'A quote whose first character is a bar goes to smoke until the caret is in it: the answer to a riddle, or a code nobody should read over your shoulder.',
    example: '>| The answer is forty-two.',
    task: 'Hide a line.',
    passes: line(/^[ \t]*>\|[ \t]*\S/m),
    praise: 'Hidden in smoke.',
    hint: 'A > and a bar, with no space between, then the line: >| like this.',
  },
  {
    id: 'progress',
    chapter: 'Lines that do more',
    symbol: '#',
    rows: ['Progress'],
    title: 'Progress',
    teach: 'Nothing to type but a heading and its to-dos: the heading counts them, “1 of 2”, and says so when they are all done.',
    example: '## Packing\n- [x] Tent\n- [ ] Stove',
    task: 'Write a heading with a to-do or two under it.',
    passes: (text) => headingCounts(docOf(text)).length > 0,
    praise: 'The heading is counting.',
    hint: 'A heading, then a line like - [ ] Stove under it.',
  },

  // ---- Pointing somewhere: another note, an item, a place in this one ----------------------------------------------
  {
    id: 'wiki',
    chapter: 'Pointing somewhere',
    symbol: '[[ ]]',
    rows: ['Another note'],
    title: 'Another note',
    teach: 'Two square brackets either side of a note’s name link to that note. A name with no note yet is drawn dashed, and a tap on it makes the note.',
    example: 'the deposit is in [[The cabin trip]]',
    task: 'Link to a note by its name.',
    passes: (text) => wikiLinksIn(text).length > 0,
    praise: 'That links to the note.',
    hint: 'Two square brackets either side of the name: [[The cabin trip]].',
  },
  {
    id: 'anchor',
    chapter: 'Pointing somewhere',
    symbol: '^',
    rows: ['A name for an item'],
    title: 'A name for an item',
    teach: 'A space, a caret and a name at the very end of a list item names it, so a board or a sentence can point at it. The name is drawn small and faint.',
    example: '- [ ] Ship the pricing page ^ship-page',
    task: 'Name an item on a list.',
    passes: (text) => itemsIn(text).length > 0,
    praise: 'That item has a name.',
    hint: 'At the end of the item, a space, a caret and a name with no spaces: ^ship-page.',
  },
  {
    id: 'itemRef',
    chapter: 'Pointing somewhere',
    symbol: '[[#^ ]]',
    rows: ['That item, from the words'],
    title: 'That item, from the words',
    teach: 'Two square brackets around a hash, a caret and an item’s name point at that item from anywhere in the note. A tap goes to its line.',
    example: 'the page is waiting on [[#^ask-sam]]\n\n- Ask Sam about the copy ^ask-sam',
    task: 'Point at a named item from a sentence.',
    passes: (text) => refsIn(text).length > 0,
    praise: 'That points at the item.',
    hint: 'Two square brackets around #^ and the name: [[#^ask-sam]].',
  },
  {
    id: 'bookmark',
    chapter: 'Pointing somewhere',
    symbol: '§§',
    rows: ['The bookmark'],
    title: 'The bookmark',
    teach: 'Two section signs at the end of a line are the note’s bookmark, and the note opens there. A note has one; the bookmark button at the top of a note moves it to the line you are on.',
    example: 'the deposit is four hundred §§',
    task: 'Bookmark a line.',
    passes: (text) => bookmarkLineIn(text) !== null,
    praise: 'The note would open here.',
    hint: 'Two section signs at the very end of the line: §§',
  },
  {
    id: 'board',
    chapter: 'Pointing somewhere',
    symbol: '```board',
    rows: ['A board'],
    title: 'A board',
    teach: 'A block marked board lays named items out as columns. Each line of it is a column: its name, a colon, and the names of the items in it. The items stay in the note as they were.',
    example: '```board\nTo do: ship-page\nDone: pick-date\n```\n\n- [ ] Ship the pricing page ^ship-page\n- [x] Pick a launch date ^pick-date',
    task: 'Make a board with a column or two.',
    passes: (text) => boardsIn(text).length > 0,
    praise: 'That is a board.',
    hint: 'Three backticks and board, a line like To do: ship-page, then three backticks, and an item named ^ship-page.',
  },

  // ---- Marks and effects: the Marks plugin's, each switched off with it --------------------------------------------
  {
    id: 'spoiler',
    chapter: 'Marks and effects',
    symbol: '||',
    rows: ['Spoiler'],
    needs: 'Spoiler',
    title: 'A spoiler',
    teach: 'Two bars either side turn the words to smoke until the caret is in them: the end of a film, a surprise.',
    example: 'the ending: ||the butler did it||',
    task: 'Keep a secret in a line.',
    passes: parsed('Spoiler'),
    praise: 'Gone to smoke.',
    hint: 'Two bars either side: ||like this||.',
  },
  {
    id: 'highlight',
    chapter: 'Marks and effects',
    symbol: '==',
    rows: ['Highlight'],
    needs: 'Highlight',
    title: 'A highlight',
    teach: 'Two equals signs either side put a wash of colour behind the words, for the line you will want again.',
    example: 'meet at ==the north gate==',
    task: 'Highlight something.',
    passes: parsed('Highlight'),
    praise: 'Highlighted.',
    hint: 'Two equals signs either side: ==like this==.',
  },
  {
    id: 'tint',
    chapter: 'Marks and effects',
    symbol: '==( )',
    rows: ['A coloured highlight'],
    needs: 'Highlight',
    title: 'A coloured highlight',
    teach: 'A colour’s name in brackets straight after a highlight changes its colour: blue, red, amber, green, teal, purple or gray.',
    example: '==the cabin key==(green) and ==the deadline==(red)',
    task: 'Highlight something in a colour.',
    passes: (text) => noted(text, true),
    praise: 'In colour.',
    hint: 'A highlight, then the colour in brackets with no space: ==this==(green).',
  },
  {
    id: 'aside',
    chapter: 'Marks and effects',
    symbol: '%%',
    rows: ['Aside'],
    needs: 'Aside',
    title: 'An aside',
    teach: 'Two percent signs either side make a note to yourself inside the note: smaller, quieter, leaning.',
    example: 'the train at nine %%or the one after%%',
    task: 'Write an aside.',
    passes: parsed('Aside'),
    praise: 'A quiet aside.',
    hint: 'Two percent signs either side: %%like this%%.',
  },
  {
    id: 'unsure',
    chapter: 'Marks and effects',
    symbol: '??',
    rows: ['Unsure'],
    needs: 'Unsure',
    title: 'Unsure',
    teach: 'Two question marks either side draw a dotted line under a fact to check later.',
    example: 'the deposit is ??four hundred??',
    task: 'Mark something you are not sure of.',
    passes: parsed('Unsure'),
    praise: 'Marked to check.',
    hint: 'Two question marks either side: ??like this??.',
  },
  {
    id: 'markNote',
    chapter: 'Marks and effects',
    symbol: '( )',
    rows: ['A note on a mark'],
    needs: 'Unsure',
    title: 'A note on a mark',
    teach: 'Words in brackets straight after a mark are a note on it, and a tap on the words in a note shows it. On a fact you are unsure of, it says why.',
    example: '??four hundred??(Sam said 400)',
    task: 'Put a note on a mark.',
    passes: (text) => noted(text, false),
    praise: 'That is a note on the mark: tap the words to read it.',
    hint: 'A mark, then the note in brackets with no space: ??four hundred??(why).',
  },
  {
    id: 'shout',
    chapter: 'Marks and effects',
    symbol: '^^',
    rows: ['Shout'],
    needs: 'Shout',
    title: 'A shout',
    teach: 'Two carets either side set the words in spaced small capitals: emphasis that is not bold.',
    example: 'bring ^^the tickets^^',
    task: 'Shout something.',
    passes: parsed('Shout'),
    praise: 'Heard.',
    hint: 'Two carets either side: ^^like this^^.',
  },
  {
    id: 'added',
    chapter: 'Marks and effects',
    symbol: '++',
    rows: ['Added'],
    needs: 'Added',
    title: 'Added',
    teach: 'Two plus signs either side underline what was added, the partner of struck through for what went.',
    example: 'we leave at ~~nine~~ ++ten++',
    task: 'Mark something as added.',
    passes: parsed('Added'),
    praise: 'Added, and it shows.',
    hint: 'Two plus signs either side: ++like this++.',
  },
  {
    id: 'heat',
    chapter: 'Marks and effects',
    symbol: '🔥🔥',
    rows: ['Heat'],
    needs: 'Heat',
    title: 'Heat',
    teach: 'Two flames either side make the words bold, and the line above them wavers in the heat coming off them. An effect lifts while the caret is in its words, so they edit as plain text.',
    example: 'The air above wavers\n🔥🔥too hot to touch🔥🔥',
    task: 'Heat some words, with a line above them.',
    passes: parsed('Heat'),
    praise: 'Too hot to touch.',
    hint: 'Two flames either side: 🔥🔥like this🔥🔥. One flame is only a flame.',
  },
  {
    id: 'frost',
    chapter: 'Marks and effects',
    symbol: '❄️❄️',
    rows: ['Frost'],
    needs: 'Frost',
    title: 'Frost',
    teach: 'Two snowflakes either side turn the words cold, a rime creeping over their edges and settling.',
    example: 'the pond is ❄️❄️frozen solid❄️❄️',
    task: 'Freeze some words.',
    passes: parsed('Frost'),
    praise: 'Frozen.',
    hint: 'Two snowflakes either side: ❄️❄️like this❄️❄️.',
  },
  {
    id: 'wave',
    chapter: 'Marks and effects',
    symbol: '🌊🌊',
    rows: ['Wave'],
    needs: 'Wave',
    title: 'A wave',
    teach: 'Two waves either side set the words bobbing along the line, a ripple passing through them.',
    example: 'the boat went 🌊🌊out to sea🌊🌊',
    task: 'Send some words out on a wave.',
    passes: parsed('Wave'),
    praise: 'Bobbing along.',
    hint: 'Two waves either side: 🌊🌊like this🌊🌊.',
  },
  {
    id: 'shimmer',
    chapter: 'Marks and effects',
    symbol: '✨✨',
    rows: ['Shimmer'],
    needs: 'Shimmer',
    title: 'A shimmer',
    teach: 'Two sparkles either side send a glint across the words every few seconds.',
    example: 'a ✨✨silver thread✨✨',
    task: 'Make some words shimmer.',
    passes: parsed('Shimmer'),
    praise: 'Glinting.',
    hint: 'Two sparkles either side: ✨✨like this✨✨.',
  },
  {
    id: 'haunt',
    chapter: 'Marks and effects',
    symbol: '👻👻',
    rows: ['Haunt'],
    needs: 'Haunt',
    title: 'A haunting',
    teach: 'Two ghosts either side make the words fade almost away and back, slowly, like something passing.',
    example: 'and then 👻👻nobody there👻👻',
    task: 'Haunt some words.',
    passes: parsed('Haunt'),
    praise: 'Something passed.',
    hint: 'Two ghosts either side: 👻👻like this👻👻.',
  },
];

/** The lessons on offer now: every one whose plugin mark, where it needs one, is switched on. */
export function lessonsNow(): Lesson[] {
  const on = new Set(plugins.formats().map((format) => format.name));
  return LESSONS.filter((lesson) => !lesson.needs || on.has(lesson.needs));
}

/** The lessons of a chapter, in the order they are taught, from `from` (every lesson, unless told). */
export function lessonsIn(chapter: Chapter, from: readonly Lesson[] = LESSONS): Lesson[] {
  return from.filter((lesson) => lesson.chapter === chapter);
}

/** Where a person has got to, kept between visits, so the Academy opens at the first lesson not passed. */
const KEY = 'glyph-academy';

export function readProgress(): Set<string> {
  return new Set(readStored<string[]>(KEY, [], (ids) => (Array.isArray(ids) ? ids.filter((id): id is string => typeof id === 'string') : [])));
}

/** Not kept, progress still counts for this visit. */
export function writeProgress(done: ReadonlySet<string>): void {
  writeStored(KEY, [...done]);
}
