import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Notifications (settings/NotificationsPane.tsx), by the names the page draws: the four
 * switches, and the card of organizations to mute once there is one. SettingsSheet.test.tsx renders the page and fails
 * on a name it does not draw, so the card's name is listed only while the page has an organization to draw it for.
 */
export function findable(orgs: boolean): SettingsFindable[] {
  return [
    { name: 'Team', words: 'organization members joined left removed renamed invitation accepted declined' },
    { name: 'Claude', words: 'mcp ai note created edited appended journal rule' },
    { name: 'Summaries', words: 'meeting written up summary recording' },
    { name: 'Conflicts', words: 'sync kept twice both devices' },
    ...(orgs ? [{ name: 'Mute an organization', words: 'silence quiet team news' }] : []),
  ];
}
