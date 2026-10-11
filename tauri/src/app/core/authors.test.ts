import { describe, expect, it } from 'vitest';
import { aiName, authorsAcross, authorsOf, withAuthor } from './authors.ts';
import { frontMatterValue, withFrontMatterValue } from './frontMatter.ts';

describe('a note’s authors', () => {
  it('are the front matter’s authors line, in order, each once', () => {
    expect(authorsOf('---\nauthors: matt, Claude, claude\n---\n# Trip')).toEqual(['matt', 'Claude']);
    expect(authorsOf('# Trip\n\nNo front matter.')).toEqual([]);
  });

  it('take an AI after the owner on a note that named none, and keep the words and the other keys', () => {
    const plain = withAuthor('# Trip\n\nWords.', 'Claude', 'matt');
    expect(plain).toBe('---\nauthors: matt, Claude\n---\n# Trip\n\nWords.');
    const titled = withAuthor('---\ntitle: "Map"\n---\n{"nodes":[]}', 'Claude', 'matt');
    expect(frontMatterValue(titled, 'title')).toBe('Map');
    expect(authorsOf(titled)).toEqual(['matt', 'Claude']);
    expect(titled.endsWith('{"nodes":[]}')).toBe(true);
  });

  it('don’t take a name twice, and a note already by others gains the AI last', () => {
    const once = withAuthor('# A', 'Claude', 'matt');
    expect(withAuthor(once, 'claude', 'matt')).toBe(once);
    expect(authorsOf(withAuthor('---\nauthors: sam\n---\n# A', 'Claude', 'matt'))).toEqual(['sam', 'Claude']);
  });

  it('across a book are its own and its chapters’, first met first', () => {
    expect(authorsAcross(['---\nauthors: matt, Claude\n---\n# Book', '# Plain chapter', '---\nauthors: matt, Gemini\n---\n# C'])).toEqual(['matt', 'Claude', 'Gemini']);
  });
});

describe('an AI’s name', () => {
  it('is what it says it is, else its app’s name read as the product, else nothing', () => {
    expect(aiName('Claude Opus', { name: 'claude-ai' })).toBe('Claude Opus');
    expect(aiName(undefined, { name: 'claude-ai', title: 'Claude' })).toBe('Claude');
    expect(aiName(undefined, { name: 'openai-mcp' })).toBe('ChatGPT');
    expect(aiName(undefined, { name: 'some-agent' })).toBe('some-agent');
    expect(aiName(undefined, undefined)).toBeNull();
    expect(aiName('A, B', undefined)).toBe('A B');
  });
});

describe('a front matter key written', () => {
  it('replaces, adds, or takes off one key, and front matter that held only it', () => {
    expect(withFrontMatterValue('---\nbook: true\n---\n# B', 'authors', 'a, b')).toBe('---\nbook: true\nauthors: a, b\n---\n# B');
    expect(withFrontMatterValue('---\nauthors: a\n---\n# B', 'authors', null)).toBe('# B');
    expect(withFrontMatterValue('---\nbook: true\nauthors: a\n---\n# B', 'Authors', 'c')).toBe('---\nbook: true\nauthors: c\n---\n# B'.replace('authors: c', 'Authors: c'));
  });
});
