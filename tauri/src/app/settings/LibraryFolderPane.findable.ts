import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Library folder (settings/LibraryFolderPane.tsx), by its cards' titles: the words a
 * plugin's page carried until it became a setting (docs/DESIGN.md §205). SettingsSheet.test.tsx renders the page and
 * fails on a name it does not draw.
 */
export function findable(): SettingsFindable[] {
  return [
    { name: 'Where your notes are', words: 'library folder choose move obsidian vault icloud dropbox syncthing backup drive' },
    { name: 'Good to know', words: 'sync google drive index pictures recordings' },
  ];
}
