// The web editor's own syntax trees, for the Dart port of its parser to be held against
// (lib/editor/syntax, test/editor/syntax/conformance_test.dart).
//
//   node tool/editor_trees.mjs
//
// Everything is read from tauri/ and nothing is written there: its node_modules for @lezer/markdown 1.7.2,
// @lezer/common and TypeScript, its src for the editor's own language (src/app/editor/language.ts, which Node loads
// as it is, types stripped). Four fixtures go to test/editor/syntax/fixtures/:
//
//   lezer_markdown.json   every case of @lezer/markdown's test/test-markdown.ts (the CommonMark spec, and its own)
//   lezer_extension.json  every case of its test/test-extension.ts (GFM, subscript, superscript, emoji)
//   glyph_corpus.json     the app's configured parser (glyphMarkdown with the twelve marks) over the app's own
//                         Markdown: docs/MARKDOWN.md, every string of settings/specification.ts, guide/marks.ts and
//                         academy/lessons.ts, and the guidebook
//   glyph_fuzz.json       the same parser over lines of that corpus dealt out at random (seeded), with quote marks,
//                         list marks, indents and fences thrown in: the block structure a tidy document never has
//
// Lezer's cases are run here by its own harness (spec.ts, compare-tree.ts) before they are written, so a case in
// the fixture is one Lezer itself passes; what is written is the tree Lezer parsed. A tree is its nodes in document
// order, four numbers each: the name (an index into `names`), from, to, and depth. `resolve` is what
// `tree.resolveInner(pos, side)` answers at a spread of positions, five numbers each: pos, side, name, from, to.
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';

const GLYPH = new URL('../tauri/', import.meta.url).pathname;
const OUT = new URL('../test/editor/syntax/fixtures/', import.meta.url).pathname;
const require = createRequire(`${GLYPH}package.json`);

const lezer = await import(`${GLYPH}node_modules/@lezer/markdown/dist/index.js`);
const common = await import(`${GLYPH}node_modules/@lezer/common/dist/index.js`);
const ts = require('typescript');
const { MarkdownParser, parser: commonmark, GFM, Table, TaskList, Strikethrough, Autolink, Subscript, Superscript, Emoji } = lezer;

// ---- Writing a tree down ------------------------------------------------------------------------------------------

function fixture() {
  const names = [];
  const ids = new Map();
  const id = (name) => {
    if (!ids.has(name)) {
      ids.set(name, names.length);
      names.push(name);
    }
    return ids.get(name);
  };
  return { names, id };
}

function flat(tree, id) {
  const out = [];
  let depth = 0;
  tree.iterate({
    enter: (node) => {
      out.push(id(node.name), node.from, node.to, depth);
      depth += 1;
    },
    leave: () => {
      depth -= 1;
    },
  });
  return out;
}

/** What resolveInner answers: at every position of a short text, at a stride through a long one. */
function resolved(tree, doc, id, step = doc.length <= 600 ? 1 : doc.length <= 6000 ? 7 : 41) {
  const out = [];
  for (let pos = 0; pos <= doc.length; pos += step) {
    for (const side of [-1, 0, 1]) {
      const node = tree.resolveInner(pos, side);
      out.push(pos, side, id(node.name), node.from, node.to);
    }
  }
  return out;
}

function write(file, value) {
  mkdirSync(OUT, { recursive: true });
  writeFileSync(`${OUT}${file}`, `${JSON.stringify(value)}\n`);
  console.log(`${file}: ${value.cases.length} cases, ${(JSON.stringify(value).length / 1024).toFixed(0)} kB`);
}

// ---- Lezer's own cases -------------------------------------------------------------------------------------------

// The configuration a parser was made with is remembered on it, as steps the Dart test can take again.
const EXTENSIONS = new Map([
  [GFM, 'GFM'],
  [Table, 'Table'],
  [TaskList, 'TaskList'],
  [Strikethrough, 'Strikethrough'],
  [Autolink, 'Autolink'],
  [Subscript, 'Subscript'],
  [Superscript, 'Superscript'],
  [Emoji, 'Emoji'],
]);
function describeSpec(spec) {
  if (EXTENSIONS.has(spec)) return [EXTENSIONS.get(spec)];
  if (Array.isArray(spec)) return spec.flatMap(describeSpec);
  const keys = Object.keys(spec);
  if (keys.length === 1 && keys[0] === 'remove') return [`remove:${spec.remove.join(',')}`];
  throw new Error(`A configuration this script cannot describe: ${keys}`);
}
const configure = MarkdownParser.prototype.configure;
MarkdownParser.prototype.configure = function (spec) {
  const made = configure.call(this, spec);
  // One call is one step: Lezer resolves a nested array into a single configuration.
  made.steps = [...(this.steps ?? []), describeSpec(spec)];
  return made;
};
let last = null;
const parse = MarkdownParser.prototype.parse;
MarkdownParser.prototype.parse = function (input, ...rest) {
  const tree = parse.call(this, input, ...rest);
  if (typeof input === 'string' && rest.length === 0) last = { parser: this, doc: input, tree };
  return tree;
};

