import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Developer (settings/DeveloperPane.tsx), by the names the page draws, in its order.
 * The Set-up card's two rows went in docs/DESIGN.md §138, each the same as a row elsewhere: "Choose your model" is
 * Recording's Model card, "Welcome guide" About's welcome walkthrough, and each carries the words.
 */
export const findable: SettingsFindable[] = [
  { name: 'Window', words: 'inset screen engine' },
  { name: 'Smoke bench', words: 'wisp performance frames' },
  { name: 'Play the scene', words: 'scene bench thermal heat readings' },
  { name: 'Developer settings', words: 'mode' },
  { name: 'Reset local data', words: 'clear erase' },
  { name: 'Reset everything', words: 'clear erase models' },
];
