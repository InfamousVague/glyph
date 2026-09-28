import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { CAPS, LINES, tierOf } from './tiers.ts';

/**
 * The home page's tiers (home/tiers.ts, docs/DESIGN.md §137): which side of each line a column is on, how many each
 * tier holds, and the two stylesheets held to the same lines. The page's layout is their container queries and its
 * counts are this module, and the two parting would be a desk that draws six Recent cards in a phone's layout.
 */

const bare = (css: string) => css.replace(/\/\*[\s\S]*?\*\//g, '');
const sheet = (name: string) => bare(readFileSync(join(import.meta.dirname, name), 'utf8'));
const sheets = { home: sheet('HomeScreen.module.css'), shelf: sheet('TapeShelf.module.css') };
/** The page itself, read as text for the names its sheet places: what each group says it is, in the order written. */
const page = readFileSync(join(import.meta.dirname, 'HomeScreen.tsx'), 'utf8');
const groups = [...page.matchAll(/data-group="(\w+)"/g)].map(([, name = '']) => name);

/** A sheet's top-level blocks: each at-rule's or rule's prelude, and its body, braces matched. */
function blocks(css: string): { prelude: string; body: string }[] {
  const out: { prelude: string; body: string }[] = [];
  let at = 0;
  while (at < css.length) {
    const open = css.indexOf('{', at);
    if (open < 0) break;
    let depth = 1;
    let end = open + 1;
    while (depth > 0 && end < css.length) {
      if (css[end] === '{') depth++;
      else if (css[end] === '}') depth--;
      end++;
    }
    out.push({ prelude: css.slice(at, open).trim().split(/\s+/).join(' '), body: css.slice(open + 1, end - 1) });
    at = end;
  }
  return out;
}

/** A block's rules, one level down: each selector (one line) and its body. */
const rulesOf = (body: string) => blocks(body).map(({ prelude, body: rule }) => ({ selector: prelude, body: rule }));

/** A rule's declarations, property to value. */
function declarationsOf(body: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const line of body.split(';')) {
    const colon = line.indexOf(':');
    if (colon > 0) out.set(line.slice(0, colon).trim(), line.slice(colon + 1).trim().split(/\s+/).join(' '));
  }
  return out;
}

/** The body of a sheet's `@container home-page` block with this exact query. */
const pageBlock = (css: string, query: string) => blocks(css).find(({ prelude }) => prelude === `@container home-page ${query}`)?.body ?? '';

/** The rem numbers in each of a sheet's `@container home-page (…)` preludes, both ends of a range. */
const pageQueries = (css: string) =>
  blocks(css)
    .filter(({ prelude }) => prelude.startsWith('@container home-page'))
    .map(({ prelude }) => ({ prelude, rems: [...prelude.matchAll(/(\d+(?:\.\d+)?)rem/g)].map(([, n = '']) => Number(n)) }));

