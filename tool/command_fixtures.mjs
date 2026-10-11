// What CodeMirror's own commands do, for the Dart port to be held against (lib/editor/commands/commands.dart,
// test/editor/commands/commands_test.dart).
//
//   node tool/command_fixtures.mjs
//
// Everything is read from tauri/ and nothing is written there: its node_modules for @codemirror/commands 6.11.0,
// @codemirror/state, @codemirror/view, @codemirror/language, @codemirror/lang-markdown and jsdom. One fixture goes
// to test/editor/commands/fixtures/commands.json. Seeded, so running it again writes the same file.
//
// A real EditorView is mounted under jsdom, so the commands that take a view (`view.moveByChar`, `view.moveByGroup`,
// `view.moveToLineBoundary`, `view.lineBlockAt`, the atomic ranges) run as they are. jsdom has no layout; what is
// recorded does not need one:
//   - text is left to right (no right-to-left character is in any document), so a line is one bidi span;
//   - lines do not wrap (`view.lineWrapping` is false: no `EditorView.lineWrapping`), so a line boundary is the
//     logical line's end, which is what a browser answers for an unwrapped line too;
//   - `deleteLine` asks `view.moveVertically` where the caret goes, and that is pixels. It is recorded with a
//     stand-in for that one call (the same column on the line below, counted with `countColumn`/`findColumn`),
//     which the Dart test puts in the port's `verticalMotion` facet: the fixture holds the rest of the command.
//   - the commands that are nothing but layout (cursorLineUp/Down, cursorPageUp/Down, their select twins,
//     addCursorAbove/Below) and toggleTabFocusMode are not recorded.
//
// Every case is run twice: by the web's language (`markdown({base: markdownLanguage, extensions: [{remove:
// ['SetextHeading']}], addKeymap: false})`, what src/app/editor/language.ts makes without plugin formats or the
// keymap) and by the same Markdown parser on its own (no nested HTML parser: what lib/editor/syntax parses). Where
// the two agree the case is written; where they differ (an HTML block or tag, which lang-markdown hands to
// @lezer/html, whose nodes and `wordChars` the Dart side does not have) it is counted in `skipped` and left out.
//
// The file:
//   docs      every document, once
//   commands  name -> cases; a case is [doc, selection, options, returned, result]
//     selection  a number (one caret, no side) or [main, anchor, head, assoc, bidiLevel (-1 none), undirectional, ...]
//     options    0, or {ro: 1} read-only, {atoms: [[from, to], ...]} atomic ranges, {unit: '\t'} the indent unit,
//                {tab: 2} the tab size
//   skipped   name -> how many cases the nested HTML parser answered differently (left out)
//   broken    name -> how many cases made a selection whose main index is past its ranges (left out)
//     result     0 when nothing was dispatched, else [doc change, selection, userEvent, scrollIntoView, selection
//                set, announced]: the change is 0 (none) or [prefix length, suffix length, what is between them now]
import { writeFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';

const GLYPH = new URL('../tauri/', import.meta.url).pathname;
const OUT = new URL('../test/editor/commands/fixtures/', import.meta.url).pathname;
const require = createRequire(`${GLYPH}package.json`);

// ---- A browser for the view ---------------------------------------------------------------------------------------

const { JSDOM } = require('jsdom');
const dom = new JSDOM('<!doctype html><html><body></body></html>', { pretendToBeVisual: true });
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });
define('window', dom.window);
define('document', dom.window.document);
define('navigator', dom.window.navigator);
for (const name of ['MutationObserver', 'Node', 'HTMLElement', 'Range', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'DOMRect', 'Text']) {
  define(name, typeof dom.window[name] === 'function' && /^[a-z]/.test(name) ? dom.window[name].bind(dom.window) : dom.window[name]);
}

const load = (name) => import(`${GLYPH}node_modules/${name}/dist/index.js`);
const S = await load('@codemirror/state');
const V = await load('@codemirror/view');
const L = await load('@codemirror/language');
const C = await load('@codemirror/commands');
const M = await load('@codemirror/lang-markdown');
const { EditorState, EditorSelection, Transaction, countColumn, findColumn } = S;
const { EditorView, Decoration } = V;
const { syntaxTree, ensureSyntaxTree, forceParsing, indentUnit, Language } = L;
const { markdown, markdownLanguage } = M;

