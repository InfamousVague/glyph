import { describe, expect, it } from 'vitest';
import { bodyHash } from './bodyHash.ts';
import { noteHash, prepareNote } from './pipeline.ts';

describe('a note as the model sees it', () => {
  it('hashes a note with no project as its body alone', () => {
    const body = '# Trip\n\ncall the plumber';
    expect(noteHash('no-such-note', body)).toBe(bodyHash(body));
  });

  it('swaps links for tokens the model can copy, and puts them back as the lines land and once at the end', () => {
    const { prompt, restore } = prepareNote('see [the docs](https://example.com/docs) now\n', 'format');
    expect(prompt).toContain('[the docs](link-1)');
    expect(prompt).not.toContain('https://example.com');
    expect(restore('# Notes\nsee [the docs](link-1) no', false)).toBe('# Notes\nsee [the docs](https://example.com/docs) no');
    expect(restore('* see [the docs](link-1) now', true)).toBe('- see [the docs](https://example.com/docs) now\n');
  });

  it('takes off a code fence a model put round its whole answer, with or without a language, and the blank edges', () => {
    const { restore } = prepareNote('# Trip\n', 'format');
    expect(restore('```markdown\n# Trip\n\n- call Sam\n```', true)).toBe('# Trip\n\n- call Sam\n');
    expect(restore('\n\n```\n# Trip\n```\n\n', true)).toBe('# Trip\n');
    expect(restore('\n\n# Trip\n\n\n', true)).toBe('# Trip\n');
  });

  it('leaves a code block inside the answer where it is', () => {
    const { restore } = prepareNote('# Setup\n', 'format');
    const answer = '# Setup\n\n```bash\nnpm run dev\n```\n\nThen open the page.';
    expect(restore(answer, true)).toBe(`${answer}\n`);
  });

  it('keeps a table whole through the model', () => {
    const table = '| a | b |\n| - | - |\n| 1 | 2 |';
    const { prompt, restore } = prepareNote(`# T\n\n${table}\n`, 'format');
    expect(prompt).toContain('![table-1](table)');
    expect(restore(`# T\n\n![table-1](table)\n`, true)).toBe(`# T\n\n${table}\n`);
  });
});
