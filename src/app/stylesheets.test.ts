import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * The stylesheets read as text, for the mistakes nothing else can see: a custom property that nothing declares, one
 * read with no fallback outside the place that sets it, a `composes` of a class that is not there, a composing class
 * that sets what it composes at the same weight, and a dark palette whose System twin has drifted from it.
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

interface Rule {
  /** The at-rules it sits in, `@media (…) ` for each, outermost first; empty at the top level. */
  context: string;
  selector: string;
  body: string;
}

/** A sheet's rules, each with the conditional at-rules around it. An `@keyframes` or `@property` is one rule. */
function flatRules(css: string, context = ''): Rule[] {
  const out: Rule[] = [];
  let at = 0;
  while (at < css.length) {
    const open = css.indexOf('{', at);
    if (open < 0) break;
    // After the last `;`, so an `@import` before the first rule is not read as part of its selector.
    const selector = (css.slice(at, open).split(';').pop() ?? '').trim().split(/\s+/).join(' ');
    let depth = 1;
    let end = open + 1;
    while (depth > 0 && end < css.length) {
      if (css[end] === '{') depth++;
      else if (css[end] === '}') depth--;
      end++;
    }
    const body = css.slice(open + 1, end - 1);
    if (/^@(media|supports|container|layer)\b/.test(selector)) out.push(...flatRules(body, `${context}${selector} `));
    else out.push({ context, selector, body });
    at = end;
  }
  return out;
}

/** A rule's declarations, property to value, `composes` left out. */
function declarationsOf(body: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const line of body.split(';')) {
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    const property = line.slice(0, colon).trim();
    if (property && property !== 'composes') out.set(property, line.slice(colon + 1).trim().split(/\s+/).join(' '));
  }
  return out;
}

const selectorsOf = (rule: Rule) => rule.selector.split(',').map((one) => one.trim());

/**
 * Every custom property declared at the page's root, where any rule can read it: a `:root` or `html` rule, the kit's
 * tokens, or an `@property` with an initial value.
 */
const rooted = new Set<string>();
for (const [, name = ''] of tokens.matchAll(/(--[\w-]+)\s*:/g)) rooted.add(name);
for (const css of text.values()) {
  for (const rule of flatRules(css)) {
    const property = /^@property\s+(--[\w-]+)$/.exec(rule.selector);
    if (property && rule.body.includes('initial-value')) rooted.add(property[1]!);
    if (!selectorsOf(rule).some((one) => /^(:root|html)(?![\w-])/.test(one))) continue;
    for (const [, name = ''] of rule.body.matchAll(/(--[\w-]+)\s*:/g)) rooted.add(name);
  }
}

/*
 * The properties read with no fallback although no root rule declares them and the sheet that reads them does not set
 * them either, and what makes each safe. A name ending in `*` stands for every name it begins. Anything else read bare
 * must be declared at the root or in the reading sheet: read outside the one element that sets it, it is nothing, and
 * the declaration it sits in draws nothing at all.
 */
const BARE: Record<string, string> = {
  '--app-space': "ink.css `[data-hue]`, and CanvasView.module.css reads it only under `[data-hue]` or a style that sets it",
  '--swatch-fill': "set by each swatch's `.dot` (AccentSwatch, WorkspaceSwatch), which composes swatch.module.css's `.dot`",
  '--swatch-ink': "set by each swatch's `.dot` (AccentSwatch, WorkspaceSwatch), which composes swatch.module.css's `.dot`",
  '--theme-*': 'set on each theme card from its palette (ThemeCards.tsx)',
  '--from': 'set on each cog (WorkingGears.tsx)',
  '--to': 'set on each cog (WorkingGears.tsx)',
  '--turn': 'set on each cog (WorkingGears.tsx)',
  '--ghost-image': 'set on each ghost (Ghost.tsx)',
  '--wisp-mask-*': "set on the document's root by art/wispMask.ts",
};
const bareAllowed = (name: string) => Object.keys(BARE).some((key) => (key.endsWith('*') ? name.startsWith(key.slice(0, -1)) : name === key));

