// What @codemirror/lang-markdown's own Enter and Backspace do, for the Dart ports of them to be held against
// (lib/editor/commands/markdown_commands.dart, test/editor/commands/markdown_commands_test.dart).
//
//   node tool/markdown_command_fixtures.mjs
//
// Everything is read from ../glyph's node_modules and nothing is written there: @codemirror/state,
// @codemirror/language and @codemirror/lang-markdown 6.5.2, configured as the app configures them
// (src/app/editor/language.ts `glyphMarkdown([], [])`: GFM, no Setext headings, the keymap, no code languages, HTML
// parsed by the HTML language as lang-markdown does by default). One fixture goes to
// test/editor/commands/fixtures/markdown_commands.json:
//
//   docs    for each document, at every caret position: whether Markdown is the active language on either side
//           (`active`, a digit per position: 1 for side -1, 2 for side 1), and what `insertNewlineContinueMarkup`
//           (`enter`), the same with `nonTightLists: false` (`enterTight`) and `deleteMarkupBackward` (`backspace`)
//           did: 0 where the command answered false, else the transaction's changes (ChangeSet.toJSON) and its
//           selection as anchor, head pairs
//   multi   the same commands over selections of several carets, and of ranges, which make them stand down
//
// Every command dispatches with scrollIntoView and one user event (`events`); the script throws if one does not.
import { writeFileSync, mkdirSync } from 'node:fs';

const GLYPH = '/Users/matt/Development/Apps/glyph/';
const OUT = new URL('../test/editor/commands/fixtures/', import.meta.url).pathname;

const { EditorState, EditorSelection, Transaction } = await import(`${GLYPH}node_modules/@codemirror/state/dist/index.js`);
const { ensureSyntaxTree, syntaxTree } = await import(`${GLYPH}node_modules/@codemirror/language/dist/index.js`);
const md = await import(`${GLYPH}node_modules/@codemirror/lang-markdown/dist/index.js`);

// src/app/editor/language.ts, with no plugin formats and no code languages (as its own tests make it).
const language = md.markdown({
  base: md.markdownLanguage,
  extensions: [{ remove: ['SetextHeading'] }],
  codeLanguages: [],
  addKeymap: true,
  completeHTMLTags: false,
  pasteURLAsLink: true,
});
const extensions = [language, EditorState.allowMultipleSelections.of(true)];

const commands = {
  enter: md.insertNewlineContinueMarkup,
  enterTight: md.insertNewlineContinueMarkupCommand({ nonTightLists: false }),
  backspace: md.deleteMarkupBackward,
};
const events = { enter: 'input', enterTight: 'input', backspace: 'delete' };

function stateOf(doc, selection) {
  const state = EditorState.create({ doc, selection, extensions });
  const tree = ensureSyntaxTree(state, doc.length, 10_000);
  if (!tree || syntaxTree(state).length !== doc.length) throw new Error(`Not parsed whole: ${JSON.stringify(doc)}`);
  return state;
}

function run(name, state) {
  let tr = null;
  const handled = commands[name]({ state, dispatch: (t) => (tr = t) });
  if (!handled) {
    if (tr) throw new Error(`${name} dispatched and answered false`);
    return 0;
  }
  if (!tr.scrollIntoView || tr.annotation(Transaction.userEvent) !== events[name]) throw new Error(`${name}: not the event expected`);
  return [tr.changes.toJSON(), tr.state.selection.ranges.flatMap((r) => [r.anchor, r.head]), tr.state.selection.mainIndex];
}

// ---- The documents ------------------------------------------------------------------------------------------------

