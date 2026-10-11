import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Workspaces (settings/WorkspacesPane.tsx), by the names the page draws;
 * SettingsSheet.test.tsx renders the page and fails on a name it does not draw.
 */
export function findable(): SettingsFindable[] {
  return [
    { name: 'Your workspaces', words: 'workspace rename colour color delete remove' },
    { name: 'New workspace', words: 'create make add workspace' },
  ];
}
