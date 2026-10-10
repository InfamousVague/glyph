// The web editor's own grammars for code, written out for the Dart port of the parser that runs them
// (lib/editor/code/lezer/lr.dart; lib/editor/code/grammars/*.g.dart).
//
//   node tool/code_grammars.mjs
//
// Everything is read from ../glyph's node_modules and nothing is written there. A fenced block in the web app is
// parsed by a Lezer grammar (@lezer/javascript, @lezer/python ...): tables an LR parser runs, made by
// lezer-generator and shipped as strings. The port runs the same tables, so they are copied as they are shipped:
// `states`, `stateData`, `goto` and `tokenData` in Lezer's own encoding, the node names, and the numbers beside
// them. Three things in a grammar's file are code and not tables, and are named here for the hand-written Dart
// beside each grammar to supply: its external tokenizers, its context tracker and any specializer that is a
// function.
//
// With the tables goes what the app's highlighter makes of each node: the grammar's `styleTags` give a node tags,
// and `glyphHighlight` (src/app/editor/glyphHighlight.ts) gives a tag a class. The two are folded here, by
// @lezer/highlight's own `tagHighlighter` over the list in glyphHighlight.ts, into a class for each rule of each
// node, so the port needs no tags: `rules` is, for a node's id, its rules in the order `getStyleTags` tries them,
// each with the parents it asks for (`context`), its mode (0 opaque, 1 inherit, 2 normal) and its class.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const GLYPH = '/Users/matt/Development/Apps/glyph/';
const MODULES = `${GLYPH}node_modules/`;
const OUT = new URL('../lib/editor/code/grammars/', import.meta.url).pathname;

const highlight = await import(`${MODULES}@lezer/highlight/dist/index.js`);
const common = await import(`${MODULES}@lezer/common/dist/index.js`);
const { tags, tagHighlighter, styleTags } = highlight;

// ---- glyphHighlight.ts, with the class names markdown.module.css gives ----------------------------------------------

/** The list in src/app/editor/glyphHighlight.ts, in its order: a tag, and the class the stylesheet has for it. */
export function glyphHighlighter(t = tags, make = tagHighlighter) {
  return make([
    { tag: t.heading1, class: 'h1' },
    { tag: t.heading2, class: 'h2' },
    { tag: t.heading3, class: 'h3' },
    { tag: t.heading4, class: 'h4' },
    { tag: t.heading5, class: 'h5' },
    { tag: t.heading6, class: 'h6' },
    { tag: t.strong, class: 'strong' },
    { tag: t.emphasis, class: 'em' },
    { tag: t.strikethrough, class: 'strike' },
    { tag: t.monospace, class: 'code' },
    { tag: t.link, class: 'link' },
    { tag: t.url, class: 'url' },
    { tag: t.quote, class: 'quote' },
    { tag: t.list, class: 'list' },
    { tag: t.contentSeparator, class: 'hr' },
    { tag: t.labelName, class: 'codeInfo' },
    { tag: t.atom, class: 'taskMarker' },
    { tag: [t.keyword, t.modifier, t.controlKeyword, t.operatorKeyword, t.definitionKeyword, t.moduleKeyword, t.self], class: 'codeKeyword' },
    { tag: [t.macroName], class: 'codeMacro' },
    { tag: [t.meta, t.annotation, t.special(t.variableName)], class: 'codeMeta' },
    { tag: [t.string, t.special(t.string), t.regexp], class: 'codeString' },
    { tag: [t.comment, t.lineComment, t.blockComment, t.docComment], class: 'codeComment' },
    { tag: [t.typeName, t.className, t.tagName, t.namespace], class: 'codeType' },
    { tag: [t.propertyName, t.attributeName, t.attributeValue], class: 'codeProperty' },
    { tag: [t.function(t.variableName), t.function(t.propertyName), t.definition(t.variableName)], class: 'codeName' },
    { tag: [t.number, t.bool, t.null, t.literal], class: 'codeLiteral' },
    { tag: [t.operator, t.punctuation, t.bracket, t.separator], class: 'codePunctuation' },
    { tag: t.processingInstruction, class: 'mark' },
  ]);
}

