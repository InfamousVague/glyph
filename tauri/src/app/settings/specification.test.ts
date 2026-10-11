import { describe, expect, it } from 'vitest';
import { markGroups } from '../guide/marks.ts';
import { BASE_SPECS, SPEC, specCovers } from './specification.ts';

describe('the specification (GLY-4)', () => {
  it('defines every mark the cheat sheet teaches, so a new mark cannot arrive without its definition', () => {
    const covered = specCovers();
    const taught = markGroups().flatMap((group) => group.rows.map((row) => row.name));
    expect(taught.length).toBeGreaterThan(40);
    expect(taught.filter((name) => !covered.has(name))).toEqual([]);
  });

  it('claims to cover only marks the cheat sheet has', () => {
    const taught = new Set(markGroups().flatMap((group) => group.rows.map((row) => row.name)));
    expect([...specCovers()].filter((name) => !taught.has(name))).toEqual([]);
  });

  it('shows patterns that read its own examples', () => {
    const patterned = SPEC.flatMap((section) => section.entries).filter((entry) => entry.pattern);
    expect(patterned.length).toBeGreaterThan(5);
    for (const entry of patterned) {
      const pattern = new RegExp(entry.pattern ?? '', 'mu');
      // A filled answer's pattern reads the note in its brackets, which the app hides.
      const texts = [entry.written, ...[...entry.written.matchAll(/\(([^()]*)\)/g)].map((match) => match[1] ?? '')];
      expect(
        texts.some((text) => pattern.test(text)),
        entry.name,
      ).toBe(true);
    }
  });

  it('names each entry once, and links the standard Markdown it builds on', () => {
    const names = SPEC.flatMap((section) => section.entries.map((entry) => entry.name));
    expect(new Set(names).size).toBe(names.length);
    expect(BASE_SPECS.map((spec) => spec.url)).toEqual(['https://spec.commonmark.org/', 'https://github.github.com/gfm/']);
  });
});
