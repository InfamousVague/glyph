import { describe, expect, it } from 'vitest';
import { CHAPTERS } from '../tutorial/lessons.ts';
import { saidGroups } from './cheatSheet.ts';

describe('the cheat sheet’s spoken rules', () => {
  const groups = saidGroups();

  it('covers every chapter the tutorial teaches, in its order', () => {
    expect(groups.map((group) => group.chapter)).toEqual([...CHAPTERS]);
  });

  it('gives every rule its words, and words to say for the ones that are said', () => {
    const rules = groups.flatMap((group) => group.rules);
    expect(rules.length).toBeGreaterThan(20);
    for (const rule of rules) {
      expect(rule.title.trim()).not.toBe('');
      expect(rule.teach.trim()).not.toBe('');
      if (rule.spoken) expect(rule.say.length).toBeGreaterThan(0);
    }
  });

  it('holds the cues a note is written with', () => {
    const said = groups
      .flatMap((group) => group.rules)
      .flatMap((rule) => [rule.teach, ...rule.say])
      .join(' ')
      .toLowerCase();
    for (const cue of ['title', 'heading', 'bullet', 'check', 'quote', 'bold', 'new paragraph']) expect(said).toContain(cue);
  });
});
