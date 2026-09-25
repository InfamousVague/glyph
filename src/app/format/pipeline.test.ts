import { describe, expect, it } from 'vitest';
import { bodyHash } from './formatter.ts';
import { EDITED, needsPasses, noteHash, passesFor, revisionPasses } from './pipeline.ts';

describe('the passes a note gets', () => {
  it('is one pass, by the chosen model when it is on the phone', () => {
    expect(passesFor(['qwen3.5-4b', 'qwen3.5-2b'], 'qwen3.5-4b')).toEqual(['qwen3.5-4b']);
    expect(passesFor(['qwen3.5-9b', 'qwen3.5-2b', 'qwen3.5-4b'], 'qwen3.5-4b')).toEqual(['qwen3.5-4b']);
    expect(passesFor(['qwen3.5-2b', 'qwen3.5-4b', 'qwen3.5-9b'], 'qwen3.5-9b')).toEqual(['qwen3.5-9b']);
  });

  it('makes do with what is on the phone when the chosen model is not: the biggest under it, else the smallest there is', () => {
    expect(passesFor(['qwen3.5-2b'], 'qwen3.5-4b')).toEqual(['qwen3.5-2b']);
    expect(passesFor(['qwen3.5-2b', 'qwen3.5-9b'], 'qwen3.5-4b')).toEqual(['qwen3.5-2b']);
    expect(passesFor(['qwen3.5-9b'], 'qwen3.5-2b')).toEqual(['qwen3.5-9b']);
    expect(passesFor([], 'qwen3.5-4b')).toEqual([]);
  });

  it('never repeats a model', () => {
    expect(passesFor(['qwen3.5-4b', 'qwen3.5-4b'], 'qwen3.5-4b')).toEqual(['qwen3.5-4b']);
  });
});

describe('whether a note needs formatting', () => {
  const body = '# Trip\n\ncall the plumber';
  const hash = bodyHash(body);
  const passes = ['qwen3.5-2b', 'qwen3.5-4b'];

  it('does with nothing kept, and does not with the last pass already kept for this body', () => {
    expect(needsPasses(null, hash, passes)).toBe(true);
    expect(needsPasses({ formatted: 'x', formattedFor: hash, formattedModel: 'qwen3.5-4b' }, hash, passes)).toBe(false);
  });

  it('does when the body changed, or only a draft by a smaller model is kept', () => {
    expect(needsPasses({ formatted: 'x', formattedFor: bodyHash('other'), formattedModel: 'qwen3.5-4b' }, hash, passes)).toBe(true);
    expect(needsPasses({ formatted: 'x', formattedFor: hash, formattedModel: 'qwen3.5-2b' }, hash, passes)).toBe(true);
  });

  it('never runs with no passes', () => {
    expect(needsPasses(null, hash, [])).toBe(false);
  });

  it('owes only the bigger passes when a fresh draft is kept, and all of them otherwise', () => {
    expect(revisionPasses({ formatted: 'x', formattedFor: hash, formattedModel: 'qwen3.5-2b' }, hash, passes)).toEqual(['qwen3.5-4b']);
    expect(revisionPasses({ formatted: 'x', formattedFor: hash, formattedModel: 'qwen3.5-4b' }, hash, passes)).toEqual([]);
    expect(revisionPasses({ formatted: 'x', formattedFor: bodyHash('other'), formattedModel: 'qwen3.5-4b' }, hash, passes)).toEqual(passes);
    expect(revisionPasses(null, hash, passes)).toEqual(passes);
  });

  it("leaves a person's own edit alone until the note changes", () => {
    const edited = { formatted: 'x', formattedFor: hash, formattedModel: EDITED };
    expect(needsPasses(edited, hash, passes)).toBe(false);
    expect(revisionPasses(edited, hash, passes)).toEqual([]);
    expect(needsPasses({ ...edited, formattedFor: bodyHash('other') }, hash, passes)).toBe(true);
    expect(revisionPasses({ ...edited, formattedFor: bodyHash('other') }, hash, passes)).toEqual(passes);
  });

  it('hashes a note with no project as its body alone', () => {
    expect(noteHash('no-such-note', body)).toBe(bodyHash(body));
  });
});