/** Checks the list above against the file it copies: every tag name in glyphHighlight.ts, in order. */
function checkAgainstSource() {
  const source = readFileSync(`${GLYPH}src/app/editor/glyphHighlight.ts`, 'utf8');
  const body = source.slice(source.indexOf('HighlightStyle.define(['));
  const theirs = [...body.matchAll(/class: styles\.(\w+)/g)].map((m) => m[1]);
  const mine = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'strong', 'em', 'strike', 'code', 'link', 'url', 'quote', 'list', 'hr', 'codeInfo', 'taskMarker', 'codeKeyword', 'codeMacro', 'codeMeta', 'codeString', 'codeComment', 'codeType', 'codeProperty', 'codeName', 'codeLiteral', 'codePunctuation', 'mark'];
  if (JSON.stringify(theirs) !== JSON.stringify(mine)) throw new Error(`glyphHighlight.ts has moved: ${theirs.join(' ')}`);
  const tagsThere = [...body.matchAll(/tags\.(\w+)/g)].map((m) => m[1]).join(' ');
  const tagsHere =
    'heading1 heading2 heading3 heading4 heading5 heading6 strong emphasis strikethrough monospace link url quote list contentSeparator labelName atom keyword modifier controlKeyword operatorKeyword definitionKeyword moduleKeyword self macroName meta annotation special variableName string special string regexp comment lineComment blockComment docComment typeName className tagName namespace propertyName attributeName attributeValue function variableName function propertyName definition variableName number bool null literal operator punctuation bracket separator processingInstruction';
  if (tagsThere !== tagsHere) throw new Error(`glyphHighlight.ts's tags have moved:\n${tagsThere}`);
}

// ---- A node's rules ---------------------------------------------------------------------------------------------------

/** @lezer/highlight keeps a node's rules under a prop it does not export: found by asking `styleTags` for it. */
const ruleProp = styleTags({ Probe: tags.keyword })({ name: 'Probe', prop: () => undefined })[0];

/** For each node of `parser` that has any: its rules, each `[class, mode, context...]`. */
export function rulesOf(parser, highlighter = glyphHighlighter()) {
  const out = {};
  for (const type of parser.nodeSet.types) {
    const rules = [];
    for (let rule = type.prop(ruleProp); rule; rule = rule.next) rules.push([highlighter.style(rule.tags) ?? '', rule.mode, ...(rule.context ?? [])]);
    if (rules.length) out[type.id] = rules;
  }
  return out;
}

// ---- A grammar's file, read as text -------------------------------------------------------------------------------------

/** The parts of a list written in JavaScript, split at its top-level commas. */
function splitTop(text) {
  const parts = [];
  let depth = 0, quote = '', start = 0;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (quote) {
      if (ch === '\\') i += 1;
      else if (ch === quote) quote = '';
    } else if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '(' || ch === '[' || ch === '{') depth += 1;
    else if (ch === ')' || ch === ']' || ch === '}') depth -= 1;
    else if (ch === ',' && depth === 0) {
      parts.push(text.slice(start, i).trim());
      start = i + 1;
    }
  }
  const last = text.slice(start).trim();
  if (last) parts.push(last);
  return parts;
}

/**
 * Every `LRParser.deserialize({...})` in a grammar's file, with the names its code goes by. The file is run with
 * stand-ins for @lezer/lr, so the spec arrives as the object the real parser would be made from.
 */
