import { describe, expect, it } from 'vitest';
import { lookOf, withLook } from './look.ts';

/** A note's look (look.ts): one key, two values, read in any case, and written keeping every other key. */

describe('a note’s look', () => {
  it('is read from its front matter in any case, and anything but the two is none', () => {
    expect(lookOf('---\nlook: map\n---\n# Walk\n')).toBe('map');
    expect(lookOf('---\nlocation: 51.5,-0.12\nlook: Reading\n---\n# Walk\n')).toBe('reading');
    expect(lookOf('---\nlook: serif\n---\n# Walk\n')).toBeNull();
    expect(lookOf('# Walk\n\nlook: map\n')).toBeNull();
    expect(lookOf('')).toBeNull();
    // Only where front matter can be: a `look:` past its fortieth line is words.
    expect(lookOf(`---\n${'a: 1\n'.repeat(45)}look: map\n---\n`)).toBeNull();
  });

  it('is written keeping every other key, and taken off with a block that held nothing else', () => {
    expect(withLook('# Walk\n', 'reading')).toBe('---\nlook: reading\n---\n# Walk\n');
    expect(withLook('---\nlocation: 51.5,-0.12\n---\n# Walk\n', 'map')).toBe('---\nlocation: 51.5,-0.12\nlook: map\n---\n# Walk\n');
    expect(withLook('---\nlocation: 51.5,-0.12\nlook: map\n---\n# Walk\n', 'reading')).toBe('---\nlocation: 51.5,-0.12\nlook: reading\n---\n# Walk\n');
    expect(withLook('---\nlocation: 51.5,-0.12\nlook: map\n---\n# Walk\n', null)).toBe('---\nlocation: 51.5,-0.12\n---\n# Walk\n');
    expect(withLook('---\nlook: reading\n---\n# Walk\n', null)).toBe('# Walk\n');
  });
});
