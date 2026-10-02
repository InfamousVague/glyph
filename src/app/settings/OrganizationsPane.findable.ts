import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Organizations (settings/OrganizationsPane.tsx), by the names the page draws. Signed
 * out the page is one sentence sending the person to Account, so nothing is listed then; SettingsSheet.test.tsx
 * renders the page and fails on a name it does not draw.
 */
export function findable(signedIn: boolean): SettingsFindable[] {
  return signedIn
    ? [
        { name: 'Your organizations', words: 'teams org team members' },
        { name: 'New organization', words: 'create make team org start' },
      ]
    : [];
}
