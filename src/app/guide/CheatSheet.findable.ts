import type { SettingsFindable } from '../settings/settingsSearch.ts';
import { markGroups } from './marks.ts';

/**
 * What Settings' search finds on the cheat sheet (guide/CheatSheet.tsx), a sub-page of About since docs/DESIGN.md §138:
 * every mark it shows, by its name and its characters, so looking for "bold" or "||" lands on it. Read as the marks
 * stand, so a plugin switched off takes its marks out of the search as it does out of the sheet.
 */
export function findable(): SettingsFindable[] {
  return markGroups()
    .flatMap((group) => group.rows)
    .map((row) => ({ name: row.name, words: row.symbol }));
}
