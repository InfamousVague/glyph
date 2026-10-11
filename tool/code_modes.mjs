// CodeMirror's older line-by-line modes, as the web editor's language pack loads them, written out for the port to
// run (lib/editor/code/stream/js.dart; lib/editor/code/stream/modes.g.dart).
//
//   node tool/code_modes.mjs
//
// Everything is read from the Tauri app's node_modules and nothing is written there. The pack reads ninety-odd of its
// languages with @codemirror/legacy-modes: each a `token(stream, state)` function in plain JavaScript, kept as it
// was written for CodeMirror 5. Seven of the commonest are ported to Dart by hand (stream/clike.dart,
// stream/modes.dart). The rest are run as they are: this parses each mode's file (acorn, which the web app's own
// build uses) and writes its syntax tree, and the port walks the tree. So what a mode does here is what its
// JavaScript does, quirk for quirk, and a mode costs nothing to add.
//
// A tree is written as JSON, less where each node was in the file, gzipped, in base64: 866 kB of JavaScript come
// to about 470 kB of Dart, read a mode at a time when a block first asks for it.
import { readFileSync, writeFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';

const GLYPH = new URL('../tauri/', import.meta.url).pathname;
const MODULES = `${GLYPH}node_modules/`;
const MODES = `${MODULES}@codemirror/legacy-modes/mode/`;
const OUT = new URL('../lib/editor/code/stream/modes.g.dart', import.meta.url).pathname;

const acorn = await import(`${MODULES}acorn/dist/acorn.mjs`);

/** The pack's languages that a legacy mode reads: its name, the mode's file, what the file exports for it, and
 * whether that is a function to call for the mode (`asn1({})`). */
function legacyLanguages() {
  const source = readFileSync(`${MODULES}@codemirror/language-data/dist/index.js`, 'utf8');
  const found = [];
  const entry = /name: "([^"]+)"[\s\S]*?load\(\) \{\s*return ([^;]+);/g;
  for (let m = entry.exec(source); m; m = entry.exec(source)) {
    const legacy = /import\('@codemirror\/legacy-modes\/mode\/([^']+)'\)\.then\(m => legacy\(m\.(\w+)(\(\{\}\))?\)\)/.exec(m[2]);
    if (legacy) found.push({ language: m[1], file: legacy[1], name: legacy[2], call: !!legacy[3] });
  }
  return found;
}

/** A node of acorn's tree, less what the port does not read. */
function strip(node) {
  if (Array.isArray(node)) return node.map(strip);
  if (node === null || typeof node !== 'object') return typeof node === 'bigint' ? String(node) : node;
  const out = {};
  for (const key in node) {
    if (key === 'start' || key === 'end' || key === 'raw' || key === 'sourceType') continue;
    // A pattern's own object is not JSON: its source and flags are, under `regex`.
    if (key === 'value' && node.regex) continue;
    out[key] = strip(node[key]);
  }
  return out;
}

const dartString = (value) => `'${String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;

const languages = legacyLanguages();
const files = new Map();
function need(file) {
  if (files.has(file)) return;
  const text = readFileSync(`${MODES}${file}.js`, 'utf8');
  const tree = acorn.parse(text, { ecmaVersion: 'latest', sourceType: 'module' });
  files.set(file, { tree, size: text.length });
  for (const node of tree.body) if (node.type === 'ImportDeclaration') need(node.source.value.replace(/^\.\//, '').replace(/\.js$/, ''));
}
for (const language of languages) need(language.file);

const version = JSON.parse(readFileSync(`${MODULES}@codemirror/legacy-modes/package.json`, 'utf8')).version;
let packed = 0, written = 0;
const rows = [...files].sort(([a], [b]) => (a < b ? -1 : 1)).map(([file, { tree, size }]) => {
  const data = gzipSync(JSON.stringify(strip(tree)), { level: 9 }).toString('base64');
  packed += size;
  written += data.length;
  return `  ${dartString(file)}: ${dartString(data)},`;
});

writeFileSync(
  OUT,
  `// Written by tool/code_modes.mjs from @codemirror/legacy-modes ${version} and @codemirror/language-data: do not edit
// by hand.
//
// The modes are CodeMirror's (MIT, Marijn Haverbeke and others), each file's syntax tree as acorn parses it,
// in JSON, gzipped, in base64.
// ignore_for_file: lines_longer_than_80_chars

/// The pack's languages a legacy mode reads: the language's name, the mode's file, what the file exports for it,
/// and whether that is a function to be called for the mode.
const List<(String language, String file, String name, bool call)> legacyModes = <(String, String, String, bool)>[
${languages.map((l) => `  (${dartString(l.language)}, ${dartString(l.file)}, ${dartString(l.name)}, ${l.call}),`).join('\n')}
];