// Two copies of @codemirror/state would make every instanceof a lie.
if (C.cursorDocEnd({ state: EditorState.create({ doc: 'a' }), dispatch: (tr) => { if (!(tr instanceof Transaction)) throw new Error('two @codemirror/state'); } }) !== true) throw new Error('commands did not run');

// ---- The two languages -------------------------------------------------------------------------------------------

const web = markdown({ base: markdownLanguage, extensions: [{ remove: ['SetextHeading'] }], addKeymap: false });
// The same parser with no nested HTML: lang-markdown's own data facet (commentTokens) on the bare Markdown parser.
const plain = new Language(markdownLanguage.data, markdownLanguage.parser.configure([{ remove: ['SetextHeading'] }]), [], 'markdown');

let atoms = Decoration.none;
let sink = null;
function mount(language) {
  const parent = document.body.appendChild(document.createElement('div'));
  const view = new EditorView({
    parent,
    state: EditorState.create({ doc: '' }),
    dispatchTransactions: (trs, v) => {
      if (sink) sink.push(...trs);
      else v.update(trs);
    },
  });
  // `deleteLine`'s one question of the layout, answered by column (see the head of this file).
  view.moveVertically = (range, forward) => {
    const { state } = view;
    const line = state.doc.lineAt(range.head);
    if (line.number === (forward ? state.doc.lines : 1)) return EditorSelection.cursor(range.head);
    const next = state.doc.line(line.number + (forward ? 1 : -1));
    const col = countColumn(line.text, state.tabSize, range.head - line.from);
    return EditorSelection.cursor(next.from + findColumn(next.text, col, state.tabSize));
  };
  return { view, language };
}
const views = [mount(web), mount(plain)];
if (views[0].view.lineWrapping) throw new Error('the view wraps');

// ---- Selections, written down --------------------------------------------------------------------------------------

const rangeOut = (r) => [r.anchor, r.head, r.assoc, r.bidiLevel ?? -1, r.undirectional ? 1 : 0];
function selectionOut(sel) {
  if (sel.ranges.length === 1 && sel.main.empty && sel.main.assoc === 0 && sel.main.bidiLevel == null && !sel.main.undirectional) return sel.main.head;
  return [sel.mainIndex, ...sel.ranges.flatMap(rangeOut)];
}
function selectionIn(spec) {
  if (typeof spec === 'number') return EditorSelection.single(spec);
  const ranges = [];
  for (let i = 1; i < spec.length; i += 5) {
    const [anchor, head, assoc, bidi, undirectional] = spec.slice(i, i + 5);
    const level = bidi < 0 ? undefined : bidi;
    if (undirectional) ranges.push(EditorSelection.undirectionalRange(Math.min(anchor, head), Math.max(anchor, head)));
    else if (anchor === head) ranges.push(EditorSelection.cursor(anchor, assoc, level));
    else ranges.push(EditorSelection.range(anchor, head, undefined, level, assoc || undefined));
  }
  return EditorSelection.create(ranges, spec[0]);
}

function diff(before, after) {
  if (before === after) return 0;
  let prefix = 0;
  const shortest = Math.min(before.length, after.length);
  while (prefix < shortest && before.charCodeAt(prefix) === after.charCodeAt(prefix)) prefix += 1;
  let suffix = 0;
  while (suffix < shortest - prefix && before.charCodeAt(before.length - 1 - suffix) === after.charCodeAt(after.length - 1 - suffix)) suffix += 1;
  return [prefix, suffix, after.slice(prefix, after.length - suffix)];
}

// ---- Running one case ---------------------------------------------------------------------------------------------

