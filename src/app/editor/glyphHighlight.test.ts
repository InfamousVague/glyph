import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tags } from '@lezer/highlight';
import { describe, expect, it } from 'vitest';
import { glyphHighlight } from './glyphHighlight.ts';

/*
 * The order the highlighter's rules come in is load-bearing (glyphHighlight.ts): the asterisks of `**bold**` carry
 * both the bold rule and the marker rule, the two have the same specificity, and the marker must win or a bold run's
 * `**` is drawn bold and not dimmed. Nothing a person would notice at once, and nothing else checks it. The tests run
 * without the stylesheet (vitest.config.ts `css: false`), so the stylesheet is read as text.
 */

// `import.meta.url` is the page's own under jsdom, not a file; Vitest gives the file's directory as `dirname`.
const here = import.meta.dirname;
const source = readFileSync(join(here, 'glyphHighlight.ts'), 'utf8');
const sheet = readFileSync(join(here, 'markdown.module.css'), 'utf8');

/** Where the stylesheet's own rule for `.name` starts, a rule of that class alone at the top level; -1 for none. */
function ruleAt(name: string): number {
  const found = new RegExp(String.raw`^\.${name}\s*\{`, 'm').exec(sheet);
  return found ? found.index : -1;
}

describe('the order of the highlighter’s rules', () => {
  it('ends with the markers, so a delimiter inside any styled run is dimmed', () => {
    expect(glyphHighlight.specs.at(-1)?.tag).toBe(tags.processingInstruction);
  });

  it('has the markers’ rule after every other token’s rule in the stylesheet, which is what makes it win', () => {
    const classes = [...new Set([...source.matchAll(/styles\.(\w+)/g)].map((match) => match[1]!))];
    expect(classes).toContain('mark');
    expect(classes.length).toBeGreaterThan(10);
    const mark = ruleAt('mark');
    for (const name of classes.filter((one) => one !== 'mark')) {
      const at = ruleAt(name);
      expect(at, `.${name} has a rule of its own`).toBeGreaterThanOrEqual(0);
      expect(at, `.${name} comes before .mark`).toBeLessThan(mark);
    }
  });
});