/*
 * A composing class that sets what the class it composes sets, at the same weight, loses wherever the composed rules
 * land after it, and they land after all but one composer. postcss-modules writes a copy of the composed file's rules
 * at the head of every file that composes it, and of identical rules only the last copy counts (the build's minifier
 * keeps only that one): the rules sit just before the last file in the bundle to compose them, or where the file is
 * itself imported if that is later. So a composer says a different value with a heavier selector, never by order.
 *
 * The one class that loses today, and what it loses, left as it draws: the canvas card's words ask for no height cap,
 * no margin and the card's ink over the home card's peek, and get the peek's cap, its margin and its grey, because the
 * peek's own sheet lands after the canvas's in the bundle. Giving the card what it asks for changes how it looks.
 */
const LOSES: Record<string, string> = {
  'app/canvas/CanvasView.module.css .words': 'color, margin-block-start, max-block-size',
};

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

  it('read with no fallback only a property the root declares, or one set where it is read', () => {
    const loose: string[] = [];
    for (const [sheet, css] of text) {
      const own = new Set([...css.matchAll(/(--[\w-]+)\s*:/g)].map(([, name = '']) => name));
      for (const [, name = ''] of css.matchAll(/var\(\s*(--[\w-]+)\s*\)/g)) {
        if (!rooted.has(name) && !own.has(name) && !bareAllowed(name)) loose.push(`${relative(src, sheet)} ${name}`);
      }
    }
    expect([...new Set(loose)]).toEqual([]);
    // Each name on the list is still read bare somewhere, or it comes off the list.
    const all = [...text.values()].flatMap((css) => [...css.matchAll(/var\(\s*(--[\w-]+)\s*\)/g)].map(([, name = '']) => name));
    expect(Object.keys(BARE).filter((key) => !all.some((name) => (key.endsWith('*') ? name.startsWith(key.slice(0, -1)) : name === key)))).toEqual([]);
  });

  it('let no composing class set what it composes at the same weight', () => {
    const clashes: string[] = [];
    const seen = new Set<string>();
    for (const [sheet, css] of text) {
      const rules = flatRules(css);
      for (const rule of rules) {
        for (const [, list = ''] of rule.body.matchAll(/composes:\s*([^;]+);/g)) {
          const from = /^(.+?)\s+from\s+(?:'([^']+)'|"([^"]+)")\s*$/.exec(list.trim());
          if (!from || !/^\.[\w-]+$/.test(rule.selector)) continue;
          const target = resolve(dirname(sheet), from[2] ?? from[3] ?? '');
          const theirs = flatRules(text.get(target) ?? '');
          const found = new Set<string>();
          const where = new Set<string>();
          for (const name of from[1]!.trim().split(/\s+/)) {
            for (const mine of rules) {
              for (const one of selectorsOf(mine)) {
                // The composing class, then the same pseudo-classes, attributes or descendants as the composed rule.
                if (!one.startsWith(rule.selector) || /^[\w-]/.test(one.slice(rule.selector.length))) continue;
                const twin = `.${name}${one.slice(rule.selector.length)}`;
                for (const other of theirs) {
                  if (other.context !== mine.context || !selectorsOf(other).includes(twin)) continue;
                  const set = declarationsOf(other.body);
                  for (const [property, value] of declarationsOf(mine.body)) {
                    if (!set.has(property) || set.get(property) === value) continue;
                    found.add(property);
                    where.add(`${mine.context}${one}`);
                  }
                }
              }
            }
          }
          if (!found.size) continue;
          const key = `${relative(src, sheet)} ${rule.selector}`;
          const got = [...found].sort().join(', ');
          seen.add(key);
          if (LOSES[key] !== got) clashes.push(`${key} sets ${got} over ${relative(src, target)} at the same weight (${[...where].join('; ')})`);
        }
      }
    }
    expect(clashes).toEqual([]);
    // A class that no longer loses comes off the list.
    expect(Object.keys(LOSES).filter((key) => !seen.has(key))).toEqual([]);
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