function run({ view, language }, name, doc, selection, options) {
  const extensions = [language, EditorState.allowMultipleSelections.of(true), EditorView.atomicRanges.of(() => atoms)];
  if (options) {
    if (options.ro) extensions.push(EditorState.readOnly.of(true));
    if (options.unit) extensions.push(indentUnit.of(options.unit));
    if (options.tab) extensions.push(EditorState.tabSize.of(options.tab));
  }
  atoms = options && options.atoms ? Decoration.set(options.atoms.map(([from, to]) => Decoration.mark({ class: 'a' }).range(from, to)), true) : Decoration.none;
  view.setState(EditorState.create({ doc, selection: selectionIn(selection), extensions }));
  if (!ensureSyntaxTree(view.state, doc.length, 5000) || syntaxTree(view.state).length !== doc.length) {
    forceParsing(view, doc.length, 5000);
    if (syntaxTree(view.state).length !== doc.length) throw new Error(`no whole tree for ${JSON.stringify(doc)}`);
  }
  if (view.state.doc.toString() !== doc) throw new Error(`a document the state changed: ${JSON.stringify(doc)}`);
  sink = [];
  let returned;
  try {
    returned = C[name](view);
  } finally {
    var sent = sink;
    sink = null;
  }
  if (sent.length > 1) throw new Error(`${name} dispatched ${sent.length} transactions`);
  if (sent.length === 0) return { out: [returned ? 1 : 0, 0], tr: null };
  const tr = sent[0];
  // moveLineUp/Down leave out the ranges of a block that cannot move and keep the old main index, which may then
  // point past the ranges that are left: a selection no view could hold. Not a case.
  if (!tr.newSelection.main) return { out: 'broken', tr: null };
  const announced = tr.effects.find((e) => e.is(EditorView.announce));
  if (tr.effects.some((e) => !e.is(EditorView.announce))) throw new Error(`${name} sent an effect this script does not write down`);
  return {
    out: [
      returned ? 1 : 0,
      [
        diff(doc, tr.newDoc.toString()),
        selectionOut(tr.newSelection),
        tr.annotation(Transaction.userEvent) ?? 0,
        tr.scrollIntoView ? 1 : 0,
        tr.selection ? 1 : 0,
        announced ? announced.value : 0,
      ],
    ],
    tr,
  };
}

// ---- Documents ----------------------------------------------------------------------------------------------------

// Small enough for a caret at every position.
const TINY = [
  '',
  'a',
  'ab cd',
  'one two  three',
  'a\nb',
  '\n',
  '\n\n',
  'ab\n\ncd',
  '  ab',
  '\tab',
  'ab  ',
  '  \n  x\n',
  'foo.bar(baz)',
  'a, b; c:d',
  'éa',
  '\u{1F600}a\u{1F469}‍\u{1F4BB}',
  '\u{1F1EB}\u{1F1F7}\u{1F1E9}\u{1F1EA}',
  'a❤️b',
  '# Hi\n\ntext',
  '- a\n  - b',
  '- [ ] do\n- [x] done',
  '> q\n> r',
  '```\ncode\n```',
  '[t](u) *e* **s**',
  '<!-- c -->',
  '<!-- c -->\nx',
  '(a[b]{c})',
  'x () [] {}',
  '    four\n      six',
  '\t\tx\n\ty',
  'snake_case camelCase',
  '~~s~~ `c` ==m==',
  'a  \n  b  \n',
];

