import type { SettingsFindable } from './settingsSearch.ts';

/** What Settings' search finds on Examples (settings/ExamplesPane.tsx), the four rows About's Help held until docs/DESIGN.md §138. */
export const findable: SettingsFindable[] = [
  { name: 'Add the sample note', words: 'example sample' },
  { name: 'Add the example board', words: 'example kanban' },
  { name: 'Add the example canvas', words: 'example obsidian' },
  { name: 'Add the “How Ghost.md works” canvas', words: 'example canvas how it works' },
];