function specsOf(file) {
  const source = readFileSync(file, 'utf8');
  const captured = [];
  class ExternalTokenizer {
    constructor(token, options = {}) {
      this.token = token;
      this.options = options;
    }
  }
  class LocalTokenGroup {
    constructor(data, precTable, elseToken) {
      Object.assign(this, { data, precTable, elseToken });
    }
  }
  class ContextTracker {
    constructor(spec) {
      this.spec = spec;
    }
  }
  const LRParser = {
    deserialize(spec) {
      captured.push(spec);
      const fake = { configure: () => fake, nodeSet: { types: [] } };
      return fake;
    },
  };
  // Whatever else a language package's file imports (the editor's own modules) is not run for anything kept:
  // a stand-in that can be called, made and read from, and answers itself.
  const anything = new Proxy(function () {}, { get: (_, key) => (key === Symbol.toPrimitive ? () => '' : anything), apply: () => anything, construct: () => anything });
  const known = { '@lezer/lr': { ExternalTokenizer, LocalTokenGroup, ContextTracker, LRParser }, '@lezer/highlight': highlight, '@lezer/common': common };
  const deps = new Proxy(known, { get: (target, key) => target[key] ?? anything });
  const body = source.replace(/^import\s*\{([^}]*)\}\s*from\s*'([^']+)';?$/gm, (_, names, from) => `const {${names.replace(/ as /g, ': ')}} = __deps['${from}'];`).replace(/^export\s*\{[^}]*\};?\s*$/gm, '');
  new Function('__deps', body)(deps);

  // The text of each spec, for the names: which tokenizer is which, which specializer reads which table.
  const texts = source.split('LRParser.deserialize({').slice(1);
  if (texts.length !== captured.length) throw new Error(`${file}: ${texts.length} specs in the text, ${captured.length} run`);
  const tables = Object.fromEntries([...source.matchAll(/^const (spec_\w*) = (\{__proto__:null[^\n]*\});$/gm)].map((m) => [m[1], new Function(`return ${m[2]}`)()]));
  // The numbers the grammar's own code knows its tokens by (its `parser.terms.js`), for the Dart that ports that
  // code to read by the same names.
  const terms = {};
  for (const block of source.matchAll(/\/\/ This file was generated by lezer-generator\. You probably shouldn't edit it\.\nconst ([\s\S]*?);\n/g)) {
    const pairs = block[1].split(',').map((pair) => /^\s*([\w$]+) = (\d+)\s*$/.exec(pair));
    if (pairs.every(Boolean)) for (const [, name, value] of pairs) terms[name] = Number(value);
  }
  return captured.map((spec, index) => {
    const text = texts[index];
    const line = (name) => new RegExp(`^  ${name}: (.*?),?$`, 'm').exec(text)?.[1];
    const tokenizerNames = splitTop(line('tokenizers').replace(/^\[|\]$/g, ''));
    const tokenizers = spec.tokenizers.map((value, i) => {
      if (typeof value === 'number') return { group: value };
      if (value instanceof LocalTokenGroup) return { local: value.data, precTable: value.precTable, elseToken: value.elseToken ?? null };
      return { external: tokenizerNames[i] };
    });
    const specializedText = line('specialized');
    const specialized = (spec.specialized ?? []).map((entry, i) => {
      const part = splitTop(specializedText.replace(/^\[|\]$/g, ''))[i];
      const external = /external: (\w+)/.exec(part)?.[1];
      if (external) return { term: entry.term, external, extend: !!entry.extend };
      const table = /=> (spec_\w*)\[value\]/.exec(part)?.[1];
      if (!table || !tables[table]) throw new Error(`${file}: a specializer that is neither a table nor external: ${part}`);
      return { term: entry.term, table: { ...tables[table] } };
    });
    return {
      states: spec.states,
      stateData: spec.stateData,
      goto: spec.goto,
      nodeNames: spec.nodeNames,
      maxTerm: spec.maxTerm,
      context: line('context') ?? null,
      skippedNodes: spec.skippedNodes ?? [],
      repeatNodeCount: spec.repeatNodeCount,
      tokenData: spec.tokenData,
      tokenizers,
      topRules: spec.topRules,
      dialects: spec.dialects ?? {},
      dynamicPrecedences: spec.dynamicPrecedences ?? {},
      specialized,
      tokenPrec: spec.tokenPrec,
      terms,
    };
  });
}

// ---- Dart -------------------------------------------------------------------------------------------------------------

const dartString = (value) => `'${String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n')}'`;
const dartMap = (entries, key, value) => `{${entries.map(([k, v]) => `${key(k)}: ${value(v)}`).join(', ')}}`;

/** Words a constant in a Dart class cannot be called: the language's own, and the type the constants have. */
const DART_WORDS = new Set(
  'abstract as assert async await base break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null of on operator part patch required rethrow return sealed set show static super switch sync this throw true try type typedef var void when with while yield int double bool num String Object List Map Set'.split(
    ' ',
  ),
);

/** A term's name as a Dart constant: its own, an underscore after it where Dart keeps the word. */
const dartName = (term) => {
  const name = term.replace(/^_+/, '');
  return DART_WORDS.has(name) ? `${name}_` : name;
};