const DOCS = [
  '',
  'plain words',
  'two\nlines',
  '- ',
  '- a',
  '- a\n- b',
  '- a\n- ',
  '- a\n- b\n- ',
  '- a\n\n- b',
  '- a\n\n- b\n- ',
  '- a\n\n- ',
  '* a\n* ',
  '+ a\n+ b',
  '-  two spaces\n-  ',
  '-     five spaces',
  '- a\n  - b',
  '- a\n  - b\n  - ',
  '- a\n  - ',
  '- a\n  - b\n    - c\n    - ',
  '- a\n  continued\n- b',
  '- a\n  continued',
  '- a\ncontinued lazily',
  '- a\n\n  second paragraph',
  '- a\n\n  second paragraph\n- b',
  '  - indented\n  - ',
  '1. one',
  '1. one\n2. two',
  '1. one\n2. ',
  '1. one\n2. two\n3. three',
  '1. one\n2. two\n3. three\n4. four',
  '1. one\n3. three\n4. four',
  '1) one\n2) two',
  '9. nine\n10. ten\n11. ',
  '1. one\n   - nested\n   - ',
  '1. one\n   1. inner\n   2. inner\n2. two',
  '1. one\n\n2. two\n3. ',
  '1.  wide\n2.  ',
  '1.      very wide',
  '- [ ] todo',
  '- [ ] todo\n- [x] done',
  '- [ ] todo\n- [ ] ',
  '- [x] done\n- [X] DONE\n',
  '-  [ ] spaced box',
  '1. [ ] numbered todo\n2. [x] done',
  '- [ ] a\n  - [ ] b\n  - [ ] ',
  '> quote',
  '> quote\n> more',
  '> quote\n> ',
  '> quote\n>',
  '>\n>',
  '> \n> ',
  '> a\n>\n> b',
  '>quote without space',
  '> > nested',
  '> > nested\n> > ',
  '> - item in quote',
  '> - item in quote\n> - ',
  '> - a\n> - b\n> - ',
  '> 1. one\n> 2. two',
  '- > quote in item',
  '- > quote in item\n  > more',
  '- > quote in item\n  > ',
  '- a\n  > quote under item\n  > ',
  '> - a\n>   - b\n>   - ',
  '# Heading\n\n- a\n- b\n\nPara',
  'Para\n- a\n- b',
  '- a\n- b\nPara lazily',
  '- a\n\nPara',
  '- **bold** and `code`\n- [link](https://example.com)',
  '- a  \n- b   ',
  '-\ta tab\n-\t',
  '- a\n\t- tab indented\n\t- ',
  '   - three in\n   - ',
  '- ```js\n  code\n  ```\n- after',
  '```\n- not a list\n> not a quote\n```',
  '- a\n\n  ```\n  fenced\n  ```',
  '> ```\n> code\n> ```\n> after',
  '    - indented code\n    > not quote',
  '- <div>\n  html in item</div>\n- after',
  '- <div>',
  '<div>\n- inside html block\n</div>\n\n- after',
  '> <b>html</b> in quote\n> ',
  '- a <span>inline</span> b\n- ',
  '<!-- comment -->\n- a',
  '- <!-- comment in item -->\n- b',
  '- a\n- b\n\n\n- c',
  '- a\n\n\n',
  '\n- a\n',
  '- a\n-',
  '-',
  '1.',
  '>',
  '- a\n  \n  b',
  '-  \n- b',
  '- a\n  1. one\n  2. ',
  '1. a\n   > q\n   > ',
  '- one\n- two\n- three\n\nAfter\n\n1. x\n2. y',
  '- 😀 emoji\n- é accent\n- ',
  '| a | b |\n| - | - |\n| c | d |',
  '- a\n\n| a | b |\n| - | - |',
  '- [ ]',
  '- [ ]x',
  '- [x](https://example.com)',
  '---\n- a\n---',
  '- a\n---\n- b',
  '10. ten\n11. eleven\n12. twelve',
  '1. one\n2. two\n\n   continued under two\n3. three',
  '0. zero\n1. ',
  '- a\n    - deep four\n    - ',
  '* a\n\n  * b\n\n  * ',
];

