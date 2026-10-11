import { beforeEach, describe, expect, it } from 'vitest';
import { forgetResults, keepGist, readGist } from './results.ts';

describe('the gist kept on the page', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('keeps a gist per note, with the body it came from', () => {
    keepGist('n1', { text: 'Call the plumber by Thursday', for: 11, model: 'qwen3.5-2b', len: 40, head: 'plumber' });
    keepGist('n2', { text: 'The weekend trip', for: 22, model: 'qwen3.5-2b' });
    expect(readGist('n1')).toMatchObject({ text: 'Call the plumber by Thursday', for: 11 });
    expect(readGist('n2')?.text).toBe('The weekend trip');
    expect(readGist('n3')).toBeNull();
  });

  it('forgets a note on request', () => {
    keepGist('n1', { text: 'A line', for: 11, model: 'qwen3.5-2b' });
    forgetResults('n1');
    expect(readGist('n1')).toBeNull();
    expect(localStorage.getItem('glyph-ai-results')).toBe('{}');
  });

  it('survives a broken sheet, and reads past an older sheet’s mode texts', () => {
    localStorage.setItem('glyph-ai-results', '[not json');
    expect(readGist('n1')).toBeNull();
    localStorage.setItem('glyph-ai-results', JSON.stringify({ n1: { summarize: { text: '# Short\n', for: 11, model: 'x' }, gist: { text: 'A line', for: 11, model: 'x' } } }));
    expect(readGist('n1')?.text).toBe('A line');
  });
});
