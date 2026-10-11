// What the web editor colours in a block of code, for the Dart port's highlighter to be held against
// (lib/editor/code, test/editor/code/conformance_test.dart).
//
//   node tool/code_fixtures.mjs
//
// Everything is read from tauri/ and nothing is written there: its node_modules for @codemirror/language-data
// and the grammars and legacy modes behind it, @lezer/highlight, and its src for the editor's own language
// (src/app/editor/language.ts) and highlighter (glyphHighlight.ts, whose list tool/code_grammars.mjs copies and
// checks). Three fixtures go to test/editor/code/fixtures/:
//
//   names.json      what a fence's info string resolves to: every name and alias of the language pack, and a
//                   spread of things people write that are not names (`LanguageDescription.matchLanguageName`)
//   tokens.json     a sample of each language, parsed by the parser the pack loads for it, and the runs
//                   `highlightTree` gives with the app's classes: from, to, classes
//   documents.json  whole notes (fences in quotes and lists, HTML in a line and as a block, a fence with no
//                   language and one nobody knows), parsed by the app's own `glyphMarkdown()` with every language
//                   loaded, and the runs of the whole note
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { glyphHighlighter } from './code_grammars.mjs';

const GLYPH = new URL('../tauri/', import.meta.url).pathname;
const MODULES = `${GLYPH}node_modules/`;
const OUT = new URL('../test/editor/code/fixtures/', import.meta.url).pathname;
const SAMPLES = new URL('../test/editor/code/samples/', import.meta.url).pathname;

const { languages } = await import(`${MODULES}@codemirror/language-data/dist/index.js`);
const { LanguageDescription } = await import(`${MODULES}@codemirror/language/dist/index.js`);
const { highlightTree } = await import(`${MODULES}@lezer/highlight/dist/index.js`);
const { glyphMarkdown } = await import(`${GLYPH}src/app/editor/language.ts`);

const highlighter = glyphHighlighter();

function runs(tree) {
  const out = [];
  highlightTree(tree, highlighter, (from, to, classes) => out.push([from, to, classes]));
  return out;
}

// ---- names ------------------------------------------------------------------------------------------------------------

const asked = new Set();
for (const language of languages) for (const alias of language.alias) asked.add(alias);
for (const extra of [
  '', 'JS', 'Js', 'TypeScript', 'ts', 'tsx', 'jsx', 'mjs', 'node', 'json5', 'jsonc', 'c', 'h', 'cpp', 'c++', 'cxx', 'cc', 'hpp', 'cs', 'csharp', 'c#', 'objc', 'objective-c', 'py', 'python3', 'py3', 'rb', 'rs', 'golang',
  'kt', 'kts', 'sh', 'bash', 'zsh', 'shell', 'console', 'shellscript', 'fish', 'ps1', 'powershell', 'yml', 'toml', 'ini', 'conf', 'md', 'markdown', 'mdx', 'xml', 'svg', 'html', 'htm', 'xhtml', 'vue', 'svelte', 'css', 'scss',
  'sass', 'less', 'diff', 'patch', 'dart', 'lua', 'sql', 'mysql', 'postgres', 'postgresql', 'psql', 'sqlite', 'plsql', 'tex', 'latex', 'text', 'txt', 'plain', 'plaintext', 'mermaid', 'query', 'math', 'comments', 'board',
  'dockerfile', 'docker', 'makefile', 'make', 'graphql', 'proto', 'protobuf', 'r', 'd', 'q', 'f#', 'fsharp', 'hs', 'haskell', 'elixir', 'ex', 'erl', 'clj', 'scala', 'groovy', 'gradle', 'perl', 'pl', 'php', 'asm', 'wasm',
  'wat', 'nginx', 'http', 'csv', 'java', 'javascript', 'js{1,3}', 'js:app.js', 'python,linenos', 'c-sharp', 'x-c', 'a-c', 'cmake', 'swift', 'zig', 'nim', 'ocaml', 'ml', 'jl', 'julia', 'vb', 'vbnet', 'pas', 'pascal', 'go',
  'rust', 'ruby', 'kotlin', 'yaml', 'json', 'objective-c++', 'apl', 'ts-node', 'node.js', 'language-js', 'lang-py', 'sh-session', 'c++17', 'es6', 'htmlbars', 'jinja2', 'liquid', 'angular', 'properties', 'env', 'dotenv',
]) asked.add(extra);

const names = {};
for (const info of [...asked].sort()) {
  // lang-markdown's `getCodeParser`: what comes before the first space, then the pack's own match.
  const word = /\S*/.exec(info)[0];
  names[info] = word ? (LanguageDescription.matchLanguageName(languages, word, true)?.name ?? null) : null;
}

// ---- tokens -----------------------------------------------------------------------------------------------------------