function dartSpec(name, spec, rules, from) {
  const tokenizers = spec.tokenizers
    .map((t) => ('group' in t ? `TokenizerSpec.group(${t.group})` : 'local' in t ? `TokenizerSpec.local(${dartString(t.local)}, ${t.precTable}, ${t.elseToken})` : `TokenizerSpec.external(${dartString(t.external)})`))
    .join(', ');
  const specialized = spec.specialized
    .map((s) => (s.external ? `SpecializerSpec.external(${s.term}, ${dartString(s.external)}, extend: ${s.extend})` : `SpecializerSpec.table(${s.term}, ${dartMap(Object.entries(s.table), dartString, String)})`))
    .join(',\n    ');
  const ruleLines = Object.entries(rules)
    .map(([id, list]) => `    ${id}: [${list.map(([cls, mode, ...context]) => `StyleRule(${dartString(cls)}, ${mode}${context.length ? `, [${context.map(dartString).join(', ')}]` : ''})`).join(', ')}],`)
    .join('\n');
  const className = `${name[0].toUpperCase()}${name.slice(1)}Terms`;
  const terms = Object.entries(spec.terms).map(([term, value]) => `  static const int ${dartName(term)} = ${value};`).join('\n');
  return `/// The grammar's tokens, by the names its tokenizers know them by (${from} \`parser.terms.js\`).
abstract final class ${className} {
${terms}
}

/// ${from}
final LRParserSpec ${name}Spec = LRParserSpec(
  states: ${dartString(spec.states)},
  stateData: ${dartString(spec.stateData)},
  goto: ${dartString(spec.goto)},
  nodeNames: ${dartString(spec.nodeNames)},
  maxTerm: ${spec.maxTerm},
  context: ${spec.context ? dartString(spec.context) : 'null'},
  skippedNodes: [${spec.skippedNodes.join(', ')}],
  repeatNodeCount: ${spec.repeatNodeCount},
  tokenData: ${dartString(spec.tokenData)},
  tokenizers: [${tokenizers}],
  topRules: ${dartMap(Object.entries(spec.topRules), dartString, (v) => `(${v[0]}, ${v[1]})`)},
  dialects: ${dartMap(Object.entries(spec.dialects), dartString, String)},
  dynamicPrecedences: ${dartMap(Object.entries(spec.dynamicPrecedences), String, String)},
  specialized: [
    ${specialized}
  ],
  tokenPrec: ${spec.tokenPrec},
  rules: {
${ruleLines}
  },
);
`;
}

/**
 * The grammars, each with where its parser is: the package, and which of the file's parsers when it has several.
 * `rulesFrom` loads the parser whose nodes carry the rules: the package's own, which is the one a language package
 * configures (a dialect, a top rule), or the language package's where it adds tags of its own.
 */
const GRAMMARS = [
  { name: 'javascript', pkg: '@lezer/javascript' },
  { name: 'json', pkg: '@lezer/json' },
  { name: 'css', pkg: '@lezer/css' },
  { name: 'html', pkg: '@lezer/html' },
  { name: 'python', pkg: '@lezer/python' },
  { name: 'rust', pkg: '@lezer/rust' },
  { name: 'go', pkg: '@lezer/go' },
  { name: 'java', pkg: '@lezer/java' },
  { name: 'cpp', pkg: '@lezer/cpp' },
  { name: 'php', pkg: '@lezer/php' },
  { name: 'xml', pkg: '@lezer/xml' },
  { name: 'yaml', pkg: '@lezer/yaml' },
  { name: 'sass', pkg: '@lezer/sass' },
  // The SQL grammar is in its language package, with the one tokenizer every dialect configures.
  { name: 'sql', pkg: '@codemirror/lang-sql', parser: (m) => m.StandardSQL.language.parser, more: sqlDialects },
];

