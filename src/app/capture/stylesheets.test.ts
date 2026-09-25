import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/**
 * Every class the recorder's components ask of a stylesheet is one that stylesheet has.
 *
 * A CSS module answers undefined for a class it does not define, and the element is drawn with no class at all - no
 * error, no warning, and in the tests (which run with CSS off) no difference. That is how the table card lost its card
 * when the confirm card's rules moved to ai/ (20618bb): it went on asking the recorder's stylesheet for `confirm`.
 * So the check is on the text: each `styles.name` in a component here against the `.name` rules of the module it
 * imported as `styles`.
 */

const here = dirname(fileURLToPath(import.meta.url));
const IMPORT = /^import (\w+) from '([^']+\.module\.css)';$/gm;

function asked(source: string, name: string): string[] {
  const uses = new Set<string>();
  for (const found of source.matchAll(new RegExp(String.raw`\b${name}\.([A-Za-z_]\w*)`, 'g'))) uses.add(found[1] ?? '');
  for (const found of source.matchAll(new RegExp(String.raw`\b${name}\[['"]([\w-]+)['"]\]`, 'g'))) uses.add(found[1] ?? '');
  return [...uses];
}

const components = readdirSync(here).filter((file) => file.endsWith('.tsx') && !file.includes('.test.'));

describe('the recorder’s stylesheets', () => {
  it.each(components)('define every class %s asks of them', (file) => {
    const source = readFileSync(join(here, file), 'utf8');
    const missing: string[] = [];
    for (const [, name = '', path = ''] of source.matchAll(IMPORT)) {
      const css = readFileSync(join(here, path), 'utf8');
      for (const cls of asked(source, name)) if (!new RegExp(String.raw`\.${cls}(?![\w-])`).test(css)) missing.push(`${path} .${cls}`);
    }
    expect(missing).toEqual([]);
  });
});