function load(file, modules) {
  const source = readFileSync(`${GLYPH}node_modules/@lezer/markdown/test/${file}`, 'utf8');
  const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
  const exports = {};
  const cases = [];
  const it = (name, run) => {
    last = null;
    run(); // Throws where Lezer's own test would fail.
    if (!last) throw new Error(`${name} parsed nothing`);
    cases.push({ name, ...last });
  };
  const describe = (_name, run) => run();
  new Function('require', 'exports', 'describe', 'it', outputText)((name) => modules[name] ?? (() => { throw new Error(`No module ${name}`); })(), exports, describe, it);
  return { exports, cases };
}

const compareTree = load('compare-tree.ts', { '@lezer/common': common }).exports;
const spec = load('spec.ts', { '@lezer/common': common, '..': lezer }).exports;
const harness = { '../dist/index.js': lezer, './compare-tree.js': compareTree, './spec.js': spec };

for (const [file, out] of [
  ['test-markdown.ts', 'lezer_markdown.json'],
  ['test-extension.ts', 'lezer_extension.json'],
]) {
  const { names, id } = fixture();
  const cases = load(file, harness).cases.map(({ name, parser, doc, tree }) => ({
    name,
    steps: parser.steps ?? [],
    doc,
    tree: flat(tree, id),
    resolve: resolved(tree, doc, id),
  }));
  write(out, { source: `@lezer/markdown 1.7.2 test/${file}`, names, cases });
}
MarkdownParser.prototype.configure = configure;
MarkdownParser.prototype.parse = parse;

// ---- The app's own parser ----------------------------------------------------------------------------------------

// The twelve marks (src/app/plugins/marks/index.tsx), restated: that file is JSX, which Node will not load. The file
// is read as text below and held to this list, so a mark added there stops this script until it is added here.
const FORMATS = [
  { name: 'Spoiler', delimiter: '||' },
  { name: 'Highlight', delimiter: '==' },
  { name: 'Aside', delimiter: '%%' },
  { name: 'Unsure', delimiter: '??' },
  { name: 'Redact', delimiter: '@@' },
  { name: 'Shout', delimiter: '^^' },
  { name: 'Added', delimiter: '++' },
  { name: 'Heat', delimiter: '🔥🔥' },
  { name: 'Frost', delimiter: '❄️❄️' },
  { name: 'Wave', delimiter: '🌊🌊' },
  { name: 'Shimmer', delimiter: '✨✨' },
  { name: 'Haunt', delimiter: '👻👻' },
];
{
  const source = readFileSync(`${GLYPH}src/app/plugins/marks/index.tsx`, 'utf8');
  const written = [...source.matchAll(/name: '(\w+)',\s*delimiter: '([^']+)'/g)].map(([, name, delimiter]) => ({ name, delimiter }));
  if (JSON.stringify(written) !== JSON.stringify(FORMATS)) throw new Error(`plugins/marks/index.tsx no longer has the marks restated here: ${JSON.stringify(written)}`);
}

const { glyphMarkdown } = await import(`${GLYPH}src/app/editor/language.ts`);
// The editor's parser as the app makes it; no code languages, as a fence's own language is not ported.
const web = glyphMarkdown(FORMATS, []).language.parser;
// The same parser without its wrapper (`parseCode`: a fence's language and HTML, laid over the tree), which is what
// the Dart port is. Every tree below is parsed by both and they are held to each other, so what is written is the
// web's own tree.
const bare = new MarkdownParser(web.nodeSet, web.blockParsers, web.leafBlockParsers, web.blockNames, web.endLeafBlock, web.skipContextMarkup, web.inlineParsers, web.inlineNames, []);

/** Every string written in a TypeScript file; a template's `${…}` is written as a date, which is what the one in guide/marks.ts is. */
function stringsIn(file) {
  const source = ts.createSourceFile(file, readFileSync(`${GLYPH}${file}`, 'utf8'), ts.ScriptTarget.ES2022, true);
  const found = [];
  const visit = (node) => {
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) found.push(node.text);
    else if (ts.isTemplateExpression(node)) found.push(node.head.text + node.templateSpans.map((span) => `2026-10-09${span.literal.text}`).join(''));
    ts.forEachChild(node, visit);
  };
  visit(source);
  return found;
}

