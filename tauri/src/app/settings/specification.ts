import { BLANK, FILLED } from '../core/blanks.ts';
import { COMMENT_ANCHOR } from '../core/comments/format.ts';
import { ANCHOR, BOOKMARK, CHOICE, COUNTER } from '../core/itemSyntax.ts';
import { MATHS } from '../core/maths.ts';
import { GEO_LINK } from '../core/placeRefs.ts';
import { TAG } from '../core/tags.ts';

/**
 * The specification Settings shows under About (settings/SpecPane.tsx; GLY-4, Matt: "Add specification page under the
 * settings page, it should strictly define all our custom AI fills, and custom markdown format extensions as well as a
 * link to the official base markdown spec"; docs/DESIGN.md §164).
 *
 * What the page says is the definition, so it is held to the code three ways. Where a rule is a pattern, the page shows
 * the pattern the app runs, imported from the module that runs it, not a copy of it. Every mark the cheat sheet teaches
 * is defined here (`covers`), and a test fails when one is not (settings/specification.test.ts), so a new mark cannot
 * arrive without its definition. And each entry says how any other app shows the same characters, which is the promise
 * every extension keeps: the file is plain Markdown, and the app only draws more from it.
 */

export interface SpecEntry {
  name: string;
  /** How it is written. */
  written: string;
  /** The rule, exactly. */
  rule: string;
  /** How any other Markdown app shows it. */
  elsewhere: string;
  /** The pattern the app reads it by, where one pattern is the rule. */
  pattern?: string;
  /** The cheat sheet's names for the marks this entry defines (guide/marks.ts). */
  covers?: readonly string[];
}

export interface SpecSection {
  id: string;
  title: string;
  intro: string;
  entries: readonly SpecEntry[];
}

/** The base specifications, which every note is first. */
export const BASE_SPECS = [
  { name: 'CommonMark', url: 'https://spec.commonmark.org/', about: 'The standard Markdown every note is, read by the app’s own parser.' },
  { name: 'GitHub Flavored Markdown', url: 'https://github.github.com/gfm/', about: 'Tables, task lists, strikethrough and bare links, on top of CommonMark.' },
] as const;

const OBSIDIAN = 'Obsidian reads it the same way; other apps show the characters as written.';
const AS_WRITTEN = 'Shown as the characters written.';

