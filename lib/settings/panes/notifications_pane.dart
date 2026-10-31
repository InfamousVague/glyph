import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../core/phone_notices.dart';
import '../../core/preferences.dart';
import '../../sync/phone.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'pane_parts.dart';
import 'settings_host.dart';
import '../../core/iphone_app.dart' show recordsVoice;
import '../../reminders/reminder_host.dart' show ReminderHost, phoneReminders;
import 'reminders_section.dart';
import 'ticket_digest_section.dart';

/// What Settings' search finds on Notifications (`findable`, src/app/settings/NotificationsPane.findable.ts): the four
/// switches, and the card of organizations to mute once there is one to draw it for.
List<SettingsFindable> notificationsFindable({required bool orgs}) => [
      // Reminders, where the phone reminds (reminders_section.dart).
      if (phoneReminders.value != null) ...remindersFindable,
      const SettingsFindable('Team', 'organization members joined left removed renamed invitation accepted declined'),
      const SettingsFindable('Claude', 'mcp ai note created edited appended journal rule'),
      const SettingsFindable('Summaries', 'meeting written up summary recording'),
      const SettingsFindable('Conflicts', 'sync kept twice both devices'),
      if (orgs) const SettingsFindable('Mute an organization', 'silence quiet team news'),
      // The morning's ticket digest (ticket_digest_section.dart).
      ...ticketDigestFindable,
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
/// - The account and its organizations are the [AccountServices] it is handed ([services], or the [AccountScope]
///   over Settings): signed out, the callout sends the person to Account; a member of an organization gets its row
///   to mute. Without one, [signedIn] and [orgs] are what it was handed before there was an account.
/// - "On this phone", the bell's rows as the phone's own notifications (lib/sync/phone.dart), is drawn where the
///   page drew it: on a phone whose app can raise them. Here that is a build with an account service on Android
///   ([phone], the account's own [PhoneNotices], whose phone has answered); a build with no service has no feed to
///   post, and a desktop, an iPhone or a test answers nothing, so the card is not drawn, as on the Mac or in a
///   browser. "Allow notifications" raises Android's prompt by asking the phone itself ([PhoneNotices.allow], the
///   page's `requestNotifications`): wherever the row is drawn it can be pressed, with or without a recorder or a
///   meeting service. What Android answered is read again every second while it is keeping them from showing, as
///   the page does.
class NotificationsPane extends StatelessWidget {
  const NotificationsPane({super.key, this.store, this.signedIn = false, this.orgs = const [], this.services, this.onOpenAccount, this.phone, this.reminders});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;
  final bool signedIn;

  /// The organizations the account is a member of.
  final List<SettingsOrg> orgs;

  /// The account; with one, who is signed in and the organizations are read from it.
  final AccountServices? services;

  /// Lands on Account; without it the word is a plain word.
  final VoidCallback? onOpenAccount;

  /// The phone's own notifications for the bell's rows; the account's ([AccountServices.phoneNotices]) unless given.
  /// With none, or on a device whose binary has none, "On this phone" is not drawn.
  final PhoneNotices? phone;

  /// The phone's reminders, which draw their own group first; the app's own where it has them
  /// ([phoneReminders], Android over the real library) unless given. With none, no group.
  final ReminderHost? reminders;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return NotificationsPane(
      signedIn: host?.features.signedIn ?? false,
      orgs: host?.features.orgs ?? const [],
      services: AccountScope.maybeOf(context),
      onOpenAccount: host == null ? null : () => host.go('account'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    final store = this.store ?? services?.prefs ?? preferences;
    return AccountBuilder(
      services: services,
      builder: (context) => _PhoneRead(
        phone: phone ?? services?.phoneNotices,
        builder: (context, phone, state) => _page(context, store, services, phone, state),
      ),
    );
  }

  Widget _page(BuildContext context, PreferencesStore store, AccountServices? services, PhoneNotices? phone, NoticesState? state) {
    final signedIn = services?.signedIn ?? this.signedIn;
    // Team news comes to members; an invitation has nothing to mute yet, and is never muted anyway.
    final orgs = services == null ? this.orgs : [for (final row in services.joined) SettingsOrg(id: row.id, name: row.name, members: row.members)];
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

        final reminders = this.reminders ?? phoneReminders.value;
        return PaneBody(
          children: [
            // This phone's own, signed in or not: nothing of it needs an account.
            if (reminders != null) RemindersSection(host: reminders),
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
                    // An iPhone has no Recording section and writes up no meeting itself ([recordsVoice]).
                    hint: Text(category == 'summaries' && !recordsVoice ? 'A meeting written up on another of your devices.' : _switches[category]!.$2),
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
            // The morning's ticket digest (lib/book/ticket_digest.dart; Matt, 2026-10-31): the account's choices, on
            // every device, under what the bell takes in.
            TicketDigestSection(store: store, reminders: reminders),
            if (phone != null && state != null)
              PaneSection(
                title: 'On this phone',
                footer: const Text('Within about fifteen minutes while Ghost.md is closed, and as they arrive while it runs in the background. Not while it is open in front of you: the bell has them.'),
                children: [
                  SettingRow(
                    label: 'Phone notifications',
                    hint: Text(
                      state == NoticesState.blocked
                          ? 'It’s on, but Android is not showing notifications from Ghost.md. Allow them below, or in the app’s system settings.'
                          : 'Team news, invitations and Claude’s changes, as the switches above say. Meetings have their own, under Recording.',
                    ),
                    control: GlacierSwitch(ariaLabel: 'Phone notifications', checked: phone.on, onCheckedChange: (on) => unawaited(phone.setOn(on))),
                  ),
                ],
              ),
            if (phone != null && state == NoticesState.blocked)
              PaneActions(
                children: [
                  RowAction(onPress: () => unawaited(phone.allow()), child: const Text('Allow notifications')),
                ],
              ),
            const SettingsFootnote(child: Text('Ghost.md looks when it opens; the bell shows what arrived.')),
          ],
        );
      },
    );
  }
}

