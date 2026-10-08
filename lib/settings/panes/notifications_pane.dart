import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/preferences.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'settings_host.dart';

/// What Settings' search finds on Notifications (`findable`, src/app/settings/NotificationsPane.findable.ts): the four
/// switches, and the card of organizations to mute once there is one to draw it for.
List<SettingsFindable> notificationsFindable({required bool orgs}) => [
      const SettingsFindable('Team', 'organization members joined left removed renamed invitation accepted declined'),
      const SettingsFindable('Claude', 'mcp ai note created edited appended journal rule'),
      const SettingsFindable('Summaries', 'meeting written up summary recording'),
      const SettingsFindable('Conflicts', 'sync kept twice both devices'),
      if (orgs) const SettingsFindable('Mute an organization', 'silence quiet team news'),
    ];

/// Notifications' row in the list: how many of the four switches are on.
String notificationsSummary(NotificationPrefs prefs) => '${NotificationPrefs.categories.where(prefs.isOn).length} of ${NotificationPrefs.categories.length} on';

/// Each switch's words, in the order the pane draws them (`SWITCHES`).
const Map<String, (String, String)> _switches = {
  'team': ('Team', 'Who joined, left or was removed, an organization renamed or deleted, and your invitations answered.'),
  'claude': ('Claude', 'A note Claude made, edited or added to through the MCP server, with the first line it changed.'),
  'summaries': ('Summaries', 'A meeting written up. Here, in the list; the phone’s own notification is under Recording.'),
  'conflicts': ('Conflicts', 'A note changed on two devices at once and kept twice.'),
};

/// Port of `NotificationsPane` (src/app/settings/NotificationsPane.tsx): one switch for each category of what reaches
/// the feed and the bell, and a row for each organization whose team news can be muted. An invitation has no switch,
/// since whoever sent it is waiting for an answer. The choices are synced preferences (`Preferences.notifications`),
/// which lib/core/notifications.dart reads to decide what is drawn and counted.
///
/// What differs from the web original:
/// - There is no account yet, so [signedIn] and [orgs] are handed in: signed out, the callout sends the person to
///   Account; with no organizations there is no card of mutes.
/// - "On this phone", the bell's rows as the phone's own notifications, and its Allow, wait for the native side
///   (core/notifications/phone.ts): nothing here raises a phone notification yet, so the card is not drawn, as on a
///   binary from before them.
class NotificationsPane extends StatelessWidget {
  const NotificationsPane({super.key, this.store, this.signedIn = false, this.orgs = const [], this.onOpenAccount});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;
  final bool signedIn;

  /// The organizations the account is a member of.
  final List<SettingsOrg> orgs;

  /// Lands on Account; without it the word is a plain word.
  final VoidCallback? onOpenAccount;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return NotificationsPane(
      signedIn: host?.features.signedIn ?? false,
      orgs: host?.features.orgs ?? const [],
      onOpenAccount: host == null ? null : () => host.go('account'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? preferences;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) {
        final notifications = prefs.notifications;
        void write(NotificationPrefs next) => store.update((now) => now.copyWith(notifications: next));
        void flip(String category, bool on) => write(switch (category) {
              'team' => notifications.copyWith(team: on),
              'claude' => notifications.copyWith(claude: on),
              'summaries' => notifications.copyWith(summaries: on),
              _ => notifications.copyWith(conflicts: on),
            });
        void mute(String id, bool muted) {
          final others = [for (final held in notifications.mutedOrgs) if (held != id) held];
          write(notifications.copyWith(mutedOrgs: muted ? [...others, id] : others));
        }

        return PaneBody(
          children: [
            if (!signedIn)
              SettingsCallout(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Notifications come with an account. Sign in under '),
                      WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Account', onPress: onOpenAccount)),
                      const TextSpan(text: ' and they arrive here.'),
                    ],
                  ),
                ),
              ),
            PaneSection(
              title: 'What reaches you',
              footer: const Text('An invitation to an organization always arrives: whoever sent it is waiting for your answer.'),
              children: [
                for (final category in NotificationPrefs.categories)
                  SettingRow(
                    key: ValueKey(category),
                    label: _switches[category]!.$1,
                    hint: Text(_switches[category]!.$2),
                    control: GlacierSwitch(ariaLabel: _switches[category]!.$1, checked: notifications.isOn(category), onCheckedChange: (on) => flip(category, on)),
                  ),
              ],
            ),
            if (orgs.isNotEmpty)
              PaneSection(
                title: 'Mute an organization',
                footer: const Text('Muted, its team news is not drawn or counted. Its invitations still are.'),
                children: [
                  for (final org in orgs)
                    SettingRow(
                      key: ValueKey(org.id),
                      label: org.name,
                      hint: Text(org.members == 1 ? '1 member' : '${org.members} members'),
                      control: GlacierSwitch(ariaLabel: 'Mute ${org.name}', checked: notifications.mutedOrgs.contains(org.id), onCheckedChange: (muted) => mute(org.id, muted)),
                    ),
                ],
              ),
            const SettingsFootnote(child: Text('Ghost.md looks when it opens; the bell shows what arrived.')),
          ],
        );
      },
    );
  }
}
