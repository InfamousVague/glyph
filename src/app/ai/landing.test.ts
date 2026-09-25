import { describe, expect, it } from 'vitest';
import { frontMatterEnd, matchLine, similar, tokens, wordDiff } from './landing.ts';

describe('a line as words', () => {
  it('keeps the space before each word and leaves trailing space to nobody', () => {
    expect(tokens('  a  bc ')).toEqual([
      { lead: '  ', word: 'a' },
      { lead: '  ', word: 'bc' },
    ]);
    expect(tokens('')).toEqual([]);
  });
});

describe('two lines word by word', () => {
  it('marks only the words that differ, and joins the rest back to the new line', () => {
    const segments = wordDiff('- call the plumber thursday', '- [ ] Call the plumber on **Thursday**.');
    expect(segments.filter((s) => s.kind !== 'removed').map((s) => s.text).join('')).toBe('- [ ] Call the plumber on **Thursday**.');
    expect(segments.filter((s) => s.kind === 'removed').map((s) => s.text.trim())).toEqual(['call', 'thursday']);
    expect(segments.filter((s) => s.kind === 'added').map((s) => s.text.trim())).toEqual(['[ ] Call', 'on **Thursday**.']);
  });

  it('is all the same for the same line, and all added for a line from nothing', () => {
    expect(wordDiff('a b c', 'a b c')).toEqual([{ kind: 'same', text: 'a b c' }]);
    expect(wordDiff('', 'a b')).toEqual([{ kind: 'added', text: 'a b' }]);
    expect(wordDiff('a b', '')).toEqual([{ kind: 'removed', text: 'a b' }]);
  });

  it('rides the new line’s trailing space on its last piece', () => {
    expect(wordDiff('a b', 'a b  ')).toEqual([{ kind: 'same', text: 'a b  ' }]);
  });
});

describe('whether a line is another rewritten', () => {
  it('is, with half the words shared and at least two', () => {
    expect(similar('call the plumber about the tap', '- [ ] Call the plumber about the leaking tap.')).toBe(true);
    expect(similar('eggs and coffee', 'Pick up eggs and coffee on the way home.')).toBe(false);
    expect(similar('trip', '# Trip')).toBe(true);
    expect(similar('# Trip', '# Trip to Bath')).toBe(false);
    expect(similar('line 0', 'line 11')).toBe(false);
    expect(similar('# Trip', '# Plans')).toBe(false);
    expect(similar('', 'words')).toBe(false);
  });
});

describe('where a finished line belongs', () => {
  const old = ['# trip', '', 'call the plumber', 'eggs and coffee', '', 'notes'];

  it('keeps an old line that is the same, dropping the ones before it', () => {
    expect(matchLine(old, '# trip')).toEqual({ kind: 'keep', at: 0 });
    expect(matchLine(old, 'eggs and coffee')).toEqual({ kind: 'keep', at: 3 });
    expect(matchLine(old, 'notes  ')).toEqual({ kind: 'keep', at: 5 });
  });

  it('rewrites a line that is nearly the same, and adds one that is new', () => {
    expect(matchLine(old, '- [ ] Call the plumber.')).toEqual({ kind: 'replace', at: 2 });
    expect(matchLine(old, '## Errands')).toEqual({ kind: 'insert' });
  });

  it('looks for a blank line only at the very next line', () => {
    expect(matchLine(old, '')).toEqual({ kind: 'insert' });
    expect(matchLine(old.slice(1), '')).toEqual({ kind: 'keep', at: 0 });
  });

  it('does not look too far ahead', () => {
    const far = Array.from({ length: 12 }, (_, i) => `line ${i}`);
    expect(matchLine(far, 'line 11')).toEqual({ kind: 'insert' });
    expect(matchLine(far, 'line 7')).toEqual({ kind: 'keep', at: 7 });
  });
});

describe('where the front matter ends', () => {
  it('is after the closing fence, or the start where there is none', () => {
    expect(frontMatterEnd('---\ntitle: "A"\n---\n# A\n')).toBe(19);
    expect(frontMatterEnd('# A\n')).toBe(0);
    expect(frontMatterEnd('---\ntitle: "A"\n')).toBe(0);
    expect(frontMatterEnd('---\n---')).toBe(7);
  });
});