describe('the home page’s tiers', () => {
  it('puts a column on the side of each line it is on, at the root’s rem', () => {
    expect([703.9, 704, 1055.9, 1056].map((px) => tierOf(px, 16))).toEqual(['stack', 'wide', 'wide', 'desk']);
    // Settings' interface size moves the root's rem, and the lines with it, as it moves the container queries'.
    expect([879, 880, 1319, 1320].map((px) => tierOf(px, 20))).toEqual(['stack', 'wide', 'wide', 'desk']);
    // A phone's column is the stack, and so is one jsdom never laid out.
    expect([367, 331, 0].map((px) => tierOf(px, 16))).toEqual(['stack', 'stack', 'stack']);
  });

  it('holds the phone’s four notes and five to-dos until the desk, which holds six and eight', () => {
    expect(CAPS).toEqual({ stack: { recent: 4, tasks: 5 }, wide: { recent: 4, tasks: 5 }, desk: { recent: 6, tasks: 8 } });
  });

  it('asks the page’s container at the lines tiers.ts draws, and at every one of them', () => {
    const lines: number[] = Object.values(LINES);
    const asked = new Set<number>();
    for (const [name, css] of Object.entries(sheets)) {
      const queries = pageQueries(css);
      expect(queries.length, name).toBeGreaterThan(0);
      for (const { prelude, rems } of queries) {
        expect(rems.length, prelude).toBeGreaterThan(0);
        for (const rem of rems) {
          expect(lines, `${name}: ${prelude}`).toContain(rem);
          asked.add(rem);
        }
      }
    }
    expect([...asked].sort((a, b) => a - b)).toEqual([...lines].sort((a, b) => a - b));
  });

  it('asks exactly these questions of the page: from each line, and between two of them, never at one', () => {
    const { wide, tapesGrid, desk } = LINES;
    const preludes = (css: string) => pageQueries(css).map(({ prelude }) => prelude.replace('@container home-page ', ''));
    expect(preludes(sheets.home)).toEqual([`(min-width: ${wide}rem)`, `(${wide}rem <= width < ${desk}rem)`, `(min-width: ${desk}rem)`]);
    expect(preludes(sheets.shelf)).toEqual([`(min-width: ${tapesGrid}rem)`, `(${tapesGrid}rem <= width < ${desk}rem)`, `(min-width: ${desk}rem)`]);
    // The shelf is a grid only from its own line: under it, the phone's sideways row.
    const grids = blocks(sheets.shelf).filter(({ body }) => rulesOf(body).some(({ selector, body: rule }) => selector === '.row' && declarationsOf(rule).get('display') === 'grid'));
    expect(grids.map(({ prelude }) => prelude)).toEqual([`@container home-page (min-width: ${tapesGrid}rem)`]);
  });

  it('gives the phone nothing new: the page’s wrappers and its placing names only inside a question of the page', () => {
    // A rule for the grid, the head or the notices, or one naming a group's place, at the sheet's top level would
    // reach a phone, which is meant to draw exactly what it drew before the page was laid out wide.
    for (const { prelude } of blocks(sheets.home).filter(({ prelude }) => !prelude.startsWith('@container home-page'))) {
      expect(prelude, prelude).not.toMatch(/\.(grid|head|notices)\b|\[data-(group|paired)\b/);
    }
    // The column is the container every question asks, and it is wider than the desk's line, or there could be no desk.
    const column = declarationsOf(blocks(sheets.home).find(({ prelude }) => prelude === '.page')!.body);
    expect(column.get('container')).toBe('home-page / inline-size');
    expect(Number(/^(\d+)rem$/.exec(column.get('max-inline-size') ?? '')?.[1])).toBeGreaterThan(LINES.desk);
    // The heading rows keep clear of the dock while the pane is narrow enough for it to cross the column, which is
    // until the pane is wider than the column's cap by twice the dock's reach: the line is past the cap.
    const dockLine = blocks(sheets.home).find(({ prelude }) => prelude.startsWith('@container home-pane'))!.prelude;
    expect(Number(/max-width: (\d+)rem/.exec(dockLine)?.[1])).toBeGreaterThan(Number(/^(\d+)rem$/.exec(column.get('max-inline-size') ?? '')?.[1]));
  });

  it('places the groups by the names the page writes, and the desk’s rows in the page’s order', () => {
    expect(groups).toEqual(['pinned', 'tasks', 'tapes', 'library', 'recent']);
    // Every group the sheet names is one the page writes; a name the page does not write places nothing.
    const named = new Set([...sheets.home.matchAll(/\[data-group='(\w+)'\]/g)].map(([, name = '']) => name));
    expect([...named].sort()).toEqual([...groups].sort());
    // The pair is the page's to say (HomeScreen.tsx `paired`), on the grid, and the sheet asks for it by that name.
    expect(page).toMatch(/className=\{styles\.grid\} data-paired=/);
    expect([...sheets.home.matchAll(/(\S*)\[data-paired\]/g)].map(([, on]) => on)).toEqual(['.grid', '.grid']);
    // The desk: the head, then each group in the main in the page's order beside To do's rail, a flexible row, the foot.
    const desk = rulesOf(pageBlock(sheets.home, `(min-width: ${LINES.desk}rem)`));
    const areas = (selector: string) => [...(declarationsOf(desk.find((rule) => rule.selector === selector)!.body).get('grid-template-areas') ?? '').matchAll(/'([^']*)'/g)].map(([, row]) => row);
    const main = groups.filter((group) => group !== 'tasks');
    expect(areas('.grid')).toEqual(['head head', ...main.map((group) => `${group} tasks`), '. tasks', 'foot foot']);
    // With no To do at all, one column in the same order.
    expect(areas(".grid:not(:has(> [data-group='tasks']))")).toEqual(['head', ...main, '.', 'foot']);
    // And every group is put in the area of its own name.
    for (const group of groups) {
      const rule = desk.find(({ selector }) => selector === `.grid > [data-group='${group}']`);
      expect(rule && declarationsOf(rule.body).get('grid-area'), group).toBe(group);
    }
  });

  it('places the tapes on the units only between the tapes’ line and the desk’s, so the desk’s grid never inherits a column', () => {
    const placed = blocks(sheets.shelf).filter(({ prelude, body }) => prelude.includes('.tape:nth-child') || body.includes('.tape:nth-child'));
    expect(placed.map(({ prelude }) => prelude)).toEqual([`@container home-page (${LINES.tapesGrid}rem <= width < ${LINES.desk}rem)`]);
  });

  it('declares the units and the shelf’s count in the home page’s sheet, where the tiers set them, and reads them with a fallback', () => {
    expect(sheets.home).toMatch(/--home-units\s*:/);
    expect(sheets.home).toMatch(/--shelf-across\s*:/);
    // Wherever nothing sets them a fallback stands in: one unit (a group in a unit, a rail), and three tapes across the main.
    const fallbacks = { '--home-units': '1', '--shelf-across': '3' };
    for (const [name, css] of Object.entries(sheets)) {
      const reads = [...css.matchAll(/var\(\s*(--home-units|--shelf-across)\s*(?:,\s*([^)]*))?\)/g)];
      expect(reads.length, name).toBeGreaterThan(0);
      for (const [read, property = '', fallback] of reads) expect(fallback?.trim(), `${name}: ${read}`).toBe(fallbacks[property as keyof typeof fallbacks]);
    }
  });
});
