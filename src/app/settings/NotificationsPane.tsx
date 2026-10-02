import { Switch } from '@glacier/react';
import { useAccount } from '../core/account/account.ts';
import { CATEGORIES } from '../core/notifications/kinds.ts';
import { useOrgs } from '../core/orgs/orgs.ts';
import { setPreferences, usePreferences, type NotificationPrefs } from '../core/preferences.ts';
import type { SettingsTarget } from './SettingsScreen.tsx';
import { GoWord, PaneSection, SettingRow, SettingsCallout, SettingsFootnote } from './kit/settingsKit.tsx';

/**
 * Notifications, a listed page of Settings beside Account (docs/TEAMS.md, D8 and D9; Matt: "there should be a
 * notifications section in settings in order to customize the notifications we receive"): one switch for each
 * category of what reaches the feed and the bell, and a row for each organization whose team news can be muted. An
 * invitation has no switch, since whoever sent it is waiting for an answer. The choices are synced preferences
 * (core/preferences.ts `notifications`), so a mute made on the phone holds on the Mac; every row is still written to
 * the account, and these decide what is drawn and counted.
 *
 * No row for the phone's own notifications in this slice: nothing syncs while the app is closed, and the host has no
 * way to raise one yet, so the footer says what is true instead - Ghost.md looks when it opens, and the bell shows
 * what arrived. The summaries row says where the phone's own notification for a meeting still lives (Recording), so
 * the two rows that read as one thing say which is which.
 *
 * What the search finds here is NotificationsPane.findable.ts; SettingsSheet.tsx reads "n of 4 on" from the same
 * preference for its row (the file beside the page keeps the words for the search, as the other panes' do).
 */

/** Each switch's words, in the order the pane draws them (core/notifications/kinds.ts `CATEGORIES`). */
const SWITCHES: Record<(typeof CATEGORIES)[number], { label: string; hint: string }> = {
  team: { label: 'Team', hint: 'Who joined, left or was removed, an organization renamed or deleted, and your invitations answered.' },
  claude: { label: 'Claude', hint: 'A note Claude made, edited or added to through the MCP server, with the first line it changed.' },
  summaries: { label: 'Summaries', hint: 'A meeting written up. Here, in the list; the phone’s own notification is under Recording.' },
  conflicts: { label: 'Conflicts', hint: 'A note changed on two devices at once and kept twice.' },
};

export function NotificationsPane({ onOpen }: { onOpen?: (target: SettingsTarget) => void }) {
  const prefs = usePreferences();
  const account = useAccount();
  const { list } = useOrgs();
  const notifications = prefs.notifications;
  // Team news comes to members; an invitation has nothing to mute yet, and is never muted anyway.
  const orgs = list.filter((row) => row.state === 'member');
  const write = (change: Partial<NotificationPrefs>) => setPreferences({ notifications: { ...notifications, ...change } });
  const mute = (id: string, muted: boolean) => write({ mutedOrgs: muted ? [...notifications.mutedOrgs.filter((held) => held !== id), id] : notifications.mutedOrgs.filter((held) => held !== id) });

  return (
    <>
      {account.session ? null : (
        <SettingsCallout>
          <span>
            Notifications come with an account. Sign in under <GoWord onPress={onOpen ? () => onOpen({ id: 'account' }) : undefined}>Account</GoWord> and they arrive here.
          </span>
        </SettingsCallout>
      )}
      <PaneSection title="What reaches you" footer="An invitation to an organization always arrives: whoever sent it is waiting for your answer.">
        {CATEGORIES.map((category) => (
          <SettingRow
            key={category}
            label={SWITCHES[category].label}
            hint={SWITCHES[category].hint}
            control={<Switch aria-label={SWITCHES[category].label} checked={notifications[category]} onCheckedChange={(on) => write({ [category]: on })} />}
          />
        ))}
      </PaneSection>
      {orgs.length ? (
        <PaneSection title="Mute an organization" footer="Muted, its team news is not drawn or counted. Its invitations still are.">
          {orgs.map((org) => (
            <SettingRow
              key={org.id}
              label={org.name}
              hint={org.members === 1 ? '1 member' : `${org.members} members`}
              control={<Switch aria-label={`Mute ${org.name}`} checked={notifications.mutedOrgs.includes(org.id)} onCheckedChange={(muted) => mute(org.id, muted)} />}
            />
          ))}
        </PaneSection>
      ) : null}
      <SettingsFootnote>Ghost.md looks when it opens; the bell shows what arrived.</SettingsFootnote>
    </>
  );
}