const DOCS = [
  'The quick brown fox, jumps over: the lazy dog.',
  'Hello, world!\nSecond line here.\nThird.',
  '# Heading one\n\nA paragraph with *emphasis* and **strong** and `code`.\n\n## Heading two\n\nMore text.',
  '- one\n- two\n  - nested a\n  - nested b\n    - deeper\n- three',
  '1. first\n2. second\n   continued\n3. third',
  '- [ ] todo item\n- [x] done item\n  - [ ] sub task',
  '> a quote\n> on two lines\n\n> > nested quote\n\nafter',
  '```js\nconst a = [1, 2, 3];\nif (a) { b(); }\n```\n\ntext after',
  '~~~\ntilde fence\n~~~',
  'A [link](https://example.com "title") and ![image](a.png) and <https://auto.link>.',
  'Line with trailing spaces   \n\tTabbed line\t\n  indented  \n\nlast',
  '    indented code\n    more code\n\nparagraph',
  'word1 word2\tword3  word4...word5---word6',
  'café naïve été 你好世界 日本語',
  '\u{1F600}\u{1F601} smile \u{1F44D}\u{1F3FD} thumbs \u{1F468}‍\u{1F469}‍\u{1F467} family',
  'ź̶à combining q̃',
  '| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |',
  'Text\n\n---\n\nAfter the rule\n\n***\n',
  'fn(a, (b + c) * [d, e], {f: g})\nouter(inner(deep()))\nunbalanced ( [ }',
  '(\n  nested\n)\n[]{}()',
  '<!-- a comment -->\n\ntext <!-- inline --> more',
  '<!--\nmulti\nline\n-->\nafter',
  '  <!-- indented comment -->\n  plain',
  'before\n\n<div class="x">\n  <p>html-block</p>\n</div>\n\nafter',
  'inline <span>html</span> tag and <br/> here',
  'Setext looking\n===\n\nnot a heading\n---\n',
  '\n\n\nblank lines above\n\n\n',
  '   \n\t\n  \t  \nonly whitespace lines above',
  'a_b_c __d__ *e*f* **g** ***h***',
  '#tag @person [[wiki link]] ==mark== ^sup^ ~sub~ :emoji:',
  'hard break\\\nnext line  \nthird\\',
  'https://example.com/path?q=1&r=2#frag and www.example.org.',
  '* star list\n+ plus list\n- dash list\n\n10. ten\n11. eleven',
  '- item\n\n  paragraph in item\n\n  ```\n  code in item\n  ```\n- next',
  '> - quote list\n>   continued\n> - second\n>\n> para',
  'x\n\ty\n\t\tz\n\t  mixed\n  \tmixed2',
  'CamelCaseWord snake_case_word kebab-case-word dotted.name path/to/file',
  'a\n\nb\n\nc\n\nd',
  'one-line-with-no-spaces-at-all-just-dashes',
  '"quoted" \'single\' (paren) [bracket] {brace} <angle>',
];

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const random = rng(20261007);
const int = (n) => Math.floor(random() * n);
const pick = (list) => list[int(list.length)];

const PIECES = [
  'a', 'b', 'word', 'two', 'Mixed', 'x1', '_', ' ', ' ', ' ', '  ', '\t', '.', ',', ';', ':', '!', '-', '--', '(', ')', '[', ']', '{', '}', '()', '[]', '{}',
  '*', '**', '`', '#', '>', '~~', 'é', 'é', '\u{1F600}', '\u{1F44D}\u{1F3FD}', '你好', '❤️', '<!--', '-->', '<!-- c -->', '"', "'", '/', '\\', '=', '+',
];
const STARTS = ['', '', '', '', '  ', '    ', '\t', '- ', '  - ', '1. ', '> ', '# ', '## ', '- [ ] ', '```', '\t\t', '   ', '<!-- ', '> - '];
function randomLine() {
  if (int(7) === 0) return pick(['', '', '  ', '\t']);
  let line = pick(STARTS);
  for (let n = int(8); n > 0; n -= 1) line += pick(PIECES);
  return line;
}
function randomDoc() {
  return Array.from({ length: 1 + int(6) }, randomLine).join('\n');
}
const RANDOM = Array.from({ length: 90 }, randomDoc);

// Documents with atomic ranges over them: what the app hides behind a widget.
const ATOMIC = [
  ['one [[link]] two', [[4, 12]]],
  ['a ![pic](x.png) b\nnext', [[2, 15]]],
  ['ab\ncd', [[1, 4]]],
  ['{{chip}}{{chip}} end', [[0, 8], [8, 16]]],
  ['start ==mark== end', [[6, 8], [12, 14]]],
  ['x', [[0, 1]]],
  ['nested atoms here', [[2, 10], [4, 8]]],
];

// ---- Cases --------------------------------------------------------------------------------------------------------

const docs = [];
const docIds = new Map();
function docId(doc) {
  if (!docIds.has(doc)) {
    docIds.set(doc, docs.length);
    docs.push(doc);
  }
  return docIds.get(doc);
}

