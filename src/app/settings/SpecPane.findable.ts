import type { SettingsFindable } from './settingsSearch.ts';
import { BASE_SPECS, SPEC } from './specification.ts';

/**
 * What Settings' search finds on the specification (settings/SpecPane.tsx): each base specification by name, and
 * each definition by its name and its part's title, so looking for "front matter" or "fills" lands on it. Not by the
 * characters it is written with: the cheat sheet is found by those, and a definition's examples are full of words
 * (a board's height=) that would answer searches meant for other pages.
 */
export function findable(): SettingsFindable[] {
  return [
    ...BASE_SPECS.map((spec) => ({ name: spec.name, words: 'markdown standard' })),
    ...SPEC.flatMap((section) => section.entries.map((entry) => ({ name: entry.name, words: section.title }))),
  ];
}