/** The SQL dialects the pack loads, by its names for them: each one's switches and its words. */
function sqlDialects(m) {
  const names = { StandardSQL: 'SQL', PostgreSQL: 'PostgreSQL', MySQL: 'MySQL', MariaSQL: 'MariaDB SQL', MSSQL: 'MS SQL', SQLite: 'SQLite', Cassandra: 'CQL', PLSQL: 'PLSQL' };
  const kinds = { 20: 'keywords', 21: 'types', 24: 'builtin', 5: 'bools', 6: 'nulls' };
  const rows = Object.entries(names).map(([exported, name]) => {
    const d = m[exported].dialect;
    const words = { keywords: [], types: [], builtin: [], bools: [], nulls: [] };
    for (const [word, kind] of Object.entries(d.words)) words[kinds[kind]].push(word);
    const flags = ['backslashEscapes', 'hashComments', 'spaceAfterDashes', 'slashComments', 'doubleQuotedStrings', 'doubleDollarQuotedStrings', 'unquotedBitLiterals', 'treatBitsAsBytes', 'charSetCasts', 'plsqlQuotingMechanism']
      .filter((flag) => d[flag])
      .map((flag) => `${flag}: true`);
    return `  ${dartString(name)}: SqlDialectSpec(
    ${[...flags, `operatorChars: ${dartString(d.operatorChars)}`, `specialVar: ${dartString(d.specialVar)}`, `identifierQuotes: ${dartString(d.identifierQuotes)}`].join(', ')},
    keywords: ${dartString(words.keywords.join(' '))},
    types: ${dartString(words.types.join(' '))},
    builtin: ${dartString(words.builtin.join(' '))},
    bools: ${dartString(words.bools.join(' '))},
    nulls: ${dartString(words.nulls.join(' '))},
  ),`;
  });
  return `
/// A dialect as \`SQLDialect.define\` makes it: the switches its tokenizer reads, and its words by what they are.
class SqlDialectSpec {
  const SqlDialectSpec({
    this.backslashEscapes = false,
    this.hashComments = false,
    this.spaceAfterDashes = false,
    this.slashComments = false,
    this.doubleQuotedStrings = false,
    this.doubleDollarQuotedStrings = false,
    this.unquotedBitLiterals = false,
    this.treatBitsAsBytes = false,
    this.charSetCasts = false,
    this.plsqlQuotingMechanism = false,
    required this.operatorChars,
    required this.specialVar,
    required this.identifierQuotes,
    required this.keywords,
    required this.types,
    required this.builtin,
    required this.bools,
    required this.nulls,
  });

  final bool backslashEscapes, hashComments, spaceAfterDashes, slashComments, doubleQuotedStrings, doubleDollarQuotedStrings, unquotedBitLiterals, treatBitsAsBytes, charSetCasts, plsqlQuotingMechanism;
  final String operatorChars, specialVar, identifierQuotes;
  final String keywords, types, builtin, bools, nulls;
}

/// The dialects, by the language pack's name for each.
const Map<String, SqlDialectSpec> sqlDialects = <String, SqlDialectSpec>{
${rows.join('\n')}
};
`;
}

/** The language pack's names: each language's name and the other names a fence may call it by, in the pack's order. */
async function writeNames() {
  const { languages } = await import(`${MODULES}@codemirror/language-data/dist/index.js`);
  const version = JSON.parse(readFileSync(`${MODULES}@codemirror/language-data/package.json`, 'utf8')).version;
  const rows = languages.map((language) => `  (${dartString(language.name)}, [${language.alias.map(dartString).join(', ')}]),`).join('\n');
  const dart = `// Written by tool/code_grammars.mjs from @codemirror/language-data ${version}: do not edit by hand.
//
// Every language of the pack, in its order: its name, and the names a fence may call it by (\`LanguageDescription.alias\`:
// the aliases the pack lists and the name itself, in lower case). The order matters: the first that matches wins.
const List<(String name, List<String> alias)> languageNames = <(String, List<String>)>[
${rows}
];
`;
  writeFileSync(new URL('../lib/editor/code/language_names.g.dart', import.meta.url).pathname, dart);
  console.log(`names: ${languages.length} languages`);
}

/**
 * What the older line-by-line modes need of @lezer/highlight: they name a token by a word (`keyword`, `def`,
 * `string.special`), CodeMirror turns the word into tags (`createTokenType`), and the highlighter finds a tag's class
 * through the tags it was made from. So: each tag's parents, the modifiers in the order they were made, the
 * six legacy words CodeMirror renames, and the tags glyphHighlight.ts has a class for.
 */
