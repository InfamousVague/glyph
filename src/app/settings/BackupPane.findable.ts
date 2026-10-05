import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Backup (settings/BackupPane.tsx), by the names the page draws. The page's rows are
 * the drives plugged in, which no search can name ahead of time, so the section is found by its own name and words
 * (SettingsSheet.tsx); SettingsSheet.test.tsx renders the page and fails on a name it does not draw.
 */
export function findable(): SettingsFindable[] {
  return [];
}