// A seeded source, so the fixture is the same each run (mulberry32).
function random(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = random(20261007);
const pick = (list) => list[Math.floor(rand() * list.length)];
const LEADS = ['', '', '- ', '- ', '* ', '+ ', '1. ', '2. ', '3) ', '- [ ] ', '- [x] ', '> ', '> ', '>', '> > ', '> - ', '> 1. ', '- > ', '# ', '```', '    ', '\t'];
const INDENTS = ['', '', '', '  ', '  ', '    ', '   ', ' ', '\t', '> ', '>   '];
const WORDS = ['', '', 'a', 'milk', 'two words', '**b**', '`c`', '<i>x</i>', '<div>', '[ ]', 'x  ', '1.', '-', '>', '😀'];
for (let n = 0; n < 150; n += 1) {
  const lines = [];
  for (let i = 1 + Math.floor(rand() * 5); i > 0; i -= 1) lines.push(`${pick(INDENTS)}${pick(LEADS)}${pick(WORDS)}`);
  DOCS.push(lines.join('\n'));
}

// ---- Running them -------------------------------------------------------------------------------------------------

const docs = [];
let count = 0;
for (const doc of [...new Set(DOCS)]) {
  const entry = { doc, active: '', enter: [], enterTight: [], backspace: [] };
  for (let pos = 0; pos <= doc.length; pos += 1) {
    const state = stateOf(doc, EditorSelection.single(pos));
    entry.active += String((md.markdownLanguage.isActiveAt(state, pos, -1) ? 1 : 0) + (md.markdownLanguage.isActiveAt(state, pos, 1) ? 2 : 0));
    for (const name of Object.keys(commands)) {
      entry[name].push(run(name, state));
      count += 1;
    }
  }
  docs.push(entry);
}

const multi = [];
const MULTI = [
  ['- a\n- b\n- ', [[3, 3], [7, 7]], 0],
  ['- a\n- b\n- ', [[3, 3], [10, 10]], 1],
  ['- a\n- \n- b\n- ', [[6, 6], [13, 13]], 0],
  ['1. one\n2. two\n3. three', [[6, 6], [13, 13]], 1],
  ['1. one\n2. two\n3. three', [[6, 6], [13, 13], [22, 22]], 2],
  ['> a\n> b', [[3, 3], [7, 7]], 0],
  ['- a\nplain', [[3, 3], [9, 9]], 0],
  ['- a\nplain', [[3, 3]], 0],
  ['- a\n- b', [[2, 3]], 0],
  ['- a\n- b', [[3, 2]], 0],
  ['- a\n- b', [[3, 3], [6, 7]], 0],
  ['- \n- \n- ', [[2, 2], [5, 5], [8, 8]], 1],
  ['- a\n  - \n  - ', [[8, 8], [13, 13]], 0],
  ['> - \n> - ', [[4, 4], [9, 9]], 1],
  ['- [ ] \n- [ ] ', [[6, 6], [13, 13]], 0],
  ['1. \n2. \n3. ', [[3, 3], [7, 7], [11, 11]], 0],
];
for (const [doc, ranges, main] of MULTI) {
  for (const name of Object.keys(commands)) {
    const selection = EditorSelection.create(ranges.map(([anchor, head]) => EditorSelection.range(anchor, head)), main);
    multi.push({ doc, ranges, main, command: name, result: run(name, stateOf(doc, selection)) });
    count += 1;
  }
}

mkdirSync(OUT, { recursive: true });
const out = { langMarkdown: '6.5.2', events, docs, multi };
writeFileSync(`${OUT}markdown_commands.json`, `${JSON.stringify(out)}\n`);
const handled = docs.reduce((sum, d) => sum + ['enter', 'enterTight', 'backspace'].reduce((s, k) => s + d[k].filter(Boolean).length, 0), 0);
console.log(`markdown_commands.json: ${docs.length} documents, ${count} cases (${handled} handled), ${(JSON.stringify(out).length / 1024).toFixed(0)} kB`);
