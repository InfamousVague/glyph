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

/** The rem numbers in each of a sheet's `@container home-page (…)` preludes, both ends of a range. */
const pageQueries = (css: string) =>
  blocks(css)
    .filter(({ prelude }) => prelude.startsWith('@container home-page'))
    .map(({ prelude }) => ({ prelude, rems: [...prelude.matchAll(/(\d+(?:\.\d+)?)rem/g)].map(([, n = '']) => Number(n)) }));

describe('the home page’s tiers', () => {
  it('puts a column on the side of each line it is on, at the root’s rem', () => {
    expect([703.9, 704, 959.9, 960].map((px) => tierOf(px, 16))).toEqual(['stack', 'wide', 'wide', 'desk']);
    // Settings' interface size moves the root's rem, and the lines with it, as it moves the container queries'.
    expect([879, 880, 1199, 1200].map((px) => tierOf(px, 20))).toEqual(['stack', 'wide', 'wide', 'desk']);
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

  it('places the tapes on the units only between the tapes’ line and the desk’s, so the desk’s grid never inherits a column', () => {
    const placed = blocks(sheets.shelf).filter(({ prelude, body }) => prelude.includes('.tape:nth-child') || body.includes('.tape:nth-child'));
    expect(placed.map(({ prelude }) => prelude)).toEqual([`@container home-page (${LINES.tapesGrid}rem <= width < ${LINES.desk}rem)`]);
  });

  it('declares the units and the shelf’s count in the home page’s sheet, where the tiers set them, and reads them with a fallback', () => {
    expect(sheets.home).toMatch(/--home-units\s*:/);
    expect(sheets.home).toMatch(/--shelf-across\s*:/);
    // Under the first line nothing sets them, so wherever they are read a fallback stands in.
    let reads = 0;
    for (const css of Object.values(sheets)) {
      for (const [read, name = '', after = ''] of css.matchAll(/var\(\s*(--home-units|--shelf-across)\s*([,)])/g)) {
        reads++;
        expect(after, `${name}: ${read}`).toBe(',');
      }
    }
    expect(reads).toBe(2);
  });
});