/** The samples: a file each in test/editor/code/samples, named for the info string a fence would carry. */
const SAMPLE_FILES = [
  'javascript', 'typescript', 'jsx', 'tsx', 'json', 'html', 'css', 'python', 'rust', 'go', 'java', 'kotlin', 'swift', 'c', 'cpp', 'csharp', 'php', 'ruby', 'bash', 'sql', 'yaml', 'toml', 'markdown', 'xml', 'diff',
  'dart', 'lua', 'scss', 'less', 'ini', 'dockerfile', 'powershell', 'perl', 'r', 'haskell', 'scala', 'objc', 'clojure', 'latex', 'nginx', 'protobuf', 'erlang', 'groovy', 'pascal', 'julia', 'fsharp', 'ocaml', 'cmake', 'http',
  'vb', 'sass', 'wast', 'mysql', 'postgresql', 'broken-js', 'broken-python', 'broken-html',
  // A page's scripts and styles by what their tags say they are.
  'html-scripts',
  // The rest of the pack, each read by one of its older modes or by a grammar of its own.
  'apl', 'pgp', 'asn1', 'asterisk', 'brainfuck', 'cobol', 'clojurescript', 'gss', 'coffeescript', 'commonlisp', 'cypher', 'cython', 'crystal', 'd', 'dtd', 'dylan', 'ebnf', 'ecl', 'edn', 'eiffel', 'elm', 'esper', 'factor',
  'fcl', 'forth', 'fortran', 'gas', 'gherkin', 'haxe', 'hxml', 'idl', 'jsonld', 'livescript', 'mirc', 'mathematica', 'modelica', 'mumps', 'mbox', 'nsis', 'ntriples', 'objcpp', 'octave', 'oz', 'pig', 'puppet', 'q',
  'rpmchanges', 'rpmspec', 'sas', 'scheme', 'sieve', 'smalltalk', 'solr', 'sml', 'sparql', 'spreadsheet', 'squirrel', 'stylus', 'stex', 'systemverilog', 'tcl', 'textile', 'tiddlywiki', 'tiki', 'troff', 'ttcn', 'ttcncfg',
  'turtle', 'webidl', 'vbscript', 'velocity', 'verilog', 'vhdl', 'xquery', 'yacas', 'z80', 'mscgen', 'xu', 'msgenny', 'pug', 'jinja', 'liquid', 'vue',
];

const tokens = [];
for (const file of SAMPLE_FILES) {
  let code;
  try {
    code = readFileSync(`${SAMPLES}${file}.txt`, 'utf8');
  } catch {
    continue;
  }
  // A sample's first line is the info string its fence carries; the rest is the code. Eight of the pack's
  // languages have a space in every name they go by (`Tiki wiki`, `RPM Spec`), and an info string is read up to
  // its first space: no fence can ask for them. Their samples say the pack's own name after an `=`.
  const split = code.indexOf('\n');
  const info = code.slice(0, split), body = code.slice(split + 1).replace(/\n$/, '');
  const found = info.startsWith('=') ? languages.find((language) => language.name === info.slice(1)) : LanguageDescription.matchLanguageName(languages, /\S*/.exec(info)[0], true);
  if (!found) {
    console.log(`${file}: nothing in the pack for "${info}"`);
    continue;
  }
  const support = await found.load();
  // A mode may throw on what it is given (Pug's answers `true` for a token, which CodeMirror cannot name): the
  // sample then says so, and that the web colours nothing of it.
  try {
    const tree = support.language.parser.parse(body);
    tokens.push({ file, info, language: found.name, code: body, runs: runs(tree).flat() });
  } catch (error) {
    console.log(`${file}: the web's own parser throws: ${error.message}`);
    tokens.push({ file, info, language: found.name, code: body, runs: [], throws: String(error.message) });
  }
}

// ---- documents --------------------------------------------------------------------------------------------------------

await Promise.all(languages.map((language) => language.load().catch(() => null)));
const markdown = glyphMarkdown().language.parser;

const documents = [];
for (const file of ['note-fences', 'note-html', 'note-nested']) {
  let doc;
  try {
    doc = readFileSync(`${SAMPLES}${file}.md`, 'utf8');
  } catch {
    continue;
  }
  documents.push({ file, doc, runs: runs(markdown.parse(doc)).flat() });
}

mkdirSync(OUT, { recursive: true });
writeFileSync(`${OUT}names.json`, `${JSON.stringify(names, null, 0)}\n`);
writeFileSync(`${OUT}tokens.json`, `${JSON.stringify(tokens)}\n`);
writeFileSync(`${OUT}documents.json`, `${JSON.stringify(documents)}\n`);
console.log(`names: ${Object.keys(names).length}; tokens: ${tokens.length} samples, ${tokens.reduce((n, t) => n + t.runs.length / 3, 0)} runs; documents: ${documents.length}`);