// A position that is not inside a surrogate pair is all a selection needs; one inside a cluster is a real case.
function position(doc) {
  let pos = int(doc.length + 1);
  if (pos > 0 && pos < doc.length && (doc.charCodeAt(pos) & 0xfc00) === 0xdc00 && (doc.charCodeAt(pos - 1) & 0xfc00) === 0xd800) pos -= 1;
  return pos;
}
function randomSelection(doc) {
  const kind = int(10);
  if (kind < 3) return position(doc);
  if (kind < 7) {
    const anchor = position(doc), head = position(doc);
    return anchor === head ? anchor : [0, anchor, head, 0, -1, 0];
  }
  const count = 2 + int(3);
  const ranges = [];
  for (let i = 0; i < count; i += 1) {
    const anchor = position(doc);
    const head = int(2) ? anchor : position(doc);
    ranges.push(anchor === head ? EditorSelection.cursor(anchor) : EditorSelection.range(anchor, head));
  }
  const made = EditorSelection.create(ranges, int(ranges.length));
  return selectionOut(made);
}

// Every command of the port, by family. The names are CodeMirror's and the Dart's.
const FAMILIES = {
  move: [
    'cursorCharLeft', 'cursorCharRight', 'cursorCharForward', 'cursorCharBackward', 'cursorCharForwardLogical', 'cursorCharBackwardLogical',
    'cursorGroupLeft', 'cursorGroupRight', 'cursorGroupForward', 'cursorGroupBackward', 'cursorGroupForwardWin',
    'cursorSyntaxLeft', 'cursorSyntaxRight',
    'cursorLineBoundaryForward', 'cursorLineBoundaryBackward', 'cursorLineBoundaryLeft', 'cursorLineBoundaryRight',
    'cursorLineStart', 'cursorLineEnd', 'cursorDocStart', 'cursorDocEnd', 'cursorMatchingBracket',
  ],
  select: [
    'selectCharLeft', 'selectCharRight', 'selectCharForward', 'selectCharBackward', 'selectCharForwardLogical', 'selectCharBackwardLogical',
    'selectGroupLeft', 'selectGroupRight', 'selectGroupForward', 'selectGroupBackward', 'selectGroupForwardWin',
    'selectSyntaxLeft', 'selectSyntaxRight',
    'selectLineBoundaryForward', 'selectLineBoundaryBackward', 'selectLineBoundaryLeft', 'selectLineBoundaryRight',
    'selectLineStart', 'selectLineEnd', 'selectDocStart', 'selectDocEnd', 'selectMatchingBracket',
    'selectAll', 'selectLine', 'selectParentSyntax', 'simplifySelection',
  ],
  delete: [
    'deleteCharBackward', 'deleteCharBackwardStrict', 'deleteCharForward', 'deleteGroupBackward', 'deleteGroupForward', 'deleteGroupForwardWin',
    'deleteToLineStart', 'deleteToLineEnd', 'deleteLineBoundaryBackward', 'deleteLineBoundaryForward',
    'deleteLine', 'deleteTrailingWhitespace', 'splitLine', 'transposeChars',
  ],
  edit: [
    'insertNewline', 'insertNewlineAndIndent', 'insertNewlineKeepIndent', 'insertBlankLine',
    'indentMore', 'indentLess', 'indentSelection', 'insertTab',
    'moveLineUp', 'moveLineDown', 'copyLineUp', 'copyLineDown',
    'toggleComment', 'toggleLineComment', 'toggleBlockComment', 'toggleBlockCommentByLine', 'lineComment', 'lineUncomment', 'blockComment', 'blockUncomment',
  ],
};
const ALL = Object.values(FAMILIES).flat();
for (const name of ALL) if (typeof C[name] !== 'function') throw new Error(`no command ${name}`);
// Atomic ranges only reach the commands that go through the view's motion or `skipAtomic`.
const ATOM_AWARE = ALL.filter((name) => /^(cursor|select)(Char(Left|Right|Forward|Backward)|Group)|^delete(?!Trailing)/.test(name));
const INDENT_AWARE = ['deleteCharBackward', 'insertNewlineAndIndent', 'insertBlankLine', 'indentMore', 'indentLess', 'indentSelection', 'insertTab', 'insertNewlineKeepIndent'];
const READS_ONLY = new Set([...FAMILIES.move, ...FAMILIES.select]);

const commands = {};
const skipped = {};
const broken = {};
const counts = {};
const seen = new Set();