/// Each mode file's syntax tree, by the file's name.
const Map<String, String> modeFiles = <String, String>{
${rows.join('\n')}
};
`,
);
console.log(`${languages.length} languages in ${files.size} files: ${packed} bytes of JavaScript, ${written} written`);

// ---- the JavaScript itself --------------------------------------------------------------------------------------------
//
// What the port's reader of JavaScript (lib/editor/code/stream/js) must make of the language the modes are written
// in: each of these is a function's body, run here by Node for its answer and written out with its syntax tree
// for the port to run and be held to (test/editor/code/js_test.dart, fixtures/js.json). They are the turns of
// JavaScript the modes lean on, the odd ones first.
const PROGRAMS = {
  'closures keep their own variables': `function counter() { var n = 0; return function () { return ++n; }; } var a = counter(), b = counter(); a(); a(); return [a(), b()];`,
  'functions and vars are hoisted': `var out = [typeof f, typeof v, f()]; var v = 1; function f() { return typeof g; function g() {} } return out;`,
  'a named function expression knows its name': `var fact = function f(n) { return n <= 1 ? 1 : n * f(n - 1); }; return fact(6);`,
  'arguments, apply, call, bind': `function sum() { var t = 0; for (var i = 0; i < arguments.length; i++) t += arguments[i]; return t; } function pass() { return sum.apply(null, arguments); } var add5 = sum.bind(null, 2, 3); return [pass(1, 2, 3), sum.call(null, 4, 5), add5(10), arguments.length];`,
  'this, new and prototypes': `function Context(indent, prev) { this.indent = indent; this.prev = prev; } Context.prototype.depth = function () { return this.prev ? 1 + this.prev.depth() : 0; }; var c = new Context(2, new Context(0, null)); var keys = []; for (var k in c) keys.push(k); return [c.depth(), c instanceof Context, c instanceof Object, keys, c.hasOwnProperty("depth"), typeof Context.prototype];`,
  'a class': `class State { constructor(n) { this.n = n; this.list = []; } copy() { var s = new State(this.n); s.list = this.list.slice(); return s; } } var a = new State(3); a.list.push(1); var b = a.copy(); b.list.push(2); var keys = []; for (let k in b) keys.push(k); return [a.list, b.list, keys, b instanceof State];`,
  'switch falls through and breaks': `function f(x) { var out = ""; switch (x) { case 1: out += "one"; case 2: out += "two"; break; case "3": out += "three"; break; default: out += "other"; case 4: out += "four"; } return out; } return [f(1), f(2), f("3"), f(3), f(4), f(9)];`,
  'labels': `var out = []; outer: for (var i = 0; i < 4; i++) { for (var j = 0; j < 4; j++) { if (j == 2) continue outer; if (i == 3) break outer; out.push(i * 10 + j); } } block: { out.push("in"); if (out.length) break block; out.push("never"); } scan: for (;;) { for (var k = 0; k < 3; k++) { if (k == 1) { continue scan; } out.push("k" + k); if (out.length > 12) break scan; } } return out;`,
  'for-in lists numbers first': `var o = { b: 1, 2: "two", a: 2, 1: "one", "01": "x" }; var keys = []; for (var k in o) keys.push(k); var arr = ["x", "y"]; arr.extra = 1; var akeys = []; for (var i in arr) akeys.push(i); return [keys, akeys, Object.keys(o)];`,
  'loose and strict equality': `var o = {}; return [null == undefined, null === undefined, 0 == "", 0 == "0", "" == "0", 1 == true, "1" == true, null == 0, undefined == 0, NaN == NaN, o == o, "[object Object]" == o, [1, 2] == "1,2", "a" != o, 2 === 2.0, "2" === 2];`,
  'truthiness': `var all = [0, -0, NaN, "", "0", " ", null, undefined, [], {}, false, true, 1e-9, function () {}]; var out = []; for (var i = 0; i < all.length; i++) out.push(all[i] ? 1 : 0); return [out, !!"false", null || "d", 0 && "x", "a" && "b", undefined || 0];`,
  'plus and the other operators': `return [1 + 2, "1" + 2, 1 + "2", 1 + null, 1 + undefined + "", "a" + null, "a" + undefined, [1, 2] + "", {} + "", true + 1, "3" * "4", "9" - 4, 7 % 3, -7 % 3, 7 / 2, 1 / 0 + "", 5 | 2, 5 & 6, 1 << 4, -9 >> 1, "b" > "a", "B" > "a", "10" > "9", 10 > "9", "abc" < "abd", null >= 0, undefined >= 0, typeof (1 + "")];`,
  'numbers as strings': `return [String(2), String(2.5), String(4 / 2), String(1e21), String(1 / 3), String(-0), (255).toString(16), (0.1 + 0.2 === 0.3) + "", 1e3 + "", parseInt("42px"), parseInt("ff", 16), parseInt("0x1f"), parseInt("x") + "", parseFloat("3.14abc"), parseFloat(".5"), parseFloat("1.50").toString() === "1.50", Number("12"), Number(" 12 "), Number("") , Number("1e3"), isNaN("x"), isNaN(" "), isNaN("1"), Math.max(1, 5, 3), Math.max(0, -2)];`,
  'typeof and instanceof': `function F() {} return [typeof undefined, typeof null, typeof 1, typeof "s", typeof true, typeof {}, typeof [], typeof F, typeof /x/, typeof notDeclared, [] instanceof Array, [] instanceof Object, /x/ instanceof RegExp, "s" instanceof Object, F instanceof Function, ({}) instanceof Array, new RegExp("a") instanceof RegExp];`,
  'strings': `var s = "Hello, World"; return [s.length, s.charAt(1), s.charAt(99), s[0], s[99] === undefined, s.charCodeAt(0), s.indexOf("o"), s.indexOf("o", 5), s.indexOf("zz"), s.lastIndexOf("o"), s.slice(1, 4), s.slice(-5), s.slice(-5, -1), s.slice(4, 2), s.substr(7), s.substr(-5, 3), s.substr(1, 0), s.substring(7, 2), s.substring(-1, 3), s.toLowerCase(), s.toUpperCase(), "  x ".trim(), s.split(", "), s.split(""), "".split(","), "a,b,,c".split(","), "abc".split("", 2), s.concat("!", 1), "abc" < "abd"];`,
  'arrays': `var a = [3, 1, 2]; var out = [a.push(9), a.pop(), a.shift(), a.unshift(7, 8), a.slice(), a.slice(1, -1), a.slice(-2), a.concat([5], 6, [[7]]), a.join("-"), a.join(), a.indexOf(1), a.indexOf(42), a.reverse().slice(), a.length]; a.length = 2; out.push(a.slice()); a[4] = "x"; out.push(a.length, a[3] === undefined, a.join()); out.push([1, 2, 3, 4, 5].splice(1, 2), (function () { var b = [1, 2, 3, 4]; b.splice(1, 2, "a", "b", "c"); return b; })()); var seen = []; [1, 2].forEach(function (x, i) { seen.push(x * 10 + i); }); out.push(seen, [].concat([1], [2, 3], 4), [1, [2, 3]].toString(), [null, undefined, 1].join("|")); return out;`,
  'sort, as V8 sorts': `var words = ["in", "and", "or", "not", "is not", "is a", "is", "isnt", "defined", "if unless"]; var a = words.slice().sort(function (a, b) { return b > a; }); var b = words.slice().sort(); var c = [10, 9, 1, 100, 25].sort(); var d = [10, 9, 1, 100, 25].sort(function (x, y) { return x - y; }); var e = [3, 1, 2].sort(function (x, y) { return y - x; }); var big = []; for (var i = 0; i < 50; i++) big.push((i * 37) % 50); big.sort(function (x, y) { return x - y; }); var f = ["b", undefined, "a"].sort(); return [a, b, c, d, e, big, f.length, f[0], f[2] === undefined];`,
  'regular expressions': `var re = /(\\d+)-(\\w)?/; var m = re.exec("ab 12-x 34-"); var g = /a(b)?/g; var all = []; var r; while ((r = g.exec("ab a ab"))) all.push([r[0], r.index, g.lastIndex, r[1] === undefined]); var t = /x/g; var tests = [t.test("xx"), t.lastIndex, t.test("xx"), t.lastIndex, t.test("xx"), t.lastIndex]; return [m[0], m[1], m[2], m.index, m.length, m.input, re.exec("zz"), all, tests, /^\\s*$/.test(""), /\\w/.test(undefined), re.source, /a/gi.flags, /a/i.ignoreCase, /a/.global, new RegExp("^(?:" + ["a", "b\\\\."].join("|") + ")$", "i").test("B."), new RegExp(/x+/i).source, String(new RegExp("a/b")), /(?:)/.source, new RegExp("").test("")];`,
  'match, replace, split, search': `var s = "a1b22c333"; return [s.match(/\\d+/), s.match(/\\d+/g), s.match(/z/), s.match(/z/g), s.match(/(\\d)(\\d)/).slice(), "x".match("x").index, s.replace(/\\d+/, "#"), s.replace(/\\d+/g, "#"), s.replace(/(\\w)(\\d+)/g, "$2$1"), s.replace(/\\d+/g, function (m, i) { return "<" + m.length + "@" + i + ">"; }), s.replace("b", "$&$&"), "a.b.c".replace(/\\./g, " "), "a.b".replace(".", "$$"), s.split(/\\d+/), s.split(/(\\d)\\d*/), "a  b".split(/\\s*/), s.search(/\\d\\d/), s.search(/z/), "aaa".lastIndexOf("a")];`,
  'objects': `var base = { a: 1, b: 2 }; var o = { ...base, b: 3, "c d": 4, 5: 6, f() { return this.a; } }; delete o.a; var has = ["b" in o, "a" in o, "toString" in o, o.hasOwnProperty("b"), o.hasOwnProperty("toString"), o.propertyIsEnumerable("c d"), o.propertyIsEnumerable("nope")]; var shorthand = 7, p = { shorthand }; o.x = o.y = 1; return [Object.keys(o), has, o.f() === undefined, p.shorthand, o["c d"], o[5], o.missing === undefined, String(o), typeof o.f];`,
  'try, throw and finally': `var out = []; function f(x) { try { if (x) throw new Error("bad " + x); out.push("ok"); return "returned"; } catch (e) { out.push(e.message); return "caught"; } finally { out.push("finally"); } } out.push(f(0), f(1)); try { null.x; } catch (e) { out.push(e instanceof Error || typeof e.message == "string"); } try { undefinedFunction(); } catch (e) { out.push("reference"); } return out;`,
  'update and compound assignment': `var i = 5, o = { n: 1, list: [1, 2] }, out = []; out.push(i++, i, ++i, i--, --i, i += 2, i -= 1, i *= 2, i |= 1); out.push(o.n++, ++o.n, o.n += 10, o.list[1]++, o.list[1], o["n"]--, o.n); var s = "a"; s += 1; s += null; out.push(s); var u; out.push(u++ + ""); return out;`,
  'the comma, the conditional and void': `var a = (1, 2, 3); var b = a > 2 ? "big" : a > 1 ? "mid" : "small"; for (var i = 0, j = 10; i < j; i++, j--) {} return [a, b, i, j, void 0 === undefined, typeof void 0];`,
  'default parameters and let in a block': `function f(a, b = a + 1, c = "c") { return [a, b, c]; } let x = 1; { let x = 2; var seen = x; } const k = 3; var out = []; for (let i = 0; i < 2; i++) { let y; out.push(y === undefined); y = i; } return [f(1), f(1, undefined, null), f(1, 5), x, seen, k, out];`,
  'a word list the way the modes make one': `function words(str) { var obj = {}, list = str.split(" "); for (var i = 0; i < list.length; ++i) obj[list[i]] = true; return obj; } var kw = words("if else while for constructor toString"); function wordRE(list) { return new RegExp("^((" + list.join(")|(") + "))\\\\b"); } var re = wordRE(["else", "elseif", "if"]); return [kw.propertyIsEnumerable("if"), kw.propertyIsEnumerable("toString"), kw.propertyIsEnumerable("valueOf"), kw.hasOwnProperty("constructor"), kw["while"], kw["nope"] === undefined, "elseif x".match(re)[0], re.exec("iffy"), Object.keys(kw).length];`,
  'the default copy of a state': `function copy(state) { if (typeof state != "object") return state; var out = {}; for (var prop in state) { var val = state[prop]; out[prop] = val instanceof Array ? val.slice() : val; } return out; } function S() { this.stack = [1]; this.ctx = { n: 1 }; } S.prototype.kind = "s"; var a = new S(), b = copy(a); b.stack.push(2); b.ctx.n = 2; return [a.stack, b.stack, a.ctx.n, Object.keys(b), copy(null), copy(true), copy("s"), b instanceof S];`,
};
const tests = Object.entries(PROGRAMS).map(([name, body]) => {
  const answer = new Function(`"use strict";${body}`)();
  // `undefined` in an array is `null` in JSON, as the port's test writes it too.
  return { name, answer: JSON.parse(JSON.stringify(answer === undefined ? null : answer)), tree: strip(acorn.parse(`export const answer = (function () {${body}})();`, { ecmaVersion: 'latest', sourceType: 'module' })) };
});
writeFileSync(new URL('../test/editor/code/fixtures/js.json', import.meta.url).pathname, `${JSON.stringify(tests)}\n`);
console.log(`${tests.length} programs for the port's JavaScript, with Node's answers`);
