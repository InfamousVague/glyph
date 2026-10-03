import { useEffect } from 'react';
import { Switch } from '@glacier/react';
import { useAccount } from '../core/account/account.ts';
import { requestNotifications } from '../core/host.ts';
import { phoneNoticesOn, readPhoneNotices, setPhoneNoticesOn, usePhoneNotices } from '../core/notifications/phone.ts';
import { CATEGORIES } from '../core/notifications/kinds.ts';
import { useOrgs } from '../core/orgs/orgs.ts';
import { setPreferences, usePreferences, type NotificationPrefs } from '../core/preferences.ts';
import type { SettingsTarget } from './SettingsScreen.tsx';
import { GoWord, PaneSection, RowAction, SettingRow, SettingsCallout, SettingsFootnote } from './kit/settingsKit.tsx';

/**
 * Notifications, a listed page of Settings beside Account (docs/TEAMS.md, D8 and D9; Matt: "there should be a
 * notifications section in settings in order to customize the notifications we receive"): one switch for each
 * category of what reaches the feed and the bell, and a row for each organization whose team news can be muted. An
 * invitation has no switch, since whoever sent it is waiting for an answer. The choices are synced preferences
 * (core/preferences.ts `notifications`), so a mute made on the phone holds on the Mac; every row is still written to
 * the account, and these decide what is drawn and counted.
 *
 * On a phone whose app can raise them (native generation 23; core/notifications/phone.ts), one more section, On this
 * phone: the bell's rows as the phone's own notifications, on unless turned off here, with Allow when Android is
 * keeping them from showing (Matt: "also send notifications as actual phone notifications too"). The summaries row
 * says where the phone's own notification for a meeting lives (Recording), so the two rows that read as one thing say
 * which is which.
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
  // What Android says of the phone's notices: null on the Mac, in a browser, or on an APK from before them. Read as the
  // page opens and every second while Android is keeping them from showing, so Allow's answer shows when it is given.
  const phone = usePhoneNotices();
  useEffect(() => {
    readPhoneNotices();
  }, []);
  useEffect(() => {
    if (phone !== 'blocked') return undefined;
    const id = window.setInterval(readPhoneNotices, 1000);
    return () => window.clearInterval(id);
  }, [phone]);
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
      {phone !== null ? (
        <PaneSection title="On this phone" footer="Within about fifteen minutes while Ghost.md is closed, and as they arrive while it runs in the background. Not while it is open in front of you: the bell has them.">
          <SettingRow
            label="Phone notifications"
            hint={
              phone === 'blocked'
                ? 'It’s on, but Android is not showing notifications from Ghost.md. Allow them below, or in the app’s system settings.'
                : 'Team news, invitations and Claude’s changes, as the switches above say. Meetings have their own, under Recording.'
            }
            control={<Switch aria-label="Phone notifications" checked={phoneNoticesOn()} onCheckedChange={(on) => setPhoneNoticesOn(on)} />}
          />
        </PaneSection>
      ) : null}
      {phone === 'blocked' ? (
        <div className="settingsScreen__actions">
          <RowAction onPress={() => requestNotifications()}>Allow notifications</RowAction>
        </div>
      ) : null}
      <SettingsFootnote>Ghost.md looks when it opens; the bell shows what arrived.</SettingsFootnote>
    </>
  );
}