/** Every string an imported value holds. */
function stringsOf(value, found = []) {
  if (typeof value === 'string') found.push(value);
  else if (Array.isArray(value)) for (const item of value) stringsOf(item, found);
  else if (value && typeof value === 'object') for (const item of Object.values(value)) stringsOf(item, found);
  return found;
}

const corpus = [];
const seen = new Set();
function add(name, doc) {
  if (seen.has(doc)) return;
  seen.add(doc);
  corpus.push({ name, doc });
}
add('docs/MARKDOWN.md', readFileSync(`${GLYPH}docs/MARKDOWN.md`, 'utf8'));
add('guidebook/index.md', readFileSync(`${GLYPH}src/app/guidebook/index.md`, 'utf8'));
for (const chapter of readdirSync(`${GLYPH}src/app/guidebook/chapters`).sort()) {
  if (chapter.endsWith('.md')) add(`guidebook/chapters/${chapter}`, readFileSync(`${GLYPH}src/app/guidebook/chapters/${chapter}`, 'utf8'));
}
{
  const specification = await import(`${GLYPH}src/app/settings/specification.ts`);
  stringsOf([specification.SPEC, specification.BASE_SPECS]).forEach((text, i) => text.length > 2 && add(`settings/specification.ts #${i}`, text));
}
for (const file of ['src/app/settings/specification.ts', 'src/app/guide/marks.ts', 'src/app/academy/lessons.ts']) {
  stringsIn(file).forEach((text, i) => text.length > 2 && add(`${file.slice(8)} "${i}"`, text));
}

function caseOf(name, doc, id, step) {
  const tree = bare.parse(doc);
  const nodes = flat(tree, id);
  const webs = flat(web.parse(doc), id);
  if (JSON.stringify(nodes) !== JSON.stringify(webs)) throw new Error(`${name}: the app's parser and the same parser unwrapped disagree`);
  return { name, doc, tree: nodes, resolve: resolved(tree, doc, id, step) };
}

{
  const { names, id } = fixture();
  write('glyph_corpus.json', { source: 'glyphMarkdown(MARKS, []) over the app\'s own Markdown', formats: FORMATS, names, cases: corpus.map(({ name, doc }) => caseOf(name, doc, id)) });
}

// ---- The same parser over lines dealt at random ------------------------------------------------------------------

/** mulberry32: the same numbers every run. */
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

{
  const next = random(20261007);
  const pick = (list) => list[Math.floor(next() * list.length)];
  const lines = corpus.flatMap(({ doc }) => doc.split('\n')).filter((line) => line.length < 160);
  const prefixes = ['', '', '', '', '> ', '> ', '>', '- ', '- ', '* ', '+ ', '1. ', '2) ', '   ', '    ', '\t', '  - ', '    - ', '> - ', '- > ', '> > ', '- [ ] ', '- [x] ', '# ', '## ', '   > '];
  const loose = ['', '', '', '```', '```js', '~~~', '---', '***', '===', '-', '>', '<div>', '</div>', '<!-- note', '-->', '| a | b |', '| - | :-: |', '|---|---|', '[ref]: /url "title"', '[ref]:', '    code', '  ', '\\', 'a  ', '<?php', '?>'];
  const inline = ['**', '*', '_', '__', '`', '``', '~~', '~', '^', '||', '==', '%%', '??', '@@', '^^', '++', '🔥🔥', '❄️❄️', '🌊🌊', '✨✨', '👻👻', '🔥', '[', ']', '](', ')', '![', '<', '>', '\\', '&amp;', ':smile:', ' https://ghostmarkdown.com/a_b ', ' www.example.com. ', ' sam@example.com ', '|', '  \n', '\t'];
  const { names, id } = fixture();
  const cases = [];
  for (let n = 0; n < 600; n += 1) {
    const out = [];
    const count = 2 + Math.floor(next() * 14);
    for (let i = 0; i < count; i += 1) {
      if (next() < 0.22) {
        out.push(pick(prefixes) + pick(loose));
        continue;
      }
      let line = pick(lines);
      // A mark or two dropped into the words, so delimiters meet each other where no one would write them.
      for (let k = next() < 0.5 ? 0 : 1 + Math.floor(next() * 3); k > 0; k -= 1) {
        const at = Math.floor(next() * (line.length + 1));
        line = line.slice(0, at) + pick(inline) + line.slice(at);
      }
      out.push(pick(prefixes) + line);
    }
    const doc = out.join('\n');
    if (seen.has(doc)) continue;
    seen.add(doc);
    cases.push(caseOf(`dealt ${n}`, doc, id, 5));
  }
  write('glyph_fuzz.json', { source: 'glyphMarkdown(MARKS, []) over corpus lines dealt at random, seed 20261007', formats: FORMATS, names, cases });
}