function record(name, doc, selection, options) {
  const key = `${name}\u0000${doc}\u0000${JSON.stringify(selection)}\u0000${JSON.stringify(options)}`;
  if (seen.has(key)) return null;
  seen.add(key);
  const [a, b] = views.map((v) => run(v, name, doc, selection, options));
  if (a.out === 'broken' || b.out === 'broken') {
    broken[name] = (broken[name] ?? 0) + 1;
    return null;
  }
  if (JSON.stringify(a.out) !== JSON.stringify(b.out)) {
    skipped[name] = (skipped[name] ?? 0) + 1;
    return null;
  }
  (commands[name] ??= []).push([docId(doc), selection, options, ...b.out]);
  counts[name] = (counts[name] ?? 0) + 1;
  return b.tr;
}

for (const name of ALL) {
  const follow = [];
  const note = (tr) => {
    if (tr) follow.push(tr);
  };
  // A caret at every position of the tiny documents (every other one for a command that has nothing to say about
  // where the caret is).
  const everywhere = !/^(cursorDoc|selectDoc|selectAll|deleteTrailingWhitespace)/.test(name);
  for (const doc of TINY) {
    for (let pos = 0; pos <= doc.length; pos += everywhere ? 1 : 5) note(record(name, doc, pos, 0));
  }
  // Ranges, both ways round, and several at once.
  for (const doc of TINY) {
    for (let n = 0; n < 2; n += 1) note(record(name, doc, randomSelection(doc), 0));
  }
  for (const doc of DOCS) {
    for (let n = 0; n < 2; n += 1) note(record(name, doc, randomSelection(doc), 0));
  }
  for (const doc of RANDOM) note(record(name, doc, randomSelection(doc), 0));
  // What the command made, taken again: carets with a side, ranges with a direction, a document it changed.
  for (let n = 0; n < 40 && follow.length; n += 1) {
    const tr = follow.splice(int(follow.length), 1)[0];
    const doc = tr.newDoc.toString();
    if (doc.length > 2500) continue;
    record(int(3) ? name : pick(ALL), doc, selectionOut(tr.newSelection), 0);
  }
  // Read-only.
  for (let n = 0; n < (READS_ONLY.has(name) ? 3 : 10); n += 1) {
    const doc = pick(int(2) ? TINY : DOCS);
    record(name, doc, randomSelection(doc), { ro: 1 });
  }
  if (ATOM_AWARE.includes(name)) {
    for (const [doc, ranges] of ATOMIC) {
      for (let pos = 0; pos <= doc.length; pos += 1) record(name, doc, pos, { atoms: ranges });
      for (let n = 0; n < 3; n += 1) record(name, doc, randomSelection(doc), { atoms: ranges });
    }
  }
  if (INDENT_AWARE.includes(name)) {
    for (const options of [{ unit: '\t' }, { unit: '    ' }, { unit: '\t', tab: 2 }, { tab: 8 }, { unit: '   ', tab: 3 }]) {
      for (const doc of ['\t\tx\n\ty', '    four\n      six', '  ab', 'x\n\ty\n\t\tz\n\t  mixed\n  \tmixed2', '        eight\n     five\n\t \tz', '  \n\t\n      ']) {
        for (let pos = 0; pos <= doc.length; pos += 2) record(name, doc, pos, options);
        for (let n = 0; n < 3; n += 1) record(name, doc, randomSelection(doc), options);
      }
    }
  }
}

mkdirSync(OUT, { recursive: true });
const text = JSON.stringify({ source: '@codemirror/commands 6.11.0', docs, commands, skipped, broken });
writeFileSync(`${OUT}commands.json`, `${text}\n`);
let total = 0;
for (const [family, names] of Object.entries(FAMILIES)) {
  console.log(family);
  for (const name of names) {
    total += counts[name] ?? 0;
    console.log(`  ${name}: ${counts[name] ?? 0}${skipped[name] ? ` (${skipped[name]} left out: nested HTML)` : ''}${broken[name] ? ` (${broken[name]} left out: main index out of range)` : ''}`);
  }
}
console.log(`commands.json: ${total} cases, ${docs.length} documents, ${(text.length / 1024).toFixed(0)} kB`);
process.exit(0);