async function writeTags() {
  const version = JSON.parse(readFileSync(`${MODULES}@lezer/highlight/package.json`, 'utf8')).version;
  const nameOf = new Map();
  const modifiers = [];
  for (const [name, value] of Object.entries(tags)) {
    if (typeof value === 'function') modifiers.push(name);
    else nameOf.set(value, name);
  }
  // A modifier's id is the order it was defined in, which is the order a tag's modifiers are kept in.
  const idOf = (name) => tags[name](tags.name).modified[0].id;
  modifiers.sort((a, b) => idOf(a) - idOf(b));
  const parents = [...nameOf].map(([tag, name]) => `  ${dartString(name)}: [${tag.set.slice(1).map((parent) => dartString(nameOf.get(parent))).join(', ')}],`);
  // The highlighter's own list, as tags: read back from a highlighter made over a recording `tagHighlighter`.
  const classed = [];
  glyphHighlighter(tags, (specs) => {
    for (const spec of specs) {
      for (const tag of Array.isArray(spec.tag) ? spec.tag : [spec.tag]) {
        const base = nameOf.get(tag.base ?? tag);
        const mods = tag.modified.map((mod) => modifiers.find((name) => tags[name](tags.name).modified[0] === mod));
        classed.push(`  ${dartString([base, ...mods].join('.'))}: ${dartString(spec.class)},`);
      }
    }
    return { style: () => null };
  });
  const language = readFileSync(`${MODULES}@codemirror/language/dist/index.js`, 'utf8');
  const legacy = /for \(let \[legacyName, name\] of (\[[\s\S]*?\])\)\s*defaultTable/.exec(language);
  if (!legacy) throw new Error("@codemirror/language's table of legacy token names has moved");
  const renamed = new Function(`return ${legacy[1]}`)().map(([from, to]) => `  ${dartString(from)}: ${dartString(to)},`);
  const dart = `// Written by tool/code_grammars.mjs from @lezer/highlight ${version}, @codemirror/language and
// src/app/editor/glyphHighlight.ts: do not edit by hand.

/// Each highlighting tag's parents, nearest first (\`Tag.set\` without the tag itself).
const Map<String, List<String>> tagParents = <String, List<String>>{
${parents.join('\n')}
};

/// The tag modifiers, in the order they were defined: the order a tag's modifiers are kept in.
const List<String> tagModifiers = <String>[${modifiers.map(dartString).join(', ')}];

/// The words CodeMirror renames before reading a mode's token as tags (@codemirror/language \`defaultTable\`).
const Map<String, String> legacyTokenNames = <String, String>{
${renamed.join('\n')}
};

/// The tags glyphHighlight.ts gives a class, a modified tag as \`base.modifier\`, and the class.
const Map<String, String> classedTags = <String, String>{
${classed.join('\n')}
};
`;
  writeFileSync(new URL('../lib/editor/code/stream/tags.g.dart', import.meta.url).pathname, dart);
  console.log(`tags: ${nameOf.size} tags, ${modifiers.length} modifiers, ${classed.length} with a class`);
}

async function main() {
  checkAgainstSource();
  mkdirSync(OUT, { recursive: true });
  mkdirSync(new URL('../lib/editor/code/stream/', import.meta.url).pathname, { recursive: true });
  if (!process.argv.slice(2).length) {
    await writeNames();
    await writeTags();
  }
  const only = process.argv.slice(2);
  for (const grammar of GRAMMARS) {
    if (only.length && !only.includes(grammar.name)) continue;
    const file = `${MODULES}${grammar.pkg}/dist/index.js`;
    const version = JSON.parse(readFileSync(`${MODULES}${grammar.pkg}/package.json`, 'utf8')).version;
    const specs = specsOf(file);
    const real = await import(file);
    const parsers = grammar.parser ? [[grammar.name, grammar.parser(real)]] : Object.entries(real).filter(([, value]) => value && value.nodeSet && value.states);
    if (specs.length !== 1 || parsers.length !== 1) throw new Error(`${grammar.pkg}: ${specs.length} specs, ${parsers.length} parsers`);
    const rules = rulesOf(parsers[0][1]);
    const more = grammar.more ? grammar.more(real) : '';
    const dart = `// Written by tool/code_grammars.mjs from ${grammar.pkg} ${version}: do not edit by hand.
//
// The grammar's tables as Lezer ships them (MIT, Marijn Haverbeke and others), and the class
// src/app/editor/glyphHighlight.ts gives each node's tags.
// ignore_for_file: lines_longer_than_80_chars, constant_identifier_names, non_constant_identifier_names
import '../lezer/lr.dart';

${dartSpec(grammar.name, specs[0], rules, `${grammar.pkg} ${version}.`)}${more}`;
    writeFileSync(`${OUT}${grammar.name}.g.dart`, dart);
    console.log(`${grammar.name}: ${dart.length} bytes, ${Object.keys(rules).length} nodes with rules`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) await main();
