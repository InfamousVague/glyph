import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createElement, type ComponentType } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import * as icons from '@glacier/icons';
import { describe, expect, it } from 'vitest';
import { bodiesOf, OPEN_BODIES, walkPath, WASH, washRule, type IconShape } from './iconWash.ts';

/**
 * Which shapes of an icon wear the wash (art/iconWash.ts), and the stylesheet made from it (iconWash.css): every
 * icon of the kit's that the app draws, by name, with its body's place among its shapes. The stylesheet is written
 * here - `npm run icons:wash` - and this fails when it is not what the icons in use would make, so an icon brought
 * into the app comes with its wash or the suite says so.
 */

const ROOT = resolve(__dirname, '../../..');
const SHEET = join(ROOT, 'src/app/iconWash.css');

/** The icons washed whole by app.css: one closed silhouette each, or dots too small to be a body. Left to it. */
const WHOLE = new Set(['bookmark', 'play', 'puzzle', 'square', 'pause', 'layout-grid', 'ellipsis-vertical']);

function sourceFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === 'node_modules' || entry.name === 'dist' ? [] : sourceFiles(path);
    return /\.tsx?$/.test(entry.name) ? [path] : [];
  });
}

/** Every icon the app, the reader page and the kit's own components bring in from the kit, by the name they import. */
function iconsInUse(): string[] {
  const names = new Set<string>();
  for (const file of [...sourceFiles(join(ROOT, 'src')), ...sourceFiles(join(ROOT, 'vendor/@glacier/react'))]) {
    const text = readFileSync(file, 'utf8');
    for (const match of text.matchAll(/import\s+(?:type\s+)?\{([^}]+)\}\s+from\s+['"](?:@glacier\/icons|lucide-react)['"]/g)) {
      for (const part of match[1]!.split(',')) {
        const name = part.trim().replace(/^type\s+/, '').split(/\s+as\s+/)[0]!.trim();
        if (/^[A-Z]/.test(name)) names.add(name);
      }
    }
  }
  return [...names].sort();
}

/** An icon as it is drawn: the name its svg wears, and its shapes in order. Null for a name that is not an icon. */
function drawn(name: string): { name: string; shapes: IconShape[] } | null {
  const Icon = (icons as unknown as Record<string, ComponentType | undefined>)[name];
  if (!Icon || typeof Icon === 'string') return null;
  let markup: string;
  try {
    markup = renderToStaticMarkup(createElement(Icon));
  } catch {
    return null;
  }
  const svg = new DOMParser().parseFromString(markup, 'image/svg+xml').documentElement;
  const worn = [...svg.classList].find((c) => c.startsWith('lucide-'));
  if (svg.tagName !== 'svg' || !worn) return null;
  const shapes = [...svg.children].map((el) => ({ tag: el.tagName, attrs: Object.fromEntries([...el.attributes].map((a) => [a.name, a.value])) }));
  return { name: worn.slice('lucide-'.length), shapes };
}

function sheet(): string {
  const rules = new Map<string, string>();
  for (const used of iconsInUse()) {
    const icon = drawn(used);
    if (!icon || WHOLE.has(icon.name) || rules.has(icon.name)) continue;
    const bodies = [...new Set([...bodiesOf(icon.shapes), ...(OPEN_BODIES[icon.name] ?? [])])].sort((a, b) => a - b);
    if (bodies.length) rules.set(icon.name, washRule(icon.name, bodies));
  }
  const names = [...rules.keys()].sort();
  return [
    '/*',
    ' * The wash on each icon\'s body (art/iconWash.ts says which shape that is, and why only that one). MADE, not',
    ' * written: `npm run icons:wash` writes it from the icons the app draws, and art/iconWash.test.ts fails when it is',
    ' * out of step with them. Each rule names an icon by the class the kit gives its svg, and its washed shapes by',
    ' * their place among its shapes.',
    ' */',
    `${names.map((name) => rules.get(name)).join(',\n')} {`,
    `  fill: ${WASH};`,
    '}',
    '',
  ].join('\n');
}

describe('an icon’s body', () => {
  const shape = (tag: string, attrs: IconShape['attrs']): IconShape => ({ tag, attrs });

  it('is its largest closed shape, and an open path is never one', () => {
    // The mic: a stand, the cup round the capsule (open), and the capsule.
    const mic = [shape('path', { d: 'M12 19v3' }), shape('path', { d: 'M19 10v2a7 7 0 0 1-14 0v-2' }), shape('rect', { x: 9, y: 2, width: 6, height: 13, rx: 3 })];
    expect(bodiesOf(mic)).toEqual([2]);
  });

  it('leaves what is inside the body a stroke: a cog’s hole, a tick in a circle', () => {
    const inCircle = [shape('circle', { cx: 12, cy: 12, r: 10 }), shape('path', { d: 'm9 12 2 2 4-4' }), shape('circle', { cx: 12, cy: 12, r: 3 })];
    expect(bodiesOf(inCircle)).toEqual([0]);
  });

  it('takes a second shape that is clear of the first and of some size, and never a dot', () => {
    const two = [shape('rect', { x: 2, y: 2, width: 8, height: 8 }), shape('rect', { x: 14, y: 14, width: 8, height: 8 }), shape('circle', { cx: 18, cy: 5, r: 1 })];
    expect(bodiesOf(two)).toEqual([0, 1]);
  });

  it('has none in an icon of lines alone', () => {
    expect(bodiesOf([shape('path', { d: 'M5 12h14' }), shape('path', { d: 'm12 5 7 7-7 7' })])).toEqual([]);
  });

  it('knows a path that comes back to its start, by a z or by arriving there', () => {
    expect(walkPath('M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z').closed).toBe(true);
    // The bell: no z, but its last curve ends where it began.
    expect(walkPath('M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326').closed).toBe(true);
    expect(walkPath('M19 10v2a7 7 0 0 1-14 0v-2').closed).toBe(false);
    // Two lines in one path are not one shape.
    expect(walkPath('M4 4h4v4H4zM14 14h4v4h-4z').closed).toBe(false);
    // An arc's flags set against the next number.
    expect(walkPath('M2 12a10 10 0 1020 0 10 10 0 10-20 0').closed).toBe(true);
  });
});

describe('the icons’ stylesheet', () => {
  it('is what the icons the app draws make of it', () => {
    const made = sheet();
    if (process.env.UPDATE_ICON_WASH) writeFileSync(SHEET, made);
    expect(readFileSync(SHEET, 'utf8'), 'run `npm run icons:wash`').toBe(made);
  });

  it('washes the ones that were hollow, each by its body', () => {
    const made = sheet();
    for (const name of ['mic', 'bell', 'file-text', 'settings', 'search', 'folder', 'lock', 'image', 'copy', 'palette', 'trash', 'flag']) {
      expect(made, name).toContain(`:where(svg.lucide-${name}) > :nth-child(`);
    }
    // And never an icon of lines alone.
    for (const name of ['arrow-left', 'check', 'x', 'plus', 'chevron-down']) expect(made, name).not.toContain(`svg.lucide-${name})`);
  });
});
