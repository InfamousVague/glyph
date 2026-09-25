import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * The stylesheets read as text, for the mistakes nothing else can see: a custom property that nothing declares, a
 * `composes` of a class that is not there, and a dark palette whose System twin has drifted from it.
 *
 * The tests run with CSS off (vitest.config.ts `css: false`), so none of these shows in any of them, and none shows
 * on the page as an error. A `var()` of a kit step the scale does not have (it has no 7, 9, 11 or 14) is no size at all:
 * the Claude drawer's close button, All notes' search pill and its clear and order words asked for one, and have
 * drawn at their content's size since. A fallback hides the same mistake behind a number that looks meant. And a
 * `composes` of a class the other file does not define drops that class from the element without a word.
 */

const app = import.meta.dirname;
const src = dirname(app);
const repo = dirname(src);

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

const files = walk(src);
const sheets = files.filter((file) => file.endsWith('.css'));
const code = files
  .filter((file) => /\.tsx?$/.test(file) && !file.includes('.test.'))
  .map((file) => readFileSync(file, 'utf8'))
  .join('\n');
const bare = (css: string) => css.replace(/\/\*[\s\S]*?\*\//g, '');
const text = new Map(sheets.map((sheet) => [sheet, bare(readFileSync(sheet, 'utf8'))]));
const tokens = readFileSync(join(repo, 'vendor/@glacier/tokens/css/tokens.css'), 'utf8');

/** Every custom property something declares: a stylesheet, the kit's tokens, or the code, by name in a string. */
const declared = new Set<string>();
for (const css of [...text.values(), tokens]) {
  for (const [, name = ''] of css.matchAll(/(--[\w-]+)\s*:/g)) declared.add(name);
  for (const [, name = ''] of css.matchAll(/@property\s+(--[\w-]+)/g)) declared.add(name);
}
for (const [, name = ''] of code.matchAll(/['"`](--[\w-]+)['"`]/g)) declared.add(name);

/** The classes a stylesheet defines, outside `:global()`. */
function classesOf(css: string): Set<string> {
  const out = new Set<string>();
  for (const [, selector = ''] of css.matchAll(/([^{};]+)\{/g)) {
    if (selector.trim().startsWith('@')) continue;
    for (const [, name = ''] of selector.replace(/:global\([^)]*\)/g, ' ').matchAll(/\.(-?[A-Za-z_][\w-]*)/g)) out.add(name);
  }
  return out;
}

/** A sheet's rules as selector and body, top level and inside `@media (prefers-color-scheme: dark)` apart. */
function rulesOf(css: string): { top: Map<string, string>; dark: Map<string, string> } {
  const top = new Map<string, string>();
  const dark = new Map<string, string>();
  let at = 0;
  const flat = (text: string) => text.split(';').map((line) => line.trim()).filter(Boolean).join('; ');
  while (at < css.length) {
    const open = css.indexOf('{', at);
    if (open < 0) break;
    const selector = css.slice(at, open).trim().split(/\s+/).join(' ');
    let depth = 1;
    let end = open + 1;
    while (depth > 0 && end < css.length) {
      if (css[end] === '{') depth++;
      else if (css[end] === '}') depth--;
      end++;
    }
    const body = css.slice(open + 1, end - 1);
    if (selector === '@media (prefers-color-scheme: dark)') {
      for (const [inner, innerBody] of rulesOf(body).top) dark.set(inner, innerBody);
    } else if (!selector.startsWith('@')) top.set(selector, flat(body));
    at = end;
  }
  return { top, dark };
}

/*
 * The one twin that does not repeat its rule, and why. Written down so that it is a known difference rather than a
 * silent one: under System on a dark phone an inverse surface takes the paper's hue lift (a workspace's colour set for
 * white), and under an explicit Dark it keeps the page's own. Which is right is a question for the page, not for a
 * stylesheet tidy, so it stays as it draws until it is decided.
 */
const KNOWN: Record<string, string> = {
  "app/ink.css :root:not([data-theme='light']) .app-inverse": '--app-hue-lift and --app-hue-chroma',
};

const globals = new Set([...text].filter(([sheet]) => !sheet.endsWith('.module.css')).flatMap(([, css]) => [...classesOf(css)]));

describe('the stylesheets', () => {
  it('read no custom property that nothing declares', () => {
    const missing: string[] = [];
    for (const [sheet, css] of text) {
      for (const [, name = ''] of css.matchAll(/var\(\s*(--[\w-]+)/g)) {
        if (!declared.has(name)) missing.push(`${relative(src, sheet)} ${name}`);
      }
    }
    expect([...new Set(missing)]).toEqual([]);
  });

  it('compose only classes that are there', () => {
    const missing: string[] = [];
    for (const [sheet, css] of text) {
      for (const [, list = ''] of css.matchAll(/composes:\s*([^;]+);/g)) {
        const from = /^(.+?)\s+from\s+(?:'([^']+)'|"([^"]+)"|(global))\s*$/.exec(list.trim());
        const names = (from ? from[1]! : list).trim().split(/\s+/);
        const target = from ? (from[4] ? null : resolve(dirname(sheet), from[2] ?? from[3] ?? '')) : sheet;
        const have = target === null ? globals : classesOf(text.get(target) ?? '');
        for (const name of names) if (!have.has(name)) missing.push(`${relative(src, sheet)} composes ${name}${from ? ` from ${from[4] ?? relative(src, target!)}` : ''}`);
      }
    }
    expect(missing).toEqual([]);
  });

  it('write each dark palette the same twice, for Dark and for System on a dark phone', () => {
    const drifted: string[] = [];
    let twins = 0;
    for (const [sheet, css] of text) {
      const { top, dark } = rulesOf(css);
      for (const [selector, body] of dark) {
        const twin = [":root[data-theme='dark']", "[data-theme='dark']"].map((dark) => selector.replace(":root:not([data-theme='light'])", dark)).find((one) => top.has(one));
        if (!twin) continue;
        twins++;
        const name = `${relative(src, sheet)} ${selector}`;
        if (top.get(twin) !== body && !KNOWN[name]) drifted.push(name);
      }
    }
    expect(twins).toBeGreaterThan(6);
    expect(drifted).toEqual([]);
  });
});