export const SPEC: readonly SpecSection[] = [
  {
    id: 'base',
    title: 'Standard Markdown',
    intro:
      'Every note is CommonMark with GitHub’s extensions, parsed by the app’s editor. Two choices differ from a renderer’s defaults: a line of = or - under a paragraph is not a heading (setext headings are off, since on a phone they turned a paragraph into a heading whenever a list began under it), and HTML is shown as text and never run.',
    entries: [
      {
        name: 'Emphasis and code',
        written: '**bold**  *italic*  ***both***  ~~struck~~  `code`',
        rule: 'As CommonMark and GFM define them.',
        elsewhere: 'The same everywhere.',
        covers: ['Bold', 'Italic', 'Both', 'Struck through', 'Code'],
      },
      {
        name: 'Headings, lists, quotes and rules',
        written: '# Title\n## Heading\n### Smaller heading\n- A list\n1. In order\n- [ ] A to-do\n- [x] Done\n> A quote\n---',
        rule: 'As CommonMark and GFM define them. A note’s first line is its title, a heading or not. A to-do’s box is [ ], [x] or [X] standing as a word after a list marker.',
        elsewhere: 'The same everywhere.',
        covers: ['Title', 'Heading', 'Smaller heading', 'A list', 'In order', 'A to-do', 'Done', 'A quote', 'A dividing line'],
      },
      {
        name: 'Links, pictures, tables and code blocks',
        written: '[words](https://…)  ![a picture](image/…)\n| A | B |\n| --- | --- |\n```js\ncode\n```',
        rule: 'As CommonMark and GFM define them. A line that is only a link gets a card under it with the page’s title.',
        elsewhere: 'The same everywhere.',
        covers: ['A link', 'A table', 'A picture', 'A block of code'],
      },
      {
        name: 'Front matter',
        written: '---\ntitle: "A name"\n---',
        rule: 'A fence of --- or +++ on the first line, then only key: lines or blank lines, then a closing fence, all within the first 40 lines. Anything else is a rule and words. The keys Ghost.md reads are listed below.',
        elsewhere: 'Obsidian and static sites read it as properties; CommonMark shows a rule and a heading.',
      },
    ],
  },
  {
    id: 'shared',
    title: 'Extensions other apps share',
    intro: 'Written the way Obsidian, GitHub and Pandoc write them, so a note reads the same there.',
    entries: [
      {
        name: 'Links between notes',
        written: '[[Another note]]  [[Note#^anchor]]  [[Note|words]]  ![[A canvas]]',
        rule: 'Double brackets around a note’s title, matched without regard to case. What follows a # is a place in it (^anchor for an item); what follows | is not part of the title. ![[…]] on a line of its own draws that canvas in a frame. A ticket’s key, [[GHO-12]], opens the ticket.',
        elsewhere: OBSIDIAN,
        covers: ['Another note'],
      },
      {
        name: 'Tags',
        written: '#tag  #work/clients',
        rule: 'A # straight against a letter, after the line’s start, a space or an opening bracket; then letters, digits, _, - or /. A trailing - or / is punctuation. Not inside code, links, front matter or a blank’s question.',
        elsewhere: OBSIDIAN,
        pattern: TAG.source,
        covers: ['A tag'],
      },
      {
        name: 'Item anchors',
        written: '- [ ] Ship the pricing page ^ship-page',
        rule: 'A space, a caret and a name of lower-case letters, digits, _ and -, ending a list item’s line. It names the item, for a board and for links. After the anchor only an item’s mark may follow.',
        elsewhere: OBSIDIAN,
        pattern: ANCHOR,
        covers: ['A name for an item', 'That item, from the words'],
      },
      {
        name: 'Callouts',
        written: '> [!NOTE]\n> Words',
        rule: 'A quote whose first line is [!NOTE], [!TIP], [!IMPORTANT], [!WARNING] or [!CAUTION].',
        elsewhere: 'GitHub and Obsidian draw the callout; others show a quote.',
        covers: ['A callout'],
      },
      {
        name: 'Footnotes',
        written: 'Words[^sam]\n\n[^sam]: What it says.',
        rule: 'A marker [^name] and a definition line [^name]: words. A marker with no definition stays as typed.',
        elsewhere: 'GitHub, Obsidian and Pandoc draw it; others show the brackets.',
        covers: ['A footnote'],
      },
      {
        // docs/SHARED.md, S8; core/comments/format.ts reads and writes it.
        name: 'Comments',
        written: 'The ==venue==[^c1] is booked.\n\n```comments\nc1 matt 2026-10-04T19:00:12Z\nThe hall or the barn?\n  sam 2026-10-04T19:05:40Z\n  The hall.\n  resolved sam 2026-10-04T19:06:02Z\n```',
        rule:
          'An anchor [^c<id>] after the words, or ==round them==[^c<id>], and one ```comments fence at the end of the note. A thread is a line "<id> <handle> <ISO time>" and its words on the lines under it; a reply is the same indented two spaces; "  resolved <handle> <time>" closes it. A words line that would read as a head, or starts with a backslash or three backticks, is written behind a backslash. Ids are c and a short tail, never one the note has used. A line the format does not know is kept as it is.',
        elsewhere: 'A footnote’s marker and a code block of lines; the selection is a highlight where highlights are drawn.',
        pattern: COMMENT_ANCHOR.source,
        covers: ['A comment'],
      },
      {
        name: 'Definition lists',
        written: 'Term\n: The meaning',
        rule: 'A line, then a line that starts with a colon and a space.',
        elsewhere: 'Pandoc and PHP Markdown Extra draw it; others show the colon.',
        covers: ['A definition'],
      },
      {
        name: 'Raised and lowered',
        written: 'x^2^  H~2~O',
        rule: 'One word between carets is raised; between single tildes it is lowered. Never across a space.',
        elsewhere: 'Pandoc draws it; others show the characters.',
        covers: ['Raised', 'Lowered'],
      },
      {
        name: 'Maths',
        written: '$x^2$  $$ … $$',
        rule: 'Pandoc’s rule: an opening $ has a non-space after it, a closing $ has a non-space before it and no digit after it, and a $ after a backslash is a dollar. So “It costs $5, or $6” is two prices.',
        elsewhere: 'Obsidian, GitHub and Pandoc draw it; others show the dollars.',
        pattern: MATHS.source,
        covers: ['Maths'],
      },
      {
        name: 'Emoji',
        written: ':tada:',
        rule: 'A known emoji name between colons is drawn as the emoji. An unknown name stays as typed.',
        elsewhere: 'GitHub draws it; others show the name.',
        covers: ['An emoji'],
      },
      {
        name: 'Diagrams',
        written: '```mermaid\nflowchart LR\n  A --> B\n```',
        rule: 'A fence called mermaid is drawn as the diagram it describes. One that cannot be drawn stays as its text, with the reason under it.',
        elsewhere: 'GitHub and Obsidian draw it; others show the code.',
        covers: ['A diagram'],
      },
      {
        name: 'Fields on a to-do',
        written: '- [ ] Fix the login loop @sam ⏫ 📅 2026-10-03  [effort:: 3]',
        rule: 'Obsidian Tasks’ emoji, each with a space and a date (YYYY-MM-DD) where it takes one: 📅 due, 🛫 start, ⏳ scheduled, ✅ done, ➕ created, ❌ cancelled, 🔁 repeats; 🔺 ⏫ 🔼 🔽 ⏬ for highest to lowest priority. A person is @ and a name after a space or the line’s start. Any other field is Dataview’s [key:: value]. Fields sit at the end of the words, before the bookmark, a mark, a counter and the anchor.',
        elsewhere: 'Obsidian with Tasks and Dataview reads them; others show the characters.',
        covers: ['A due date', 'A priority', 'A person', 'A field by name'],
      },
    ],
  },
  {
    id: 'own',
    title: 'Ghost.md’s own marks',
    intro: 'The Marks plugin’s, each switched off with it. Every one is ordinary characters, so the words are still there in any other app.',
    entries: [
      { name: 'Spoiler', written: '||the ending||', rule: 'Two bars either side: the words go to smoke until the caret is in them.', elsewhere: AS_WRITTEN, covers: ['Spoiler'] },
      { name: 'Hidden line', written: '>| the answer', rule: 'A quote whose first character is a bar goes to smoke until the caret is in it. Part of the spoiler.', elsewhere: 'A quote.', covers: ['A hidden line'] },
      {
        name: 'Highlight',
        written: '==words==  ==words==(green)',
        rule: 'Two equals signs either side. A color by name in brackets straight after: blue, red, amber, green, teal, purple or gray. Any other name is the plain highlight with its brackets as a note.',
        elsewhere: 'Obsidian draws the plain highlight; others show the signs.',
        covers: ['Highlight', 'A colored highlight'],
      },
      { name: 'Aside', written: '%%an aside%%', rule: 'Two percent signs either side: quiet words beside the rest.', elsewhere: 'Obsidian hides it as a comment; others show it.', covers: ['Aside'] },
      { name: 'Unsure', written: '??four hundred??', rule: 'Two question marks either side: words to check.', elsewhere: AS_WRITTEN, covers: ['Unsure'] },
      { name: 'Redact', written: '@@4417@@', rule: 'Two at signs either side: a bar of ink over the words wherever no caret lifts it. A look only: the words stay in the file.', elsewhere: AS_WRITTEN, covers: ['Redact'] },
      { name: 'Shout', written: '^^loud^^', rule: 'Two carets either side.', elsewhere: AS_WRITTEN, covers: ['Shout'] },
      { name: 'Added', written: '++new words++', rule: 'Two plus signs either side.', elsewhere: AS_WRITTEN, covers: ['Added'] },
      {
        name: 'A note on a mark',
        written: '??four hundred??(Sam said 400)',
        rule: 'Any mark followed straight away by words in brackets: the words are its note, shown on a tap.',
        elsewhere: AS_WRITTEN,
        covers: ['A note on a mark'],
      },
      {
        name: 'Effects',
        written: '🔥🔥heat🔥🔥  ❄️❄️frost❄️❄️  🌊🌊wave🌊🌊  ✨✨shimmer✨✨  👻👻haunt👻👻',
        rule: 'An effect’s emoji twice either side. One emoji is a word. Effects nest, lift while the caret is in them, and hold still under reduced motion.',
        elsewhere: 'The emoji and the words.',
        covers: ['Heat', 'Frost', 'Wave', 'Shimmer', 'Haunt'],
      },
    ],
  },
  {
    id: 'lines',
    title: 'Ghost.md’s own lines and blocks',
    intro: 'Plain characters that read sensibly anywhere, which the app does more with.',
    entries: [
      { name: 'Counter', written: '- Water [3/8]', rule: 'A count and a goal in square brackets, up to four digits each. A tap adds one, a hold takes one away.', elsewhere: AS_WRITTEN, pattern: COUNTER, covers: ['A counter'] },
      {
        name: 'Sum',
        written: '= $450 + 120 * 2',
        rule: 'A line, list item or quote that starts with = and a space shows its answer after it, never written into the note. Arithmetic only: + - * / ^, brackets, % after a number. A currency sign and thousands commas carry over.',
        elsewhere: AS_WRITTEN,
        covers: ['A sum'],
      },
      { name: 'Choice', written: '- ( ) Red\n- (x) Blue', rule: 'A round box after a bullet. One is picked per group of choice lines at one indent.', elsewhere: 'A list.', pattern: CHOICE, covers: ['A choice'] },
      { name: 'Progress', written: '## Packing', rule: 'Nothing to type: a heading with to-dos under it, its subsections included, says how many are done.', elsewhere: 'A heading.', covers: ['Progress'] },
      { name: 'Bookmark', written: 'Where I left off §§', rule: 'Two section signs ending a line’s words, before a mark, counter and anchor. One per note; the note opens there.', elsewhere: AS_WRITTEN, pattern: BOOKMARK, covers: ['The bookmark'] },
      {
        name: 'Place',
        written: '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)',
        rule: 'A link to a geo: address (RFC 5870), alone on its line. A map card is drawn under it; at the very top of a note, on its first line or the one under the title, it is the note’s header. Four decimals, or two for a rough place.',
        elsewhere: 'A link.',
        pattern: GEO_LINK.source,
        covers: ['A place'],
      },
      {
        name: 'Video',
        written: '[![video 0:12](image/poster.jpg)](video/clip.mp4)',
        rule: 'A poster picture linked to a film under video/, alone on its line. The alt is “video” and its length.',
        elsewhere: 'A linked picture.',
        covers: ['A video'],
      },
      {
        name: 'Board',
        written: '```board height=18\nTo do: ship-page\nDone: pick-date\n```',
        rule: 'A fence called board; each line a column, its name, a colon and the anchors of its items in order. An anchor is read into the first column that has it. height= sets the lanes’ height in ems, 5 to 60.',
        elsewhere: 'A code block, and the list of items it names.',
        covers: ['A board'],
      },
      {
        name: 'Ticket',
        written: '---\ntype: ticket\nid: GHO-12\nstatus: In progress\n---',
        rule: 'A note whose front matter says type: ticket. Its keys are below. A notebook’s key: numbers its tickets, the next one past the highest ever used.',
        elsewhere: 'Front matter, read as properties by Obsidian.',
        covers: ['A ticket'],
      },
      {
        name: 'Query',
        written: '```query\nfrom: tasks #launch\nwhere: due <= today+7\nsort: due, priority\nshow: list\n```',
        rule: 'A fence called query. One line each, every one optional: from: (notes, tickets or tasks, then #tags, [[notebooks]], @people and "words", with or, not and brackets), where: (=, !=, <, <=, >, >=, contains, is empty, joined by and and or), sort:, group:, show: (table, list, board, calendar, gantt, count), columns:, total:, limit:.',
        elsewhere: 'A code block.',
        covers: ['A query'],
      },
    ],
  },
  {
    id: 'fills',
    title: 'AI fills',
    intro:
      'A blank is a question written where its answer belongs. Nothing fills until Fill is pressed, and every answer the AI writes says where it came from, in the note itself.',
    entries: [
      {
        name: 'A blank',
        written: '{?what day / time?}  {?}',
        rule: 'A question in curly brackets with a question mark after the first bracket, one line, at most 160 characters, with no | in it. Not {{?…}}, not after a backslash or a $, not {??. {?} asks about the sentence it is in, or the question just before it.',
        elsewhere: AS_WRITTEN,
        pattern: BLANK.source,
        covers: ['A blank'],
      },
      {
        name: 'What answers it',
        written: '{?total?}  {?weather in Lisbon today?}  {?capital of Australia?}',
        rule: 'Asked in this order. Worked out by the app with no AI: a total, an average, a count, the days until or since, a weekday, a date, a unit conversion, the time in a city. Then looked up live by the phone, where the answer is something now: the weather (Open-Meteo), an exchange rate (Frankfurter), news and the newest of anything (Wikipedia and Wikidata). Otherwise the on-device model answers from what it knows or from the note. A question nothing can answer says so.',
        elsewhere: AS_WRITTEN,
      },
      {
        name: 'A filled answer',
        written: '??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)',
        rule: 'The answer is written as an Unsure mark whose note says whose answer it is, from where (from memory, from this note, or from a named source such as Open-Meteo), the day, what was asked, and N of M for one of several items. The note is hidden in the app and read back by this pattern. A title is filled as plain words.',
        elsewhere: 'The answer between question marks, and its note in brackets.',
        pattern: FILLED.source,
      },
    ],
  },
  {
    id: 'keys',
    title: 'Front matter keys',
    intro: 'The keys Ghost.md reads. Every other key is kept as it was written.',
    entries: [
      { name: 'title', written: 'title: "A name"', rule: 'The note’s name where it has no first line of words: a canvas, a notebook, a journal entry.', elsewhere: 'A property.' },
      { name: 'book, journal, key, statuses', written: 'book: true\nkey: GHO\nstatuses: [Backlog, To do, Done]', rule: 'book: true makes the note a notebook, its list of [[links]] its pages; journal: true a journal. key: (2 to 10 capitals and digits, a capital first) numbers its tickets; statuses: is its workflow, else Backlog, To do, In progress, In review, Done.', elsewhere: 'Properties.' },
      {
        name: 'Ticket keys',
        written: 'type: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\npriority: high\ndue: 2026-10-03\nstart: 2026-09-28\nestimate: 3\nblocked-by: "[[GHO-9]]"\nparent: "[[GHO-1]]"\nlabels: [bug, ui]',
        rule: 'id is a key, a dash and a number. priority is highest, high, medium, low or lowest. Days are YYYY-MM-DD. estimate is the number it starts with. blocked-by and parent are links; labels a list.',
        elsewhere: 'Properties.',
      },
      { name: 'look', written: 'look: map', rule: 'map draws where the note was written as its header; reading sets it as a page to read. Any other value is no look.', elsewhere: 'A property.' },
      { name: 'location, place', written: 'location: 51.5074,-0.1278\nplace: London', rule: 'Where the note was written, and the place’s name.', elsewhere: 'Properties; Obsidian’s Map View reads location.' },
      { name: 'authors', written: 'authors: Matt, Claude', rule: 'Who wrote the note, the AI among them when it co-wrote it.', elsewhere: 'A property.' },
      { name: 'tags', written: 'tags: [errands, home]', rule: 'Tags for the whole note, read with the tags in its words.', elsewhere: 'Obsidian reads them as tags.' },
    ],
  },
  {
    id: 'templates',
    title: 'Template placeholders',
    intro: 'In a template’s words, filled when a note is made from it. Obsidian’s names, and one of Ghost.md’s.',
    entries: [
      {
        name: 'Placeholders',
        written: '{{date}}  {{time}}  {{weekday}}  {{title}}  {{journal}}  {{date:D MMMM}}  {{next-id}}',
        rule: 'date is the long day (“Monday 28 September”), time a 24-hour clock, and a format after a colon is Moment’s tokens, words in square brackets. next-id is the next ticket key of the notebook the note is made in; an id: line holding only it is left out where there is none. Any other name is left as typed.',
        elsewhere: 'Obsidian’s templates fill the same names.',
      },
    ],
  },
];

/** Every name the cheat sheet teaches that the specification defines. */
export function specCovers(): Set<string> {
  return new Set(SPEC.flatMap((section) => section.entries.flatMap((entry) => entry.covers ?? [])));
}
