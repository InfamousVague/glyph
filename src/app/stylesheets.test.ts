import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * The stylesheets read as text, for the two mistakes nothing else can see: a custom property that nothing declares,
 * and a `composes` of a class that is not there.
 *
 * The tests run with CSS off (vitest.config.ts `css: false`), so neither shows in any of them, and neither shows on
 * the page as an error. A `var()` of a kit step the scale does not have (it has no 7, 9, 11 or 14) is no size at all:
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
});
