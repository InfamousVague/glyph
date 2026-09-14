import { beforeEach, describe, expect, it } from 'vitest';
import { forgetResults, keepResult, keptFor } from './results.ts';

describe('where each mode keeps its text', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('keeps a summary and an enhanced text apart, per note, on the page', async () => {
    await keepResult('n1', 'summarize', '# Short\n', 11, 'qwen3.5-2b');
    await keepResult('n1', 'enhance', '# Long\n', 11, 'qwen3.5-4b');
    await keepResult('n2', 'summarize', '# Other\n', 22, 'qwen3.5-2b');
    expect(await keptFor('n1', 'summarize')).toEqual({ formatted: '# Short\n', formattedFor: 11, formattedModel: 'qwen3.5-2b' });
    expect(await keptFor('n1', 'enhance')).toEqual({ formatted: '# Long\n', formattedFor: 11, formattedModel: 'qwen3.5-4b' });
    expect(await keptFor('n2', 'enhance')).toBeNull();
    expect(await keptFor('n3', 'summarize')).toBeNull();
  });

  it('forgets a mode with a null hash, and a whole note on request', async () => {
    await keepResult('n1', 'summarize', '# Short\n', 11, 'qwen3.5-2b');
    await keepResult('n1', 'enhance', '# Long\n', 11, 'qwen3.5-4b');
    await keepResult('n1', 'summarize', '', null, null);
    expect(await keptFor('n1', 'summarize')).toBeNull();
    expect(await keptFor('n1', 'enhance')).not.toBeNull();
    forgetResults('n1');
    expect(await keptFor('n1', 'enhance')).toBeNull();
    expect(localStorage.getItem('glyph-ai-results')).toBe('{}');
  });

  it('survives a broken sheet', async () => {
    localStorage.setItem('glyph-ai-results', '[not json');
    expect(await keptFor('n1', 'summarize')).toBeNull();
    await keepResult('n1', 'summarize', '# Short\n', 11, 'qwen3.5-2b');
    expect((await keptFor('n1', 'summarize'))?.formatted).toBe('# Short\n');
  });
});