/// What Android says of the phone's notices, for the page: read as the page opens, and every second while Android
/// is keeping them from showing, so Allow's answer shows when it is given (NotificationsPane.tsx's two effects).
/// Null where there are none to ask about.
class _PhoneRead extends StatefulWidget {
  const _PhoneRead({required this.phone, required this.builder});

  final PhoneNotices? phone;
  final Widget Function(BuildContext context, PhoneNotices? phone, NoticesState? state) builder;

  @override
  State<_PhoneRead> createState() => _PhoneReadState();
}

class _PhoneReadState extends State<_PhoneRead> {
  Timer? _again;

  @override
  void initState() {
    super.initState();
    _hear(widget.phone);
  }

  @override
  void didUpdateWidget(_PhoneRead old) {
    super.didUpdateWidget(old);
    if (!identical(old.phone, widget.phone)) {
      _unhear(old.phone);
      _hear(widget.phone);
    }
  }

  void _hear(PhoneNotices? phone) {
    if (phone == null) return;
    phone.addListener(_changed);
    phone.shown.addListener(_changed);
    unawaited(phone.read());
    _beat();
  }

  void _unhear(PhoneNotices? phone) {
    _again?.cancel();
    _again = null;
    if (phone == null) return;
    phone.removeListener(_changed);
    phone.shown.removeListener(_changed);
  }

  /// A look every second, only while Android is keeping them from showing.
  void _beat() {
    final phone = widget.phone;
    final blocked = phone?.shown.value == NoticesState.blocked;
    if (!blocked) {
      _again?.cancel();
      _again = null;
    } else {
      _again ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(phone!.read()));
    }
  }

  void _changed() {
    if (!mounted) return;
    _beat();
    setState(() {});
  }

  @override
  void dispose() {
    _unhear(widget.phone);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.phone, widget.phone?.shown.value);
}
