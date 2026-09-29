import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * Every word the fills say, in the app's voice (docs/DESIGN.md §21): no dashes, no semicolons, no ellipses. Read from
 * the source, so a sentence added later is held to it too.
 */

const FILES = [
  'src/app/ai/fills/queue.ts',
  'src/app/ai/fills/web.ts',
  'src/app/editor/blanks.ts',
  'src/app/editor/fillPanel.ts',
  'src/app/core/fillFacts.ts',
  'src/app/core/fillLive.ts',
  'src/app/settings/PrivacyCard.tsx',
];

/** The string literals of a file that read as words: a letter, a space, and no code about them. */
function sentences(file: string): string[] {
  const source = readFileSync(resolve(process.cwd(), file), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '');
  const found = [...source.matchAll(/'((?:[^'\\\n]|\\.)*)'|`((?:[^`\\]|\\.)*)`/g)].map((m) => m[1] ?? m[2] ?? '');
  return found.filter((text) => /[a-z] [a-z]/i.test(text) && !/^[\w./@-]+$/.test(text) && !/https?:|[{}()=>]/.test(text.replace(/\$\{[^}]*\}/g, '')));
}

describe('the fills’ words', () => {
  it('have no semicolon, dash or ellipsis', () => {
    const bad = FILES.flatMap((file) => sentences(file).filter((text) => /[;—–…]/.test(text)).map((text) => `${file}: ${text}`));
    expect(bad).toEqual([]);
  });

  it('are read from each file', () => {
    for (const file of FILES) expect(sentences(file).length, file).toBeGreaterThan(0);
  });
});
